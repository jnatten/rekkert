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

    @Test func eightWithFourApart() throws {
        let session = try draw(ruled(makeFriendly(players: 8), apart(0, 1, 2, 3)), rounds: 30)
        let group = Set(session.players.prefix(4).map(\.id))
        var history = PairingHistory()
        for round in session.rounds {
            for side in TeamSide.allCases {
                #expect(Set(round.teams[side]).intersection(group).count < 2, "two of the four as partners")
            }
            let repeats = { (teams: BySide<[PlayerID]>) in
                TeamSide.allCases.contains { history.partnerCount(teams[$0][0], teams[$0][1]) > 0 }
            }
            if repeats(round.teams) {
                let four = round.teams.a + round.teams.b
                let keeping = fourWayPartitions(four).filter { session.activeRules.breaks($0).isEmpty }
                #expect(keeping.allSatisfy(repeats), "a fresh partner was there to be had")
            }
            history.record([round.teams], sitOuts: round.sitOuts)
        }
    }

    @Test(arguments: 5 ... 12)
    func benchStaysFair(players: Int) throws {
        let session = try draw(ruled(makeFriendly(players: players), apart(0, 1, 2)), rounds: 30)
        var counts = Dictionary(uniqueKeysWithValues: session.players.map { ($0.id, 0) })
        for round in session.rounds {
            for id in round.sitOuts { counts[id, default: 0] += 1 }
            #expect((counts.values.max() ?? 0) - (counts.values.min() ?? 0) <= 1)
        }
    }

    @Test func tieBreakLeansTowardsTheRules() throws {
        let session = try draw(ruled(makeFriendly(players: 5), apart(0, 1, 2)), rounds: 10)
        let group = Set(session.players.prefix(3).map(\.id))
        let broken = session.rounds.filter { !$0.unkept.isEmpty }
        #expect(broken.count == 4, "two in every five: when the bench has to take one of the other two")
        for round in broken {
            #expect(round.unkept.count == 1)
            #expect(round.unkept.allSatisfy { $0.kind == .apart && Set($0.players).isSubset(of: group) })
        }
        for round in session.rounds where round.unkept.isEmpty {
            for side in TeamSide.allCases {
                #expect(Set(round.teams[side]).intersection(group).count < 2)
            }
        }
    }

    @Test func fourWithThreeApartFlagsEveryRound() throws {
        let session = try draw(ruled(makeFriendly(players: 4), apart(0, 1, 2)), rounds: 9)
        #expect(session.rounds.allSatisfy { !$0.unkept.isEmpty })
        #expect(Set(session.rounds.prefix(3).map(partition)).count == 3)
        for round in session.rounds {
            #expect(round.teams == session.rounds[round.index % 3].teams)
        }
    }

    @Test func sixteenPlayersDrawPromptly() throws {
        let session = ruled(makeFriendly(players: 16), apart(0, 1, 2, 3, 4, 5, 6, 7))
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try draw(session, rounds: 30) }
        #expect(elapsed < .milliseconds(500))
    }

    @Test func fourWithTwoTogetherRepeat() throws {
        let session = try draw(ruled(makeFriendly(players: 4), together(0, 1)), rounds: 20)
        let p = session.players.map(\.id)
        #expect(arePartners(session.rounds[0], p[0], p[1]))
        #expect(session.rounds.allSatisfy { $0.teams == session.rounds[0].teams && $0.unkept.isEmpty })
    }

    @Test func sixWithTwoTogether() throws {
        let session = try draw(ruled(makeFriendly(players: 6), together(0, 1)), rounds: 12)
        let p = session.players.map(\.id)
        var counts = Dictionary(uniqueKeysWithValues: p.map { ($0, 0) })
        for round in session.rounds {
            let onCourt = Set(round.teams.a + round.teams.b)
            if onCourt.contains(p[0]), onCourt.contains(p[1]) {
                #expect(arePartners(round, p[0], p[1]))
            }
            #expect(round.unkept.isEmpty)
            for id in round.sitOuts { counts[id, default: 0] += 1 }
            #expect((counts.values.max() ?? 0) - (counts.values.min() ?? 0) <= 1)
        }
    }

    @Test func togetherAndApartThatCannotBothHoldAreFlagged() throws {
        let rules = { (ids: [PlayerID]) in together(0, 1)(ids) + apart(2, 3)(ids) }
        let session = try draw(ruled(makeFriendly(players: 4), rules), rounds: 9)
        #expect(session.rounds.allSatisfy { $0.unkept.count == 1 })
        for round in session.rounds {
            #expect(round.teams == session.rounds[round.index % 3].teams)
        }
    }

    @Test func fourAfterAMidSessionChange() throws {
        var session = try draw(makeFriendly(players: 4), rounds: 3)
        let p = session.players.map(\.id)
        let allowed = session.rounds.filter { !arePartners($0, p[0], p[1]) }
        #expect(allowed.count == 2)
        session.pairingRules = [PairingRule(kind: .apart, players: [p[0], p[1]])]
        let after = try draw(session, rounds: 3)
        #expect(after.rounds[3].teams == allowed[0].teams, "the allowed line-up that came up first, sides and all")
        #expect(after.rounds[4].teams == allowed[1].teams)
        #expect(after.rounds[5].teams == allowed[0].teams)
    }
}
