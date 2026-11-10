import Foundation
import RekkertCore
@testable import RekkertSync

/// Spec 005, D-11: the simulated radio's speed, fitted to a host's exported record from a real
/// court, so the harness predicts what that court would do with more guests.
@MainActor
enum Calibration {
    /// What a host's record says about its guests' points over Bluetooth.
    struct Measured: Equatable {
        var guests: Int
        var points: Int
        /// A point every this often, on average.
        var spacing: Duration
        /// The 5th percentile: points that met nothing in the way, so the radio's own latency.
        var fastest: Duration
        var p95: Duration
    }

    /// The host's timed Bluetooth arrivals from guests, read from an exported record. Nil when
    /// there are too few to fit anything to.
    static func measure(_ export: String, in calendar: Calendar) -> Measured? {
        let lines = LinkRecord.parse(export, in: calendar)
        let arrivals = lines.filter { $0.device == .phone && $0.link.hasPrefix("guest ") && $0.radios == [.bluetooth] }
        let delays = arrivals.compactMap { line -> TimeInterval? in
            if case .pointArrived(let latency?) = line.kind { latency } else { nil }
        }.sorted()
        guard delays.count >= 20, let first = arrivals.first?.time, let last = arrivals.last?.time else { return nil }
        let guests = Set(lines.filter { $0.device == .phone && $0.link.hasPrefix("guest ") }.map(\.link)).count
        return Measured(
            guests: guests,
            points: delays.count,
            spacing: .seconds(max(1, last.timeIntervalSince(first) / Double(delays.count))),
            fastest: .seconds(percentile(delays, 0.05)),
            p95: .seconds(percentile(delays, 0.95))
        )
    }

    /// The same court in the harness: the host's simulated fastest and 95th-percentile delay.
    static func replay(_ measured: Measured, settings: Airwaves.Settings, points: Int? = nil) async -> (fastest: Duration, p95: Duration) {
        var timing = CourtHarness.Timing()
        timing.skipsIdleTime = true
        let court = CourtHarness(guests: measured.guests, withWatches: true, settings: settings, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        _ = await court.until(within: .seconds(180)) { court.allInStep() }
        let scorers = court.devices.filter { $0 !== court.host.phone && $0 !== court.host.watch }
        for index in 0 ..< (points ?? min(measured.points, 120)) {
            court.score(on: scorers[index % scorers.count], team: index.isMultiple(of: 2) ? .a : .b)
            await court.run(for: measured.spacing)
        }
        let delays = court.arrivals(on: court.host.phone).compactMap(\.delay).map(\.seconds).sorted()
        guard !delays.isEmpty else { return (.zero, .zero) }
        return (.seconds(percentile(delays, 0.05)), .seconds(percentile(delays, 0.95)))
    }

    /// Latency from the fastest points on a radio too fast to matter, then the speed that brings
    /// the 95th percentile to the record's. The two trade off: the fastest points carry transfer
    /// time as well, so the latency comes out high and the speed low, and a second round does not
    /// separate them. The 95th percentile is what FR-017 holds the fit to; the two-court evening
    /// checks how it extrapolates (FR-018).
    static func fit(_ measured: Measured, rounds: Int = 1, steps: Int = 6, points: Int? = nil) async -> Airwaves.Settings {
        var settings = Airwaves.Settings()
        settings.bytesPerSecond = 200_000
        for _ in 0 ..< rounds {
            var low = 0.001, high = measured.fastest.seconds
            for _ in 0 ..< steps {
                settings.latency = .seconds((low + high) / 2)
                let (fastest, _) = await replay(measured, settings: settings, points: points)
                if fastest > measured.fastest { high = settings.latency.seconds } else { low = settings.latency.seconds }
            }
            settings.latency = .seconds((low + high) / 2)

            var slow = 200.0, quick = 200_000.0
            for _ in 0 ..< steps {
                settings.bytesPerSecond = Int((slow * quick).squareRoot())
                let (_, p95) = await replay(measured, settings: settings, points: points)
                if p95 > measured.p95 { slow = Double(settings.bytesPerSecond) } else { quick = Double(settings.bytesPerSecond) }
            }
            settings.bytesPerSecond = Int((slow * quick).squareRoot())
        }
        return settings
    }

    private static func percentile(_ sorted: [TimeInterval], _ share: Double) -> TimeInterval {
        sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * share).rounded()))]
    }
}
