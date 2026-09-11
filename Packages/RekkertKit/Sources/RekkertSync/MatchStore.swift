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

    private var outbox: Outbox
    private let device: DeviceID
    private let transport: any PeerTransport
    private let store: SessionStore?
    private var lastSnapshotPublished = Date.distantPast
    private var isFlushing = false
    private var needsFlush = false
    private let snapshotInterval: TimeInterval

    public init(
        device: DeviceID,
        transport: any PeerTransport,
        store: SessionStore? = nil,
        session: ActiveSession? = nil,
        snapshotInterval: TimeInterval = 1
    ) {
        self.device = device
        self.transport = transport
        self.store = store
        self.snapshotInterval = snapshotInterval
        self.log = session?.log ?? MatchLog()
        self.outbox = session?.outbox ?? Outbox()
        self.state = SessionReducer.state(of: self.log)
    }

    // MARK: - Local mutations

    public func configure(_ setup: SessionSetup) { record(.configure(setup)) }
    public func tap(court: Int = 0, team: TeamSide) { record(.point(court: court, team: team)) }
    public func setScore(court: Int, points: BySide<Int>) { record(.setScore(court: court, points: points)) }
    public func chooseServeSide(_ court: ServeCourt) { record(.chooseServeSide(court)) }
    public func confirmRound() { record(.confirmRound) }
    public func nextRound() { record(.nextRound) }
    public func finish() { record(.finish) }

    public var canUndo: Bool { log.lastUndoableEvent() != nil }

    public func undoLast() {
        guard let target = log.lastUndoableEvent() else { return }
        record(.undo(target.id))
    }

    public func startNewSession() {
        log = MatchLog()
        outbox = Outbox()
        replacedSessionTitle = nil
        refresh()
    }

    public func acknowledgeReplacedSession() {
        replacedSessionTitle = nil
    }

    // MARK: - Sync

    public func run() async {
        transport.activate()
        // The inbound consumers must be live before any anti-entropy round trip, or two
        // devices starting at once would each block waiting for a reply the other cannot
        // yet produce.
        async let packets: Void = consumeInbound()
        async let reachability: Void = consumeReachability()
        async let initial: Void = synchronise()
        _ = await (packets, reachability, initial)
    }

    private func consumeInbound() async {
        for await packet in transport.inbound {
            handle(packet)
            // Never await an outbound round trip here: the peer may be waiting on a reply
            // that only this loop can deliver.
            Task { await self.flush() }
        }
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

        guard let reply = await transport.sendLive(payload) else { return }
        if case .hello(_, let vector)? = try? Wire.decode(reply) {
            outbox.acknowledge(upTo: vector)
            persist()
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
            guard sessionID == log.sessionID else { return requestSnapshot(packet) }
            packet.reply?(encode(.events(sessionID: log.sessionID, events: log.events(missingRelativeTo: vector))))

        case .events(let sessionID, let events):
            guard sessionID == log.sessionID else { return requestSnapshot(packet) }
            if log.merge(events) { refresh() }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.vector)))

        case .snapshot(let incoming):
            if incoming.isEmpty {
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

    private func requestSnapshot(_ packet: InboundPacket) {
        packet.reply?(encode(.snapshot(log)))
    }

    private func publishSnapshot(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSnapshotPublished) >= snapshotInterval else { return }
        lastSnapshotPublished = now
        transport.publishSnapshot(encode(.snapshot(log)))
    }

    private func encode(_ wire: Wire) -> Data {
        (try? wire.encoded()) ?? Data()
    }

    private func refresh() {
        state = SessionReducer.state(of: log)
        persist()
    }

    private func persist() {
        try? store?.save(ActiveSession(log: log, outbox: outbox))
    }
}
