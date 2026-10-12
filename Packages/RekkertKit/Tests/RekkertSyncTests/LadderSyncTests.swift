import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private func setup() -> SessionSetup {
    .tournament(Tournament(
        id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!),
        name: "Thursday",
        format: .winnerCourt,
        players: (0 ..< 8).map { Player(name: "P\($0)") },
        config: TournamentConfig(courtCount: 2, ladder: LadderRules(partners: .fixed, start: .asListed))
    ))
}

private struct Pair {
    let phone: MatchStore
    let watch: MatchStore

    init() {
        let (one, two) = LoopbackTransport.pair()
        let session = ActiveSession(log: MatchLog(sessionID: UUID(uuidString: "55555555-0000-0000-0000-000000000000")!))
        phone = MatchStore(device: DeviceID(), transport: one, session: session, snapshotInterval: 0)
        watch = MatchStore(device: DeviceID(), transport: two, session: session, snapshotInterval: 0)
    }

    func run() -> [Task<Void, Never>] {
        [Task { await phone.run() }, Task { await watch.run() }]
    }
}

private func ladder(_ store: MatchStore) -> Tournament? {
    guard case .tournament(let tournament) = store.state else { return nil }
    return tournament
}

@Suite("A ladder across two devices", .serialized)
@MainActor
struct LadderSyncTests {
    @Test func theWhistleFromTheWatchEndsEveryCourt() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(setup())
        pair.phone.nextRound()
        await eventually { inStep(pair.phone, pair.watch) }
        for _ in 0 ..< 4 { pair.watch.tap(round: 0, court: 0, team: .b) }
        for _ in 0 ..< 4 { pair.phone.tap(round: 0, court: 1, team: .a) }
        pair.watch.endRound()
        await eventually { inStep(pair.phone, pair.watch) }

        let onPhone = try #require(ladder(pair.phone))
        #expect(onPhone.currentRound?.isEnded == true)
        #expect(onPhone.status(round: 0, court: 0)?.winner == .b)
        #expect(onPhone.status(round: 0, court: 1)?.winner == .a)
    }

    @Test func drawingWaitsForTheDecidingPoints() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(setup())
        pair.phone.nextRound()
        pair.phone.endRound()
        pair.phone.nextRound()
        await eventually { inStep(pair.phone, pair.watch) }
        #expect(ladder(pair.watch)?.rounds.count == 1, "two courts still level")

        pair.watch.tap(round: 0, court: 0, team: .a)
        pair.watch.tap(round: 0, court: 1, team: .b)
        await eventually { inStep(pair.phone, pair.watch) }
        pair.phone.nextRound()
        await eventually { inStep(pair.phone, pair.watch) && ladder(pair.watch)?.rounds.count == 2 }

        let onWatch = try #require(ladder(pair.watch))
        let names = onWatch.currentRound?.matches.map { match in
            match.teams.map { $0.compactMap { onWatch.player($0)?.name } }
        }
        #expect(names == [
            BySide(a: ["P0", "P1"], b: ["P6", "P7"]),
            BySide(a: ["P2", "P3"], b: ["P4", "P5"]),
        ], "court 1's winners stay up with court 2's winners; the losers meet below")
    }

    @Test func aSnoozeOnOneDeviceMovesTheCountdownOnBoth() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(setup())
        pair.phone.nextRound()
        await eventually { inStep(pair.phone, pair.watch) }
        let before = try #require(ladder(pair.phone)?.currentRound?.clock?.endsAt)

        pair.watch.snoozeRound(minutes: 2)
        await eventually { inStep(pair.phone, pair.watch) }
        let after = try #require(ladder(pair.phone)?.currentRound?.clock?.endsAt)
        #expect(after.timeIntervalSince(before) == 120)

        pair.phone.pauseRound()
        await eventually { inStep(pair.phone, pair.watch) }
        #expect(ladder(pair.watch)?.currentRound?.clock?.isPaused == true)
    }
}
