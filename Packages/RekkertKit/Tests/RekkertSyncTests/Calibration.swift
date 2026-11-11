import Foundation
import RekkertCore
@testable import RekkertSync

/// Spec 005, D-11: the simulated radio's speed, fitted to a host's exported record from a real
/// court, so the harness predicts what that court would do with more guests.
@MainActor
enum Calibration {
    /// What a host's record says about its guests' points: when each was tapped and by whom,
    /// when each guest was out of reach or its Bluetooth link down, and how late the points that
    /// came over Bluetooth were.
    struct Measured: Equatable {
        struct Tap: Equatable {
            /// Seconds after the record's first tap.
            var at: TimeInterval
            var guest: Int
        }

        struct Away: Equatable {
            var from: TimeInterval
            var to: TimeInterval
            var guest: Int
        }

        var guests: Int
        var taps: [Tap]
        var away: [Away]
        /// The 5th percentile: points that met nothing in the way, so the radio's own latency.
        var fastest: Duration
        var p95: Duration
    }

    /// Nil when there are too few timed Bluetooth points to fit anything to.
    static func measure(_ export: String, in calendar: Calendar) -> Measured? {
        let lines = LinkRecord.parse(export, in: calendar).filter { $0.device == .phone }.sorted { $0.time < $1.time }
        var guests: [String] = []
        for line in lines where line.link.hasPrefix("guest ") && !guests.contains(line.link) { guests.append(line.link) }

        let arrivals = lines.compactMap { line -> (time: Date, latency: TimeInterval?, guest: Int, radios: [LinkRadio]?)? in
            guard case .pointArrived(let latency) = line.kind, let guest = guests.firstIndex(of: line.link) else { return nil }
            return (line.time, latency, guest, line.radios)
        }
        let delays = arrivals.filter { $0.radios == [.bluetooth] }.compactMap(\.latency).sorted()
        guard delays.count >= 20 else { return nil }
        let typical = percentile(delays, 0.5)
        let tapped = arrivals.map { (time: $0.time.addingTimeInterval(-($0.latency ?? typical)), guest: $0.guest) }
        guard let origin = tapped.map(\.time).min() else { return nil }

        var away: [Measured.Away] = []
        var since: [Int: Date] = [:]
        var linkDownSince: [Int: Date] = [:]
        for line in lines {
            guard let guest = guests.firstIndex(of: line.link) else { continue }
            switch line.kind {
            case .outOfReach:
                since[guest] = since[guest] ?? line.time
            case .backInStep:
                if let from = since.removeValue(forKey: guest) { away.append(span(from, line.time, guest, origin)) }
            case .dropped, .wroteOff:
                if line.radios?.contains(.bluetooth) == true { linkDownSince[guest] = linkDownSince[guest] ?? line.time }
            case .proven:
                if line.radios?.contains(.bluetooth) == true, let from = linkDownSince.removeValue(forKey: guest) {
                    away.append(span(from, line.time, guest, origin))
                }
            default:
                break
            }
        }
        return Measured(
            guests: guests.count,
            taps: tapped.map { Measured.Tap(at: $0.time.timeIntervalSince(origin), guest: $0.guest) }.sorted { $0.at < $1.at },
            away: away.filter { $0.to > 0 }.sorted { $0.from < $1.from },
            fastest: .seconds(percentile(delays, 0.05)),
            p95: .seconds(percentile(delays, 0.95))
        )
    }

    /// The same court in the harness, over Bluetooth: each guest's taps at the times the record
    /// shows, and each guest gone for as long as it was (FR-017). `points` replays only the
    /// first so many taps. Returns the host's simulated fastest and 95th-percentile delay.
    static func replay(_ measured: Measured, settings: Airwaves.Settings, points: Int? = nil) async -> (fastest: Duration, p95: Duration) {
        var timing = CourtHarness.Timing()
        timing.skipsIdleTime = true
        let court = CourtHarness(guests: measured.guests, withWatches: true, settings: settings, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        _ = await court.until(within: .seconds(180)) { court.allInStep() }
        let phones = court.guests.map(\.phone)

        let taps = Array(measured.taps.prefix(points ?? measured.taps.count))
        let end = (taps.last?.at ?? 0) + 1
        enum Step { case tap(Int, Int), leave(Int), back(Int) }
        var steps: [(at: TimeInterval, step: Step)] = taps.enumerated().map { ($1.at, .tap($1.guest, $0)) }
        for gone in measured.away where gone.from < end {
            steps.append((max(0, gone.from), .leave(gone.guest)))
            steps.append((min(gone.to, end), .back(gone.guest)))
        }
        steps.sort { $0.at < $1.at }

        let start = court.clock.now
        for (at, step) in steps {
            let wait = Duration.seconds(at) - (court.clock.now - start)
            if wait > .zero { await court.run(for: wait) }
            switch step {
            case .tap(let guest, let index): court.score(on: phones[guest], team: index.isMultiple(of: 2) ? .a : .b)
            case .leave(let guest): court.outOfRange(phones[guest])
            case .back(let guest): court.backInRange(phones[guest])
            }
        }
        await court.run(for: .seconds(30))

        let delays = court.arrivals(on: court.host.phone).compactMap(\.delay).map(\.seconds).sorted()
        guard !delays.isEmpty else { return (.zero, .zero) }
        return (.seconds(percentile(delays, 0.05)), .seconds(percentile(delays, 0.95)))
    }

    private static func span(_ from: Date, _ to: Date, _ guest: Int, _ origin: Date) -> Measured.Away {
        Measured.Away(from: from.timeIntervalSince(origin), to: to.timeIntervalSince(origin), guest: guest)
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
