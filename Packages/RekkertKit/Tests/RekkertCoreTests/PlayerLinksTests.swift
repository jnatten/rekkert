import Foundation
import Testing
@testable import RekkertCore

@Suite("Merging and separating players")
struct PlayerLinksTests {
    private let jon = Filed.record(Filed.match(["Jon"], ["Kim"], winner: .a), day: 0)
    private let john = Filed.record(Filed.match(["John"], ["Kim"], winner: .a), day: 1)
    private let johnny = Filed.record(Filed.match(["Johnny"], ["Kim"], winner: .a), day: 2)

    private func appearance(of name: String, in record: HistoryRecord, _ stats: PlayerStats) throws -> Appearance {
        try #require(stats.people.flatMap(\.appearances).first { $0.record == record.id && $0.name == name })
    }

    private func johns() -> [HistoryRecord] {
        (0 ..< 3).map { Filed.record(Filed.match(["John"], ["Kim"], winner: .a), day: $0) }
    }

    // MARK: - Merging

    @Test func mergingTwoNamesCountsThemAsOne() throws {
        var links = PlayerLinks()
        let kept = links.merge(.named("Jon"), into: .named("John"))
        let stats = PlayerStats.make(from: [jon, john], links: links)

        #expect(kept == .named("John"))
        let person = try #require(stats.named("John"))
        #expect(person.overall == Tally(won: 2))
        #expect(person.merged.map(\.name) == ["Jon"])
        #expect(stats.named("Jon")?.id == person.id, "a page still open on Jon finds where he went")
        #expect(stats.people.count == 2)
    }

    @Test func aMergedNameTakesItsFutureAppearancesToo() {
        var links = PlayerLinks()
        links.merge(.named("Jon"), into: .named("John"))
        let later = Filed.record(Filed.match(["Jon"], ["Kim"], winner: .b), day: 5)
        let stats = PlayerStats.make(from: [jon, john, later], links: links)

        #expect(stats.named("John")?.overall == Tally(won: 2, lost: 1))
    }

    @Test func unmergingBringsBackTheNameAndEverythingMergedIntoIt() {
        var links = PlayerLinks()
        links.merge(.named("Johnny"), into: .named("Jon"))
        links.merge(.named("Jon"), into: .named("John"))
        #expect(PlayerStats.make(from: [jon, john, johnny], links: links).named("John")?.overall.played == 3)

        links.unmerge(.named("Jon"))
        let stats = PlayerStats.make(from: [jon, john, johnny], links: links)
        #expect(stats.named("John")?.overall.played == 1)
        #expect(stats.named("Jon")?.overall.played == 2)
        #expect(stats.named("Jon")?.merged.map(\.name) == ["Johnny"])
    }

    @Test func mergingAPersonWithThemselvesOrTheirOwnMergedNameChangesNothing() {
        var links = PlayerLinks()
        links.merge(.named("John"), into: .named("john"))
        #expect(links == PlayerLinks())

        links.merge(.named("Jon"), into: .named("John"))
        let merged = links
        #expect(links.merge(.named("John"), into: .named("Jon")) == .named("John"))
        #expect(links == merged)
    }

    @Test func mergingRoundInACircleNeverLoops() {
        var links = PlayerLinks()
        links.merge(.named("Jon"), into: .named("John"))
        links.merge(.named("John"), into: .named("Johnny"))
        links.merge(.named("Johnny"), into: .named("Jon"))

        #expect(links.canonical(.named("Jon")) == .named("Johnny"))
        #expect(links.canonical(.named("Johnny")) == .named("Johnny"))
        #expect(PlayerStats.make(from: [jon, john, johnny], links: links).people.count == 2)
    }

    @Test func aNameAbsorbsASeparatedPersonWhicheverWayRoundTheMergeIsDone() throws {
        let records = johns()
        let stats = PlayerStats.make(from: records, links: PlayerLinks())
        let seat = try appearance(of: "John", in: records[0], stats)

        for intoSeparated in [false, true] {
            var links = PlayerLinks()
            let other = links.separate([seat], note: "from work")
            let kept = intoSeparated
                ? links.merge(.named("John"), into: other)
                : links.merge(other, into: .named("John"))
            #expect(kept == .named("John"))
            #expect(PlayerStats.make(from: records, links: links).named("John")?.overall.played == 3)
            #expect(links.note(for: .named("John")) == nil, "the note stays with who it was written about")
        }
    }

    // MARK: - Separating

    @Test func separatingMovesOnlyTheChosenAppearances() throws {
        let records = johns()
        var links = PlayerLinks()
        let seat = try appearance(of: "John", in: records[1], PlayerStats.make(from: records, links: links))
        let other = links.separate([seat], note: "  from work ")
        let stats = PlayerStats.make(from: records, links: links)

        #expect(stats.named("John")?.overall.played == 2)
        #expect(stats.person(other)?.overall.played == 1)
        #expect(stats.person(other)?.name == "John")
        #expect(stats.person(other)?.note == "from work")
        #expect(stats.person(other)?.appearances.map(\.record) == [records[1].id])
    }

    @Test func aNewAppearanceOfTheNameStillJoinsTheMainPlayer() throws {
        let records = johns()
        var links = PlayerLinks()
        let other = links.separate([try appearance(of: "John", in: records[1], PlayerStats.make(from: records, links: links))])
        let later = Filed.record(Filed.match(["John"], ["Kim"], winner: .a), day: 9)
        let stats = PlayerStats.make(from: records + [later], links: links)

        #expect(stats.named("John")?.overall.played == 3)
        #expect(stats.person(other)?.overall.played == 1)
    }

