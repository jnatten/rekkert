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
