import Foundation
import Testing
@testable import RekkertCore

private func leaving(_ index: Int, from tournament: Tournament) -> Tournament {
    TournamentEngine.settingAway(
        TournamentFixture.playerID(index), isAway: true, after: tournament.rounds.count - 1, placed: nil, in: tournament
    )
}

private func partners(_ round: Round) -> [PairKey] {
    round.matches.flatMap { match in TeamSide.allCases.map { PairKey(match.teams[$0][0], match.teams[$0][1]) } }
}

private func mostTimesPartnered(_ rounds: some Collection<Round>, among players: Set<PlayerID>? = nil) -> Int {
    var counts: [PairKey: Int] = [:]
    for round in rounds {
        for pair in partners(round) where players.map({ $0.contains(pair.low) && $0.contains(pair.high) }) ?? true {
            counts[pair, default: 0] += 1
        }
    }
    return counts.values.max() ?? 0
}

/// Spec 008, FR-004 and FR-008: whoever has left is in no round drawn after.
@Suite("The draw leaves out whoever has left")
struct AbsenceDrawTests {
    @Test(arguments: [TournamentFormat.americano, .mexicano], 5 ... 16)
    func nobodyAwayIsDrawn(format: TournamentFormat, players: Int) throws {
        for courts in 1 ... 4 {
            var tournament = try TournamentFixture.drawing(TournamentFixture.make(format, players: players, courts: courts), rounds: 3)
            tournament = leaving(1, from: tournament)
            tournament = try TournamentFixture.drawing(tournament, rounds: 10)
            let gone = TournamentFixture.playerID(1)
            let here = players - 1
            let playing = min(courts, here / 4)
            for round in tournament.rounds.dropFirst(3) {
                #expect(!round.matches.flatMap(\.allPlayers).contains(gone), "\(format) \(players) on \(courts): round \(round.index + 1)")
                #expect(!round.sitOuts.contains(gone))
                #expect(round.matches.count == playing)
                #expect(round.sitOuts.count == here - playing * 4)
            }
        }
    }

    @Test func mexicanoRanksOnlyThosePresent() throws {
        var tournament = try TournamentFixture.drawing(TournamentFixture.make(.mexicano, players: 9, courts: 2), rounds: 3)
        let leader = try #require(Leaderboard.standings(for: tournament, onlyConfirmed: true).first).id
        tournament = TournamentEngine.settingAway(leader, isAway: true, after: 2, placed: nil, in: tournament)
        let topFour = Leaderboard.standings(for: tournament, onlyConfirmed: true).map(\.id).filter { $0 != leader }.prefix(4)
        tournament = try TournamentFixture.draw(tournament)
        let courtOne = try #require(tournament.currentRound?.matches.first { $0.courtIndex == 0 })
        #expect(Set(courtOne.allPlayers) == Set(topFour))
    }

    /// SC-005: an Americano that lost somebody pairs the rest no worse than one that started
    /// with that many and played as many rounds. Counted over every round, since the rounds
    /// before the departure partnered the rest too, and the draw goes on from them.
    @Test(arguments: 6 ... 13)
    func americanoRepeatsNoMoreThanAFreshStart(players: Int) throws {
        let rest = players - 1
        let rounds = try #require(TournamentPlan.fewestRounds(players: rest, courts: 2))
        var tournament = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: players, courts: 2), rounds: 2)
        tournament = leaving(0, from: tournament)
        tournament = try TournamentFixture.drawing(tournament, rounds: rounds)
        let stayed = Set((1 ..< players).map { TournamentFixture.playerID($0) })
        let fresh = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: rest, courts: 2, seed: 2), rounds: 2 + rounds)
        #expect(mostTimesPartnered(tournament.rounds, among: stayed) <= mostTimesPartnered(fresh.rounds))
    }

    @Test func pickingTheBenchIgnoresWhoIsAway() throws {
        var tournament = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 10, courts: 2), rounds: 2)
        tournament = leaving(1, from: tournament)
        #expect(throws: TournamentError.invalidSitOuts) {
            try RoundScheduler.chosen([TournamentFixture.playerID(1)], in: tournament)
        }
    }
}
