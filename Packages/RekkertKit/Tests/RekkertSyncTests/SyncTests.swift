import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

private struct Pair {
    let phone: MatchStore
    let watch: MatchStore
    let phoneLink: LoopbackTransport
    let watchLink: LoopbackTransport

    init() {
        let (one, two) = LoopbackTransport.pair()
        phoneLink = one
        watchLink = two
        let session = ActiveSession(log: MatchLog(sessionID: UUID(uuidString: "33333333-0000-0000-0000-000000000000")!))
        phone = MatchStore(device: DeviceID(), transport: one, session: session, snapshotInterval: 0)
        watch = MatchStore(device: DeviceID(), transport: two, session: session, snapshotInterval: 0)
    }

    func run() -> [Task<Void, Never>] {
        [Task { await phone.run() }, Task { await watch.run() }]
    }
}

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(60))
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .traditional(let session) = store.state else { return nil }
    return session.score.points
}

@Suite("Watch and phone sync")
@MainActor
struct SyncTests {
    @Test func aTapOnThePhoneReachesTheWatch() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        pair.phone.tap(team: .a)
        try await settle()

        #expect(points(pair.watch) == BySide(a: 1, b: 0))
        #expect(pair.watch.state == pair.phone.state)
    }

    @Test func aTapOnTheWatchReachesThePhone() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        try await settle()
        pair.watch.tap(team: .b)
        try await settle()

        #expect(points(pair.phone) == BySide(a: 0, b: 1))
    }

    @Test func simultaneousTapsOnBothDevicesBothCount() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        try await settle()

        pair.phoneLink.setDroppingOutgoing(true)
        pair.watchLink.setDroppingOutgoing(true)
        pair.phone.tap(team: .a)
        pair.watch.tap(team: .a)
        try await settle()

        pair.phoneLink.setDroppingOutgoing(false)
        pair.watchLink.setDroppingOutgoing(false)
        try await settle()

        #expect(points(pair.phone) == BySide(a: 2, b: 0), "neither tap was lost")
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func tapsMadeWhileDisconnectedArriveOnReconnect() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        try await settle()

        pair.phoneLink.setDroppingOutgoing(true)
        for _ in 0 ..< 3 { pair.phone.tap(team: .a) }
        try await settle()
        #expect(points(pair.watch) == BySide(a: 0, b: 0), "watch is still in the dark")

        pair.phoneLink.setDroppingOutgoing(false)
        try await settle()
        #expect(points(pair.watch) == BySide(a: 3, b: 0))
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func undoOnTheWatchReachesThePhone() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        pair.phone.tap(team: .a)
        pair.phone.tap(team: .a)
        try await settle()

        pair.watch.undoLast()
        try await settle()

        #expect(points(pair.phone) == BySide(a: 1, b: 0))
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func aColdWatchPicksUpTheSessionFromASnapshot() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        let watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(setup)
        phone.tap(team: .b)
        phone.tap(team: .b)
        try await settle()

        #expect(watch.log.sessionID == phone.log.sessionID, "the empty watch adopted the phone's session")
        #expect(points(watch) == BySide(a: 0, b: 2))
    }

    @Test func anEmptyPeerIsNotAConflict() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        let watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0)

        phone.configure(setup)
        phone.tap(team: .a)

        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        #expect(phone.replacedSessionTitle == nil, "a watch with no session displaces nothing")
        #expect(watch.replacedSessionTitle == nil)
        #expect(watch.log.sessionID == phone.log.sessionID)
        #expect(points(watch) == BySide(a: 1, b: 0))
    }

    @Test func theMoreRecentlyStartedSessionWins() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let old = ActiveSession(log: MatchLog(createdAt: .now.addingTimeInterval(-3600)))
        let watch = MatchStore(device: DeviceID(), transport: watchLink, session: old, snapshotInterval: 0)
        watch.configure(setup)
        watch.tap(team: .a)

        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        phone.configure(setup)
        phone.tap(team: .b)
        phone.tap(team: .b)

        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        #expect(watch.log.sessionID == phone.log.sessionID, "the stale watch session gives way")
        #expect(points(watch) == BySide(a: 0, b: 2))
        #expect(points(phone) == BySide(a: 0, b: 2))
    }

    @Test func aReplacedSessionIsArchivedNotLost() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionStore = SessionStore(directory: directory)

        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let old = ActiveSession(log: MatchLog(createdAt: .now.addingTimeInterval(-3600)))
        let watch = MatchStore(device: DeviceID(), transport: watchLink, store: sessionStore, session: old, snapshotInterval: 0)
        watch.configure(setup)
        watch.tap(team: .a)

        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        phone.configure(setup)
        phone.tap(team: .b)

        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        #expect(watch.replacedSessionTitle == "Us vs Them")
        #expect(try sessionStore.history().count == 1, "the discarded match went to history")
    }

    @Test func tournamentCourtsSyncIndependently() async throws {
        let tournament = Tournament(
            name: "Thursday",
            format: .americano,
            players: (0 ..< 8).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 2)
        )
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(.tournament(tournament))
        pair.phone.nextRound()
        try await settle()

        pair.watch.tap(court: 1, team: .a)
        pair.phone.setScore(court: 0, points: BySide(a: 9, b: 7))
        try await settle()

        guard case .tournament(let synced) = pair.watch.state else {
            Issue.record("watch has no tournament")
            return
        }
        #expect(synced.rounds[0].matches[0].state.points == BySide(a: 9, b: 7))
        #expect(synced.rounds[0].matches[1].state.points == BySide(a: 1, b: 0))
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func stateSurvivesARestartFromDisk() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)

        let device = DeviceID()
        let first = MatchStore(device: device, transport: LoopbackTransport(reachable: false), store: store)
        first.configure(setup)
        first.tap(team: .a)
        first.tap(team: .b)
        first.tap(team: .a)

        let reloaded = try #require(try store.loadActive())
        let second = MatchStore(device: device, transport: LoopbackTransport(reachable: false), session: reloaded)

        #expect(points(second) == BySide(a: 2, b: 1))
        #expect(second.log.ordered == first.log.ordered)
        #expect(reloaded.outbox.pending.count == 4, "nothing was acknowledged while offline")
    }
}
