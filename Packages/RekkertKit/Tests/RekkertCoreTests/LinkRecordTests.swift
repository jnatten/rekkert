import Foundation
import RekkertCore
import Testing

@Suite("The sharing record")
struct LinkRecordTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }()

    /// 2026-10-26 19:02:11.204 in Oslo.
    private let evening = Date(timeIntervalSince1970: 1_793_037_731.204)
    private let phone = DeviceID(UUID(uuidString: "7F3A0000-0000-4000-8000-000000000001")!)
    private let watch = DeviceID(UUID(uuidString: "19C20000-0000-4000-8000-000000000002")!)
    private let guest = DeviceID(UUID(uuidString: "A41D0000-0000-4000-8000-000000000003")!)
    private let match = UUID(uuidString: "5E1B0000-0000-4000-8000-000000000004")!

    private func at(_ seconds: Double) -> Date { evening.addingTimeInterval(seconds) }

    private var header: LinkRecord.Header {
        LinkRecord.Header(
            app: "1.0 (56) abc1234", phoneSystem: "iOS 26.1", watchSystem: "watchOS 26.1",
            phone: phone, watch: watch
        )
    }

    @Test func entriesAreMergedByTimeAndDeduplicatedById() {
        let early = LinkRecordEntry(time: at(0), device: .phone, kind: .launched(.user))
        let late = LinkRecordEntry(time: at(10), device: .phone, kind: .sharingStarted)
        let middle = LinkRecordEntry(time: at(5), device: .watch, link: .pair, kind: .dropped(.timeout))
        var record = LinkRecord([late, early])
        record.merge([middle, early, late])
        #expect(record.entries == [early, middle, late])
    }

    @Test func daysOlderThanSevenAreNotKept() {
        let today = Date(timeIntervalSince1970: 1_793_098_800) // 2026-10-27 noon in Oslo.
        #expect(LinkRecord.day(of: today, in: calendar) == "2026-10-27")
        #expect(LinkRecord.isKept(day: "2026-10-27", today: today, in: calendar))
        #expect(LinkRecord.isKept(day: "2026-10-20", today: today, in: calendar))
        #expect(!LinkRecord.isKept(day: "2026-10-19", today: today, in: calendar))
    }

    @Test func theExportReadsAsTheContractSays() {
        let record = LinkRecord([
            LinkRecordEntry(time: at(0), device: .phone, kind: .launched(.user)),
            LinkRecordEntry(time: at(4.676), device: .phone, session: match, kind: .sharingStarted),
            LinkRecordEntry(time: at(50.913), device: .phone, session: match, link: .guest(guest), kind: .proven),
            LinkRecordEntry(time: at(2385.802), device: .watch, link: .pair, kind: .dropped(.timeout)),
        ])
        let text = record.export(header, now: at(3600), in: calendar)
        #expect(text.components(separatedBy: "\n") == [
            "Rekkert sharing record",
            "App 1.0 (56) abc1234 · iOS 26.1 · watchOS 26.1",
            "This phone \(phone.raw.uuidString) · its watch \(watch.raw.uuidString)",
            "Covers 2026-10-19 to 2026-10-26",
            "",
            "2026-10-26 19:02:11.204  phone  radio       launched(user)",
            "  summary  host · 19:02–19:41 · 0 points (0 timed, 0 older) · median – · slowest – · not enough timed points · drops wifi 0, bt 0 · nobody unreachable",
            "2026-10-26 19:02:15.880  phone  radio       sharingStarted              match 5E1B…",
            "2026-10-26 19:03:02.117  phone  guest A41D  proven                      match 5E1B…",
            "2026-10-26 19:41:57.006  watch  pair        dropped(timeout)",
        ])
    }

    @Test func anExportReadsBackIntoItsEntries() {
        let kinds: [LinkEvent] = [
            .launched(.restored), .appHadBeenEnded, .sharingRestored, .joinStarted, .joined,
            .refused(.noRoom), .outOfReach, .backInStep, .caughtUp(events: 12), .wroteOff, .redialled,
            .standIn, .standDown, .radioOff, .radioOn, .permissionDenied, .notificationPosted,
            .recordReceived(from: .watch), .pointArrived(latency: 0.842), .dropped(.closedByPeer), .sharingStopped,
            .endOfMatchAsked, .endOfMatchAnswered(.keepSharing), .endOfMatchAnswered(.stopSharing),
            .endOfMatchAnswered(.stay), .endOfMatchAnswered(.leave), .endOfMatchUnanswered, .newMatchShown,
            .newMatchAnswered(.ok), .newMatchAnswered(.leave), .idleStop,
        ]
        let entries = kinds.enumerated().map { index, kind in
            LinkRecordEntry(time: at(Double(index)), device: index.isMultiple(of: 2) ? .phone : .watch,
                            session: match, link: .host(guest), kind: kind)
        }
        let lines = LinkRecord.parse(LinkRecord(entries).export(header, now: at(60), in: calendar), in: calendar)
        #expect(lines.map(\.kind) == kinds)
        #expect(lines.map(\.device) == entries.map(\.device))
        #expect(zip(lines, entries).allSatisfy { abs($0.time.timeIntervalSince($1.time)) < 0.0005 })
        #expect(lines.allSatisfy { $0.link == "host A41D" && $0.session == "5E1B" })
    }

    @Test func anEntryCarriesTimesIdsAndKindsAndNothingElse() throws {
        let entry = LinkRecordEntry(time: at(0), device: .phone, session: match, link: .guest(guest), kind: .caughtUp(events: 3))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        #expect(Set(object.keys) == ["id", "time", "device", "session", "link", "kind"])
    }

    @Test func theHeaderSaysHowFarTheWatchHasGotWhenItIsBehind() {
        var behind = header
        behind.watchUpTo = at(2385.802)
        let lines = LinkRecord([]).export(behind, now: at(3600), in: calendar).components(separatedBy: "\n")
        #expect(lines.contains("Watch entries up to 19:41 (not in touch since)"))
        #expect(!LinkRecord([]).export(header, now: at(3600), in: calendar).contains("Watch entries up to"))
    }

    /// Spec 005, contracts/sharing-record.md.
    @Test func radiosDetailsUnknownDelaysAndBatteryComeBackAsWritten() {
        let entries = [
            LinkRecordEntry(time: at(0), device: .phone, session: match, link: .host(guest), kind: .pointArrived(latency: 0.412), radios: [.wifi]),
            LinkRecordEntry(time: at(1), device: .phone, session: match, link: .host(guest), kind: .pointArrived(latency: nil), radios: [.bluetooth]),
            LinkRecordEntry(time: at(2), device: .phone, session: match, link: .host(guest), kind: .pointArrived(latency: nil), radios: [.bluetooth], detail: "older"),
            LinkRecordEntry(time: at(3), device: .phone, session: match, link: .host(guest), kind: .dropped(.closedByPeer), radios: [.wifi], detail: "ETIMEDOUT"),
            LinkRecordEntry(time: at(4), device: .phone, session: match, link: .guest(guest), kind: .outOfReach, radios: [.wifi, .bluetooth]),
            LinkRecordEntry(time: at(5), device: .watch, kind: .battery(level: 0.83)),
        ]
        let text = LinkRecord(entries).export(header, now: at(60), in: calendar)
        #expect(text.contains("host A41D wifi  pointArrived(0.412s)"))
        #expect(text.contains("pointArrived(unknown; older)"))
        #expect(text.contains("dropped(closedByPeer; ETIMEDOUT)"))
        #expect(text.contains("guest A41D bt+wifi  outOfReach"))
        #expect(text.contains("battery(83%)"))

        let lines = LinkRecord.parse(text, in: calendar)
        #expect(lines.map(\.kind) == entries.map(\.kind))
        #expect(lines.map(\.radios) == entries.map(\.radios))
        #expect(lines.map(\.detail) == entries.map(\.detail))
        #expect(lines.map(\.link) == ["host A41D", "host A41D", "host A41D", "host A41D", "guest A41D", "radio"])
    }

    @Test func anOlderLineWithoutRadiosStillDecodes() throws {
        let older = #"{"id":"6E3B0000-0000-4000-8000-000000000009","time":0,"device":"phone","link":{"radio":{}},"kind":{"pointArrived":{"latency":0.25}}}"#
        let entry = try JSONDecoder().decode(LinkRecordEntry.self, from: Data(older.utf8))
        #expect(entry.kind == .pointArrived(latency: 0.25))
        #expect(entry.radios == nil && entry.detail == nil)
    }
}
