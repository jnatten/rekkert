import Foundation
import Testing
@testable import RekkertCore

private func four() -> (FriendlySession, [PlayerID]) {
    let session = makeFriendly(players: 4)
    return (session, session.players.map(\.id))
}

private func keys(_ value: some Encodable) throws -> Set<String> {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return Set(object?.keys.map { $0 } ?? [])
}

@Suite("Pairing rules")
struct PairingRulesTests {
    @Test func wellFormed() {
        let p = (0 ..< 4).map { _ in PlayerID() }
        #expect(!PairingRule(kind: .apart, players: [p[0]]).isWellFormed)
        #expect(!PairingRule(kind: .apart, players: [p[0], p[0]]).isWellFormed)
        #expect(PairingRule(kind: .apart, players: [p[0], p[1]]).isWellFormed)
        #expect(PairingRule(kind: .apart, players: [p[0], p[1], p[2]]).isWellFormed)
        #expect(PairingRule(kind: .together, players: [p[0], p[1]]).isWellFormed)
        #expect(!PairingRule(kind: .together, players: [p[0], p[1], p[2]]).isWellFormed)
        #expect(!PairingRule(kind: .together, players: [p[0], p[0]]).isWellFormed)
        let rule = PairingRule(kind: .apart, players: [p[3], p[1], p[2]])
        #expect(rule.players == [p[3], p[1], p[2]].sorted(), "kept sorted, whatever order it was given in")
    }

    @Test func sameTwoBothWays() {
        let (_, p) = four()
        let apart = PairingRule(kind: .apart, players: [p[0], p[1]])
        let together = PairingRule(kind: .together, players: [p[1], p[0]])
        #expect([apart, together].conflicts == [PairingConflict(rules: [apart.id, together.id], reason: .sameTwoBothWays)])
    }

    @Test func twoPartnersForOne() {
        let (_, p) = four()
        let one = PairingRule(kind: .together, players: [p[0], p[1]])
        let two = PairingRule(kind: .together, players: [p[0], p[2]])
        #expect([one, two].conflicts == [PairingConflict(rules: [one.id, two.id], reason: .twoPartnersForOne)])
    }

    @Test func togetherInsideApart() {
        let (_, p) = four()
        let together = PairingRule(kind: .together, players: [p[0], p[1]])
        let apart = PairingRule(kind: .apart, players: [p[0], p[1], p[2]])
        #expect([together, apart].conflicts == [PairingConflict(rules: [together.id, apart.id], reason: .togetherInsideApart)])
    }

    @Test func overlappingApartGroupsDoNotClash() {
        let (_, p) = four()
        let one = PairingRule(kind: .apart, players: [p[0], p[1], p[2]])
        let two = PairingRule(kind: .apart, players: [p[1], p[2], p[3]])
        let together = PairingRule(kind: .together, players: [p[0], p[3]])
        #expect([one, two, together].conflicts.isEmpty)
    }

    @Test func pruning() {
        let (_, p) = four()
        let group = PairingRule(kind: .apart, players: [p[0], p[1], p[2]])
        let pair = PairingRule(kind: .apart, players: [p[0], p[3]])
        let together = PairingRule(kind: .together, players: [p[1], p[3]])
        let pruned = [group, pair, together].pruned(to: [p[0], p[1], p[2]])
        #expect(pruned.map(\.id) == [group.id], "the pair and the together rule each lost one")
        #expect(pruned.first?.players == [p[0], p[1], p[2]].sorted())

        let smaller = [group].pruned(to: [p[0], p[1], p[3]])
        #expect(smaller.first?.players == [p[0], p[1]].sorted(), "a group of three that loses one stays as two")
        #expect([pair].pruned(to: [p[0]]).isEmpty)
    }

    @Test func renamingKeepsThePlayerInTheRule() {
        var (session, p) = four()
        session.pairingRules = [PairingRule(kind: .apart, players: [p[0], p[1]])]
        session.players[0].name = "Renamed"
        #expect(session.activeRules.first?.players.contains(p[0]) == true)
    }

    @Test func breaks() {
        let (_, p) = four()
        let apart = [PairingRule(kind: .apart, players: [p[0], p[1]])]
        #expect(apart.breaks(BySide(a: [p[0], p[1]], b: [p[2], p[3]])) == [UnkeptRule(kind: .apart, players: [p[1], p[0]])])
        #expect(apart.breaks(BySide(a: [p[0], p[2]], b: [p[1], p[3]])).isEmpty)

        let together = [PairingRule(kind: .together, players: [p[0], p[1]])]
        #expect(together.breaks(BySide(a: [p[0], p[2]], b: [p[1], p[3]])) == [UnkeptRule(kind: .together, players: [p[0], p[1]])])
        #expect(together.breaks(BySide(a: [p[0], p[1]], b: [p[2], p[3]])).isEmpty)
        let fifth = PlayerID()
        #expect(together.breaks(BySide(a: [p[0], p[2]], b: [p[3], fifth])).isEmpty, "one of the two is on the bench")
    }

    @Test func activeRules() {
        let three = makeFriendly(players: 3)
        var singles = three
        singles.pairingRules = [PairingRule(kind: .apart, players: [three.players[0].id, three.players[1].id])]
        #expect(singles.activeRules.isEmpty, "singles have no partners")

        var (session, p) = four()
        session.pairingRules = [
            PairingRule(kind: .apart, players: [p[0], p[1]]),
            PairingRule(kind: .together, players: [p[0], p[1]]),
        ]
        #expect(session.activeRules.isEmpty, "a clashing set is no set")

        let gone = PlayerID()
        let rule = PairingRule(kind: .apart, players: [p[0], p[1], gone])
        session.pairingRules = [rule]
        #expect(session.activeRules == [PairingRule(id: rule.id, kind: .apart, players: [p[0], p[1]])])
    }

    @Test func rulesKeyIsStated() throws {
        let (session, p) = four()
        #expect(try keys(session).contains("pairingRules"), "this build always states the rules, none included")

        var older = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
        older.removeValue(forKey: "pairingRules")
        let read = try JSONDecoder().decode(FriendlySession.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(read.statedPairingRules == nil)
        #expect(read.pairingRules.isEmpty)

        let round = FriendlyRound(index: 0, teams: BySide(a: [p[0], p[1]], b: [p[2], p[3]]))
        #expect(try !keys(round).contains("unkept"))

        var withRules = session
        withRules.pairingRules = [PairingRule(kind: .apart, players: [p[0], p[1]])]
        #expect(try JSONDecoder().decode(FriendlySession.self, from: JSONEncoder().encode(withRules)) == withRules)

        var flagged = round
        flagged.unkept = [UnkeptRule(kind: .apart, players: [p[0], p[1]])]
        #expect(try JSONDecoder().decode(FriendlyRound.self, from: JSONEncoder().encode(flagged)) == flagged)
    }

    @Test func aCorrectionNotAboutTheRulesLeavesThemUnstated() {
        var (session, p) = four()
        session.pairingRules = [PairingRule(kind: .apart, players: [p[0], p[1]])]
        #expect(session.leavingPairingRulesUnstated().statedPairingRules == nil)
        #expect(session.statedPairingRules?.count == 1)
    }
}
