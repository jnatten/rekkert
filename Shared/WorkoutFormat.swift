import Foundation
import RekkertCore

/// One place the numbers are spelled, so the watch counting them up and the phone filing
/// them away cannot drift apart.
enum WorkoutFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond)
        )
    }

    static func energy(_ kilocalories: Double) -> String {
        "\(kilocalories.formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    static func beats(_ beatsPerMinute: Double) -> String {
        "\(beatsPerMinute.formatted(.number.precision(.fractionLength(0)))) bpm"
    }

    /// Both ends open, the way the Workout app writes them: the lowest zone has no floor and
    /// the highest no ceiling, so they read as "under 134" and "170+" rather than pretending
    /// to bounds nobody set.
    static func zoneRange(lower: Double?, upper: Double?) -> String {
        switch (lower, upper) {
        case (nil, let upper?): "under \(Int(upper) + 1)"
        case (let lower?, nil): "\(Int(lower))+"
        case (let lower?, let upper?): "\(Int(lower))–\(Int(upper))"
        case (nil, nil): "every beat"
        }
    }

    /// Only the parts that exist. A workout recorded with Health's read access refused has
    /// neither figure, and saying so would be reporting an absence nobody asked about.
    static func summary(of workout: WorkoutRecord, matches: Int) -> String? {
        var parts: [String] = []
        if matches > 0 { parts.append(matches == 1 ? "1 match" : "\(matches) matches") }
        if let burned = workout.activeEnergyKilocalories { parts.append(energy(burned)) }
        if let average = workout.heartRateAverage { parts.append("avg \(beats(average))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
