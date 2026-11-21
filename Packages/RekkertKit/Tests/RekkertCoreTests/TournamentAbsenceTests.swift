import Foundation
import Testing
@testable import RekkertCore

private let p = (0 ..< 9).map { TournamentFixture.playerID($0) }

private func marking(_ player: PlayerID, away isAway: Bool = true, in tournament: Tournament, placed: RoundPlacement? = nil) -> Tournament {
    TournamentEngine.settingAway(player, isAway: isAway, after: tournament.rounds.count - 1, placed: placed, in: tournament)
}

/// Spec 008, D-3 and D-4: what marking a player as gone, or back, does to a tournament.
@Suite("Marking a player as gone")
struct TournamentAbsenceTests {
    @Test func beforeTheFirstRound() {
        let marked = marking(p[4], in: TournamentFixture.make(.americano, players: 9, courts: 2))
        #expect(marked.absences == [TournamentAbsence(player: p[4], from: 0)])
    }

    @Test func afterAFinishedRound() throws {
        let tournament = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 9, courts: 2), rounds: 2)
        let marked = marking(p[4], in: tournament)
        #expect(marked.absences == [TournamentAbsence(player: p[4], from: 2)])
        #expect(marked.rounds == tournament.rounds)
    }

    @Test func afterACancelledRound() throws {
        var tournament = try TournamentFixture.drawing(TournamentFixture.make(.mexicano, players: 9, courts: 2), rounds: 1)
        tournament = try TournamentFixture.draw(tournament)
        tournament.rounds[1].isCancelled = true
        let marked = marking(p[4], in: tournament)
        #expect(marked.absences == [TournamentAbsence(player: p[4], from: 2)])
        #expect(marked.rounds == tournament.rounds)
    }

    @Test func markingTwiceKeepsTheFirstStart() throws {
        var tournament = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 9, courts: 2), rounds: 2)
        tournament = marking(p[4], in: tournament)
        tournament = try TournamentFixture.drawing(tournament, rounds: 1)
        tournament = marking(p[4], in: tournament)
        #expect(tournament.absences == [TournamentAbsence(player: p[4], from: 2)])
    }

    @Test func aLadderAFinishedTournamentAndAStrangerAreUntouched() throws {
        let ladder = TournamentFixture.make(.winnerCourt, players: 9, courts: 2)
        #expect(marking(p[4], in: ladder) == ladder)

        var finished = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 9, courts: 2), rounds: 1)
        finished.isFinished = true
        #expect(marking(p[4], in: finished) == finished)

        let tournament = TournamentFixture.make(.americano, players: 9, courts: 2)
        #expect(marking(PlayerID(), in: tournament) == tournament)
    }
}
