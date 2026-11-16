import Foundation
import Testing
@testable import RekkertCore

private func counted(_ session: FriendlySession, rounds: Int) throws -> (breaking: Int, unkept: [UnkeptRule]) {
    let drawn = try draw(session, rounds: rounds)
    var unkept: [UnkeptRule] = []
    for round in drawn.rounds.suffix(rounds) {
        for one in round.unkept where !unkept.contains(one) { unkept.append(one) }
    }
    return (drawn.rounds.suffix(rounds).count { !$0.unkept.isEmpty }, unkept)
}

@Suite("The pairing forecast")
struct PairingForecastTests {
    @Test func rotationLength() {
        for (players, rounds) in [(5, 5), (6, 3), (7, 7), (8, 2), (12, 3), (16, 4)] {
            #expect(ruled(makeFriendly(players: players), apart(0, 1, 2)).forecast()?.rounds == rounds, "\(players) players")
        }
        #expect(ruled(makeFriendly(players: 4), apart(0, 1)).forecast()?.rounds == 2)
        #expect(ruled(makeFriendly(players: 4), together(0, 1)).forecast()?.rounds == 1)
        #expect(ruled(makeFriendly(players: 4), apart(0, 1, 2)).forecast()?.rounds == 3)
        #expect(ruled(makeFriendly(players: 2), apart(0, 1)).forecast() == nil)
        #expect(ruled(makeFriendly(players: 3), apart(0, 1)).forecast() == nil)
        #expect(makeFriendly(players: 6).forecast() == nil)
    }

    @Test(arguments: 4 ... 12)
    func matchesTheDraw(players: Int) throws {
        let half = Array(0 ..< players / 2)
        let sets: [([PlayerID]) -> [PairingRule]] = [
            apart(0, 1),
            apart(0, 1, 2),
            { ids in [PairingRule(kind: .apart, players: half.map { ids[$0] })] },
            together(0, 1),
            { ids in together(0, 1)(ids) + apart(2, 3)(ids) },
        ]
        for rules in sets {
            let session = ruled(makeFriendly(players: players), rules)
            let forecast = try #require(session.forecast())
            let actual = try counted(session, rounds: forecast.rounds)
            #expect(forecast.breaking == actual.breaking)
            #expect(forecast.unkept == actual.unkept)
        }
    }

    @Test func midSessionPlaysOnFromHere() throws {
        let session = try draw(ruled(makeFriendly(players: 5), apart(0, 1, 2)), rounds: 3)
        let forecast = try #require(session.forecast())
        let actual = try counted(session, rounds: forecast.rounds)
        #expect(forecast.breaking == actual.breaking)
        #expect(forecast.unkept == actual.unkept)
    }
}
