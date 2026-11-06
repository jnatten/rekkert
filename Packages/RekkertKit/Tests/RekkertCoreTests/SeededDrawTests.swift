import Foundation
import Testing
@testable import RekkertCore

/// Every device folds the same log into the same draw, so a draw may never change between
/// builds or between a phone and a watch. These were taken from builds already installed, on
/// 64-bit hardware: a build that draws anything else disagrees with them.
@Suite("Seeded draws")
struct SeededDrawTests {
    private func tournament(_ format: TournamentFormat, players: Int, courts: Int) -> Tournament {
        Tournament(
            id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!),
            name: "Test",
            format: format,
            players: (0 ..< players).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
        )
    }

    private func friendly(players: Int) -> FriendlySession {
        FriendlySession(
            id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!),
            name: "Thursday",
            rules: TraditionalRules(setsToWin: 1),
            players: (0 ..< players).map { Player(name: "P\($0)") }
        )
    }

    private func drawing(_ tournament: Tournament, rounds: Int) throws -> Tournament {
        try (0 ..< rounds).reduce(tournament) { current, _ in try TournamentEngine.appendingRound(to: current) }
    }

    private func courts(_ tournament: Tournament) -> [[[[String]]]] {
        tournament.rounds.map { round in
            round.matches.map { match in
                TeamSide.allCases.map { side in match.teams[side].compactMap { tournament.player($0)?.name } }
            }
        }
    }

    private func benches(_ tournament: Tournament) -> [[String]] {
        tournament.rounds.map { $0.sitOuts.compactMap { tournament.player($0)?.name } }
    }

    @Test func americanoWithABenchDrawsAsItAlwaysHas() throws {
        let t = try drawing(tournament(.americano, players: 6, courts: 1), rounds: 3)
        #expect(courts(t) == [
            [[["P2", "P3"], ["P0", "P5"]]],
            [[["P1", "P4"], ["P5", "P3"]]],
            [[["P4", "P0"], ["P2", "P1"]]],
        ])
        #expect(benches(t) == [["P4", "P1"], ["P2", "P0"], ["P3", "P5"]])
    }

    @Test func americanoOnTwoCourtsDrawsAsItAlwaysHas() throws {
        let t = try drawing(tournament(.americano, players: 9, courts: 2), rounds: 3)
        #expect(courts(t) == [
            [[["P1", "P3"], ["P2", "P4"]], [["P5", "P7"], ["P0", "P8"]]],
            [[["P4", "P5"], ["P2", "P7"]], [["P0", "P3"], ["P8", "P6"]]],
            [[["P5", "P8"], ["P6", "P4"]], [["P2", "P1"], ["P0", "P7"]]],
        ])
        #expect(benches(t) == [["P6"], ["P1"], ["P3"]])
    }

    @Test func mexicanoFirstRoundDrawsAsItAlwaysHas() throws {
        let t = try drawing(tournament(.mexicano, players: 6, courts: 1), rounds: 1)
        #expect(courts(t) == [[[["P2", "P5"], ["P3", "P0"]]]])
        #expect(benches(t) == [["P4", "P1"]])
    }

    @Test func randomLadderStartDrawsAsItAlwaysHas() throws {
        let t = try drawing(makeLadder(players: 10, courts: 2, start: .random), rounds: 1)
        #expect(courts(t) == [[[["P0", "P1"], ["P8", "P9"]], [["P2", "P3"], ["P6", "P7"]]]])
        #expect(benches(t) == [["P4", "P5"]])
    }

    @Test(arguments: [
        (4, [[["P0", "P2"], ["P3", "P1"]], [["P1", "P0"], ["P3", "P2"]], [["P2", "P1"], ["P3", "P0"]]], [[String]](repeating: [], count: 3)),
        (5, [[["P3", "P0"], ["P4", "P2"]], [["P0", "P4"], ["P3", "P1"]], [["P4", "P1"], ["P2", "P0"]]], [["P1"], ["P2"], ["P3"]]),
    ])
    func friendlyDrawsAsItAlwaysHas(players: Int, teams: [[[String]]], bench: [[String]]) throws {
        let session = try (0 ..< 3).reduce(friendly(players: players)) { current, _ in
            try FriendlyScheduler.appendingRound(to: current)
        }
        func name(_ id: PlayerID) -> String? { session.players.first { $0.id == id }?.name }
        #expect(session.rounds.map { round in TeamSide.allCases.map { round.teams[$0].compactMap(name) } } == teams)
        #expect(session.rounds.map { $0.sitOuts.compactMap(name) } == bench)
    }

    /// Pinned to numbers, which the `UInt64` arithmetic gives whatever the width of `Int`.
    @Test func drawsBelowABoundArePinned() {
        var generator = SeededGenerator(seed: 42)
        let bounds: [UInt64] = [2, 3, 6, 7, 1000, 1 << 40, .max]
        #expect(bounds.map { generator.next(below: $0) } == [1, 0, 1, 2, 38, 954_626_865_724, 4_028_864_712_777_624_924])
    }

    /// Installed builds drew with the stdlib's shuffle, so on 64-bit hardware the seeded one
    /// has to be it exactly.
    @Test(.enabled(if: Int.bitWidth == 64))
    func theSeededShuffleIsTheStdlibsOnSixtyFourBits() {
        var seeds = TestGenerator(seed: 2026)
        var differing: [(seed: UInt64, length: Int)] = []
        for _ in 0 ..< 1000 {
            let seed = seeds.next()
            for length in 0 ... 16 {
                var seeded = SeededGenerator(seed: seed)
                var stdlib = TestGenerator(seed: seed)
                let items = Array(0 ..< length)
                if items.shuffled(seededBy: &seeded) != items.shuffled(using: &stdlib) {
                    differing.append((seed, length))
                }
            }
        }
        #expect(differing.isEmpty, "\(differing.prefix(5))")
    }
}
