import CryptoKit
import Foundation
import Observation
import RekkertCore

@Observable
public final class MatchStore {
    public private(set) var log: MatchLog
    public private(set) var state: SessionState?
    public private(set) var isReachable = false
    public private(set) var isPairReachable = false
    /// Set when a peer's session replaced ours and the discarded one had real scores in
    /// it. It was archived to history first; this just lets the UI say so.
    public private(set) var replacedSessionTitle: String?
    /// The session that just ended, so the app can show how it went instead of dropping
    /// straight back to the start. Local to this device and deliberately not persisted — it
    /// is a curtain call, not state worth resuming.
    public private(set) var lastResult: SessionState?
    /// The session as it stood one event before it ended, when that event can be taken
    /// back. The escape hatch for a misclick that happened to win the match: by the time
    /// the result is on screen the log has been filed away, so the way back has to be
    /// worked out while it is still in hand.
    public private(set) var resultRewind: RewindableResult?
    /// Which end of a shared session this device is on.
    public private(set) var role: SessionRole
    /// Saved configurations. Edited on the phone, readable on both.
    public private(set) var presets = PresetLibrary()
    /// How the phone draws its scoreboard. Shared so the watch can flip it from the wrist;
    /// only the phone acts on it.
    public private(set) var display = DisplayPreferences()
    /// When the watch buzzes for a point. Shared so either device can set it; only the watch
    /// acts on it, having the only wrist between them.
    public private(set) var haptics = HapticPreferences()
    /// One point, just played, on a board that just moved. Everything that is not that is
    /// filtered out here rather than left to the listener — see `announce(_:before:after:)`.
    @ObservationIgnored public var onPoint: ((ScoredPoint) -> Void)?
    /// What a phone and its own watch say to each other about a workout. `MatchStore` only
    /// carries these — the workout is none of its business — but this is the channel that
    /// already exists between exactly those two devices, and no other.
    @ObservationIgnored public var onWorkout: ((WorkoutSignal) -> Void)?
    /// Joining somebody's match, asked for from the wrist. Same two devices as the workout,
    /// and the same shape: the watch hands the code to the phone and is told how it went — and
    /// is told the code of a match the phone is on, to reach the host itself when the phone
    /// cannot.
    @ObservationIgnored public var onSharing: ((SharingSignal) -> Void)?
    /// This device is off a match that belongs to somebody else — its watch stepped off and
    /// took it along, or something of its own was started on top. Whatever is holding a link to
    /// the host open has to let go of it. Fired as the session is dropped: after, when something
    /// of this device's own is started, and before, when its watch stepped off, so nothing said
    /// on the way off reaches the host.
    @ObservationIgnored public var onLeft: (() -> Void)?
    /// The last thing this device said about its own workout, so a reconnect can say it
    /// again. The whole signal rather than the moment it started: a held clock carries the
    /// reading it stopped at, and repeating that later is still the truth. Live state,
    /// deliberately not persisted: a "running" restored from disk would be a lie the moment
    /// either app is relaunched.
    @ObservationIgnored private var announcedWorkout: WorkoutSignal?
    @ObservationIgnored private var announcedStandby: SharingSignal?

    private var outbox: Outbox
    /// This install's own id. Public because an event carries its author's, and telling the
    /// two apart is the whole of "did somebody else score that".
    public let device: DeviceID
    /// The other half of this pair — a phone's own watch, or a watch's own phone — learnt from
    /// its hello and kept across launches. The first packets after a cold start come off the
    /// pair's persisted channels, before any hello, and "is this the pair's own match" has to be
    /// answered on them. A stale id matches events nobody is making, and the next hello replaces it.
    @ObservationIgnored private var pairedDevice: DeviceID?

    /// Whether that point was put in by one of these two devices rather than by somebody else.
    /// A phone propped at the net post is still you, so a point tapped on it is not news to
    /// the wrist in the way a partner's tap is.
    public func isOurs(_ author: DeviceID) -> Bool {
        author == device || author == pairedDevice
    }
    private let transport: any PeerTransport
    private let store: SessionStore?
    private var lastSnapshotPublished = Date.distantPast
    private var isFlushing = false
    private var retryPatience = 1
    private static let maximumRetryPatience = 8
    private var snapshotPending = false
    /// With the session: event ids start again at one in every match, so the first events of the
    /// next one would otherwise read as the batch already queued.
    private var queued = QueueLedger()
    private var retired: [UUID]
    /// The retired sessions that were called off rather than kept. The retirement notice
    /// carries it, so a counterpart that missed the ending does not file a match nobody wanted.
    private var discarded: [UUID]
    /// What the counterpart on the paired channel says it is. A guest's watch must not offer
    /// to end a match that belongs to whoever started it.
    private var pairedRole: SessionRole
    /// The session this device was last a guest on, kept past the watch dropping its role.
    private var guestOf: UUID?
    /// A step down to solo that the pair may not have heard, since a reconnect otherwise keeps
    /// quiet about solo.
    private var roleIsUnsaid = false
    /// Waiting to be handed somebody else's session. Readable so the screen that asked can
    /// step aside when it has been, which the role alone does not say for a guest walking
    /// back in.
    public private(set) var isJoining = false
    private var joinRefuses: UUID?
    /// The logs the last few sessions ended on, by session id. The outbox is cleared with
    /// the session, so this is the only copy of the point that ended a match once it has
    /// been filed — and the thing to hand a counterpart that was out of reach for it.
    private var farewells: [UUID: MatchLog]
    /// Oldest ending first, which is the order they are let go of in.
    private var farewellsInOrder: [UUID]
    /// The session this device stepped off, so a peer still on it — the watch on the same
    /// wrist, or a host whose link has not been cut yet — cannot hand it straight back.
    private var leftSessionID: UUID?
    /// A session the pair is off together: one half stepped off and the other has said it
    /// followed. Refused from everybody, the pair included — a host packet still in flight, or
    /// a snapshot the pair sent before it heard, would otherwise put the match straight back —
    /// until the pair says it is a guest again. Only a phone can walk back in, and that is its
    /// watch's cue to follow.
    private var counterpartLeftSessionID: UUID?
    /// Which session the result on screen came from, so taking it back can drop the record
    /// filed for it.
    private var concludedSessionID: UUID?
    /// The session last looked at for a result taken back, so the look is taken once.
    private var checkedTakeBack: UUID?
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
        self.discarded = session?.discarded ?? []
        self.role = session?.role ?? .solo
        self.pairedRole = session?.pairedRole ?? .solo
        self.guestOf = session?.guestOf
        self.leftSessionID = session?.leftSessionID
        self.counterpartLeftSessionID = session?.counterpartLeftSessionID
        self.pairedDevice = session?.pairedDevice
        self.device = device
        self.transport = transport
        self.store = store
        self.snapshotInterval = snapshotInterval
        self.log = session?.log ?? MatchLog()
        self.outbox = session?.outbox ?? Outbox()
        let saved = store?.farewells() ?? []
        self.farewells = Dictionary(saved.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
        self.farewellsInOrder = saved.reversed().map(\.sessionID)
        self.presets = store?.loadPresets() ?? PresetLibrary()
        self.display = store?.loadDisplay() ?? DisplayPreferences()
        self.haptics = store?.loadHaptics() ?? HapticPreferences()
        self.state = SessionReducer.state(of: self.log)
    }

    // MARK: - Local mutations

    public func configure(_ setup: SessionSetup) {
        // Something of this device's own, started on nothing. A guest between two of the host's
        // matches, or one still waiting on a join, is stepping off — as starting a preset is.
        if log.isEmpty, role == .guest || isJoining { startNewSession() }
        resetDisplayForNewMatch()
        record(.configure(setup, at: Date()))
    }
    public func tap(round: Int = 0, court: Int = 0, team: TeamSide) {
        record(.point(round: round, court: court, team: team))
    }

    public func setScore(round: Int = 0, court: Int, points: BySide<Int>) {
        record(.setScore(round: round, court: court, points: points))
    }

    public func chooseServeSide(_ court: ServeCourt) { record(.chooseServeSide(court)) }

