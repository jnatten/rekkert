import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private func clock(_ store: MatchStore) -> Date? {
    store.state.flatMap { ScoreboardSnapshot.make(from: $0) }?.clockStart
}

@Suite("The clock across devices", .serialized)
@MainActor
struct RoundClockSyncTests {
    private func pair(_ directory: URL? = nil) -> (MatchStore, MatchStore) {
        let (one, two) = LoopbackTransport.pair()
        let phone = MatchStore(
            device: DeviceID(), transport: one,
            store: directory.map { SessionStore(directory: $0) }, snapshotInterval: 0
        )
        let watch = MatchStore(device: DeviceID(), transport: two, snapshotInterval: 0, keepsHistory: false)
        return (phone, watch)
    }

    @Test func thePhoneAndTheWatchTimeTheSameRound() async throws {
        let (phone, watch) = pair()
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.winnerCourt(rules: WinnerCourtRules(), teams: BySide(a: .home, b: .away)))
        let started = try #require(clock(phone))
        await eventually { clock(watch) != nil }
        #expect(clock(watch) == started, "one clock, not one each")

        // The whistle from the wrist, which is where it usually comes from.
        for _ in 0 ..< 4 { phone.tap(team: .a) }
        await eventually { watch.state?.serveOrder() != nil }
        watch.endRound()
        await eventually { clock(phone) != started }

        let round = try #require(clock(phone))
        #expect(round > started, "the next round is timed from the whistle")
        await eventually { clock(watch) == round }
        #expect(clock(watch) == round)
    }

    @Test func aGuestJoiningMidRoundPicksUpTheRoundsOwnClock() async throws {
        let (phone, watch) = pair()
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.tournament(Tournament(
            name: "Thursday",
            format: .americano,
            players: (0 ..< 8).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2)
        )))
        phone.nextRound()
        let drawn = try #require(clock(phone))
        await eventually { clock(watch) != nil }
        #expect(clock(watch) == drawn, "not zero, and not when the watch heard about it")
    }

    @Test func pickingASessionUpOutOfHistoryRestartsTheClockButTakingAResultBackDoesNot() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        let started = try #require(clock(phone))

        // Won outright, then taken straight back: nothing stopped, so the clock should not
        // have either.
        for _ in 0 ..< 48 { phone.tap(team: .a) }
        await eventually { phone.resultRewind != nil }
        phone.undoResult()
        await eventually { clock(phone) != nil }
        #expect(clock(phone) == started, "the match never went away")

        // Filed and picked up again, which is a different thing entirely.
        phone.finish()
        await eventually { (try? store.history().first) != nil }
        phone.resume(try #require(try store.history().first).state)
        await eventually { clock(phone) != nil }

        let resumed = try #require(clock(phone))
        #expect(resumed > started, "it did not go on running while it sat in history")
        await eventually { clock(watch) == resumed }
        #expect(clock(watch) == resumed, "and the watch reads the same one")
    }
}
