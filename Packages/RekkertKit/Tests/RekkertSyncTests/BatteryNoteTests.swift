import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, D-12 and FR-019: battery in the record when sharing starts and stops, and at most
/// every 10 minutes otherwise, however often the app hands a level over.
@Suite("Battery in the record")
@MainActor
struct BatteryNoteTests {
    nonisolated private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func recorder(_ clock: Clock) -> LinkRecorder {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("battery-\(UUID().uuidString)")
        return LinkRecorder(directory: directory, device: .phone, now: { clock.now })
    }

    private func levels(_ recorder: LinkRecorder) -> [Double] {
        recorder.read().entries.compactMap { if case .battery(let level) = $0.kind { level } else { nil } }
    }

    @Test func notedWhenSharingStartsAndStops() {
        let clock = Clock()
        let recorder = recorder(clock)
        recorder.offer(batteryLevel: 0.95)
        clock.now += 60
        recorder.note(.sharingStarted)
        recorder.offer(batteryLevel: 0.9)
        clock.now += 60
        recorder.offer(batteryLevel: 0.89)
        recorder.note(.sharingStopped)
        recorder.offer(batteryLevel: 0.88)
        #expect(levels(recorder) == [0.95, 0.9, 0.88])
    }

    @Test func aJoinAndLeavingAreNotedToo() {
        let clock = Clock()
        let recorder = recorder(clock)
        recorder.offer(batteryLevel: 0.8)
        clock.now += 5
        recorder.note(.joined)
        recorder.offer(batteryLevel: 0.8)
        clock.now += 5
        recorder.note(.newMatchAnswered(.leave))
        recorder.offer(batteryLevel: 0.79)
        #expect(levels(recorder).count == 3)
    }

    @Test func otherwiseEveryTenMinutes() {
        let clock = Clock()
        let recorder = recorder(clock)
        recorder.offer(batteryLevel: 0.7)
        clock.now += 599
        recorder.offer(batteryLevel: 0.69)
        clock.now += 1
        recorder.offer(batteryLevel: 0.68)
        #expect(levels(recorder) == [0.7, 0.68])
    }

    @Test func neverMoreOftenHoweverOftenOffered() {
        let clock = Clock()
        let recorder = recorder(clock)
        for _ in 0 ..< 540 {
            recorder.offer(batteryLevel: 0.5)
            clock.now += 1
        }
        #expect(levels(recorder).count == 1)
    }

    @Test func anUnknownLevelIsNotNoted() {
        let recorder = recorder(Clock())
        recorder.note(.sharingStarted)
        recorder.offer(batteryLevel: nil)
        #expect(levels(recorder).isEmpty)
    }
}