    /// Hands service to the other team, each side keeping its own first server. Sending the
    /// resulting order rather than "swap" means two devices correcting it together agree.
    public func swapServingTeam(round: Int = 0, court: Int = 0) {
        guard let order = state?.serveOrder(round: round, court: court) else { return }
        record(.setServeOrder(round: round, court: court, order: order.swappingTeams()))
    }

    /// The other partner on the serving side takes the serve — and, since partners never
    /// serve back to back, every later turn of that side's.
    public func swapServingPlayer(round: Int = 0, court: Int = 0) {
        guard let order = state?.serveOrder(round: round, court: court),
              let serving = state?.serve(round: round, court: court)?.slot.team else { return }
        record(.setServeOrder(round: round, court: court, order: order.swappingPlayers(of: serving)))
    }

    /// Recorded rather than sent through `configure`, which would reset the board's flip.
    public func setChangeEnds(_ rule: ChangeEndsRule) {
        guard let current = state?.changeEnds, current != rule else { return }
        switch state {
        case .traditional(var session):
            session.rules.changeEnds = rule
            record(.configure(.traditional(rules: session.rules, teams: session.teams)))
        case .friendly(var session):
            session.rules.changeEnds = rule
            record(.configure(.friendly(session)))
        case .tournament, .winnerCourt, .pointCount, .none:
            break
        }
    }

    public func setRoundConfirmed(_ round: Int, _ isConfirmed: Bool = true) {
        record(.setRoundConfirmed(round: round, isConfirmed: isConfirmed))
    }

    public func setRoundCancelled(_ round: Int, _ isCancelled: Bool = true) {
        record(.setRoundCancelled(round: round, isCancelled: isCancelled))
    }
    /// Draws the next round. Addressed to the round on screen now, so two devices tapping
    /// at once still produce one round.
    public func nextRound() {
        switch state {
        // -1 when nothing has been drawn yet, so the first round is "the one after none".
        case .tournament(let tournament):
            record(.nextRound(after: tournament.rounds.count - 1, at: Date()))
        case .friendly(let session):
            record(.nextRound(after: session.rounds.count - 1, at: Date()))
        case .traditional, .winnerCourt, .pointCount, .none:
            break
        }
    }

    /// Draws the tournament round in play again with these players sitting it out. Lands
    /// only while nothing has been played in it.
    public func redrawRound(sittingOut sitOuts: [PlayerID]) {
        guard case .tournament(let tournament) = state, let last = tournament.rounds.indices.last else { return }
        record(.nextRound(after: last - 1, at: Date(), sitOuts: sitOuts))
    }

    /// The whistle in winner court, and calling a friendly round off where it stands.
    public func endRound() {
        switch state {
        case .winnerCourt(let session):
            record(.endRound(round: session.completedRounds.count, at: Date()))
        case .friendly(let session):
            record(.endRound(round: session.currentIndex, at: Date()))
        case .traditional, .tournament, .pointCount, .none:
            break
        }
    }
    /// Ends the session and keeps it in history if anything was played.
    public func finish() {
        guard canEndSession else { return }
        record(.finish(archive: true))
    }

    /// Ends the session and throws it away — for calling a match off rather than recording
    /// how far it got.
    public func discardSession() {
        guard canEndSession else { return }
        record(.finish(archive: false))
    }

    /// Whether this device may end the match for everybody. A guest scores, corrects and
    /// undoes like anyone else, but the match belongs to the people who started it — and the
    /// watch has to be told, because it cannot see whose phone it is paired to.
    ///
    /// A convention rather than a boundary: with nobody holding the ring there is nothing to
    /// stop a modified client appending the event itself. These are four people on a court.
    public var canEndSession: Bool {
        role == .host || (
            role != .guest && guestOf != log.sessionID
                && (pairedRole != .guest || isThePairsOwn(log, strictly: true))
        )
    }

    /// Says that this phone's score is the score, for everybody.
    ///
    /// The merge loses nothing, which is the right default: a guest that went on scoring while
    /// the host's phone was in a pocket kept real points, and an overwrite would throw them
    /// away. But a union can still come to a number nobody in front of it recognises — usually
    /// because the same rally was scored on two phones — and then somebody has to be able to
    /// say what it actually is.
    ///
    /// A `.restore` of the state as it stands here, appended to the same session. It carries
    /// the highest Lamport stamp, so it folds last everywhere and the reducer replays straight
    /// to this number. Deliberately not a new session: retiring this one and starting another
    /// would file the match everybody is playing away to History and hand it back as somebody
    /// else's, which is the loud version of the problem it is meant to fix.
    ///
    /// A line in the sand rather than a lock. Anything scored before it is overridden; a tap
    /// made after it on a phone still out of earshot lands on top — which is why it is only
    /// worth offering while the others are there to hear it.
    public func settleScore() {
        guard canSettleScore, let state else { return }
        record(.restore(state))
    }

    /// Whose score it is to settle. The same convention as the whistle: a guest scores and
    /// corrects like anyone else, but the match belongs to whoever started it.
    public var canSettleScore: Bool {
        guard let state, !state.isFinished else { return false }
        return role == .host
    }

    /// Opens this session to other phones. Changes nothing about the session itself — only
    /// what this device is willing to be told about it.
    public func startSharing() {
        guard role != .guest else { return }
        role = .host
        // A search left running underneath would conclude on the first guest to say hello
        // and make this phone a guest on its own match.
        isJoining = false
        persist()
        shareRole()
    }

    public func stopSharing() {
        guard role == .host else { return }
        role = .solo
        persist()
        shareRole()
    }

    /// Waits to be handed somebody else's session. Until one arrives this device goes on
    /// showing whatever it had.
    ///
    /// `steppingOff` when this device is on somebody's match, or hosting one, and was given a
    /// different code: whatever that match still sends is not the answer to this join.
    public func beginJoining(steppingOff: Bool = false) {
        isJoining = true
        joinRefuses = steppingOff && !log.isEmpty ? log.sessionID : nil
        // Say hello straight away rather than waiting to be spoken to. The counterpart
        // answers a session id it does not recognise with its own, which is exactly the
        // offer being waited for.
        Task { await synchronise() }
    }

    public func cancelJoining() {
        isJoining = false
        joinRefuses = nil
    }

    private func tellThePairItLeft(_ session: UUID) {
        let notice = encode(.left(sessionID: session))
        transport.queue(notice)
        Task { _ = await sendLive(notice) }
    }

    /// A watch on a match through its phone holds no role of its own: the phone's decides.
    public func followPairedDevice() {
        guard role == .guest, !isJoining else { return }
        if !log.isEmpty { guestOf = log.sessionID }
        role = .solo
        roleIsUnsaid = true
        persist()
        shareRole()
    }

    /// Steps off a shared session without ending it for anybody else.
    ///
    /// Deliberately not `startNewSession()`, which retires the session id: retiring is how a
    /// device says a match is over, so a guest that left and came back would refuse the
    /// host's session and announce its retirement — ending the match it was trying to rejoin.
    public func leaveSharedSession() {
        leftSessionID = log.sessionID
        // The watch on the same wrist mirrors this match and would go on showing it — and
        // offering it back — unless told. Queued as well as sent: it may not be running.
        tellThePairItLeft(log.sessionID)
        dropSession()
    }

    /// Clears the match without retiring it. Remembering it as left is the leaver's alone: the
    /// other half of the pair only ever hears of it from the leaver, and has to be free to
    /// follow the same phone back in.
    private func dropSession() {
        if keepsHistory, log.hasProgress, let state = SessionReducer.state(of: log) {
            file(state, from: log)
        }
        log = MatchLog()
        outbox = Outbox()
        role = .solo
        isJoining = false
        lastResult = nil
        resultRewind = nil
        refresh()
        // The application context and the fan-out's cache still hold the match just dropped,
        // and would hand it to a counterpart waking up later — after the queued notice has
        // already landed on an empty log and done nothing. An empty snapshot says "nothing
        // here", which is what a counterpart arriving now should be told.
        transport.publishSnapshot(encode(.snapshot(log)))
        transport.forgetSnapshot()
        shareRole()
    }

    /// The live copy is encoded as it goes out, so one that runs late says the role as it is
    /// then rather than as it was — a guest's landing after the Leave would say otherwise.
    private func shareRole() {
        transport.queue(encode(.role(role)))
        Task { _ = await sendLive(encode(.role(role))) }
    }

