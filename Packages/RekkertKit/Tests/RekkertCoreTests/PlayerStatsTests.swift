import Foundation
import Testing
@testable import RekkertCore

@Suite("Player stats across history")
struct PlayerStatsTests {
    private func stats(_ records: HistoryRecord..., links: PlayerLinks = PlayerLinks()) -> PlayerStats {
        PlayerStats.make(from: records, links: links)
    }

    // MARK: - Match and Points

    @Test func aWonMatchCountsForEveryNamedPlayerOnBothSides() throws {
        let stats = stats(Filed.record(Filed.match(["Jonas", "Ada"], ["Kim", "Sam"], winner: .a), day: 0))

        #expect(stats.named("Jonas")?.overall == Tally(won: 1))
        #expect(stats.named("Ada")?.overall == Tally(won: 1))
        #expect(stats.named("Kim")?.overall == Tally(lost: 1))
        #expect(stats.named("Sam")?.overall == Tally(lost: 1))

        let jonas = try #require(stats.named("Jonas"))
        #expect(jonas.partners.map(\.name) == ["Ada"])
        #expect(Set(jonas.opponents.map(\.name)) == ["Kim", "Sam"])
        #expect(jonas.modes.map(\.name) == ["Match"])
    }

    @Test func aStoppedMatchWithoutAWinnerCountsForNobody() throws {
        let stats = stats(Filed.record(Filed.match(["Jonas"], ["Kim"], winner: nil), day: 0))

        let jonas = try #require(stats.named("Jonas"), "still listed, so they can be merged or separated")
        #expect(jonas.overall.played == 0)
        #expect(jonas.appearances.count == 1)
    }

    @Test func aPointsRoundTiedAtTheTargetIsADraw() {
        let stats = stats(Filed.record(Filed.points(["Jonas"], ["Kim"], .score(8, 8)), day: 0))
        #expect(stats.named("Jonas")?.overall == Tally(drawn: 1))
        #expect(stats.named("Kim")?.overall == Tally(drawn: 1))
    }

    @Test func aStoppedPointsRoundIsLeftOut() {
        let stats = stats(Filed.record(Filed.points(["Jonas"], ["Kim"], .score(5, 3), stopped: true), day: 0))
        #expect(stats.named("Jonas")?.overall.played == 0)
    }

    // MARK: - Winner court

    @Test func everyCompletedWinnerCourtRoundCountsAndALevelOneIsADraw() {
        let stats = stats(Filed.record(
            Filed.winnerCourt(["Jonas", "Ada"], [], rounds: [.score(6, 4), .score(3, 5), .score(4, 4)]),
            day: 0
        ))
        #expect(stats.named("Jonas")?.overall == Tally(won: 1, drawn: 1, lost: 1))
    }

    @Test func theWinnerCourtRoundStillInProgressIsLeftOut() {
        let stats = stats(Filed.record(
            Filed.winnerCourt(["Jonas"], [], rounds: [.score(6, 4)], inProgress: .score(3, 1)),
            day: 0
        ))
        #expect(stats.named("Jonas")?.overall.played == 1)
    }

    @Test func winnerCourtCountsForPartnersButNotHeadToHead() throws {
        let stats = stats(Filed.record(
            Filed.winnerCourt(["Jonas", "Ada"], ["Kim"], rounds: [.score(6, 4)]),
            day: 0
        ))
        let jonas = try #require(stats.named("Jonas"))
        #expect(jonas.partners.map(\.name) == ["Ada"])
        #expect(jonas.opponents.isEmpty, "whoever was across the net changed at every whistle")
        #expect(stats.named("Kim")?.overall == Tally(lost: 1))
    }

    // MARK: - Friendly

    @Test func aFriendlyCountsOnlyTheRoundsSomebodyWon() {
        let group = Group("Jonas", "Ada", "Kim", "Sam")
        let state = Filed.friendly(group, rounds: [
            Filed.round(0, group[0, 1], group[2, 3], winner: .a),
            Filed.round(1, group[0, 2], group[1, 3], winner: nil),
        ])
        let stats = stats(Filed.record(state, day: 0))

        #expect(stats.named("Jonas")?.overall == Tally(won: 1))
        #expect(stats.named("Jonas")?.partners.map(\.name) == ["Ada"])
    }

