import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let winnerCourt = SessionSetup.winnerCourt(rules: WinnerCourtRules(), teams: BySide(a: .home, b: .away))

private let americano = SessionSetup.tournament(Tournament(
    name: "Thursday", format: .americano,
    players: ["Ada", "Bob", "Cy", "Di"].map { Player(name: $0) },
    config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
))

@MainActor
private final class Court {
    let host: MatchStore
    let phone: MatchStore
    let watch: MatchStore
    private var tasks: [Task<Void, Never>] = []

    init(_ setup: SessionSetup, warmup: Bool = false, guestStore: SessionStore? = nil) {
        let hostDevice = DeviceID()
        var log = MatchLog()
        log.append(warmup ? .configure(setup, at: Date(), warmup: true) : .configure(setup), from: hostDevice)

        let (hostToPhone, phoneToHost) = LoopbackTransport.pair()
        let (phoneToWatch, watchToPhone) = LoopbackTransport.pair()

        let hostFan = FanOutTransport()
        hostFan.attach(hostToPhone, as: .sharedSession)
        host = MatchStore(device: hostDevice, transport: hostFan, session: ActiveSession(log: log), snapshotInterval: 0)

        let phoneFan = FanOutTransport()
        phoneFan.attach(phoneToWatch, as: .pairedDevice)
        phoneFan.attach(phoneToHost, as: .sharedSession)
        phone = MatchStore(device: DeviceID(), transport: phoneFan, store: guestStore, snapshotInterval: 0)

        let watchFan = FanOutTransport()
        watchFan.attach(watchToPhone, as: .pairedDevice)
        watch = MatchStore(device: DeviceID(), transport: watchFan, snapshotInterval: 0, keepsHistory: false)
    }

    func open(default access: ShareAccess = .full) async {
        tasks = [host, phone, watch].map { store in Task { await store.run() } }
        await quietPeriod()
        host.setDefaultAccess(access)
        host.startSharing()
        phone.beginJoining()
        // The watch's list too: a match handed on from the host's live offer comes without one,
        // and the list follows it.
        await eventually {
            phone.role == .guest && phone.accessTable != nil && !watch.canEndSession && watch.accessTable != nil
        }
    }

    func close() {
        tasks.forEach { $0.cancel() }
    }
}

/// A host that answers a hello with its match and its list and says nothing else, so whatever
/// a guest knows of the list came with the match.
nonisolated private final class ScriptedHost: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { _ in }
    let reachability = AsyncStream<Bool> { _ in }
    private let answer: Data
    private let lock = NSLock()
    private var snapshots: [Data] = []

    init(answer: Wire) throws {
        self.answer = try answer.encoded()
    }

    var isReachable: Bool { true }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? {
        guard case .hello? = try? Wire.decode(payload) else { return nil }
        return answer
    }
    func publishSnapshot(_ payload: Data) { lock.withLock { snapshots.append(payload) } }
    func queue(_ payload: Data) {}

    var published: [Wire] { lock.withLock { snapshots.compactMap { try? Wire.decode($0) } } }
}

/// Everything that reaches the far end of a link, for a test that wants to read what was said
/// rather than have a store act on it.
nonisolated private final class Overhearing: @unchecked Sendable {
    private let lock = NSLock()
    private var heard: [Wire] = []
    private var listening: Task<Void, Never>?

    init(_ end: LoopbackTransport) {
        listening = Task { [weak self] in
            for await packet in end.inbound {
                if let wire = try? Wire.decode(packet.payload) { self?.lock.withLock { self?.heard.append(wire) } }
            }
        }
    }

    deinit { listening?.cancel() }

    var snapshots: [(log: MatchLog, access: ShareAccessTable?)] {
        lock.withLock {
            heard.compactMap { if case .snapshot(let log, _, let access) = $0 { (log, access) } else { nil } }
        }
    }
}

private func games(_ store: MatchStore) -> BySide<Int>? {
    guard case .winnerCourt(let session) = store.state else { return nil }
    return session.score.points
}

