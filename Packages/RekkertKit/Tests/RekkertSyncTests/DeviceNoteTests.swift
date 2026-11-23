import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Bug shared-guest-half-board: what a device was running is in the record at launch, whenever
/// it changes, and once in every day's file, however often the app hands it over.
@Suite("What a device was running, in the record")
@MainActor
struct DeviceNoteTests {
    nonisolated private final class Clock: @unchecked Sendable {
        /// 2027-01-15 08:00 UTC.
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("device-\(UUID().uuidString)")

    private func recorder(_ clock: Clock, as device: LinkRecordEntry.Device = .watch) -> LinkRecorder {
        LinkRecorder(directory: directory, device: device, now: { clock.now }, calendar: calendar)
    }

    private func notes(_ recorder: LinkRecorder) -> [DeviceNote] {
        recorder.read().entries.compactMap { if case .device(let note) = $0.kind { note } else { nil } }
    }

    private let running = DeviceNote(
        app: "1.2 (82) 181886a", system: "watchOS 27.2.1", model: "Watch7,5", lowPower: false, reduceMotion: false
    )

    @Test func notedOnceHoweverOftenItIsOffered() {
        let clock = Clock()
        let recorder = recorder(clock)
        for _ in 0 ..< 540 {
            recorder.offer(device: running)
            clock.now += 1
        }
        #expect(notes(recorder) == [running])
    }

    @Test func notedAgainWhenItChanges() {
        let clock = Clock()
        let recorder = recorder(clock)
        var saving = running
        saving.lowPower = true
        recorder.offer(device: running)
        clock.now += 60
        recorder.offer(device: saving)
        clock.now += 60
        recorder.offer(device: saving)
        clock.now += 60
        recorder.offer(device: running)
        #expect(notes(recorder) == [running, saving, running])
    }

    @Test func everyDaysFileSaysWhatWroteIt() {
        let clock = Clock()
        let recorder = recorder(clock)
        recorder.offer(device: running)
        clock.now += 86_400
        recorder.offer(device: running)
        recorder.offer(device: running)
        let days = recorder.read().entries.map { LinkRecord.day(of: $0.time, in: calendar) }
        #expect(days == ["2027-01-15", "2027-01-16"])
    }

    @Test func aLaunchSaysItAgain() {
        let clock = Clock()
        recorder(clock).offer(device: running)
        clock.now += 60
        recorder(clock).offer(device: running)
        #expect(notes(recorder(clock)).count == 2)
    }

    @Test func nothingToSayNotesNothing() {
        let recorder = recorder(Clock())
        recorder.offer(device: nil)
        #expect(recorder.read().entries.isEmpty)
    }

    /// A phone on an older build is handed its newer watch's day whole, this line in it.
    @Test func aLineOfAKindABuildDoesNotKnowIsPassedOver() throws {
        let clock = Clock()
        let known = LinkRecordEntry(time: clock.now, device: .watch, kind: .battery(level: 0.8))
        let newer = LinkRecordEntry(time: clock.now.addingTimeInterval(1), device: .watch, kind: .device(running))
        let lines = try [known, newer].map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        #expect(lines[1].contains(#""device""#))
        let unknown = lines[1].replacingOccurrences(of: #""device""#, with: #""somethingNewer""#)

        let phone = recorder(clock, as: .phone)
        phone.receive(watchDay: LinkRecord.day(of: clock.now, in: calendar), contents: Data((lines[0] + "\n" + unknown + "\n").utf8))
        #expect(phone.read().entries.filter { $0.device == .watch }.map(\.kind) == [.battery(level: 0.8)])
    }
}
