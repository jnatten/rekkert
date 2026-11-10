import Foundation
import RekkertCore
import Testing

@Suite("A summary of each stretch of sharing")
struct SharingSummaryTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let host = DeviceID()
    private let guest = DeviceID()
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func entry(_ seconds: Double, _ kind: LinkEvent, _ link: LinkRecordEntry.Link = .radio,
                       on device: LinkRecordEntry.Device = .phone, radios: [LinkRadio]? = nil, detail: String? = nil) -> LinkRecordEntry {
        LinkRecordEntry(time: at(seconds), device: device, link: link, kind: kind, radios: radios, detail: detail)
    }

    /// A guest on the host over both radios, and `count` points arriving every 10 s.
    private func guestStint(points latencies: [TimeInterval?], from offset: Double = 0) -> [LinkRecordEntry] {
        var entries = [
            entry(offset, .joined),
            entry(offset + 1, .proven, .host(host), radios: [.bluetooth]),
            entry(offset + 2, .proven, .host(host), radios: [.wifi]),
        ]
        for (index, latency) in latencies.enumerated() {
            entries.append(entry(offset + 40 + Double(index) * 10, .pointArrived(latency: latency), .host(host), radios: [.wifi]))
        }
        return entries
    }

    @Test func aStintRunsFromAJoinUntilTheGuestLeaves() {
        var entries = guestStint(points: [0.3])
        entries.append(entry(100, .newMatchAnswered(.leave)))
        entries.append(entry(200, .pointArrived(latency: 0.5), .host(host)))
        entries += guestStint(points: [0.4], from: 300)
        let summaries = LinkRecord(entries).summaries()
        #expect(summaries.count == 2)
        #expect(summaries.map(\.role) == [.guest, .guest])
        #expect(summaries.map(\.points) == [1, 1])
        #expect(summaries[0].end == at(100))
    }

    @Test func hostingStartsWhenSharingStartsOrComesBack() {
        let entries = [
            entry(0, .sharingStarted), entry(50, .sharingStopped),
            entry(100, .sharingRestored), entry(150, .proven, .guest(guest), radios: [.bluetooth]),
        ]
        let summaries = LinkRecord(entries).summaries()
        #expect(summaries.map(\.role) == [.host, .host])
        #expect(summaries.map(\.start) == [at(0), at(100)])
        #expect(summaries[1].end == at(150))
    }

    @Test func delaysAreCountedWhereNothingWasWrong() {
        let latencies: [TimeInterval?] = Array(repeating: 0.4, count: 96) + [1.5, 1.5, 3.0, 0.2]
        let summary = LinkRecord(guestStint(points: latencies)).summaries()[0]
        #expect(summary.points == 100)
        #expect(summary.knownDelays == 100)
        #expect(summary.medianDelay == 0.4)
        #expect(summary.slowestDelay == 3.0)
        #expect(summary.withinOne == 0.97)
        #expect(summary.withinTwo == 0.99)
        #expect(summary.judgeable)
    }

    @Test func fewerThanAHundredTimedPointsCannotBeJudged() {
        let summary = LinkRecord(guestStint(points: Array(repeating: 0.4, count: 99))).summaries()[0]
        #expect(!summary.judgeable)
        #expect(summary.line(in: .current).contains("not enough timed points"))
    }

    @Test func unknownDelaysCountAgainstTheCapButOlderOnesDoNot() {
        var entries = guestStint(points: Array(repeating: 0.4, count: 100) + Array(repeating: nil, count: 12))
        entries.append(entry(5_000, .pointArrived(latency: nil), .host(host), radios: [.wifi], detail: "older"))
        let summary = LinkRecord(entries).summaries()[0]
        #expect(summary.olderPoints == 1)
        #expect(summary.unknownShare.map { abs($0 - 12.0 / 112.0) < 1e-9 } == true)
        #expect(!summary.judgeable)
        #expect(summary.line(in: .current).contains("too many unknown"))
    }

    @Test func dropsAreCountedPerRadioAndTheHostsOwnRestartsApart() {
        let entries = [
            entry(0, .sharingStarted),
            entry(10, .dropped(.closedByPeer), .guest(guest), radios: [.wifi], detail: "ETIMEDOUT"),
            entry(20, .dropped(.closedByPeer), .guest(guest), radios: [.wifi]),
            entry(30, .dropped(.timeout), .guest(guest), radios: [.bluetooth]),
            entry(40, .radioOff),
            entry(40.001, .dropped(.radioOff), .guest(guest), radios: [.bluetooth]),
            entry(42, .radioOn),
        ]
        let summary = LinkRecord(entries).summaries()[0]
        #expect(summary.drops == [.wifi: 2, .bluetooth: 1])
        #expect(summary.hostRestarts == 1)
    }

    @Test func unreachableTimeRunsFromOutOfReachToBackInStep() {
        let entries = [
            entry(0, .sharingStarted),
            entry(100, .outOfReach, .guest(guest)), entry(131, .backInStep, .guest(guest)),
            entry(200, .outOfReach, .guest(guest)), entry(212, .backInStep, .guest(guest)),
        ]
        let summary = LinkRecord(entries).summaries()[0]
        #expect(summary.unreachable[String(guest.raw.uuidString.prefix(4))] == 43)
    }

    @Test func batteryIsGivenPerHourForPhoneAndWatch() {
        let entries = [
            entry(0, .joined),
            entry(1, .battery(level: 0.9)), entry(1, .battery(level: 0.8), on: .watch),
            entry(7_201, .battery(level: 0.78)), entry(7_201, .battery(level: 0.62), on: .watch),
        ]
        let summary = LinkRecord(entries).summaries()[0]
        #expect(summary.batteryPerHour[.phone].map { abs($0 - 0.06) < 1e-9 } == true)
        #expect(summary.batteryPerHour[.watch].map { abs($0 - 0.09) < 1e-9 } == true)
    }

    @Test func theLastStintSaysHowFarTheWatchHasGot() {
        let summaries = LinkRecord(guestStint(points: [0.3])).summaries(watchUpTo: at(30))
        #expect(summaries.last?.watchUpTo == at(30))
    }

    @Test func aStintWithNoPointsStillSummarises() {
        let summary = LinkRecord([entry(0, .joined)]).summaries()[0]
        #expect(summary.points == 0)
        #expect(summary.medianDelay == nil)
        #expect(summary.withinOne == nil)
    }

    @Test func theHeaderReadsAsTheScreensContractSays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        var entries = guestStint(points: Array(repeating: 0.4, count: 97) + [1.2, 1.5, 1.9])
        entries.append(entry(1_100, .dropped(.closedByPeer), .host(host), radios: [.wifi]))
        entries.append(entry(1_200, .battery(level: 0.9)))
        entries.append(entry(4_800, .battery(level: 0.84)))
        let lines = LinkRecord(entries).summaries().first!.headerLines(in: calendar)
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("Guest · 15 Jan, "))
        #expect(lines[1] == "97% within 1 s · slowest 1.9 s · 100 of 100 timed")
        #expect(lines[2] == "Wi-Fi dropped once · Bluetooth 0 · host never unreachable")
        #expect(lines[3] == "Battery: iPhone 6%/h")
    }

    @Test func aHeaderWithNoPointsLeavesTheDelayLineOut() {
        let lines = LinkRecord([entry(0, .sharingStarted)]).summaries().first!.headerLines(in: .current)
        #expect(lines.count == 2)
        #expect(lines[1] == "Wi-Fi dropped 0 times · Bluetooth 0 · nobody unreachable")
    }

    @Test func aThousandPointsReadWithAComma() {
        let lines = LinkRecord(guestStint(points: Array(repeating: 0.4, count: 1_184))).summaries()[0].headerLines(in: .current)
        #expect(lines[1].hasSuffix("1,184 of 1,184 timed"))
    }

    @Test func entriesAreGroupedUnderTheStintTheyBelongTo() {
        var entries = [entry(-10, .launched(.user))]
        entries += guestStint(points: [0.3])
        entries.append(entry(100, .newMatchAnswered(.leave)))
        entries.append(entry(110, .dropped(.closedByPeer), .host(host), radios: [.wifi], detail: "ETIMEDOUT"))
        entries += guestStint(points: [0.4], from: 300)
        let sections = LinkRecord(entries).sections()
        #expect(sections.map { $0.summary == nil } == [true, false, false])
        #expect(sections.map(\.entries.count) == [1, 6, 4])
        #expect(sections[1].entries.last?.kindText == "dropped(closedByPeer; ETIMEDOUT)")
    }

    @Test func theSummaryLineIsSkippedWhenAnExportIsReadBack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let record = LinkRecord(guestStint(points: [0.3, 0.4]))
        let header = LinkRecord.Header(app: "1.2 (80)", phoneSystem: "iOS 27.0", phone: DeviceID())
        let text = record.export(header, now: at(600), in: calendar)
        #expect(text.contains("  summary  guest"))
        #expect(LinkRecord.parse(text, in: calendar).count == record.entries.count)
    }
}