    // MARK: - Presets

    public func savePreset(_ preset: Preset) {
        var updated = presets
        updated.save(preset)
        apply(updated, publish: true)
    }

    public func updatePreset(_ id: UUID, _ change: (inout Preset) -> Void) {
        var updated = presets
        updated.update(id, change)
        apply(updated, publish: true)
    }

    public func movePresets(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updated = presets
        updated.move(fromOffsets: source, toOffset: destination)
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

    /// Picks an archived session back up as a fresh one, carrying its score across. The
    /// copy in history stays where it is; this is a continuation, not a move.
    public func resume(_ archived: SessionState, from recordID: UUID? = nil) {
        guard let resumable = archived.resumed() else { return }
        startNewSession()
        resetDisplayForNewMatch()
        if keepsHistory, let recordID, let timeline = store?.timeline(recordID) {
            try? store?.save(carry: TimelineCarry(sessionID: log.sessionID, reason: .resumed, timeline: timeline))
        }
        record(.restore(resumable.restarted(at: Date())))
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

    /// Swaps which side is drawn blue, on both devices — unlike mirroring, this is about
    /// which team you are rather than where you are standing.
    public func setTeamColorsSwapped(_ swapped: Bool) {
        guard swapped != display.areColorsSwapped else { return }
        apply(display.setting(colorsSwapped: swapped), publish: true)
    }

    public func toggleTeamColors() {
        setTeamColorsSwapped(!display.areColorsSwapped)
    }

    /// Changes how the watch buzzes, from either device. Absolute values rather than steps,
    /// so a repeated delivery settles on the same answer instead of walking past it.
    public func setHaptics(
        mode: HapticMode? = nil,
        onlyWhenSomeoneElseScores: Bool? = nil,
        strength: HapticStrength? = nil,
        tapAnywhere: Bool? = nil
    ) {
        let next = haptics.setting(
            mode: mode,
            onlyWhenSomeoneElseScores: onlyWhenSomeoneElseScores,
            strength: strength,
            tapAnywhere: tapAnywhere
        )
        guard next.mode != haptics.mode
            || next.onlyWhenSomeoneElseScores != haptics.onlyWhenSomeoneElseScores
            || next.strength != haptics.strength
            || next.tapAnywhere != haptics.tapAnywhere
        else { return }
        apply(next, publish: true)
    }

    /// Who this pair of devices is playing as in the current tournament, if they have said.
    public var me: PlayerID? {
        guard let me = haptics.me, me.session == log.sessionID else { return nil }
        return me.player
    }

    public func setMe(_ player: PlayerID?) {
        guard player != me else { return }
        apply(haptics.choosing(me: player.map { Me(session: log.sessionID, player: $0) }), publish: true)
    }

    /// A match starts the way everyone reads it — us blue on the left, them orange on the
    /// right — whatever the last one was flipped to. A flip answers where you are standing
    /// and which side of the draw you are on today, and neither survives the match it was
    /// made for. Set here rather than on `startNewSession()`, which taking back a result
    /// also goes through: that reopens the match you were already reading.
    private func resetDisplayForNewMatch() {
        guard !display.isDefault else { return }
        apply(display.reset(), publish: true)
    }

    private func apply(_ preferences: HapticPreferences, publish: Bool) {
        haptics = preferences
        try? store?.save(preferences)
        guard publish else { return }
        let payload = encode(.haptics(preferences))
        transport.queue(payload)
        Task { _ = await sendLive(payload) }
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

    public var canUndo: Bool { !undoTargets(UndoScope()).isEmpty }

    public func undoLast() {
        for target in undoTargets(UndoScope()) { record(.undo(target.id)) }
    }

    /// Undo on one court's own screen: the last thing scored there, not on the court next door.
    public func canUndo(round: Int, court: Int) -> Bool { !undoTargets(UndoScope(round: round, court: court)).isEmpty }

    public func undoLast(round: Int, court: Int) {
        for target in undoTargets(UndoScope(round: round, court: court)) { record(.undo(target.id)) }
    }

    private struct UndoScope: Hashable {
        var round: Int?
        var court: Int?
    }

    /// Worked out by replaying the log, and asked on every redraw, so kept until the log grows. A
    /// session's log only ever grows, so its id and length say whether the answer still holds.
    @ObservationIgnored private var knownUndoTargets: [UndoScope: (session: UUID, count: Int, targets: [MatchEvent])] = [:]

    private func undoTargets(_ scope: UndoScope) -> [MatchEvent] {
        if let known = knownUndoTargets[scope], known.session == log.sessionID, known.count == log.events.count {
            return known.targets
        }
        let targets = if let round = scope.round, let court = scope.court {
            log.undoTargets(round: round, court: court)
        } else {
            log.undoTargets()
        }
        knownUndoTargets[scope] = (log.sessionID, log.events.count, targets)
        return targets
    }

    public func startNewSession() {
        // Starting something of your own while on somebody else's match is stepping off it,
        // not ending it. Retiring it would answer the host's next packet with "this ended
        // here", and the host would end the match for everyone still playing it.
        let leaving = !canEndSession && !log.isEmpty
        // A guest whose shared match has already ended is still a guest of that host, and
        // still on the link: the host's next match would land here. Starting its own is
        // stepping off just the same — and so is giving up on a join that never concluded.
        let steppingOff = role == .guest || isJoining
        if leaving {
            leftSessionID = log.sessionID
            tellThePairItLeft(log.sessionID)
        } else {
            retire(log.sessionID)
            leftSessionID = nil
        }
        clearSession()
        if role == .guest {
            role = .solo
            // The watch on this wrist read this phone as a guest, and would go on offering to
            // leave a match that is now this phone's own rather than to end it.
            shareRole()
        }
        refresh()
        if leaving || steppingOff { onLeft?() }
    }

    /// A fresh log, and nothing left over from the one before. The role is untouched.
    private func clearSession() {
        log = MatchLog()
        outbox = Outbox()
        replacedSessionTitle = nil
        lastResult = nil
        resultRewind = nil
        isJoining = false
        counterpartLeftSessionID = nil
    }

    /// A session is retired where it ends, and stays retired, so a counterpart that has not
    /// caught up cannot hand it back. `archive` is how it ended, for the notice that tells it.
    private func retire(_ id: UUID, archive: Bool = true) {
        guard !log.isEmpty, !retired.contains(id) else { return }
        retired.append(id)
        if !archive { discarded.append(id) }
        if retired.count > 20 { retired.removeFirst(retired.count - 20) }
        discarded.removeAll { !retired.contains($0) }
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
            // Filed under the session's own id, so archiving twice replaces rather than
            // duplicates — and so taking the result back knows which record to remove.
            file(finished, from: log)
        }
        // Nothing to celebrate about a session that was called off or never played.
        lastResult = keeping ? finished : nil
        // Tied to the result screen: the way back is a button on it, so offering one
        // without the other would be a capability nothing can reach.
        resultRewind = keeping ? rewinding(log) : nil

        // The counterpart has to learn this before the log disappears from here, or it
        // will keep offering the session back as though it were still live.
        let farewell = encode(.snapshot(log))
        transport.queue(farewell)
        transport.publishSnapshot(farewell)
        // Sent, then forgotten: whoever is here now needs to be told, and whoever arrives
        // afterwards must not be handed a finished match as though it were live.
        transport.forgetSnapshot()
        lastSnapshotPublished = Date()
        Task { _ = await sendLive(farewell) }

        concludedSessionID = log.sessionID
        retire(log.sessionID, archive: wasAskedToArchive)
        remember(farewell: log)
        log = MatchLog()
        outbox = Outbox()
        state = nil
        persist()
        return true
    }

    /// Bounded tighter than the retired list: these are whole logs.
    private func remember(farewell: MatchLog) {
        farewells[farewell.sessionID] = farewell
        farewellsInOrder.removeAll { $0 == farewell.sessionID }
        farewellsInOrder.append(farewell.sessionID)
        while farewellsInOrder.count > SessionStore.farewellsKept {
            farewells.removeValue(forKey: farewellsInOrder.removeFirst())
        }
        try? store?.save(farewell: farewell)
    }

    public func acknowledgeReplacedSession() {
        replacedSessionTitle = nil
    }

    /// Dismisses the result screen.
    public func acknowledgeResult() {
        lastResult = nil
        resultRewind = nil
    }

    /// Takes the result back: puts the session in play again as it stood before the event
    /// that ended it, and drops the record that was filed for it.
    ///
    /// It comes back under a fresh session id rather than resurrecting the old one, which
    /// both devices have already retired and would refuse to be handed back. A guest stays a
    /// guest: the host, standing on nothing since the ending, takes the reopened match up, and
    /// it is still theirs.
    public func undoResult() {
        guard let rewind = resultRewind else { return }
        let filed = concludedSessionID
        // Not `startNewSession()`: the log is already empty and retired, and a guest taking
        // a result back is not stepping off — the host takes the reopened match up.
        leftSessionID = nil
        clearSession()
        // The same session wherever it is taken back, so two devices doing it at once reopen
        // one match rather than splitting it in two.
        if let filed { log = MatchLog(sessionID: Self.reopening(filed), createdAt: farewells[filed]?.createdAt ?? Date()) }
        if keepsHistory, let filed, let ended = farewells[filed] {
            try? store?.save(carry: .takingBack(
                ended, into: log.sessionID, carried: store?.carry(for: filed), me: me(in: filed)
            ))
        }
        record(.restore(rewind.state, takingBack: filed))
        if keepsHistory, let filed { try? store?.deleteHistory(filed) }
    }

    /// A name for the match a session is taken back into, the same on every device.
    static func reopening(_ ended: UUID) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("rekkert.reopened|".utf8) + withUnsafeBytes(of: ended.uuid) { Data($0) }).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Files a session under its own id, with the timeline its log leaves behind. The one way
    /// in, so finishing, stepping off and being displaced all keep the same things.
    private func file(_ state: SessionState, from log: MatchLog) {
        let carry = store?.carry(for: log.sessionID)
        let span = log.playedSpan
        // A result taken back is the same match going on, so it started when that one did.
        let continued = carry?.reason == .takenBack ? carry?.startedAt : nil
        try? store?.archive(HistoryRecord(
            id: log.sessionID, title: state.title, state: state,
            startedAt: continued ?? span?.lowerBound ?? log.createdAt,
            playedUntil: span?.upperBound
        ))
        let timeline = MatchTimeline.make(from: log, continuing: carry, me: me(in: log.sessionID))
        if !timeline.isEmpty { try? store?.archive(timeline, for: log.sessionID) }
    }

    /// A result taken back elsewhere — on the watch, or by the host — arrives as a new session
    /// restored from it. The record this device filed for the old one goes, since this is the
    /// same match going on, and what it had been through is carried into this one.
    private func absorbTakeBack() {
        guard keepsHistory, !log.isEmpty, checkedTakeBack != log.sessionID else { return }
        checkedTakeBack = log.sessionID
        guard let named = log.takesBack else { return }
        let takenBack = store?.historyRecord(named) == nil ? endedHere(named) ?? named : named

        if store?.carry(for: log.sessionID) == nil {
            let carry: TimelineCarry?
            if let ended = farewells[takenBack] {
                carry = .takingBack(ended, into: log.sessionID, carried: store?.carry(for: takenBack), me: me(in: takenBack))
            } else if var timeline = store?.timeline(takenBack) {
                // Without the log to take the last event back from, the point that won it is
                // the one taken back.
                if case .match? = timeline.entries.last?.ended { timeline.entries.removeLast() }
                carry = TimelineCarry(
                    sessionID: log.sessionID, reason: .takenBack,
                    startedAt: store?.historyRecord(takenBack)?.startedAt, timeline: timeline
                )
            } else {
                carry = nil
            }
            if let carry { try? store?.save(carry: carry) }
        }
        try? store?.deleteHistory(takenBack)
    }

    private func me(in session: UUID) -> PlayerID? {
        guard let me = haptics.me, me.session == session else { return nil }
        return me.player
    }

    /// The state one undo short of the end, or `nil` when there is nothing to take back or
    /// taking it back would not actually reopen the session.
    private func rewinding(_ ended: MatchLog) -> RewindableResult? {
        let targets = ended.undoTargets()
        guard let target = targets.first else { return nil }
        let undoesAPoint: Bool
        switch target.kind {
        case .point, .setScore: undoesAPoint = true
        default: undoesAPoint = false
        }
        // A misclick that won the match is anybody's to take back. The ending somebody called is
        // only theirs: a guest reopening the host's Finish would be a match nobody hosts.
        guard undoesAPoint || canEndSession else { return nil }

        var rewound = ended
        for target in targets { rewound.append(.undo(target.id), from: device) }
        guard let state = SessionReducer.state(of: rewound), !state.isFinished else { return nil }
        return RewindableResult(state: state, undoesAPoint: undoesAPoint)
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
        // Never await an outbound round trip here: the peer may be waiting on a reply
        // that only this loop can deliver.
        for await packet in transport.inbound {
            handle(packet)
        }
    }

    /// Reachability does not always change when a send fails, and a phone cannot wake the
    /// watch app the way a watch can wake the phone — so without this the outbox could sit
    /// full with nothing ever prompting another attempt.
    private func retryUndelivered() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: retryInterval * retryPatience)
            guard !outbox.isEmpty else {
                retryPatience = 1
                continue
            }

