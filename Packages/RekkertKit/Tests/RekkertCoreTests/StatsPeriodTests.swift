import Foundation
import Testing
@testable import RekkertCore

@Suite("Stats over a period")
struct StatsPeriodTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// A Monday afternoon.
    private var now: Date { day(2026, 9, 28, hour: 15) }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func interval(_ period: StatsPeriod) -> DateInterval? {
        period.interval(now: now, calendar: calendar)
    }

    // MARK: - Where a period starts and ends

    @Test func allTimeHasNoBounds() {
        #expect(interval(.allTime) == nil)
    }

    @Test func theLastSevenDaysAreTodayAndTheSixBefore() {
        #expect(interval(.last(7, .day)) == DateInterval(start: day(2026, 9, 22), end: day(2026, 9, 29)))
    }

    @Test func theLastTwelveMonthsRunToTheEndOfToday() {
        #expect(interval(.last(12, .month)) == DateInterval(start: day(2025, 9, 29), end: day(2026, 9, 29)))
    }

    @Test func theLastFiveYears() {
        #expect(interval(.last(5, .year)) == DateInterval(start: day(2021, 9, 29), end: day(2026, 9, 29)))
    }

    @Test func yearToDateStartsOnTheFirstOfJanuary() {
        #expect(interval(.current(.year)) == DateInterval(start: day(2026, 1, 1), end: day(2026, 9, 29)))
    }

    @Test func thisWeekStartsOnTheCalendarsFirstDayOfTheWeek() {
        #expect(interval(.current(.week)) == DateInterval(start: day(2026, 9, 28), end: day(2026, 9, 29)))
    }

    @Test func lastWeekIsTheWholeWeekBeforeThisOne() {
        #expect(interval(.previous(.week)) == DateInterval(start: day(2026, 9, 21), end: day(2026, 9, 28)))
    }

    @Test func lastMonthIsTheWholeMonthBeforeThisOne() {
        #expect(interval(.previous(.month)) == DateInterval(start: day(2026, 8, 1), end: day(2026, 9, 1)))
    }

    @Test func lastYearIsTheCalendarYearBefore() {
        #expect(interval(.previous(.year)) == DateInterval(start: day(2025, 1, 1), end: day(2026, 1, 1)))
    }

    @Test func aYearIsThatCalendarYear() {
        #expect(interval(.year(2024)) == DateInterval(start: day(2024, 1, 1), end: day(2025, 1, 1)))
    }

    @Test func sinceRunsToTheEndOfToday() {
        #expect(interval(.since(day(2026, 3, 3, hour: 18))) == DateInterval(start: day(2026, 3, 3), end: day(2026, 9, 29)))
    }

    @Test func betweenTakesInBothDaysWhicheverWayRoundTheyAreGiven() {
        let expected = DateInterval(start: day(2026, 3, 3), end: day(2026, 4, 10))
        #expect(interval(.between(day(2026, 3, 3, hour: 9), day(2026, 4, 9, hour: 9))) == expected)
        #expect(interval(.between(day(2026, 4, 9), day(2026, 3, 3))) == expected)
    }

    @Test func eachPeriodSaysWhatItIs() {
        #expect(StatsPeriod.allTime.title == "All time")
        #expect(StatsPeriod.last(30, .day).title == "Last 30 days")
        #expect(StatsPeriod.last(1, .week).title == "Past week")
        #expect(StatsPeriod.current(.year).title == "Year to date")
        #expect(StatsPeriod.current(.month).title == "This month")
        #expect(StatsPeriod.previous(.year).title == "Last year")
        #expect(StatsPeriod.previous(.day).title == "Yesterday")
        #expect(StatsPeriod.year(2025).title == "2025")
    }

    @Test func aPeriodSurvivesBeingSaved() throws {
        for period: StatsPeriod in [.allTime, .last(30, .day), .previous(.year), .year(2025), .between(now, day(2026, 1, 1))] {
            let decoded = try JSONCoding.decoder.decode(StatsPeriod.self, from: JSONCoding.encoder.encode(period))
            #expect(decoded == period)
        }
    }

    // MARK: - What gets counted

    @Test func onlyMatchesFinishedInThePeriodCount() {
        let august = HistoryRecord(finishedAt: day(2026, 8, 20), title: "", state: Filed.match(["Jonas"], ["Kim"], winner: .a))
        let september = HistoryRecord(finishedAt: day(2026, 9, 20), title: "", state: Filed.match(["Jonas"], ["Ada"], winner: .b))

        let stats = PlayerStats.make(from: [august, september], links: PlayerLinks(), during: interval(.previous(.month)))
        #expect(stats.named("Jonas")?.overall == Tally(won: 1))
        #expect(stats.named("Kim") != nil)
        #expect(stats.named("Ada") == nil, "nobody who only played outside it is listed")
    }

    @Test func aResumedTournamentCountsInThePeriodOfTheCopyHoldingItsRounds() {
        let group = Group("Jonas", "Ada", "Kim", "Sam")
        let id = TournamentID()
        let first = Round(index: 0, matches: [Filed.court(group[0, 1], group[2, 3], .score(10, 6))], sitOuts: [])
        let second = Round(index: 1, matches: [Filed.court(group[0, 2], group[1, 3], .score(10, 6))], sitOuts: [])
        let records = [
            HistoryRecord(finishedAt: day(2026, 8, 30), title: "", state: Filed.tournament(group, id: id, rounds: [first])),
            HistoryRecord(finishedAt: day(2026, 9, 2), title: "", state: Filed.tournament(group, id: id, rounds: [first, second])),
        ]

        let august = PlayerStats.make(from: records, links: PlayerLinks(), during: interval(.previous(.month)))
        let september = PlayerStats.make(from: records, links: PlayerLinks(), during: interval(.current(.month)))
        #expect(august.people.isEmpty, "the older copy is only part of the one resumed from it")
        #expect(september.named("Jonas")?.overall == Tally(won: 2))
    }
}