    @Test func aSinglesFriendlyHasOpponentsButNoPartners() throws {
        let group = Group("Jonas", "Kim")
        let stats = stats(Filed.record(
            Filed.friendly(group, rounds: [Filed.round(0, group[0], group[1], winner: .b)]),
            day: 0
        ))
        let jonas = try #require(stats.named("Jonas"))
        #expect(jonas.overall == Tally(lost: 1))
        #expect(jonas.partners.isEmpty)
        #expect(jonas.opponents.map(\.name) == ["Kim"])
    }

    // MARK: - Americano and Mexicano

    @Test func onlyFinishedOrConfirmedCourtsCountAndCancelledRoundsAreSkipped() {
        let group = Group("Jonas", "Ada", "Kim", "Sam")
        let state = Filed.tournament(group, rounds: [
            Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: []),
            Round(index: 1, matches: [Filed.court(group[0, 2], group[1, 3], .score(5, 3), confirmed: true)], sitOuts: []),
            Round(index: 2, matches: [Filed.court(group[0, 3], group[1, 2], .score(16, 0))], sitOuts: [], isCancelled: true),
        ])
        let stats = stats(Filed.record(state, day: 0))
        #expect(stats.named("Jonas")?.overall == Tally(won: 2))
    }

    @Test func partScoredCourtsInARoundSavedMidwayAreLeftOut() {
        let group = Group("Jonas", "Ada", "Kim", "Sam")
        let state = Filed.tournament(group, rounds: [
            Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(9, 7))], sitOuts: []),
            Round(index: 1, matches: [Filed.court(group[0, 2], group[1, 3], .score(5, 3))], sitOuts: []),
        ])
        let stats = stats(Filed.record(state, day: 0))
        #expect(stats.named("Jonas")?.overall == Tally(won: 1))
        #expect(stats.named("Jonas")?.points[.americano]?.pointsFor == 9)
    }

    @Test func americanoPointsAverageOverCourtsPlayedAndIgnoreSitOutCompensation() throws {
        let group = Group("Jonas", "Ada", "Kim", "Sam", "Ola")
        let state = Filed.tournament(group, rounds: [
            Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: group[4]),
            Round(index: 1, matches: [Filed.court(group[0, 4], group[1, 2], .score(7, 9))], sitOuts: group[3]),
        ])
        let stats = stats(Filed.record(state, day: 0))

        let jonas = try #require(stats.named("Jonas")?.points[.americano])
        #expect(jonas.rounds == 2)
        #expect(jonas.average == 8.5)
        #expect(jonas.share == 17.0 / 32.0)

        let ola = try #require(stats.named("Ola")?.points[.americano])
        #expect(ola.rounds == 1, "the round on the bench scores compensation, not points played")
        #expect(ola.average == 7)
    }

    @Test func mexicanoPointsAreKeptApartFromAmericano() throws {
        let group = Group("Jonas", "Ada", "Kim", "Sam")
        let rounds = [Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: [])]
        let stats = stats(
            Filed.record(Filed.tournament(group, rounds: rounds), day: 0),
            Filed.record(Filed.tournament(group, format: .mexicano, rounds: rounds), day: 1)
        )
        let jonas = try #require(stats.named("Jonas"))
        #expect(jonas.points[.americano]?.rounds == 1)
        #expect(jonas.points[.mexicano]?.rounds == 1)
        #expect(Set(jonas.modes.map(\.name)) == ["Americano", "Mexicano"])
    }

    // MARK: - People

    @Test func teamNamesAndBlankSlotsAreNobody() throws {
        let state = SessionState.traditional({
            var session = TraditionalSession(
                rules: TraditionalRules(setsToWin: 1),
                teams: BySide(a: TeamInfo(name: "Blue", players: ["", "Ada"]), b: TeamInfo(name: "Orange"))
            )
            session.score = session.engine.winGames(6, for: .a, from: session.score)
            return session
        }())
        let stats = stats(Filed.record(state, day: 0))

        #expect(stats.people.map(\.name) == ["Ada"])
        #expect(stats.named("Ada")?.overall == Tally(won: 1))
        #expect(stats.named("Ada")?.partners.isEmpty == true)
    }

    @Test func caseAndAccentsFoldTogetherButØIsNotO() {
        let stats = stats(
            Filed.record(Filed.match(["jonas"], ["Bjørn"], winner: .a), day: 0),
            Filed.record(Filed.match(["Jónas"], ["Bjorn"], winner: .a), day: 1)
        )
        #expect(stats.named("Jonas")?.overall.played == 2)
        #expect(stats.named("Bjørn")?.overall.played == 1)
        #expect(stats.named("Bjorn")?.overall.played == 1)
        #expect(stats.named("Bjørn")?.id != stats.named("Bjorn")?.id)
    }

    @Test func theDisplayNameIsTheMostRecentSpelling() throws {
        let stats = stats(
            Filed.record(Filed.match(["Jonas"], ["Kim"], winner: .a), day: 0),
            Filed.record(Filed.match(["jonas "], ["Kim"], winner: .a), day: 1),
            Filed.record(Filed.match(["JONAS"], ["Kim"], winner: .a), day: 2)
        )
        let jonas = try #require(stats.named("Jonas"))
        #expect(jonas.name == "JONAS")
        #expect(jonas.spellings == ["JONAS", "jonas", "Jonas"])
    }

    @Test func somebodyWhoOnlySatOutIsListedWithNoResults() throws {
        let group = Group("Jonas", "Ada", "Kim", "Sam", "Ola")
        let state = Filed.tournament(group, rounds: [
            Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: group[4]),
        ])
        let stats = stats(Filed.record(state, day: 0))

        let ola = try #require(stats.named("Ola"))
        #expect(ola.overall.played == 0)
        #expect(ola.points.isEmpty)
        #expect(stats.people.last?.name == "Ola", "the people with nothing decided go last")
    }

    @Test func aRenamedPlayerFollowsTheNewName() {
        let record = Filed.record(Filed.match(["Jon", "Ada"], ["Kim"], winner: .a), day: 0)
        let renamed = record.renamed(.sides(event: "", teams: Filed.teams(["John", ""], [])))
        let stats = stats(renamed)

        #expect(stats.named("John")?.overall == Tally(won: 1))
        #expect(stats.named("Jon") == nil)
    }

    @Test func thePeopleWhoPlayedMostAreListedFirst() {
        let stats = stats(
            Filed.record(Filed.match(["Ada"], ["Kim"], winner: .a), day: 0),
            Filed.record(Filed.match(["Ada"], ["Sam"], winner: .a), day: 1)
        )
        #expect(stats.people.map(\.name) == ["Ada", "Kim", "Sam"])
    }

    // MARK: - Resumed sessions

    @Test func aResumedTournamentCountsOnce() {
        let group = Group("Jonas", "Ada", "Kim", "Sam")
        let id = TournamentID()
        let first = Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: [])
        let second = Round(index: 1, matches: [Filed.court(group[0, 2], group[1, 3], .score(10, 6))], sitOuts: [])
        let stats = stats(
            Filed.record(Filed.tournament(group, id: id, rounds: [first]), day: 0),
            Filed.record(Filed.tournament(group, id: id, rounds: [first, second]), day: 1)
        )
        #expect(stats.named("Jonas")?.overall == Tally(won: 2))
        #expect(stats.named("Jonas")?.appearances.count == 1)
    }

    @Test func aResumedFriendlyCountsOnce() {
        let group = Group("Jonas", "Ada", "Kim", "Sam")
        let id = FriendlyID()
        let first = Filed.round(0, group[0, 1], group[2, 3], winner: .a)
        let second = Filed.round(1, group[0, 2], group[1, 3], winner: .a)
        let stats = stats(
            Filed.record(Filed.friendly(group, id: id, rounds: [first]), day: 0),
            Filed.record(Filed.friendly(group, id: id, rounds: [first, second]), day: 1)
        )
        #expect(stats.named("Jonas")?.overall == Tally(won: 2))
    }

    @Test func aResumedWinnerCourtCountsOnce() {
        let original = Filed.record(Filed.winnerCourt(["Jonas"], [], rounds: [.score(6, 4)]), day: 0)
        let resumed = Filed.record(Filed.winnerCourt(["Jonas"], [], rounds: [.score(6, 4), .score(5, 3)]), day: 1)
        var links = PlayerLinks()
        links.resume(resumed.id, from: original.id)

        let stats = stats(original, resumed, links: links)
        #expect(stats.named("Jonas")?.overall == Tally(won: 2))
        #expect(stats.named("Jonas")?.appearances.map(\.record) == [resumed.id])
    }

    // MARK: - Partners and opponents

    @Test func theBestPartnerNeedsThreeContestsTogether() throws {
        let stats = stats(
            Filed.record(Filed.match(["Jonas", "Ada"], ["X", "Y"], winner: .a), day: 0),
            Filed.record(Filed.match(["Jonas", "Ada"], ["X", "Y"], winner: .a), day: 1),
            Filed.record(Filed.match(["Jonas", "Kim"], ["X", "Y"], winner: .a), day: 2),
            Filed.record(Filed.match(["Jonas", "Kim"], ["X", "Y"], winner: .a), day: 3),
            Filed.record(Filed.match(["Jonas", "Kim"], ["X", "Y"], winner: .b), day: 4)
        )
        let jonas = try #require(stats.named("Jonas"))
        #expect(jonas.bestPartner?.name == "Kim", "Ada has a perfect record, but only two games of it")
        #expect(jonas.bestPartner?.tally == Tally(won: 2, lost: 1))
        #expect(stats.named("Ada")?.bestPartner == nil)
    }

    @Test func bestPartnerTiesGoToMoreWins() throws {
        let ada = (0 ..< 3).map { Filed.record(Filed.match(["Jonas", "Ada"], ["X"], winner: .a), day: $0) }
        let kim = (3 ..< 7).map { Filed.record(Filed.match(["Jonas", "Kim"], ["X"], winner: .a), day: $0) }
        let stats = PlayerStats.make(from: ada + kim, links: PlayerLinks())

        #expect(stats.named("Jonas")?.bestPartner?.name == "Kim")
    }

    @Test func headToHeadReadsTheSameFromEitherSide() throws {
        let stats = stats(
            Filed.record(Filed.match(["Jonas"], ["Kim"], winner: .a), day: 0),
            Filed.record(Filed.match(["Kim"], ["Jonas"], winner: .a), day: 1),
            Filed.record(Filed.match(["Jonas"], ["Kim"], winner: .a), day: 2)
        )
        #expect(stats.named("Jonas")?.opponents.first?.tally == Tally(won: 2, lost: 1))
        #expect(stats.named("Kim")?.opponents.first?.tally == Tally(won: 1, lost: 2))
    }

    // MARK: - Clashes

    @Test func twoPlayersWithTheSameNameInOneSessionAreAClash() throws {
        let group = Group("John", "John", "Ada", "Kim")
        let record = Filed.record(Filed.tournament(group, rounds: [
            Round(index: 0, matches: [Filed.court(group[0, 2], group[1, 3], .score(10, 6))], sitOuts: []),
        ]), day: 0)
        let stats = stats(record)

        let john = try #require(stats.named("John"))
        #expect(john.clashes == [record.id])
        #expect(john.overall.played == 0, "a person on both sides of a court gets nothing from it")
        #expect(Set(john.appearances.map(\.tally)) == [Tally(won: 1), Tally(lost: 1)], "each seat keeps its own result")

        let ada = try #require(stats.named("Ada"))
        #expect(ada.overall == Tally(won: 1))
        #expect(ada.partners.isEmpty)
        #expect(ada.opponents.map(\.name) == ["Kim"])
    }

    @Test func aPersonIsNeverTheirOwnPartner() throws {
        let group = Group("John", "John", "Ada", "Kim")
        let record = Filed.record(Filed.tournament(group, rounds: [
            Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: []),
        ]), day: 0)
        let stats = stats(record)

        let john = try #require(stats.named("John"))
        #expect(john.overall == Tally(won: 1), "counted once, not once per seat")
        #expect(john.partners.isEmpty)
        #expect(john.clashes == [record.id])
    }
}
