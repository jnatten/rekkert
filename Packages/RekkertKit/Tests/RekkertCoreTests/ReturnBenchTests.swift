import Foundation
import Testing
@testable import RekkertCore

private let p1 = TournamentFixture.playerID(1)

private func set(_ player: PlayerID, away isAway: Bool, in tournament: Tournament) -> Tournament {
    TournamentEngine.settingAway(player, isAway: isAway, after: tournament.rounds.count - 1, placed: nil, in: tournament)
}

/// Away for rounds 3–5, back for round 6, as every device folds it.
private func backForSix(_ format: TournamentFormat, players: Int) throws -> Tournament {
    var tournament = try TournamentFixture.drawing(TournamentFixture.make(format, players: players, courts: 2), rounds: 2)
    tournament = set(p1, away: true, in: tournament)
    tournament = try TournamentFixture.drawing(tournament, rounds: 3)
    return set(p1, away: false, in: tournament)
}

/// Spec 008, D-6 and FR-016: whoever comes back is owed neither a rest nor a game.
@Suite("A returner is owed neither a rest nor a game")
struct ReturnBenchTests {
    @Test(arguments: [TournamentFormat.americano, .mexicano], [9, 10, 13])
    func theyPlayTheirFirstRoundBack(format: TournamentFormat, players: Int) throws {
        let tournament = try TournamentFixture.draw(backForSix(format, players: players))
        let round = try #require(tournament.currentRound)
        #expect(round.index == 5)
        #expect(!round.sitOuts.contains(p1))
        #expect(round.matches.flatMap(\.allPlayers).contains(p1))
    }

    @Test(arguments: [TournamentFormat.americano, .mexicano], [9, 10, 13])
    func theyRejoinTheRotation(format: TournamentFormat, players: Int) throws {
        var tournament = try backForSix(format, players: players)
        let bench = players - 8
        let rotation = (players + bench - 1) / bench
        tournament = try TournamentFixture.drawing(tournament, rounds: rotation)
        let since = tournament.rounds.dropFirst(5)
        let counts = Dictionary(uniqueKeysWithValues: tournament.players.map { player in
            (player.id, since.count { $0.sitOuts.contains(player.id) })
        })
        let rest = counts.filter { $0.key != p1 }.map(\.value)
        let returner = try #require(counts[p1])
        #expect(abs(returner - rest.min()!) <= 1, "\(format) \(players): \(returner) against \(rest.min()!)…\(rest.max()!)")
        #expect(returner <= rest.max()!)
    }

    @Test func nobodyLeftMeansTodaysHistory() throws {
        let tournament = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 10, courts: 2), rounds: 6)
        let history = PairingHistory(tournament)
        for player in tournament.players {
            let benched = tournament.rounds.filter { $0.sitOuts.contains(player.id) }
            #expect(history.sitOutCount(player.id) == benched.count)
            #expect(history.lastSitOut(player.id) == benched.last?.index)
        }
    }
}