@Suite("What a guest may do", .serialized)
@MainActor
struct AccessTests {
    @Test func aGuestJoinsAtTheHostsDefault() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }

        await eventually { court.watch.access == .readOnly }
        #expect(court.phone.access == .readOnly)
        #expect(court.watch.access == .readOnly, "its watch goes by what its phone was told")
        #expect(court.host.access == .full, "the host can do everything on its own match")
    }

    @Test func aReadOnlyGuestScoresNothing() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }
        await eventually { court.watch.access == .readOnly }

        court.host.tap(team: .a)
        await eventually { games(court.phone) == BySide(a: 1, b: 0) }

        court.phone.tap(team: .b)
        court.phone.setScore(court: 0, points: BySide(a: 3, b: 3))
        court.phone.undoLast()
        court.watch.tap(team: .b)
        await quietPeriod()

        #expect(!court.phone.canScore)
        #expect(!court.phone.canUndo)
        #expect(games(court.phone) == BySide(a: 1, b: 0))
        #expect(games(court.host) == BySide(a: 1, b: 0))
    }

    @Test func aScorerScoresButDoesNotBlowTheWhistle() async {
        let court = Court(winnerCourt)
        await court.open(default: .score)
        defer { court.close() }

        court.phone.tap(team: .b)
        await eventually { games(court.host) == BySide(a: 0, b: 1) }
        #expect(games(court.host) == BySide(a: 0, b: 1), "scoring is allowed")
        #expect(court.phone.canUndo, "and so is taking a point back")

        court.phone.endRound()
        await quietPeriod()
        guard case .winnerCourt(let session) = court.host.state else { Issue.record("no match"); return }
        #expect(session.completedRounds.isEmpty, "the whistle is not")

        court.host.endRound()
        await eventually {
            if case .winnerCourt(let session) = court.phone.state { !session.completedRounds.isEmpty } else { false }
        }
        #expect(!court.phone.canUndo, "nor is taking the host's whistle back")
        #expect(court.host.canUndo)
    }

    @Test func theHostChangesItsMindAndTheGuestFollows() async {
        let court = Court(winnerCourt)
        await court.open()
        defer { court.close() }
        #expect(court.phone.access == .full)

        court.host.setAccess(.readOnly, for: court.phone.device)
        await eventually { court.phone.access == .readOnly && court.watch.access == .readOnly }
        #expect(court.phone.access == .readOnly)
        #expect(court.watch.access == .readOnly)

        court.host.setDefaultAccess(.score)
        await quietPeriod()
        #expect(court.phone.access == .readOnly, "its own say beats the default")

        court.host.setAccess(nil, for: court.phone.device)
        await eventually { court.phone.access == .score }
        #expect(court.phone.access == .score, "and back on the default it goes by that")
    }

    @Test func theHostListsTheGuestsByWhoTheySayTheyAre() async {
        let court = Court(americano)
        await court.open()
        defer { court.close() }

        await eventually { court.host.guests.count == 1 }
        #expect(court.host.guests.map(\.device) == [court.phone.device], "the phone, not its watch")
        #expect(court.host.guests.first?.name == nil)

        court.phone.identify(as: "Cy")
        await eventually { court.host.guests.first?.name == "Cy" }
        #expect(court.host.guests.first?.name == "Cy")
        guard case .tournament(let tournament) = court.phone.state else { Issue.record("no tournament"); return }
        #expect(court.phone.me == tournament.players.first { $0.name == "Cy" }?.id, "and plays as them")

        court.phone.setMe(tournament.players.first { $0.name == "Di" }?.id)
        await eventually { court.host.guests.first?.name == "Di" }
        #expect(court.host.guests.count == 1, "the same phone, renamed")
        #expect(court.host.guests.first?.name == "Di")
    }

    @Test func leavingForgetsWhatTheHostSaid() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }
        court.phone.identify(as: "Ada")

        court.phone.leaveSharedSession()
        #expect(court.phone.accessTable == nil)
        #expect(court.phone.identity == nil)
        #expect(court.phone.access == .full)

        court.host.stopSharing()
        #expect(court.host.accessTable == nil)
        #expect(court.host.guests.isEmpty)
    }

    @Test func aGuestRelaunchedKeepsItsRestriction() throws {
        let hostDevice = DeviceID()
        var log = MatchLog()
        log.append(.configure(winnerCourt), from: hostDevice)
        let guest = MatchStore(
            device: DeviceID(), transport: LoopbackTransport.pair().0,
            session: ActiveSession(log: log, role: .guest, access: ShareAccessTable(standard: .readOnly)),
            snapshotInterval: 0
        )

        #expect(guest.access == .readOnly)
        guest.tap(team: .a)
        #expect(games(guest) == BySide(a: 0, b: 0))
    }

    @Test func aRelaunchedHostKeepsWhatItSaid() {
        var log = MatchLog()
        let device = DeviceID()
        log.append(.configure(winnerCourt), from: device)
        let guest = DeviceID()
        let table = ShareAccessTable(standard: .score).setting(.readOnly, for: guest)
        let host = MatchStore(
            device: device, transport: LoopbackTransport.pair().0,
            session: ActiveSession(log: log, role: .host, access: table, guests: [GuestCard(device: guest, name: "Bob")]),
            snapshotInterval: 0
        )

        host.startSharing()
        #expect(host.accessTable == table, "sharing again on a new code is the same phones")
        #expect(host.guests.map(\.name) == ["Bob"])
    }

    @Test func aGuestStartingItsOwnMatchMayDoEverything() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }

        court.phone.startNewSession()
        court.phone.configure(winnerCourt)
        court.phone.tap(team: .a)

        #expect(court.phone.access == .full)
        #expect(games(court.phone) == BySide(a: 1, b: 0))
    }

    @Test func aScorerWarmsUpButDoesNotStartTheGame() async {
        let court = Court(winnerCourt, warmup: true)
        await court.open(default: .score)
        defer { court.close() }
        #expect(court.phone.state?.warmingUpSince != nil)

        court.phone.endWarmup()
        court.watch.endWarmup()
        await quietPeriod()
        #expect(court.host.state?.warmingUpSince != nil, "starting the game is running it")

        court.host.endWarmup()
        await eventually { court.phone.state?.warmingUpSince == nil && court.watch.state?.warmingUpSince == nil }
        #expect(court.phone.state?.warmingUpSince == nil)
        #expect(court.watch.state?.warmingUpSince == nil)
    }

    @Test func aHostAnswersAJoinWithItsList() async throws {
        let (hostEnd, guestEnd) = LoopbackTransport.pair()
        let host = MatchStore(device: DeviceID(), transport: hostEnd, snapshotInterval: 0)
        host.configure(winnerCourt)
        host.setDefaultAccess(.score)
        host.startSharing()
        let run = Task { await host.run() }
        defer { run.cancel() }

        let hello = try Wire.hello(sessionID: UUID(), vector: VersionVector(), from: DeviceID()).encoded()
        let answer = await guestEnd.sendLive(hello).flatMap { try? Wire.decode($0) }

        guard case .snapshot(let log, _, let access)? = answer else { Issue.record("not a snapshot"); return }
        #expect(log.sessionID == host.log.sessionID)
        #expect(access == host.accessTable)
    }

    /// The list reached a joining phone after the match did, and its watch later still: a scorer
    /// was briefly let do everything, and a watch that ended the warm-up in that moment ended it
    /// on the host's match.
    @Test func aJoiningGuestHasTheHostsListTheMomentItHasTheMatch() async throws {
        var hostLog = MatchLog()
        hostLog.append(.configure(winnerCourt), from: DeviceID())
        let list = ShareAccessTable(standard: .score, hostName: "Ada")
        let scripted = try ScriptedHost(answer: .snapshot(hostLog, access: list))
        let (phoneToWatch, watchEnd) = LoopbackTransport.pair()
        let toTheWatch = Overhearing(watchEnd)
        let links = FanOutTransport()
        links.attach(phoneToWatch, as: .pairedDevice)
        links.attach(scripted, as: .sharedSession)
        let phone = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)
        let run = Task { await phone.run() }
        defer { run.cancel() }

        phone.beginJoining()
        await eventually { phone.role == .guest }
        #expect(phone.role == .guest)
        #expect(phone.access == .score, "from the answer alone: this host says nothing else")
        #expect(phone.hostName == "Ada")

        await eventually { toTheWatch.snapshots.contains { $0.log.sessionID == hostLog.sessionID } }
        let handedOn = toTheWatch.snapshots.first { $0.log.sessionID == hostLog.sessionID }
        #expect(handedOn?.access == list, "the watch is handed the list with the match")
        let toOtherPhones = scripted.published.compactMap { if case .snapshot(_, _, let access) = $0 { access } else { nil } }
        #expect(toOtherPhones.isEmpty, "a guest's copy is for its own watch")
    }

    @Test func aGuestsWatchHasTheListTheMomentItHasTheMatch() async throws {
        var hostLog = MatchLog()
        hostLog.append(.configure(winnerCourt), from: DeviceID())
        let list = ShareAccessTable(standard: .score, hostName: "Ada")
        let (phoneEnd, watchToPhone) = LoopbackTransport.pair()
        let links = FanOutTransport()
        links.attach(watchToPhone, as: .pairedDevice)
        let watch = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0, keepsHistory: false)
        let run = Task { await watch.run() }
        defer { run.cancel() }
        await eventually { watch.isPairReachable }

        _ = await phoneEnd.sendLive(try Wire.snapshot(hostLog, role: .guest, access: list).encoded())

        #expect(watch.log.sessionID == hostLog.sessionID)
        #expect(!watch.canEndSession)
        #expect(watch.access == .score)
    }

    /// What a link keeps for whoever connects next can be older than what was said since.
    @Test func aKeptSnapshotDoesNotPutBackAnotherSharesList() async throws {
        var hostLog = MatchLog()
        hostLog.append(.configure(winnerCourt), from: DeviceID())
        let current = ShareAccessTable(standard: .score, hostName: "Ada")
        let earlier = ShareAccessTable(standard: .full, hostName: "Ada")
        let (phoneEnd, watchToPhone) = LoopbackTransport.pair()
        let links = FanOutTransport()
        links.attach(watchToPhone, as: .pairedDevice)
        let watch = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0, keepsHistory: false)
        let run = Task { await watch.run() }
        defer { run.cancel() }
        await eventually { watch.isPairReachable }

        _ = await phoneEnd.sendLive(try Wire.snapshot(hostLog, role: .guest, access: current).encoded())
        _ = await phoneEnd.sendLive(try Wire.snapshot(hostLog, role: .guest, access: earlier).encoded())
        #expect(watch.accessTable == current)

        let readOnly = current.with(standard: .readOnly)
        _ = await phoneEnd.sendLive(try Wire.snapshot(hostLog, role: .guest, access: readOnly).encoded())
        #expect(watch.access == .readOnly, "the same list, brought up to date")
    }
}