            if transport.isReachable {
                await flush()
                retryPatience = outbox.isEmpty ? 1 : min(retryPatience * 2, Self.maximumRetryPatience)
            } else {
                retryPatience = 1
                queuePending()
            }
        }
    }

    /// Hands the backlog to the durable channel, which is the only one that reaches a
    /// counterpart whose app is not running. Merging is idempotent, so a duplicate that
    /// also arrives live costs nothing.
    private func queuePending() {
        let fresh = queued.admitting(outbox.pending, in: log.sessionID)
        guard !fresh.isEmpty else { return }
        transport.queue(encode(.events(sessionID: log.sessionID, events: fresh)))
    }

    private func consumeReachability() async {
        for await reachable in transport.reachability {
            isReachable = reachable
            isPairReachable = transport.isPairReachable
            retryPatience = 1
            if reachable { await synchronise() }
        }
    }

    /// Anti-entropy. Cheap enough to call on activation, on reachability changes and
    /// whenever the app comes to the foreground.
    public func synchronise() async {
        await askWhatIsMissing()
        publishSnapshot(force: true)
        sharePresets()
        shareDisplay()
        shareHaptics()
    }

    /// The hello, and whatever it brings back. On its own when a gap has been noticed, which
    /// wants the question asked and not everything else said again.
    private func askWhatIsMissing() async {
        isReachable = transport.isReachable
        isPairReachable = transport.isPairReachable
        // Coverage rather than the raw vector: this is the "what am I missing" question, and
        // the highest number seen is the wrong answer to it when something below is absent.
        guard let payload = try? Wire.hello(sessionID: log.sessionID, vector: log.coverage, from: device).encoded() else { return }
        // Through the timeout, like every other send: `consumeReachability` awaits this, so a
        // hello that was never answered would stop every later reconnect from being noticed.
        if let reply = await sendLive(payload) {
            handle(InboundPacket(payload: reply))
        }
        await flush()
    }

    private func record(_ kind: EventKind) {
        let before = state
        let session = log.sessionID
        let event = log.append(kind, from: device, at: MatchEvent.stamp())
        outbox.enqueue(event)
        // Reduced before `refresh()` rather than read after it: the point that wins a match
        // takes the log and the state with it, and this is the only moment the board it
        // produced still exists.
        let after = SessionReducer.state(of: log)
        refresh()
        announce([event], before: before, after: after, session: session)
        publishSnapshot(force: false)
        push([event], in: session)
    }

    /// Tells whoever is listening that a point was played, and only when one really was.
    ///
    /// Four things have to be true, and every one of them silences a way this could go off
    /// when nothing happened:
    ///
    /// - It is a `.point`. Taking one back appends an `.undo` rather than removing anything,
    ///   and a score put right by hand or a whole state restored are not points being played.
    /// - There is exactly one in the batch. More than one is a catch-up — a watch that has
    ///   been asleep is handed everything it missed at once, and counting those out on
    ///   somebody's wrist would be an alarm rather than a score.
    /// - The board actually moved. A point for a round already finished, or a tournament
    ///   court already confirmed, is dropped by the reducer and changes nothing.
    /// - There is still a session. A farewell carries the whole log of a match already over.
    private func announce(
        _ events: [MatchEvent],
        before: SessionState?,
        after: SessionState?,
        session: UUID
    ) {
        guard onPoint != nil, let after else { return }
        let points = events.compactMap { event -> ScoredPoint? in
            guard case .point(let round, let court, let team) = event.kind else { return nil }
            return ScoredPoint(
                team: team, round: round, court: court,
                session: session, scoredBy: event.id.device
            )
        }
        guard points.count == 1, let point = points.first else { return }
        guard moved(from: before, to: after, round: point.round, court: point.court) else { return }
        onPoint?(point)
    }

    /// Whether the board on that court reads differently than it did. Points alone are not
    /// enough: a point that wins a game puts them back to love-all, which is the same two
    /// numbers the game started with.
    private func moved(from before: SessionState?, to after: SessionState, round: Int, court: Int) -> Bool {
        let old = before.flatMap { ScoreboardSnapshot.make(from: $0, round: round, court: court) }
        guard let new = ScoreboardSnapshot.make(from: after, round: round, court: court) else { return false }
        guard let old else { return true }
        return old.points != new.points
            || old.games != new.games
            || old.completedSets != new.completedSets
            || old.isFinished != new.isFinished
    }

    private func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        await sendPending()
        isFlushing = false
    }

    private func sendPending() async {
        isReachable = transport.isReachable
        isPairReachable = transport.isPairReachable
        guard !outbox.isEmpty, transport.isReachable else { return }
        let session = log.sessionID
        guard let payload = try? Wire.events(sessionID: session, events: outbox.pending).encoded() else { return }

        guard let reply = await sendLive(payload) else {
            queuePending()
            return
        }
        acknowledge(reply, for: session)
    }

    /// On its own round trip, never queued behind a retry that one slow peer can hold for seconds.
    private func push(_ events: [MatchEvent], in session: UUID) {
        guard !events.isEmpty, transport.isReachable,
              let payload = try? Wire.events(sessionID: session, events: events).encoded()
        else { return }
        Task {
            guard let reply = await sendLive(payload) else {
                if session == log.sessionID { queuePending() }
                return
            }
            acknowledge(reply, for: session)
        }
    }

    private func acknowledge(_ reply: Data, for session: UUID) {
        guard case .hello(let answered, let vector, _)? = try? Wire.decode(reply) else {
            // Anything else is the counterpart saying it is not on the session we just
            // sent — which is the one thing that has to be acted on rather than dropped.
            return handle(InboundPacket(payload: reply))
        }
        guard answered == session, session == log.sessionID else { return }
        outbox.acknowledge(upTo: vector)
        persist()
    }

    /// WatchConnectivity does not promise to call back. A reply that never arrives would
    /// otherwise leave `isFlushing` set for the life of the app and wedge the outbox
    /// permanently — which looks exactly like one-way sync.
    ///
    /// Not a task group: a group waits for every child before it returns, and a send parked
    /// on a continuation the framework never resumes cannot see that it was cancelled. The
    /// send is left to finish on its own instead, and whatever it comes back with is dropped.
    private func sendLive(_ payload: Data) async -> Data? {
        let transport = transport
        let timeout = sendTimeout
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { once.resume(await transport.sendLive(payload)) }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(nil)
            }
        }
    }

    private func handle(_ packet: InboundPacket) {
        guard let wire = try? Wire.decode(packet.payload) else {
            // Always answer, so a peer awaiting a reply can never hang on bad input.
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))
            return
        }

        switch wire {
        case .hello(let sessionID, let vector, let sender):
            // Only the pair's: a stranger's phone is somebody else by definition, and on a
            // watch every packet arrives through its own phone anyway.
            if packet.isFromPairedDevice, let sender, sender != device, sender != pairedDevice {
                pairedDevice = sender
                persist()
            }
            // The pair coming back is what these are said again for. Every other phone's hello
            // repeated them to this one's own watch, and onto its queue whenever it was slow.
            if packet.isFromPairedDevice {
                sharePresets()
                shareDisplay()
                shareHaptics()
                shareRoleOnReconnect()
                shareWorkoutOnReconnect()
                shareStandbyOnReconnect()
            }
            guard !retired.contains(sessionID) else {
                return announceRetirement(of: sessionID, to: packet)
            }
            guard sessionID == log.sessionID else { return requestSnapshot(packet) }
            arrive(on: sessionID, from: packet)
            packet.reply?(encode(.events(sessionID: log.sessionID, events: log.events(missingRelativeTo: vector))))

        case .events(let sessionID, let events):
            if retired.contains(sessionID) {
                guard let ended = overturnedEnding(of: sessionID, by: events) else {
                    return announceRetirement(of: sessionID, to: packet)
                }
                pickBackUp(ended)
            }
            guard sessionID == log.sessionID else { return requestSnapshot(packet) }
            arrive(on: sessionID, from: packet)
            relay(events, from: packet)
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .retired(let sessionID, let archive, let farewell):
            // Only ever our own live session, and only once: concluding puts it in the
            // retired list here too, so a second notice is a no-op rather than a volley.
            if sessionID == log.sessionID, !log.isEmpty, !retired.contains(sessionID) {
                // Everything the other end had when it ended, merged rather than obeyed: the
                // log says whether the match is over. That is what lets a guest's copy that
                // won the match out of earshot end it here too — the winning point is in
                // there — while a guest that merely retired its copy ends nothing.
                if let farewell, farewell.sessionID == sessionID {
                    relay(farewell.ordered, from: packet)
                }
                // Still in play after that, so the ending has to be said. The same path the
                // `.finish` event would have taken, so the match is archived and the result
                // shown rather than quietly dropped. Only an ending from whoever may end the
                // match counts: a host hears it from its own watch, a guest from the host — and
                // never from its own watch, whose copy ending alone ends nothing of the host's.
                let isTheMatchsToEnd = packet.isFromPairedDevice ? canEndSession : role != .host
                if sessionID == log.sessionID, !log.isEmpty, isTheMatchsToEnd {
                    record(.finish(archive: archive))
                }
            }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .presets(let incoming):
            let merged = presets.adopting(incoming)
            if merged != presets { apply(merged, publish: false) }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .role(let incoming):
            let heldBefore = (pairedRole, leftSessionID, counterpartLeftSessionID)
            pairedRole = incoming
            defer {
                if heldBefore != (pairedRole, leftSessionID, counterpartLeftSessionID) { persist() }
            }
            // Dropping a session says solo, so this is the pair confirming it is off the one
            // left here. Until then it may still be pushing that session back; from now on
            // the only way it can hold that session is by having walked back in. This reads
            // solo as a drop because nothing else from a watch says it: `shareRoleOnReconnect`
            // keeps quiet about solo, and a watch never hosts.
            if incoming == .solo, let left = leftSessionID {
                leftSessionID = nil
                counterpartLeftSessionID = left
            }
            // The phone holds the whistle, so nothing this end left was a match it could step
            // off. A Leave taken on a role the watch had wrong is undone by this, or the watch
            // would refuse the phone's own match for the rest of it.
            if incoming == .host {
                leftSessionID = nil
                counterpartLeftSessionID = nil
            }
            // The phone walked back in — but only as the durable queue says it, which is the one
            // channel in step with the Leave: it carried the notice too. A live guest can be one
            // sent before the Leave that overtook it, and neither counts while this end's own
            // Leave is unconfirmed. Whatever came on the way back was refused, so ask for it.
            if incoming == .guest, packet.reply == nil, counterpartLeftSessionID != nil {
                counterpartLeftSessionID = nil
                Task { await synchronise() }
            }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .left(let sessionID):
            // Only ever from this device's own phone or watch — the shared scope does not
            // carry it — so the one match it can name is the one mirrored from there. A host
            // is not taken off its own match: that is ending it, and a watch cannot do that.
            if sessionID == log.sessionID, !log.isEmpty {
                if role == .host || isThePairsOwn(log, strictly: true) {
                    // The watch has already dropped its copy on a role it had wrong: a Leave
                    // names somebody else's match, and this one is not. Told who holds the
                    // whistle, it lets go of the refusal, and is then handed the match back.
                    shareRole()
                    offerOurSession()
                } else {
                    // Links first: what the store says on its way off is for its own watch, and
                    // said to the host it would hand the whole match out to everybody again.
                    onLeft?()
                    counterpartLeftSessionID = sessionID
                    dropSession()
                }
            }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .display(let incoming):
            let merged = display.adopting(incoming)
            if merged != display { apply(merged, publish: false) }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .haptics(let incoming):
            let merged = haptics.adopting(incoming)
            if merged != haptics { apply(merged, publish: false) }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .workout(let signal):
            // A finished workout is filed here because the watch that recorded it keeps no
            // history. Under its own id, so at-least-once delivery lands as exactly-once on
            // disk. Everything else is somebody's live state, and belongs to whoever asked.
            if keepsHistory {
                switch signal {
                case .finished(let record): try? store?.archive(record)
                case .series(let series): try? store?.archive(series)
                case .stop, .pause, .resume, .running, .paused, .idle: break
                }
            }
            onWorkout?(signal)
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .displaced(let lost):
            if packet.isFromPairedDevice { keep(lost, handedOverBy: .displacement) }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .sharing(let signal):
            // Only ever from the device in the same pocket — the scope drops this case before
            // it can reach anybody else — but said out loud here too, because acting on a
            // stranger's `.join` would be joining a match on their say-so.
            if packet.isFromPairedDevice { onSharing?(signal) }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))

        case .snapshot(let incoming):
            if retired.contains(incoming.sessionID) {
                guard let ended = overturnedEnding(of: incoming.sessionID, by: incoming.ordered) else {
                    return announceRetirement(of: incoming.sessionID, to: packet)
                }
                pickBackUp(ended)
                arrive(on: ended.sessionID, from: packet)
                relay(incoming.ordered, from: packet)
            } else if incoming.isEmpty {
                // A peer that has not started anything yet is not a competing session, but
                // it does need ours — and it cannot ask for it, since the reply it would
                // ask down is the one it just used to tell us it has nothing. Live as well
                // as queued: the queue reaches only this device's own watch, and a phone
                // saying this over Bluetooth would otherwise wait for its next hello, which
                // is its next unlock. Not while joining, though: that nothing is the host
                // between matches, and what this end holds is not what it went looking for.
                offerOurSession(live: !isJoining)
            } else if isJoining, !packet.isFromPairedDevice {
                if incoming.sessionID == joinRefuses {
                    // The match this device is walking away from, still in flight.
                } else if incoming.sessionID == log.sessionID {
                    // Already holding the match that was asked for — back from a relaunch,
                    // or handed it before the code was typed. Taken up rather than adopted:
                    // adopting would file the live match to History as displaced and drop
                    // whatever was scored here while out of reach.
                    arrive(on: incoming.sessionID, from: packet)
                    relay(incoming.ordered, from: packet)
                } else {
                    // A code was typed, so this is the session that was asked for, whatever
                    // the clocks say about which of the two was started more recently — and
                    // even if there is nothing here to weigh it against. Unless it is this
                    // device's own watch talking, which repeats what is already here and
                    // offers nothing.
                    let steppedOff = log.sessionID
                    let wasShared = !log.isEmpty && (role == .guest || pairedRole == .guest)
                    adopt(incoming)
                    // Filed all the same, but nobody needs telling: the code was typed to get here.
                    replacedSessionTitle = nil
                    role = .guest
                    isJoining = false
                    joinRefuses = nil
                    forgetLeaving(log.sessionID)
                    shareRole()
                    // Off the last shared match, for the watch on the same wrist too.
                    if wasShared {
                        leftSessionID = steppedOff
                        tellThePairItLeft(steppedOff)
                    }
                    persist()
                }
            } else if incoming.sessionID == leftSessionID, !isThePairsOwnFromThePair(incoming, packet) {
                // Stepped off this one on purpose. Whoever is still on it is not being
                // refused — nothing is retired — only not taken up again.
            } else if incoming.sessionID == counterpartLeftSessionID, !isThePairsOwnFromThePair(incoming, packet) {
                // Off this one as a pair, and neither the host's link nor the pair's own
                // packets in flight can be trusted to have caught up.
            } else if log.isEmpty, role == .host, !packet.isFromPairedDevice, !takesBackOneOfOurs(incoming) {
                // A host between matches keeps its code, and the phones dialling in bring whatever
                // they have on. That is theirs: the only match a guest can hand a host is the
                // host's own, taken back.
            } else if log.isEmpty {
                log = incoming
                forgetLeaving(incoming.sessionID)
                // An empty guest is handed the host's next match; that is the code lasting
                // an evening. A match its own watch started is the pair stepping off the shared
                // one — or the phone would be a guest on a match nobody hosts, unable to end it
                // and offered a Leave that throws it away. But the watch also hands on the
                // host's: a result it took back, or the next match it heard standing in.
                let steppingOff = role == .guest && packet.isFromPairedDevice && !isJoining
                    && isThePairsOwn(incoming)
                if steppingOff {
                    role = .solo
                    shareRole()
                }
                refresh()
                if steppingOff {
                    onLeft?()
                } else {
                    publishSnapshot(force: true)
                    if role == .guest, packet.isFromPairedDevice, !isJoining { offerOurSession(live: true) }
                }
            } else if incoming.sessionID == log.sessionID {
                arrive(on: incoming.sessionID, from: packet)
                relay(incoming.ordered, from: packet)
            } else if packet.isFromPairedDevice, pairedRole == .host {
                // A host is never taken over, so the watch on the same wrist is the one that
                // gives way, whatever it thought it was on.
                follow(incoming)
            } else if role == .guest, packet.isFromPairedDevice, pairedRole == .guest {
                // Both of the pair joined something. Each refusing the other would have them
                // pushing sessions at each other for ever, so the clock settles it.
                if incoming.createdAt > log.createdAt {
                    follow(incoming)
                } else if incoming.createdAt < log.createdAt {
                    offerOurSession()
                    if packet.isFromPairedDevice { keep(incoming, handedOverBy: .refusedEnding) }
                }
            } else if role == .guest, !packet.isFromPairedDevice, let ended = untakenTakeBack() {
                // The point that won it was taken back here after the host had already moved on,
                // so the host never took the reopened match up and never will. The match ended as
                // it ended; the host's next one is where this guest belongs.
                giveUpTakingBack(ended)
                log = incoming
                outbox = Outbox()
                refresh()
                publishSnapshot(force: true)
            } else if role != .solo {
                // A host is never taken over. The people in front of it are playing this
                // match, and a phone that happened to start one a moment ago is not. Nor is a
                // guest: it chose its match by code, and the only thing left to offer it
                // another is its own watch, still holding what the phone had before.
                offerOurSession()
                if packet.isFromPairedDevice { keep(incoming, handedOverBy: .refusedEnding) }
            } else if packet.isFromPairedDevice, pairedRole == .guest {
                // The phone this is paired to joined somebody else's match. Whatever it holds
                // is that match, and it is not this end's to weigh against the clock.
                adopt(incoming)
            } else if incoming.createdAt > log.createdAt {
                adopt(incoming)
            } else if incoming.createdAt < log.createdAt {
                // Ours is the newer session and wins. Only the strictly newer one offers,
                // so two devices can never sit pushing sessions at each other.
                offerOurSession()
                if packet.isFromPairedDevice { keep(incoming, handedOverBy: .refusedEnding) }
            }
            packet.reply?(encode(.hello(sessionID: log.sessionID, vector: log.coverage, from: device)))
        }
    }

    /// Merges what a peer sent and passes on whatever was new.
    ///
    /// Where there are several peers this device is the road between them, so an event that
    /// arrives here has to go back out as though it had been scored here — otherwise a point
    /// tapped on one phone reaches this one and stops dead. Only the genuinely new ones are
    /// passed on, so two devices cannot volley the same event back and forth for ever.
    /// Joining is an explicit act, so it has to conclude even when this device already
    /// happens to be on the session it asked for.
    ///
    /// A phone with nothing on it is handed a peer's match automatically — that is how the
    /// pair has always worked — so a guest can arrive already holding the right session and
    /// never be told anything about it. Without this it would go on holding the whistle for
    /// a match that belongs to whoever started it.
    ///
    /// The one voice that does not count is this device's own watch. It is on the same match
    /// the phone is, so the first answer to a join is always its, naming the session already on
    /// screen — and taking that as the host's would end the join on a stranger's behalf.
    private func arrive(on sessionID: UUID, from packet: InboundPacket) {
        guard isJoining, !packet.isFromPairedDevice, sessionID == log.sessionID, sessionID != joinRefuses,
              !log.isEmpty else { return }
        isJoining = false
        joinRefuses = nil
        role = .guest
        forgetLeaving(sessionID)
        persist()
        shareRole()
    }

    /// Walked back in by code, so whatever said this match was left no longer does.
    private func forgetLeaving(_ session: UUID) {
        if leftSessionID == session { leftSessionID = nil }
        if counterpartLeftSessionID == session { counterpartLeftSessionID = nil }
    }

    private func relay(_ incoming: [MatchEvent], from packet: InboundPacket) {
        let fresh = incoming.filter { log.events[$0.id] == nil }
        let before = state
        let session = log.sessionID
        guard log.merge(fresh) else { return }
        let overruled = packet.isFromPairedDevice ? [] : overrule(endingsIn: fresh)
        outbox.enqueue(contentsOf: fresh + overruled)
        push(fresh + overruled, in: session)
        // Only what was genuinely new, so the same point arriving over both radios is
        // mentioned once, and the board as it stands before this device redraws it.
        let after = SessionReducer.state(of: log)
        refresh()
        announce(fresh, before: before, after: after, session: session)
        // The snapshot channel too, exactly as a tap made here would. It is the one channel a
        // watch that was not reachable reads the moment it wakes; without it a point scored
        // on somebody else's phone reached this device's own watch only when the durable
        // queue got round to it, while this device's own points were there straight away.
        publishSnapshot(force: false)
        // Something new arrived over the top of something missing: a push this device never
        // got, acknowledged on the sender's behalf by a peer that did. Nothing is coming to
        // fill it unprompted, so ask now rather than wait for the next reconnect.
        if log.coverage != log.vector { Task { await askWhatIsMissing() } }
    }

    private enum Handover {
        /// The watch let go of it for another match.
        case displacement
        /// Offered by the watch and refused here as the older, having already ended there.
        case refusedEnding
    }

    /// Files a match the watch played and no longer has, since the watch keeps no history. Retired
    /// here too, so a copy the watch sent before it let go is not taken up as live.
    private func keep(_ lost: MatchLog, handedOverBy handover: Handover) {
        guard keepsHistory, !lost.isEmpty, lost.sessionID != log.sessionID, !retired.contains(lost.sessionID),
              let state = SessionReducer.state(of: lost) else { return }
        let archive: Bool = lost.effectiveEvents.reversed().lazy.compactMap { event -> Bool? in
            if case .finish(let archive) = event.kind { archive } else { nil }
        }.first ?? true
        switch handover {
        case .displacement:
            guard lost.hasProgress, store?.historyRecord(lost.sessionID) == nil else { break }
            file(state, from: lost)
        case .refusedEnding:
            guard state.isFinished else { return }
            if state.hasResults, archive { file(state, from: lost) }
        }
        retired.append(lost.sessionID)
        if !archive { discarded.append(lost.sessionID) }
        if retired.count > 20 { retired.removeFirst(retired.count - 20) }
        discarded.removeAll { !retired.contains($0) }
        persist()
    }

    /// A shared match ends where it belongs. A Finish from anybody else's phone — a build that let
    /// a guest end it, or a watch that took the host's match for its own — is taken back here
    /// before it can end anything, and the taking back goes out to everybody who has it.
    private func overrule(endingsIn fresh: [MatchEvent]) -> [MatchEvent] {
        guard role == .host else { return [] }
        return fresh.compactMap { event in
            guard case .finish = event.kind, event.id.device != device, event.id.device != pairedDevice else { return nil }
            return log.append(.undo(event.id), from: device, at: MatchEvent.stamp())
        }
    }

    /// Replaces the local session with the peer's. Anything already scored locally is
    /// archived first, so a session is never silently destroyed.
    private func adopt(_ incoming: MatchLog) {
        if keepsHistory, log.hasProgress, let state = SessionReducer.state(of: log) {
            file(state, from: log)
            replacedSessionTitle = state.title
        } else if !keepsHistory, log.hasProgress {
            // Somebody else's history, then: the phone's.
            transport.queue(encode(.displaced(log)))
        }
        log = incoming
        outbox = Outbox()
        refresh()
        // Nothing else says so. A watch holding nothing would otherwise learn of the match
        // the phone just joined only from the next point scored on it.
        publishSnapshot(force: true)
    }

    /// Started by this phone or its watch rather than handed on from somebody else's: no event in
    /// it is anybody else's, and it is not a result taken back. With the other half not yet
    /// known, a match with one author besides this device is read as that half's.
    ///
    /// `strictly` refuses to guess: only a known other half counts.
    private func isThePairsOwn(_ incoming: MatchLog, strictly: Bool = false) -> Bool {
        guard !incoming.isEmpty, incoming.takesBack == nil else { return false }
        let others = Set(incoming.events.keys.map(\.device)).subtracting([device])
        guard let pairedDevice else { return !strictly && others.count <= 1 }
        return others.isSubset(of: [pairedDevice])
    }

    /// The session a result was taken back from, while nobody but this pair has touched the match
    /// it was taken back into.
    private func untakenTakeBack() -> UUID? {
        guard let takenBack = log.takesBack, log.events.keys.allSatisfy({ isOurs($0.device) }) else { return nil }
        return takenBack
    }

    private func giveUpTakingBack(_ ended: UUID) {
        if keepsHistory, let farewell = farewells[ended], let state = SessionReducer.state(of: farewell) {
            file(state, from: farewell)
        }
        if !retired.contains(log.sessionID) { retired.append(log.sessionID) }
        if retired.count > 20 { retired.removeFirst(retired.count - 20) }
    }

    /// Nobody leaves their own match — they end it — so a Leave that names one was a mistake.
    private func isThePairsOwnFromThePair(_ incoming: MatchLog, _ packet: InboundPacket) -> Bool {
        packet.isFromPairedDevice && isThePairsOwn(incoming, strictly: true)
    }

    private func takesBackOneOfOurs(_ incoming: MatchLog) -> Bool {
        incoming.takesBack.flatMap(endedHere) != nil
    }

    /// The session that ended here which a take-back leads back to. A result taken back out of
    /// reach can be won and taken back again, and the match that reopens then names one this end
    /// never saw — but each reopened name follows from the last, so the chain can be walked on
    /// from whatever ended here. The nearest one, when more than one of them did.
    private func endedHere(_ takenBack: UUID) -> UUID? {
        let ended = Set(retired).union(farewells.keys)
        if ended.contains(takenBack) { return takenBack }
        var nearest: (session: UUID, steps: Int)?
        for session in ended {
            var reopened = session
            for steps in 1 ..< (nearest?.steps ?? 9) {
                reopened = Self.reopening(reopened)
                if reopened == takenBack {
                    nearest = (session, steps)
                    break
                }
            }
        }
        return nearest?.session
    }

    /// Takes the pair's match, and steps off whatever shared one this end was on.
    private func follow(_ incoming: MatchLog) {
        let wasShared = role != .solo
        role = .solo
        adopt(incoming)
        guard wasShared else { return }
        shareRole()
        onLeft?()
    }

    /// Offered on every reconnect, so a watch that has never seen them catches up without
    /// anyone having to think about it.
    /// Tells this device's own watch, or its own phone, what the workout is doing.
    ///
    /// A finished one is queued as well as sent, deliberately: `sendLive` returns without
    /// doing anything at all when nothing is reachable, so leaning on its own durable
    /// fallback would drop exactly the case this exists for — a workout ended with the
    /// phone in a bag on the other side of the club. Losing it is not fatal even then, since
    /// Health has the real copy, but the list should not need the Health app to explain it.
    public func send(_ signal: WorkoutSignal) {
        switch signal {
        case .running, .paused, .idle:
            announcedWorkout = signal
        // A request is not a state. Saying one again on reconnect would ask a second time
        // for something already done.
        case .stop, .pause, .resume, .finished, .series:
            break
        }
        let payload = encode(.workout(signal))
        // A statement about right now goes live only. Queued, `.stop` would land twenty
        // minutes late and end a workout started since; `.running` would switch a glyph back
        // on with nothing behind it. Only a finished workout is a fact worth keeping.
        switch signal {
        case .finished, .series: transport.queue(payload)
        case .stop, .pause, .resume, .running, .paused, .idle: break
        }
        Task { _ = await sendLive(payload) }
    }

    /// Passes a join between this device and the one in the same pocket: the code from the
    /// wrist, and how it is going back the other way.
    ///
    /// Live only. A request or a word on a join in progress goes stale: a `.join` queued and
    /// handed over twenty minutes later would go looking for a match that finished, and a
    /// `.searching` delivered after the fact would leave a watch spinning at a search nobody
    /// is running. If it did not arrive, there is nothing worth saying late. A `.standby` is
    /// the exception: it says what is true now, so it is said again on reconnect.
    /// Answers whether it actually landed, which the other signals have no need of and this
    /// one does: a watch that asked and was not heard would otherwise sit watching a search
    /// nobody is running.
    @discardableResult
    public func send(_ signal: SharingSignal) async -> Bool {
        if case .standby = signal { announcedStandby = signal }
        return await sendLive(encode(.sharing(signal))) != nil
    }

    private func shareStandbyOnReconnect() {
        guard let announcedStandby else { return }
        Task { _ = await sendLive(encode(.sharing(announcedStandby))) }
    }

    /// Offered alongside the presets on reconnect. A workout signal is never queued, so a
    /// phone that has just come back has to be told again — and one that heard "running" and
    /// missed the ending has to be corrected, or its glyph stays on over nothing.
    private func shareWorkoutOnReconnect() {
        guard let announcedWorkout else { return }
        Task { _ = await sendLive(encode(.workout(announcedWorkout))) }
    }

    private func sharePresets() {
        guard !presets.isEmpty else { return }
        let payload = encode(.presets(presets))
        Task { _ = await sendLive(payload) }
    }

    /// Offered alongside the presets on reconnect, so the watch's flip button knows which
    /// way the phone is currently reading before it sends the opposite.
    /// Offered alongside the presets on reconnect, so a watch that has just woken knows
    /// whether the phone it is paired to is holding the whistle. Never solo: the counterpart
    /// reads solo as this end having dropped a session, and a reconnect is not that.
    private func shareRoleOnReconnect() {
        Task {
            guard role != .solo || roleIsUnsaid else { return }
            if await sendLive(encode(.role(role))) != nil, role == .solo { roleIsUnsaid = false }
        }
    }

    private func shareDisplay() {
        guard display.hasBeenSet else { return }
        let payload = encode(.display(display))
        Task { _ = await sendLive(payload) }
    }

    private func shareHaptics() {
        guard haptics.hasBeenSet else { return }
        let payload = encode(.haptics(haptics))
        Task { _ = await sendLive(payload) }
    }

    /// Hands our session to a counterpart that is not on it. The snapshot channel
    /// coalesces and the live one needs the counterpart awake, so the one thing that must
    /// not be missed — which session is being played — goes on the durable queue too.
    ///
    /// `live` sends it to whoever is connected as well. Only for a counterpart known to hold
    /// nothing: offered live to one holding a different match, two devices that each think
    /// theirs is the one would sit pushing sessions at each other for ever.
    private func offerOurSession(live: Bool = false) {
        guard !log.isEmpty else { return }
        let offer = encode(.snapshot(log))
        transport.queue(offer)
        if live { Task { _ = await sendLive(offer) } }
    }

    private func requestSnapshot(_ packet: InboundPacket) {
        packet.reply?(encode(.snapshot(log)))
    }

    /// Tells the counterpart the session it is offering is over here.
    ///
    /// Pushed rather than only replied: the durable and snapshot channels both arrive with
    /// no reply handler, so answering only down the reply would leave the counterpart
    /// scoring into a session every packet of which we refuse — silently, and for good,
    /// since the retired list outlives a relaunch.
    private func announceRetirement(of sessionID: UUID, to packet: InboundPacket) {
        let notice = encode(.retired(
            sessionID: sessionID, archive: !discarded.contains(sessionID), farewell: farewells[sessionID]
        ))
        if let reply = packet.reply {
            reply(notice)
        } else if canEndSession {
            // Refusing a packet is not the same as ending a match, and a push has no
            // addressee: a guest doing this — or a watch following one — would tell everybody
            // the host's match was over.
            transport.queue(notice)
            Task { _ = await sendLive(notice) }
        }
    }

    /// The log this end ended on, when what just arrived for that match means it did not end.
    ///
    /// A copy can finish on its own — the winning point scored out of earshot while somebody
    /// else took back the point before it — and together the two are still in play. Whoever the
    /// match belongs to plays on, and this end, holding its own copy's ending as final, refused
    /// the match for good and answered every point with a notice of an ending nobody else had.
    ///
    /// Never for the end the match belongs to, whose ending is the match's; and only onto
    /// nothing, so it never displaces anything else. A code typed again is asking for exactly
    /// this match, unless it is the one being walked away from.
    private func overturnedEnding(of session: UUID, by incoming: [MatchEvent]) -> MatchLog? {
        guard !canEndSession, log.isEmpty, !(isJoining && session == joinRefuses),
              let ended = farewells[session] else { return nil }
        var merged = ended
        guard merged.merge(incoming), SessionReducer.state(of: merged)?.isFinished == false else { return nil }
        return ended
    }

    /// Back on a match whose ending turned out to be this copy's alone. The result filed for it
    /// goes, since that is not how it ended; what it ended on goes back out, since that may be
    /// exactly what the others are missing.
    private func pickBackUp(_ ended: MatchLog) {
        retired.removeAll { $0 == ended.sessionID }
        discarded.removeAll { $0 == ended.sessionID }
        if keepsHistory { try? store?.deleteHistory(ended.sessionID) }
        log = ended
        outbox = Outbox(pending: ended.ordered)
        Task { await flush() }
    }

    /// Throttled, but never dropped: a change that arrives inside the window is published
    /// when the window closes. The application context holds one value, and it is the only
    /// thing a counterpart sees at cold launch, so it must end up holding the newest state
    /// rather than whichever update happened to win the race.
    private func publishSnapshot(force: Bool) {
        // An empty log tells a counterpart nothing — it ignores empty snapshots — but
        // publishing one replaces a context that did say something. On the point that ends
        // a match the log is already cleared by the time this runs, so without this the
        // farewell would be overwritten by "nothing here" a moment after being sent.
        guard !log.isEmpty else { return }
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
            // Cleared before the log is looked at. Waking to find the match over left the
            // flag set, and every throttled publish after that was dropped on it until
            // something forced one.
            self.snapshotPending = false
            guard !self.log.isEmpty else { return }
            self.lastSnapshotPublished = Date()
            self.transport.publishSnapshot(self.encode(.snapshot(self.log)))
        }
    }

    private func encode(_ wire: Wire) -> Data {
        (try? wire.encoded()) ?? Data()
    }

    private func refresh() {
        state = SessionReducer.state(of: log)
        absorbTakeBack()
        // A session in play supersedes whatever result was on screen — including one the
        // counterpart took back, which arrives here as a new session.
        if state != nil {
            lastResult = nil
            resultRewind = nil
        }
        if concludeIfFinished() { return }
        persist()
    }

    private func persist() {
        if role == .guest, !log.isEmpty { guestOf = log.sessionID }
        try? store?.save(ActiveSession(
            log: log, outbox: outbox, retired: retired, discarded: discarded, role: role,
            pairedRole: pairedRole, guestOf: guestOf,
            leftSessionID: leftSessionID, counterpartLeftSessionID: counterpartLeftSessionID,
            pairedDevice: pairedDevice
        ))
    }
}

/// A finished session and the way back into it.
public struct RewindableResult: Sendable {
    /// The session as it stood before the event that ended it.
    public let state: SessionState
    /// True when what would be taken back is a score rather than a deliberate ending.
    public let undoesAPoint: Bool
}
