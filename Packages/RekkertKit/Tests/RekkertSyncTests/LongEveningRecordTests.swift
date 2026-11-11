import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, Edge Cases: a two-hour evening's delay entries, from a phone and its watch with ten
/// people tapping, fit in the record, export and read back whole, and are gone after a week.
@Suite("A long evening in the record")
@MainActor
struct LongEveningRecordTests {
    nonisolated private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    @Test func twoHoursOfDelaysFitAndAreStillKeptOnlyAWeek() async throws {
        let clock = Clock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("evening-\(UUID().uuidString)")
        let phone = LinkRecorder(directory: directory.appendingPathComponent("phone"), device: .phone, now: { clock.now }, calendar: calendar)
        let watch = LinkRecorder(directory: directory.appendingPathComponent("watch"), device: .watch, now: { clock.now }, calendar: calendar)
        watch.send = { day, contents in phone.receive(watchDay: day, contents: contents) }
        let host = DeviceID()

        phone.note(.joined)
        phone.note(.proven, on: .host(host), radios: [.bluetooth])
        phone.note(.proven, on: .host(host), radios: [.wifi])
        watch.note(.proven, on: .pair)
        // A point every 12 s for two hours, from any of ten people, on the phone and the watch.
        let points = 2 * 3_600 / 12
        for index in 0 ..< points {
            clock.now += 12
            phone.note(.pointArrived(latency: 0.4 + Double(index % 7) / 10), on: .host(host), radios: [.bluetooth, .wifi])
            watch.note(.pointArrived(latency: 0.5), on: .pair)
            if index.isMultiple(of: 100) { phone.offer(batteryLevel: 1 - Double(index) / 2_000) }
            // Every write is on the main actor, as in the app: the suites waiting on it in real
            // time get their turn.
            if index.isMultiple(of: 20) { await Task.yield() }
        }
        clock.now += 1
        phone.note(.newMatchAnswered(.leave))
        watch.sendDays()

        let record = phone.read()
        let delays = record.entries.filter { if case .pointArrived = $0.kind { true } else { false } }
        #expect(delays.count == points * 2)

        let text = record.export(LinkRecord.Header(app: "1.2 (80)", phoneSystem: "iOS 27.0", phone: DeviceID()), now: clock.now, in: calendar)
        #expect(LinkRecord.parse(text, in: calendar).count == record.entries.count)
        #expect(text.utf8.count < 500_000, "\(text.utf8.count) bytes exported")
        let summary = try #require(record.summaries().last)
        #expect(summary.points == points * 2)

        clock.now += 8 * 86_400
        #expect(phone.read().entries.isEmpty)
    }
}
