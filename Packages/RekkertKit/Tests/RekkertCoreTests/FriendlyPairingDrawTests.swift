import Foundation
import Testing
@testable import RekkertCore

func ruled(_ session: FriendlySession, _ rules: ([PlayerID]) -> [PairingRule]) -> FriendlySession {
    var ruled = session
    ruled.pairingRules = rules(session.players.map(\.id))
    return ruled
}

func apart(_ indices: Int...) -> ([PlayerID]) -> [PairingRule] {
    { ids in [PairingRule(kind: .apart, players: indices.map { ids[$0] })] }
}

func together(_ one: Int, _ two: Int) -> ([PlayerID]) -> [PairingRule] {
    { ids in [PairingRule(kind: .together, players: [ids[one], ids[two]])] }
}

func arePartners(_ round: FriendlyRound, _ one: PlayerID, _ two: PlayerID) -> Bool {
    TeamSide.allCases.contains { round.teams[$0].contains(one) && round.teams[$0].contains(two) }
}

@Suite("A friendly draws with its pairing rules")
struct FriendlyPairingDrawTests {
    @Test func fourWithTwoApartAlternate() throws {
        let session = try draw(ruled(makeFriendly(players: 4), apart(0, 1)), rounds: 20)
        let p = session.players.map(\.id)
        #expect(session.rounds.allSatisfy { !arePartners($0, p[0], p[1]) })
        #expect(partition(session.rounds[0]) != partition(session.rounds[1]))
        for round in session.rounds {
            #expect(round.teams == session.rounds[round.index % 2].teams, "round \(round.index + 1) repeats, sides and all")
            #expect(round.unkept.isEmpty)
        }
    }

    @Test(arguments: 5 ... 12)
    func aPairApartIsAlwaysKept(players: Int) throws {
        let session = try draw(ruled(makeFriendly(players: players), apart(0, 1)), rounds: 30)
        let p = session.players.map(\.id)
        #expect(session.rounds.allSatisfy { !arePartners($0, p[0], p[1]) && $0.unkept.isEmpty })
    }

    @Test(arguments: 2 ... 3)
    func singlesIgnoreRules(players: Int) throws {
        let plain = try draw(makeFriendly(players: players), rounds: 6)
        let withRule = try draw(ruled(makeFriendly(players: players), apart(0, 1)), rounds: 6)
        #expect(drawn(withRule) == drawn(plain))
        #expect(withRule.rounds.allSatisfy { $0.unkept.isEmpty })
    }

    @Test func clashingRulesDrawAsNone() throws {
        let plain = try draw(makeFriendly(players: 5), rounds: 10)
        let clashing = ruled(makeFriendly(players: 5)) { ids in
            [PairingRule(kind: .apart, players: [ids[0], ids[1]]), PairingRule(kind: .together, players: [ids[0], ids[1]])]
        }
        let drawnClashing = try draw(clashing, rounds: 10)
        #expect(drawn(drawnClashing) == drawn(plain))
        #expect(drawnClashing.rounds.allSatisfy { $0.unkept.isEmpty })
    }
}
