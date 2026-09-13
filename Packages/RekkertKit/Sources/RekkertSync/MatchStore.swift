import Foundation
import Observation
import RekkertCore

@Observable
public final class MatchStore {
    public private(set) var log: MatchLog
    public private(set) var state: SessionState?
    public private(set) var isReachable = false
    /// Set when a peer's session replaced ours and the discarded one had real scores in
    /// it. It was archived to history first; this just lets the UI say so.
    public private(set) var replacedSessionTitle: String?
    /// The session that just ended, so the app can show how it went instead of dropping
    /// straight back to the start. Local to this device and deliberately not persisted — it
    /// is a curtain call, not state worth resuming.
    public private(set) var lastResult: SessionState?
    /// Saved configurations. Edited on the phone, readable on both.
    public private(set) var presets = PresetLibrary()
    /// How the phone draws its scoreboard. Shared so the watch can flip it from the wrist;
    /// only the phone acts on it.
    public private(set) var display = DisplayPreferences()

    private var outbox: Outbox
    private let device: DeviceID
    private let transport: any PeerTransport
    private let store: SessionStore?
    private var lastSnapshotPublished = Date.distantPast
    private var isFlushing = false
    private var needsFlush = false
    private var snapshotPending = false
    private var lastQueued: [EventID] = []
    private var retired: [UUID]
    private let keepsHistory: Bool
    private let sendTimeout: Duration
    private let retryInterval: Duration
    private let snapshotInterval: TimeInterval

    public init(
        device: DeviceID,
        transport: any PeerTransport,
        store: SessionStore? = nil,
        session: ActiveSession? = nil,
        snapshotInterval: TimeInterval = 1,
        sendTimeout: Duration = .seconds(6),
        retryInterval: Duration = .seconds(4),
        keepsHistory: Bool = true
    ) {
        self.sendTimeout = sendTimeout
        self.retryInterval = retryInterval
        self.keepsHistory = keepsHistory
        self.retired = session?.retired ?? []
        self.device = device
        self.transport = transport
        self.store = store
        self.snapshotInterval = snapshotInterval
        self.log = session?.log ?? MatchLog()
        self.outbox = session?.outbox ?? Outbox()
        self.presets = store?.loadPresets() ?? PresetLibrary()
        self.display = store?.loadDisplay() ?? DisplayPreferences()
        self.state = SessionReducer.state(of: self.log)
    }

    // MARK: - Local mutations

    public func configure(_ setup: SessionSetup) { record(.configure(setup)) }
    public func tap(round: Int = 0, court: Int = 0, team: TeamSide) {
        record(.point(round: round, court: court, team: team))
    }

    public func setScore(round: Int = 0, court: Int, points: BySide<Int>) {
        record(.setScore(round: round, court: court, points: points))
    }

    public func chooseServeSide(_ court: ServeCourt) { record(.chooseServeSide(court)) }

    /// Hands service to the other team. The rotation alternates teams at every step, so
    /// moving the starting point on by one is exactly a swap — and sending the resulting
    /// index rather than "swap" means two devices correcting it together agree.
    public func swapServingTeam(round: Int = 0, court: Int = 0) {
        guard let current = state?.firstServerIndex(round: round, court: court) else { return }
        let swapped = (current + 1) % ServeRotation.order.count
        record(.setFirstServer(round: round, court: court, index: swapped))
    }

    public func setRoundConfirmed(_ round: Int, _ isConfirmed: Bool = true) {
        record(.setRoundConfirmed(round: round, isConfirmed: isConfirmed))
    }
    /// Draws the next round. Addressed to the round on screen now, so two devices tapping
    /// at once still produce one round.
    public func nextRound() {
        guard case .tournament(let tournament)? = state else { return }
        // -1 when nothing has been drawn yet, so the first round is "the one after none".
        record(.nextRound(after: tournament.rounds.count - 1))
    }

