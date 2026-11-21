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

private func inPlay(_ format: TournamentFormat = .americano, players: Int = 9) throws -> Tournament {
    try TournamentFixture.draw(TournamentFixture.drawing(TournamentFixture.make(format, players: players, courts: 2), rounds: 2))
}

private func scoring(_ tournament: Tournament, court: Int, _ points: BySide<Int>) -> Tournament {
    var scored = tournament
    let last = scored.rounds.count - 1
    scored.rounds[last].matches[court].state.points = points
    return scored
}

/// Spec 008, D-3 cases 2 and 3: leaving while the round is being played.
@Suite("Leaving mid-round")
struct LeavingMidRoundTests {
    @Test(arguments: [TournamentFormat.americano, .mexicano])
    func anUnstartedRoundIsDrawnAgainWithoutThem(format: TournamentFormat) throws {
        let tournament = try inPlay(format)
        let round = try #require(tournament.currentRound)
        let leaving = round.matches[0].teams.a[0]

        let marked = marking(leaving, in: tournament)
        #expect(marked.absences == [TournamentAbsence(player: leaving, from: round.index)])
        let redrawn = try #require(marked.currentRound)
        #expect(redrawn.index == round.index)
        #expect(!redrawn.matches.flatMap(\.allPlayers).contains(leaving))
        #expect(!redrawn.sitOuts.contains(leaving))

        var expected = tournament
        expected.absences = marked.absences
        let picks = Array(round.sitOuts.filter { $0 != leaving }.prefix(0))
        #expect(redrawn == (try TournamentFixture.redraw(expected, picking: picks)).currentRound)
    }

    @Test func theCarriedRedrawIsTakenWhenItIsForThisRound() throws {
        let tournament = try inPlay()
        let round = try #require(tournament.currentRound)
        let leaving = round.matches[0].teams.a[0]
        let recomputed = try #require(marking(leaving, in: tournament).currentRound)
        var courts = recomputed.matches.map(\.teams)
        let moved = courts[1].a[0]
        courts[1].a[0] = courts[1].b[1]
        courts[1].b[1] = moved
        let carried = RoundPlacement(courts: courts, sitOuts: recomputed.sitOuts)

        let taken = TournamentEngine.settingAway(leaving, isAway: true, after: round.index, placed: carried, in: tournament)
        #expect(taken.currentRound?.matches.map(\.teams) == courts)

        let stale = TournamentEngine.settingAway(leaving, isAway: true, after: round.index - 1, placed: carried, in: tournament)
        #expect(stale.currentRound == recomputed)
    }

    @Test func aCourtWithPointsStopsWhereItStands() throws {
        let tournament = scoring(try inPlay(), court: 0, BySide(a: 6, b: 5))
        let round = try #require(tournament.currentRound)
        let leaving = round.matches[0].teams.b[1]

        let marked = marking(leaving, in: tournament)
        #expect(marked.absences == [TournamentAbsence(player: leaving, from: round.index + 1)])
        #expect(marked.rounds[round.index].matches[0].isConfirmed)
        #expect(marked.rounds[round.index].matches[0].state.points == BySide(a: 6, b: 5))
        #expect(marked.rounds[round.index].matches.map(\.teams) == round.matches.map(\.teams))
        #expect(!marked.rounds[round.index].matches[1].isConfirmed)

        var state: SessionState? = .tournament(marked)
        SessionReducer.apply(.point(round: round.index, court: 0, team: .a), to: &state)
        guard case .tournament(let after)? = state else {
            Issue.record("still a tournament")
            return
        }
        #expect(after.rounds[round.index].matches[0].state.points == BySide(a: 6, b: 5), "a stopped court takes no more points")
    }

    @Test func theRoundClosesWhenTheOthersFinish() throws {
        let tournament = scoring(try inPlay(), court: 0, BySide(a: 6, b: 5))
        let round = try #require(tournament.currentRound)
        var marked = marking(round.matches[0].teams.a[0], in: tournament)
        #expect(!marked.canDrawNextRound)
        marked = scoring(marked, court: 1, BySide(a: 16, b: 0))
        #expect(marked.isDone(try #require(marked.currentRound)))
        #expect(marked.canDrawNextRound)
    }

    @Test func aZeroZeroCourtStopsToo() throws {
        let tournament = scoring(try inPlay(), court: 1, BySide(a: 5, b: 3))
        let round = try #require(tournament.currentRound)
        let leaving = round.matches[0].teams.a[1]

        let marked = marking(leaving, in: tournament)
        #expect(marked.absences == [TournamentAbsence(player: leaving, from: round.index + 1)])
        #expect(marked.rounds[round.index].matches[0].isConfirmed)
        #expect(marked.rounds[round.index].matches[0].state.points == BySide(a: 0, b: 0))
    }

    @Test func leavingFromTheBenchKeepsItsCredit() throws {
        let tournament = scoring(try inPlay(), court: 0, BySide(a: 3, b: 2))
        let round = try #require(tournament.currentRound)
        let benched = try #require(round.sitOuts.first)

        var marked = marking(benched, in: tournament)
        #expect(marked.absences == [TournamentAbsence(player: benched, from: round.index + 1)])
        #expect(marked.rounds == tournament.rounds)

        marked = TournamentFixture.score(marked, round: round.index)
        let standing = try #require(Leaderboard.standings(for: marked).first { $0.id == benched })
        let sitOuts = marked.rounds.count { $0.sitOuts.contains(benched) }
        #expect(standing.sitOuts == sitOuts)
        #expect(standing.compensation == sitOuts * marked.config.sitOutCompensation.points(target: marked.config.pointRules.target))
    }

    @Test func markingAgainSettlesARacedRound() throws {
        var tournament = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 9, courts: 2), rounds: 2)
        let p3 = TournamentFixture.playerID(3)
        tournament.absences = [TournamentAbsence(player: p3, from: 2)]
        let ids = (0 ..< 9).map { TournamentFixture.playerID($0) }
        let raced = RoundPlacement(
            courts: [BySide(a: [ids[0], ids[1]], b: [ids[2], ids[3]]), BySide(a: [ids[4], ids[5]], b: [ids[6], ids[7]])],
            sitOuts: [ids[8]]
        )
        tournament = try TournamentEngine.appendingRound(to: tournament, placed: raced)
        #expect(tournament.awayPlayersOnCourt(inRound: 2) == [p3])

        let unplayed = marking(p3, in: tournament)
        #expect(unplayed.absences == tournament.absences)
        #expect(unplayed.awayPlayersOnCourt(inRound: 2).isEmpty)
        #expect(!(unplayed.currentRound?.matches.flatMap(\.allPlayers).contains(p3) ?? true))

        let played = marking(p3, in: scoring(tournament, court: 0, BySide(a: 4, b: 4)))
        #expect(played.absences == tournament.absences)
        #expect(played.rounds[2].matches[0].isConfirmed)
        #expect(played.rounds[2].matches.map(\.teams) == raced.courts)
    }
}
