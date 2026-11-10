import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-006: every delay in the record within a tenth of a second of the truth, or
/// unknown, whatever the devices' clocks say, and no more than one in ten unknown.
@Suite("Delays timed from the tap, whatever the clocks say", .serialized)
@MainActor
struct ClockOffsetTests {
    /// Bluetooth's real round trips are tens of milliseconds; the default simulated radio's
    /// guessed speed makes them hundreds, too slow to bound a clock within a tenth at all.
    private static var quickRadio: Airwaves.Settings {
        var settings = Airwaves.Settings()
        settings.bytesPerSecond = 40_000
        settings.latency = .milliseconds(15)
        return settings
    }

    private static func skew(_ index: Int, _ isWatch: Bool) -> (offset: TimeInterval, drift: Double) {
        let offsets: [TimeInterval] = [0, 2.7, -1.9, 0.4, -3.0]
        let offset = offsets[index % offsets.count] + (isWatch ? 0.35 : 0)
        return (offset, (index.isMultiple(of: 2) ? 1 : -1) * 20e-6)
    }

    private func court() async -> CourtHarness {
        var timing = CourtHarness.Timing()
        // A round trip is measured in whole steps, so a coarse step alone would make every
        // bound too wide to time anything.
        timing.step = .milliseconds(10)
        timing.skipsIdleTime = true
        let court = CourtHarness(
            guests: 4, settings: Self.quickRadio, timing: timing,
            guestRadios: { _ in .both }, wifiSettings: Self.quickRadio, clockSkew: Self.skew
        )
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) { court.allInStep() })
        return court
    }

    @Test func everyRecordedDelayIsWithinATenthOrUnknown() async {
        let court = await court()
        let scorers = court.devices
        for index in 0 ..< 150 {
            court.score(on: scorers[index % scorers.count], team: index.isMultiple(of: 2) ? .a : .b)
            await court.run(for: .seconds(12))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })

        for device in court.devices {
            let pairs = court.recordedDelays(on: device)
            let unknown = pairs.count { $0.recorded == nil }
            #expect(pairs.count >= 100, "\(device.name): \(pairs.count) delays recorded")
            // Each hop between the tap and the arrival adds half its round trip to the error, so
            // this holds only while clocks are timed on the small `.clock` exchange. The field
            // run judges it on real round trips (T058).
            #expect(Double(unknown) <= Double(pairs.count) * 0.1, "\(device.name): \(unknown) of \(pairs.count) unknown")
            print("ClockOffset \(device.name): \(unknown) of \(pairs.count) unknown")
            for pair in pairs {
                guard let recorded = pair.recorded else { continue }
                #expect(abs(recorded - pair.truth) <= 0.1, "\(device.name): recorded \(recorded), truly \(pair.truth)")
            }
        }

        for player in court.players {
            court.separate(player)
            await court.run(for: .seconds(5))
            court.reunite(player)
        }
        await court.run(for: .seconds(15))
        for player in court.players {
            let record = player.phone.recorder.read()
            let fromWatch = record.entries.filter {
                guard $0.device == .watch, case .pointArrived(let latency?) = $0.kind else { return false }
                return latency >= 0
            }
            #expect(fromWatch.count >= 100, "\(player.phone.name): \(fromWatch.count) of its watch's delays")
            let ownTimed = record.entries.count {
                guard $0.device == .phone, case .pointArrived(_?) = $0.kind else { return false }
                return true
            }
            #expect((record.summaries().last?.knownDelays ?? 0) > ownTimed, "\(player.phone.name): the summary leaves the watch out")
        }
    }

    @Test func aClockSetForwardMidRunGivesUnknownNeverWrong() async {
        let court = await court()
        let jumper = court.guests.first!.phone
        for index in 0 ..< 40 {
            if index == 20 { court.jumpClock(of: jumper, by: 5) }
            court.score(on: court.host.phone, team: index.isMultiple(of: 2) ? .a : .b)
            await court.run(for: .seconds(12))
        }
        for pair in court.recordedDelays(on: jumper) {
            guard let recorded = pair.recorded else { continue }
            #expect(abs(recorded - pair.truth) <= 0.1, "recorded \(recorded), truly \(pair.truth)")
        }
    }
}
