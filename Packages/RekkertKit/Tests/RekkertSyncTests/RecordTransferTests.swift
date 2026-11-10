import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005: a watch back in touch sends only the days that changed since they last went, not
/// its whole week again on every reconnect.
@Suite("The watch's record goes to its phone")
struct RecordTransferTests {
    private final class Sent: @unchecked Sendable {
        var days: [String] = []
    }

    private func recorder(at moment: @escaping @Sendable () -> Date) -> LinkRecorder {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("record-\(UUID().uuidString)")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return LinkRecorder(directory: directory, device: .watch, now: moment, calendar: calendar)
    }

    @Test func aDayGoesAgainOnlyWhenItChanged() {
        let recorder = recorder(at: { Date(timeIntervalSince1970: 1_800_000_000) })
        let sent = Sent()
        recorder.send = { day, _ in sent.days.append(day) }

        recorder.note(.launched(.user))
        recorder.sendDays()
        #expect(sent.days.count == 1)

        recorder.sendDays()
        #expect(sent.days.count == 1)

        recorder.note(.pointArrived(latency: 0.4), on: .pair)
        recorder.sendDays()
        #expect(sent.days.count == 2)
    }

    @Test func comingBackInTouchSendsWhatChanged() {
        let recorder = recorder(at: { Date(timeIntervalSince1970: 1_800_000_000) })
        let sent = Sent()
        recorder.send = { day, _ in sent.days.append(day) }

        recorder.note(.proven, on: .pair)
        recorder.note(.dropped(.unknown), on: .pair)
        recorder.note(.proven, on: .pair)
        #expect(sent.days.count == 2)
    }
}
