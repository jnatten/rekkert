import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private func setup(players: Int = 5) -> SessionSetup {
    .friendly(FriendlySession(
        id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!),
        name: "Thursday",
        rules: TraditionalRules(setsToWin: 1, gamesPerSet: 6),
        players: (0 ..< players).map { Player(name: "P\($0)") }
    ))
}

private struct Pair {
    let phone: MatchStore
    let watch: MatchStore

    init() {
        let (one, two) = LoopbackTransport.pair()
        let session = ActiveSession(log: MatchLog(sessionID: UUID(uuidString: "44444444-0000-0000-0000-000000000000")!))
        phone = MatchStore(device: DeviceID(), transport: one, session: session, snapshotInterval: 0)
        watch = MatchStore(device: DeviceID(), transport: two, session: session, snapshotInterval: 0)
    }

    func run() -> [Task<Void, Never>] {
        [Task { await phone.run() }, Task { await watch.run() }]
    }
}

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
}

private func friendly(_ store: MatchStore) -> FriendlySession? {
    guard case .friendly(let session) = store.state else { return nil }
    return session
}

private func winGames(_ store: MatchStore, _ count: Int, for side: TeamSide, round: Int) {
    for _ in 0 ..< (count * 4) { store.tap(round: round, court: 0, team: side) }
}

@Suite("A friendly across two devices", .serialized)
@MainActor
struct FriendlySyncTests {
    @Test func theWatchSeesTheRoundThePhoneDrew() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.configure(setup())
        pair.phone.nextRound()
        try await settle()

        let onWatch = try #require(friendly(pair.watch))
        #expect(onWatch.rounds.count == 1)
        #expect(onWatch.rounds[0].sitOuts.count == 1, "five players, one on the bench")
        #expect(pair.watch.state == pair.phone.state, "the same draw on both, never negotiated")
    }

    @Test func thePhoneDrawsWhileTheWatchIsStillScoringTheRoundBefore() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.configure(setup())
        pair.phone.nextRound()
        try await settle()

        // The watch takes the round to 5–0 and then, at the same moment as the phone
        // finishes it off and draws the next one, taps one more point into the old round.
        winGames(pair.watch, 5, for: .a, round: 0)
        try await settle()

        winGames(pair.phone, 1, for: .a, round: 0)
        pair.watch.tap(round: 0, court: 0, team: .b)
        pair.phone.nextRound()
        try await settle()

        let onPhone = try #require(friendly(pair.phone))
        #expect(onPhone.rounds.count == 2, "one new round, however the two interleaved")
        #expect(onPhone.rounds[1].score.points == BySide(both: 0), "nothing leaked into it")
        #expect(pair.watch.state == pair.phone.state)
    }

    @Test func scoringFromBothEndsOfTheCourtConverges() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.configure(setup(players: 4))
        pair.phone.nextRound()
        try await settle()

        for _ in 0 ..< 6 {
            pair.phone.tap(round: 0, court: 0, team: .a)
            pair.watch.tap(round: 0, court: 0, team: .b)
        }
        try await settle()

        // Alternating points never win a game under advantage, so all twelve are still on
        // the board — which is exactly what makes them worth counting.
        let onPhone = try #require(friendly(pair.phone))
        #expect(onPhone.rounds[0].score.points == BySide(a: 6, b: 6), "every tap counted once")
        #expect(pair.watch.state == pair.phone.state)
    }
}