    /// The whistle in winner court.
    public func endRound() {
        guard case .winnerCourt(let session)? = state else { return }
        record(.endRound(round: session.completedRounds.count))
    }
    /// Ends the session and keeps it in history if anything was played.
    public func finish() { record(.finish(archive: true)) }

    /// Ends the session and throws it away — for calling a match off rather than recording
    /// how far it got.
    public func discardSession() { record(.finish(archive: false)) }

    // MARK: - Presets

    public func savePreset(_ preset: Preset) {
        var updated = presets
        updated.save(preset)
        apply(updated, publish: true)
    }

    public func removePreset(_ id: UUID) {
        var updated = presets
        updated.remove(id)
        apply(updated, publish: true)
    }

    /// Configures a session from a saved preset, drawing the first round when the mode
    /// needs one, so starting from the watch takes a single tap.
    public func start(_ preset: Preset) {
        var updated = presets
        updated.markUsed(preset.id)
        apply(updated, publish: true)

        startNewSession()
        configure(preset.configuration.makeSetup())
        if preset.configuration.drawsRounds { nextRound() }
    }

    /// Flips which way round the phone's scoreboard reads, from either device. Sends the
    /// resulting value rather than a toggle, so a repeated delivery settles on the same
    /// answer instead of undoing itself.
    public func setScoreboardMirrored(_ isMirrored: Bool) {
        guard isMirrored != display.isMirrored else { return }
        apply(display.setting(mirrored: isMirrored), publish: true)
    }

    public func toggleScoreboardMirrored() {
        setScoreboardMirrored(!display.isMirrored)
    }

    private func apply(_ preferences: DisplayPreferences, publish: Bool) {
        display = preferences
        try? store?.save(preferences)
        guard publish else { return }
        let payload = encode(.display(preferences))
        transport.queue(payload)
        Task { _ = await sendLive(payload) }
    }

    private func apply(_ library: PresetLibrary, publish: Bool) {
        presets = library
        try? store?.save(library)
        guard publish else { return }
        let payload = encode(.presets(library))
        transport.queue(payload)
        Task { _ = await sendLive(payload) }
    }

    public var canUndo: Bool { log.lastUndoableEvent() != nil }

    public func undoLast() {
        guard let target = log.lastUndoableEvent() else { return }
        record(.undo(target.id))
    }

    public func startNewSession() {
        retire(log.sessionID)
        log = MatchLog()
        outbox = Outbox()
        replacedSessionTitle = nil
        lastResult = nil
        refresh()
    }

    /// A session is retired where it ends, and stays retired, so a counterpart that has not
    /// caught up cannot hand it back.
    private func retire(_ id: UUID) {
        guard !log.isEmpty, !retired.contains(id) else { return }
        retired.append(id)
        if retired.count > 20 { retired.removeFirst(retired.count - 20) }
    }

    /// Finishing is one path on both devices: the `.finish` event travels, and wherever it
    /// lands the session is archived if it is worth keeping and then cleared. Clearing
    /// locally without that would leave the counterpart holding a live copy to resurrect.
    /// A session played out to its end carries no `.finish`, and is worth keeping; one
    /// that was stopped says on the event whether it should be.
    private var wasAskedToArchive: Bool {
        for event in log.effectiveEvents.reversed() {
            if case .finish(let archive) = event.kind { return archive }
        }
        return true
    }

    private func concludeIfFinished() -> Bool {
        guard let finished = state, finished.isFinished else { return false }
        let keeping = finished.hasResults && wasAskedToArchive
        if keepsHistory, keeping {
            try? store?.archive(HistoryRecord(title: finished.title, state: finished))
        }
        // Nothing to celebrate about a session that was called off or never played.
        lastResult = keeping ? finished : nil

        // The counterpart has to learn this before the log disappears from here, or it
        // will keep offering the session back as though it were still live.
        let farewell = encode(.snapshot(log))
        transport.queue(farewell)
        Task { _ = await sendLive(farewell) }

        retire(log.sessionID)
        log = MatchLog()
        outbox = Outbox()
        state = nil
        persist()
        return true
    }

