import Foundation
import Testing
@testable import RekkertCore

@Suite("Player roster")
struct PlayerRosterTests {
    @Test func remembersNamesAndCountsRepeatAppearances() {
        var roster = PlayerRoster()
        roster.remember(["Jonas", "Ada"])
        roster.remember(["Jonas"])

        #expect(roster.players.count == 2)
        #expect(roster.players.first { $0.name == "Jonas" }?.useCount == 2)
        #expect(roster.players.first { $0.name == "Ada" }?.useCount == 1)
    }

    @Test func treatsCasingAndAccentsAsTheSamePerson() {
        var roster = PlayerRoster()
        roster.remember(["Jonas", "jonas", "JONAS"])
        #expect(roster.players.count == 1)
        #expect(roster.players[0].name == "Jonas", "the first spelling is kept")
        #expect(roster.players[0].useCount == 3)

        roster.remember(["Renée"])
        roster.remember(["renee"])
        #expect(roster.players.count == 2, "an accent is not a different person")
        #expect(roster.players.last?.useCount == 2)
    }

    @Test func findsNordicNamesTypedInPlainAscii() {
        var roster = PlayerRoster()
        roster.remember(["Bjørn", "Håkon", "Kjærsti"])

        #expect(roster.suggestions(matching: "bjorn").map(\.name) == ["Bjørn"])
        #expect(roster.suggestions(matching: "hakon").map(\.name) == ["Håkon"])
        #expect(roster.suggestions(matching: "kjaer").map(\.name) == ["Kjærsti"])
        #expect(roster.suggestions(matching: "Bjørn").map(\.name) == ["Bjørn"], "and typed properly too")
    }

    @Test func ignoresBlanksAndTrimsWhitespace() {
        var roster = PlayerRoster()
        roster.remember(["  Ada  ", "", "   "])
        #expect(roster.players.count == 1)
        #expect(roster.players[0].name == "Ada")
    }

    @Test func suggestsTheMostFamiliarNamesWhenNothingIsTyped() {
        var roster = PlayerRoster()
        roster.remember(["Rare"])
        roster.remember(["Regular", "Regular"])
        roster.remember(["Regular"])

        #expect(roster.suggestions().map(\.name) == ["Regular", "Rare"])
    }

    @Test func prefersPrefixMatchesOverMatchesInTheMiddle() {
        var roster = PlayerRoster()
        roster.remember(["Johanna", "Johanna", "Johanna"])
        roster.remember(["Ann"])

        #expect(roster.suggestions(matching: "ann").map(\.name) == ["Ann", "Johanna"])
    }

    @Test func leavesOutPlayersAlreadyChosen() {
        var roster = PlayerRoster()
        roster.remember(["Jonas", "Ada", "Kim"])

        let left = roster.suggestions(excluding: ["jonas", "KIM"]).map(\.name)
        #expect(left == ["Ada"])
    }

    @Test func forgettingRemovesAName() {
        var roster = PlayerRoster()
        roster.remember(["Jonas", "Ada"])
        roster.forget("JONAS")
        #expect(roster.players.map(\.name) == ["Ada"])
    }

    @Test func staysWithinCapacityDroppingTheLeastUsed() {
        var roster = PlayerRoster()
        roster.remember((0 ..< PlayerRoster.capacity).map { "P\($0)" })
        roster.remember(["P0", "P0"])
        roster.remember(["Newcomer"])

        #expect(roster.players.count == PlayerRoster.capacity)
        #expect(roster.players.contains { $0.name == "P0" }, "the most used name survives")
    }

    @Test func survivesARoundTripThroughTheStore() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-roster-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)

        #expect(store.loadRoster().isEmpty, "nothing remembered yet")

        var roster = store.loadRoster()
        roster.remember(["Jonas", "Ada"])
        try store.save(roster)

        #expect(store.loadRoster().suggestions().map(\.name).sorted() == ["Ada", "Jonas"])
    }
}
