import Foundation
import Testing
@testable import RekkertCore

private let early = DeviceID(UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000006")!)
private let late = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000006")!)

private func friendlyLog(players: Int = 4) -> MatchLog {
    var log = MatchLog(sessionID: UUID(uuidString: "33333333-0000-0000-0000-000000000006")!)
    log.append(.configure(.friendly(makeFriendly(players: players))), from: late)
    log.drawFriendlyRound(from: late)
    return log
}

private func friendly(_ log: MatchLog) -> FriendlySession? {
    guard case .friendly(let session)? = SessionReducer.state(of: log) else { return nil }
    return session
}

private func endRound(_ log: inout MatchLog, from device: DeviceID) {
    guard let session = friendly(log) else { return }
    log.append(.point(round: session.currentIndex, court: 0, team: .a), from: device)
    log.append(.endRound(round: session.currentIndex), from: device)
}

private func olderCorrection(of session: FriendlySession) throws -> FriendlySession {
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
    object.removeValue(forKey: "pairingRules")
    return try JSONDecoder().decode(FriendlySession.self, from: JSONSerialization.data(withJSONObject: object))
}

@Suite("A friendly draw stays where it was placed")
struct FriendlyPlacementTests {
    @Test func aRuleChangeRacingADrawKeepsTheRound() throws {
        var log = friendlyLog()
        endRound(&log, from: late)
        let before = try #require(friendly(log))
        let placed = try #require(before.nextDraw())

        var drawing = log
        var changing = log
        var withRule = before
        withRule.pairingRules = [PairingRule(kind: .apart, players: placed.teams.a)]
        changing.append(.configure(.friendly(withRule)), from: early)
        drawing.append(.nextRound(after: 0, placed: RoundPlacement(placed)), from: late)
        _ = drawing.merge(Array(changing.events.values))
        _ = changing.merge(Array(drawing.events.values))

        for merged in [drawing, changing] {
            let session = try #require(friendly(merged))
            #expect(session.rounds.count == 2)
            #expect(session.rounds[1].teams == placed.teams, "the round people walked onto stays")
            #expect(session.pairingRules == withRule.pairingRules)
            let next = try #require(session.nextDraw())
            #expect(!TeamSide.allCases.contains { Set(next.teams[$0]) == Set(placed.teams.a) }, "the rule holds from the next round")
        }
        #expect(SessionReducer.state(of: drawing) == SessionReducer.state(of: changing))
    }

    @Test func aPlacementThatDoesNotFitIsDrawn() throws {
        var log = friendlyLog(players: 5)
        endRound(&log, from: late)
        let session = try #require(friendly(log))
        let expected = try #require(session.nextDraw())
        let p = session.players.map(\.id)
        let misfits = [
            RoundPlacement(courts: [BySide(a: [p[0], p[0]], b: [p[2], p[3]])], sitOuts: [p[4]]),
            RoundPlacement(courts: [BySide(a: [p[0], p[1]], b: [p[2], p[3]])], sitOuts: []),
            RoundPlacement(courts: [BySide(a: [p[0], p[1], p[4]], b: [p[2], p[3]])], sitOuts: []),
            RoundPlacement(courts: [BySide(a: [p[0]], b: [p[2]])], sitOuts: [p[1], p[3], p[4]]),
        ]
        for misfit in misfits {
            var placedLog = log
            placedLog.append(.nextRound(after: 0, placed: misfit), from: late)
            #expect(friendly(placedLog)?.rounds.last?.teams == expected.teams)
            #expect(friendly(placedLog)?.rounds.last?.sitOuts == expected.sitOuts)
        }
    }

    @Test func unkeptIsTheDrawTimeRules() throws {
        var log = friendlyLog()
        endRound(&log, from: late)
        log.drawFriendlyRound(from: late)
        let drawn = try #require(friendly(log))
        var withRule = drawn
        withRule.pairingRules = [PairingRule(kind: .apart, players: drawn.rounds[1].teams.a)]
        log.append(.configure(.friendly(withRule)), from: late)

        let after = try #require(friendly(log))
        #expect(after.rounds[1].unkept.isEmpty, "drawn before the rule, judged by the rules it was drawn under")
        endRound(&log, from: late)
        log.drawFriendlyRound(from: late)
        let third = try #require(friendly(log)?.rounds[2])
        #expect(!TeamSide.allCases.contains { Set(third.teams[$0]) == Set(drawn.rounds[1].teams.a) })
    }

    @Test func aCorrectionAdoptsTheRules() throws {
        var log = friendlyLog()
        let session = try #require(friendly(log))
        var withRule = session
        withRule.pairingRules = [PairingRule(kind: .apart, players: [session.players[0].id, session.players[1].id])]
        log.append(.configure(.friendly(withRule)), from: late)
        let adopted = try #require(friendly(log))
        #expect(adopted.pairingRules == withRule.pairingRules)
        #expect(adopted.id == session.id)
        #expect(adopted.rounds == session.rounds)

        var cleared = adopted
        cleared.pairingRules = []
        log.append(.configure(.friendly(cleared)), from: late)
        #expect(friendly(log)?.pairingRules.isEmpty == true)
    }

    @Test func anOlderCorrectionLeavesTheRules() throws {
        var log = friendlyLog()
        let session = try #require(friendly(log))
        var withRule = session
        withRule.pairingRules = [PairingRule(kind: .apart, players: [session.players[0].id, session.players[1].id])]
        log.append(.configure(.friendly(withRule)), from: late)

        var older = try olderCorrection(of: try #require(friendly(log)))
        older.rules.changeEnds = older.rules.changeEnds == .off ? .oddGames : .off
        log.append(.configure(.friendly(older)), from: early)
        let after = try #require(friendly(log))
        #expect(after.pairingRules == withRule.pairingRules, "an older build's correction cannot wipe them")
        #expect(after.rules.changeEnds == older.rules.changeEnds)
    }

    @Test func swapSidesNeverRevertsTheRulesInEitherOrder() throws {
        let base = friendlyLog()
        let session = try #require(friendly(base))
        var withRule = session
        withRule.pairingRules = [PairingRule(kind: .apart, players: [session.players[0].id, session.players[1].id])]
        var swapped = session
        swapped.rules.changeEnds = session.rules.changeEnds == .off ? .oddGames : .off

        for (ruleFrom, swapFrom) in [(early, late), (late, early)] {
            var one = base
            var two = base
            one.append(.configure(.friendly(withRule)), from: ruleFrom)
            two.append(.configure(.friendly(swapped.leavingPairingRulesUnstated())), from: swapFrom)
            _ = one.merge(Array(two.events.values))
            let after = try #require(friendly(one))
            #expect(after.pairingRules == withRule.pairingRules)
        }
    }
}
