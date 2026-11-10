import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, D-11: the fit itself, on a record whose radio speed is known because the harness
/// wrote it. The field run's record replaces it in `CalibrationTests` (T060).
@Suite("Fitting the simulated radio to a record", .serialized)
@MainActor
struct CalibrationFitTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    @Test func aRecordFromAKnownRadioIsFittedBackWithinAQuarter() async throws {
        var known = Airwaves.Settings()
        known.latency = .milliseconds(25)
        known.bytesPerSecond = 3_000
        var timing = CourtHarness.Timing()
        timing.skipsIdleTime = true
        let court = CourtHarness(guests: 2, withWatches: true, settings: known, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(120)) { court.allInStep() })
        let scorers = court.devices.filter { $0 !== court.host.phone && $0 !== court.host.watch }
        for index in 0 ..< 40 {
            court.score(on: scorers[index % scorers.count], team: index.isMultiple(of: 2) ? .a : .b)
            await court.run(for: .seconds(10))
        }
        let export = court.host.phone.recorder.read().export(
            LinkRecord.Header(app: "1.2 (80)", phoneSystem: "iOS 27.0", phone: court.host.phone.id),
            now: court.wallClock, in: calendar
        )

        let measured = try #require(Calibration.measure(export, in: calendar))
        #expect(measured.guests == 2)
        let fitted = await Calibration.fit(measured, steps: 4, points: 30)
        let (_, p95) = await Calibration.replay(measured, settings: fitted, points: 40)
        print("Calibration: known \(known.latency), \(known.bytesPerSecond) B/s; fitted \(fitted.latency), \(fitted.bytesPerSecond) B/s; p95 \(p95) against \(measured.p95)")
        #expect(abs(p95.seconds - measured.p95.seconds) <= measured.p95.seconds * 0.25)
    }
}
