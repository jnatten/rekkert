import Foundation
import Testing
@testable import RekkertCore

private let p = (0 ..< 9).map { TournamentFixture.playerID($0) }

private func twoRoundsIn() throws -> Tournament {
    try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 9, courts: 2), rounds: 2)
}

private func placement(_ courts: [[PlayerID]], bench: [PlayerID]) -> RoundPlacement {
    RoundPlacement(courts: courts.map { BySide(a: [$0[0], $0[1]], b: [$0[2], $0[3]]) }, sitOuts: bench)
}

/// Spec 008, D-5: whatever a draw carries is where people walked on, and stays so.
@Suite("A carried draw stands")
struct AbsencePlacementTests {
    @Test func americanoAdoptsAFittingPlacement() throws {
        let tournament = try twoRoundsIn()
        let sitOuts = TournamentEngine.sitOuts(for: tournament)
        let recomputed = try #require(try TournamentEngine.appendingRound(to: tournament, sitOuts: sitOuts).currentRound)
        var courts = recomputed.matches.map(\.teams)
        let moved = courts[0].a[1]
        courts[0].a[1] = courts[0].b[0]
        courts[0].b[0] = moved
        let carried = RoundPlacement(courts: courts, sitOuts: recomputed.sitOuts)

        let adopted = try TournamentEngine.appendingRound(to: tournament, sitOuts: sitOuts, placed: carried)
        #expect(adopted.currentRound?.matches.map(\.teams) == courts)
    }

    @Test func aPlacementMayIncludeSomeoneAway() throws {
        var tournament = try twoRoundsIn()
        tournament.absences = [TournamentAbsence(player: p[3], from: tournament.rounds.count)]
        let carried = placement([[p[0], p[1], p[2], p[3]], [p[4], p[5], p[6], p[7]]], bench: [p[8]])

        let adopted = try TournamentEngine.appendingRound(to: tournament, placed: carried)
        let round = try #require(adopted.currentRound)
        #expect(round.matches.map(\.teams) == carried.courts)
        #expect(round.sitOuts == [p[8]])
        #expect(adopted.awayPlayersOnCourt(inRound: round.index) == [p[3]])
    }

    @Test func awayPlayersOnAPlacedBenchGetNoCredit() throws {
        var tournament = try twoRoundsIn()
        tournament.absences = [TournamentAbsence(player: p[3], from: tournament.rounds.count)]
        let carried = placement([[p[0], p[1], p[2], p[4]], [p[5], p[6], p[7], p[8]]], bench: [p[3]])

        var adopted = try TournamentEngine.appendingRound(to: tournament, placed: carried)
        let round = try #require(adopted.currentRound)
        #expect(round.matches.map(\.teams) == carried.courts)
        #expect(round.sitOuts.isEmpty)

        adopted = TournamentFixture.score(adopted, round: round.index)
        let before = try #require(Leaderboard.standings(for: tournament).first { $0.id == p[3] })
        let after = try #require(Leaderboard.standings(for: adopted).first { $0.id == p[3] })
        #expect(after.compensation == before.compensation)
        #expect(after.sitOuts == before.sitOuts)
    }

    @Test func aPlacementMissingSomeonePresentIsRefused() throws {
        let tournament = try twoRoundsIn()
        let carried = placement([[p[0], p[1], p[2], p[3]], [p[4], p[5], p[6], p[7]]], bench: [])
        let sitOuts = TournamentEngine.sitOuts(for: tournament)

        let adopted = try TournamentEngine.appendingRound(to: tournament, sitOuts: sitOuts, placed: carried)
        let recomputed = try TournamentEngine.appendingRound(to: tournament, sitOuts: sitOuts)
        #expect(adopted.currentRound == recomputed.currentRound)
    }

    @Test func aPlacementWithAStrangerOrTwiceTheSamePlayerIsRefused() throws {
        let tournament = try twoRoundsIn()
        let stranger = PlayerID()
        let recomputed = try TournamentEngine.appendingRound(to: tournament)
        for carried in [
            placement([[p[0], p[1], p[2], p[3]], [p[4], p[5], p[6], p[7]]], bench: [stranger]),
            placement([[p[0], p[1], p[2], p[3]], [p[4], p[5], p[6], p[7]]], bench: [p[8], p[8]]),
        ] {
            #expect(try TournamentEngine.appendingRound(to: tournament, placed: carried).currentRound == recomputed.currentRound)
        }
    }
}