    public func acknowledgeReplacedSession() {
        replacedSessionTitle = nil
    }

    /// Dismisses the result screen.
    public func acknowledgeResult() {
        lastResult = nil
    }

    // MARK: - Sync

    public func run() async {
        transport.activate()
        // The inbound consumers must be live before any anti-entropy round trip, or two
        // devices starting at once would each block waiting for a reply the other cannot
        // yet produce.
        async let packets: Void = consumeInbound()
        async let reachability: Void = consumeReachability()
        async let retries: Void = retryUndelivered()
        async let initial: Void = synchronise()
        _ = await (packets, reachability, retries, initial)
    }

    private func consumeInbound() async {
        for await packet in transport.inbound {
            handle(packet)
            // Never await an outbound round trip here: the peer may be waiting on a reply
            // that only this loop can deliver.
            Task { await self.flush() }
        }
    }

    /// Reachability does not always change when a send fails, and a phone cannot wake the
    /// watch app the way a watch can wake the phone — so without this the outbox could sit
    /// full with nothing ever prompting another attempt.
    private func retryUndelivered() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: retryInterval)
            guard !outbox.isEmpty else { continue }

            if transport.isReachable {
                await flush()
            } else {
                queuePending()
            }
        }
    }

    /// Hands the backlog to the durable channel, which is the only one that reaches a
    /// counterpart whose app is not running. Merging is idempotent, so a duplicate that
    /// also arrives live costs nothing.
    private func queuePending() {
        let pending = outbox.pending.map(\.id)
        guard !pending.isEmpty, pending != lastQueued else { return }
        lastQueued = pending
        transport.queue(encode(.events(sessionID: log.sessionID, events: outbox.pending)))
    }

    private func consumeReachability() async {
        for await reachable in transport.reachability {
            isReachable = reachable
            if reachable { await synchronise() }
        }
    }

    /// Anti-entropy. Cheap enough to call on activation, on reachability changes and
    /// whenever the app comes to the foreground.
    public func synchronise() async {
        isReachable = transport.isReachable
        guard let payload = try? Wire.hello(sessionID: log.sessionID, vector: log.vector).encoded() else { return }
        if let reply = await transport.sendLive(payload) {
            handle(InboundPacket(payload: reply))
        }
        await flush()
        publishSnapshot(force: true)
        sharePresets()
        shareDisplay()
    }

    private func record(_ kind: EventKind) {
        let event = log.append(kind, from: device)
        outbox.enqueue(event)
        refresh()
        publishSnapshot(force: false)
        Task { await self.flush() }
    }

    private func flush() async {
        guard !isFlushing else {
            needsFlush = true
            return
        }
        isFlushing = true
        repeat {
            needsFlush = false
            await sendPending()
        } while needsFlush
        isFlushing = false
    }

    private func sendPending() async {
        isReachable = transport.isReachable
        guard !outbox.isEmpty, transport.isReachable else { return }
        guard let payload = try? Wire.events(sessionID: log.sessionID, events: outbox.pending).encoded() else { return }

        guard let reply = await sendLive(payload) else {
            queuePending()
            return
        }
        if case .hello(_, let vector)? = try? Wire.decode(reply) {
            outbox.acknowledge(upTo: vector)
            persist()
        }
    }

    /// WatchConnectivity does not promise to call back. A reply that never arrives would
    /// otherwise leave `isFlushing` set for the life of the app and wedge the outbox
    /// permanently — which looks exactly like one-way sync.
    private func sendLive(_ payload: Data) async -> Data? {
        let transport = transport
        let timeout = sendTimeout
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask { await transport.sendLive(payload) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func handle(_ packet: InboundPacket) {
        guard let wire = try? Wire.decode(packet.payload) else {
            // Always answer, so a peer awaiting a reply can never hang on bad input.
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.vector)))
            return
        }

        switch wire {
        case .hello(let sessionID, let vector):
            sharePresets()
            shareDisplay()
            guard !retired.contains(sessionID) else { return replyWithOurs(packet) }
            guard sessionID == log.sessionID else { return requestSnapshot(packet) }
            packet.reply?(encode(.events(sessionID: log.sessionID, events: log.events(missingRelativeTo: vector))))

        case .events(let sessionID, let events):
            guard !retired.contains(sessionID) else { return replyWithOurs(packet) }
            guard sessionID == log.sessionID else { return requestSnapshot(packet) }
            if log.merge(events) { refresh() }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.vector)))

        case .presets(let incoming):
            let merged = presets.adopting(incoming)
            if merged != presets { apply(merged, publish: false) }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.vector)))

        case .display(let incoming):
            let merged = display.adopting(incoming)
            if merged != display { apply(merged, publish: false) }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.vector)))

        case .snapshot(let incoming):
            if retired.contains(incoming.sessionID) {
                replyWithOurs(packet)
            } else if incoming.isEmpty {
                // A peer that has not started anything yet is not a competing session;
                // our own snapshot will reach it and it will adopt ours.
                break
            } else if log.isEmpty {
                log = incoming
                refresh()
            } else if incoming.sessionID == log.sessionID {
                if log.merge(incoming.ordered) { refresh() }
            } else if incoming.createdAt > log.createdAt {
                adopt(incoming)
            }
            // Otherwise ours is the newer session and wins; our own snapshot tells them so.
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.vector)))
        }
    }

    /// Replaces the local session with the peer's. Anything already scored locally is
    /// archived first, so a session is never silently destroyed.
    private func adopt(_ incoming: MatchLog) {
        if log.hasProgress, let state = SessionReducer.state(of: log) {
            try? store?.archive(HistoryRecord(title: state.title, state: state))
            replacedSessionTitle = state.title
        }
        log = incoming
        outbox = Outbox()
        refresh()
    }

    /// Offered on every reconnect, so a watch that has never seen them catches up without
    /// anyone having to think about it.
    private func sharePresets() {
        guard !presets.isEmpty else { return }
        let payload = encode(.presets(presets))
        Task { _ = await sendLive(payload) }
    }

    /// Offered alongside the presets on reconnect, so the watch's flip button knows which
    /// way the phone is currently reading before it sends the opposite.
    private func shareDisplay() {
        guard display.hasBeenSet else { return }
        let payload = encode(.display(display))
        Task { _ = await sendLive(payload) }
    }

    private func requestSnapshot(_ packet: InboundPacket) {
        packet.reply?(encode(.snapshot(log)))
    }

    /// Tells the counterpart what we have instead, which is how it learns the session it is
    /// offering is over.
    private func replyWithOurs(_ packet: InboundPacket) {
        packet.reply?(encode(.snapshot(log)))
    }

    /// Throttled, but never dropped: a change that arrives inside the window is published
    /// when the window closes. The application context holds one value, and it is the only
    /// thing a counterpart sees at cold launch, so it must end up holding the newest state
    /// rather than whichever update happened to win the race.
    private func publishSnapshot(force: Bool) {
        let elapsed = Date().timeIntervalSince(lastSnapshotPublished)
        guard force || elapsed >= snapshotInterval else {
            scheduleSnapshot(after: snapshotInterval - elapsed)
            return
        }
        snapshotPending = false
        lastSnapshotPublished = Date()
        transport.publishSnapshot(encode(.snapshot(log)))
    }

    private func scheduleSnapshot(after delay: TimeInterval) {
        guard !snapshotPending else { return }
        snapshotPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard let self, self.snapshotPending else { return }
            self.snapshotPending = false
            self.lastSnapshotPublished = Date()
            self.transport.publishSnapshot(self.encode(.snapshot(self.log)))
        }
    }

    private func encode(_ wire: Wire) -> Data {
        (try? wire.encoded()) ?? Data()
    }

    private func refresh() {
        state = SessionReducer.state(of: log)
        if concludeIfFinished() { return }
        persist()
    }

    private func persist() {
        try? store?.save(ActiveSession(log: log, outbox: outbox, retired: retired))
    }
}