    @Test func separatingEveryAppearanceLeavesTheNameWithNobody() throws {
        let records = johns()
        var links = PlayerLinks()
        let all = try #require(PlayerStats.make(from: records, links: links).named("John")).appearances
        let other = links.separate(all)
        let stats = PlayerStats.make(from: records, links: links)

        #expect(stats.named("John") == nil)
        #expect(stats.person(other)?.overall.played == 3)
    }

    @Test func movingAnAppearanceBackToItsOwnNameLeavesNoPlacementBehind() throws {
        let records = johns()
        var links = PlayerLinks()
        let seat = try appearance(of: "John", in: records[1], PlayerStats.make(from: records, links: links))
        links.separate([seat])
        links.move([seat], to: .named("John"))

        #expect(links.seats.isEmpty)
        #expect(PlayerStats.make(from: records, links: links).named("John")?.overall.played == 3)
    }

    @Test func movingToSomebodyElseSurvivesUnmergingTheirOldName() throws {
        var links = PlayerLinks()
        links.merge(.named("Jon"), into: .named("John"))
        let seat = try appearance(of: "Jon", in: jon, PlayerStats.make(from: [jon, john], links: links))
        links.move([seat], to: .named("John"))
        links.unmerge(.named("Jon"))

        let stats = PlayerStats.make(from: [jon, john], links: links)
        #expect(stats.named("John")?.overall.played == 2, "placed on John by hand, not just through the merge")
        #expect(stats.named("Jon") == nil)
    }

    // MARK: - What a placement survives

    @Test func aSeparatedPlayerStaysSeparateThroughARenameInAMatch() throws {
        let records = johns()
        var links = PlayerLinks()
        let other = links.separate([try appearance(of: "John", in: records[0], PlayerStats.make(from: records, links: links))])
        let renamed = records[0].renamed(.sides(event: "", teams: Filed.teams(["Johnny"], [])))
        let stats = PlayerStats.make(from: [renamed] + records.dropFirst(), links: links)

        #expect(stats.person(other)?.appearances.map(\.name) == ["Johnny"])
        #expect(stats.named("Johnny") == nil)
        #expect(stats.named("John")?.overall.played == 2)
    }

    @Test func aSeparatedPlayerStaysSeparateThroughARenameInATournament() throws {
        let group = Group("John", "Ada", "Kim", "Sam")
        let record = Filed.record(Filed.tournament(group, rounds: [
            Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: []),
        ]), day: 0)
        var links = PlayerLinks()
        let other = links.separate([try appearance(of: "John", in: record, PlayerStats.make(from: [record], links: links))])

        guard case .tournament(let tournament) = record.state else { Issue.record("not a tournament"); return }
        let renamed = record.renamed(.group(
            event: tournament.name,
            players: tournament.players.map { $0.name == "John" ? Player(id: $0.id, name: "Johnny") : $0 }
        ))
        let stats = PlayerStats.make(from: [renamed], links: links)

        #expect(stats.person(other)?.name == "Johnny")
        #expect(stats.person(other)?.overall == Tally(won: 1))
        #expect(stats.named("Johnny") == nil)
    }

    @Test func aPlacementCarriesIntoTheSessionResumedFromIt() throws {
        let original = Filed.record(Filed.winnerCourt(["John"], [], rounds: [.score(6, 4)]), day: 0)
        let resumed = Filed.record(Filed.winnerCourt(["John"], [], rounds: [.score(6, 4), .score(2, 6)]), day: 1)
        var links = PlayerLinks()
        let other = links.separate([try appearance(of: "John", in: original, PlayerStats.make(from: [original], links: links))])
        links.resume(resumed.id, from: original.id)
        let stats = PlayerStats.make(from: [original, resumed], links: links)

        #expect(stats.person(other)?.appearances.map(\.record) == [resumed.id])
        #expect(stats.person(other)?.overall == Tally(won: 1, lost: 1))
        #expect(stats.named("John") == nil)
    }

    // MARK: - Storage

    @Test func linksSurviveARoundTripThroughTheStore() throws {
        let store = SessionStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let records = johns()
        var links = PlayerLinks()
        links.merge(.named("Jon"), into: .named("John"))
        let other = links.separate([try appearance(of: "John", in: records[0], PlayerStats.make(from: records, links: links))], note: "from work")
        links.resume(UUID(), from: records[0].id)
        links.setNote("brother-in-law", for: .named("John"))

        try store.save(links)
        #expect(store.loadLinks() == links)
        #expect(store.loadLinks().note(for: other) == "from work")
    }

    @Test func aLinksFileMissingAFieldStillDecodes() throws {
        #expect(try JSONCoding.decoder.decode(PlayerLinks.self, from: Data("{}".utf8)) == PlayerLinks())

        var links = PlayerLinks()
        links.merge(.named("Jon"), into: .named("John"))
        var json = try #require(try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(links)) as? [String: Any])
        json["seats"] = nil
        json["resumed"] = nil
        let decoded = try JSONCoding.decoder.decode(PlayerLinks.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == links)
    }

    @Test func aMissingLinksFileIsNoLinks() {
        let store = SessionStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        #expect(store.loadLinks() == PlayerLinks())
    }
}
