import Foundation
import Testing
@testable import RekkertCore

@Suite("Pairing wording")
struct PairingTextTests {
    private let session = FriendlySession(players: ["Ada", "Bob", "Cy", "Dan"].map { Player(name: $0) })
    private var ada: PlayerID { session.players[0].id }
    private var bob: PlayerID { session.players[1].id }
    private var cy: PlayerID { session.players[2].id }
    private var dan: PlayerID { session.players[3].id }

    @Test func ruleRows() {
        #expect(PairingText.rule(PairingRule(kind: .apart, players: [bob, ada]), in: session) == "Ada and Bob apart")
        #expect(PairingText.rule(PairingRule(kind: .apart, players: [cy, ada, bob]), in: session) == "Ada, Bob and Cy apart")
        #expect(PairingText.rule(PairingRule(kind: .together, players: [dan, cy]), in: session) == "Cy and Dan together")
    }

    @Test func conflicts() {
        let both = [PairingRule(kind: .apart, players: [ada, bob]), PairingRule(kind: .together, players: [ada, bob])]
        #expect(PairingText.conflict(both.conflicts[0], in: session, rules: both) == "Ada and Bob can't be kept both apart and together.")

        let two = [PairingRule(kind: .together, players: [cy, ada]), PairingRule(kind: .together, players: [cy, dan])]
        #expect(PairingText.conflict(two.conflicts[0], in: session, rules: two) == "Cy can only be kept together with one player.")

        let inside = [PairingRule(kind: .together, players: [cy, dan]), PairingRule(kind: .apart, players: [bob, cy, dan])]
        #expect(PairingText.conflict(inside.conflicts[0], in: session, rules: inside)
            == "Cy and Dan are kept together, so they can't be in a group kept apart.")
    }

    @Test func forecasts() {
        let apart = PairingForecast(rounds: 5, breaking: 2, unkept: [
            UnkeptRule(kind: .apart, players: [ada, bob]), UnkeptRule(kind: .apart, players: [bob, cy]),
        ])
        #expect(PairingText.forecast(apart, in: session)
            == "Ada, Bob and Cy can't all be kept apart in 2 of every 5 rounds — whoever sits out decides.")

        let pair = PairingForecast(rounds: 3, breaking: 3, unkept: [UnkeptRule(kind: .apart, players: [ada, bob])])
        #expect(PairingText.forecast(pair, in: session) == "Ada and Bob can't be kept apart in any round with these players.")

        let together = PairingForecast(rounds: 5, breaking: 2, unkept: [UnkeptRule(kind: .together, players: [cy, dan])])
        #expect(PairingText.forecast(together, in: session)
            == "Cy and Dan can't be kept together in 2 of every 5 rounds — whoever sits out decides.")

        let mixed = PairingForecast(rounds: 5, breaking: 2, unkept: [
            UnkeptRule(kind: .apart, players: [ada, bob]), UnkeptRule(kind: .together, players: [cy, dan]),
        ])
        #expect(PairingText.forecast(mixed, in: session)
            == "The pairing rules can't all be kept in 2 of every 5 rounds — whoever sits out decides.")

        #expect(PairingText.forecast(PairingForecast(rounds: 5, breaking: 0, unkept: []), in: session) == nil)
    }

    @Test func unkept() {
        let apart = UnkeptRule(kind: .apart, players: [ada, bob])
        #expect(PairingText.unkept(apart, in: session, offered: true)
            == "Ada and Bob are partners — the rules couldn't keep them apart this round.")
        #expect(PairingText.unkept(apart, in: session, offered: false)
            == "Ada and Bob are partners this round — the rules couldn't keep them apart.")
        let together = UnkeptRule(kind: .together, players: [cy, dan])
        #expect(PairingText.unkept(together, in: session, offered: true)
            == "Cy and Dan are on opposite sides — the rules couldn't keep them together this round.")
        #expect(PairingText.unkept(together, in: session, offered: false)
            == "Cy and Dan are on opposite sides this round — the rules couldn't keep them together.")
    }

    @Test func turnedAway() {
        #expect(PairingText.turnedAway(0) == nil)
        #expect(PairingText.turnedAway(1) == "1 phone on an older Rekkert will be taken off this match. It can join again once updated.")
        #expect(PairingText.turnedAway(2) == "2 phones on an older Rekkert will be taken off this match. They can join again once updated.")
    }

    @Test func watchNeedsUpdate() {
        #expect(PairingText.watchNeedsUpdate == "Update Rekkert on your Apple Watch to follow this friendly there.")
    }

    @Test func aPlayerNoLongerListedReadsAsADash() {
        let gone = PlayerID()
        #expect(PairingText.rule(PairingRule(kind: .apart, players: [ada, gone]), in: session) == "Ada and — apart")
    }
}
