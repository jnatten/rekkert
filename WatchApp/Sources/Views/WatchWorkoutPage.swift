import RekkertCore
import SwiftUI

/// The workout on a page of its own: the clock, the heart, the zone and the energy, so you
/// do not have to leave the score to see what the Workout app would have shown you.
///
/// In the deck only while one is running. There is nothing here to say otherwise — starting
/// one lives on the menu and the start screen, next to the other things you do between
/// points rather than one swipe from the numbers, and stopping one stays there with it.
///
/// Read-only, and sized to be read in one look: nothing scrolls, so a glance takes in the
/// whole of it and the crown is free for the page underneath.
struct WatchWorkoutPage: View {
    @Environment(AppModel.self) private var model

    /// Blue through red, the way every heart rate chart has drawn effort since long before
    /// any of them were on a wrist. Spread across however many zones there turn out to be,
    /// because a set configured by hand in Health Settings need not be five.
    private static let zoneColors: [Color] = [.blue, .teal, .green, .orange, .red]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            elapsed
            heartRate
            if let zones = model.workout.zones { zoneBar(zones) }
            figures
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 2)
        .containerBackground(Color.pink.gradient.opacity(0.2), for: .tabView)
    }

    /// `Text(timerInterval:)` rather than a ticking `State`: the system keeps it counting
    /// without the view being redrawn, which is what lets it stay right through the minutes
    /// this page spends dimmed on a lowered wrist.
    @ViewBuilder
    private var elapsed: some View {
        Group {
            if let startedAt = model.workout.startedAt {
                Text(timerInterval: startedAt ... .distantFuture, countsDown: false)
            } else {
                Text(verbatim: "0:00")
            }
        }
        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.yellow)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityLabel("Workout time")
    }

    /// Dashes until the first sample lands, which takes a few seconds. An empty space there
    /// reads as a fault; a dash reads as "not yet", which is what it is.
    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13))
                .symbolEffect(.pulse)
            Text(model.workout.heartRate.map { "\(Int($0.rounded()))" } ?? "––")
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            Text("BPM")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.pink.opacity(0.7))
        }
        .foregroundStyle(.pink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            model.workout.heartRate.map { "\(Int($0.rounded())) beats per minute" }
                ?? "Heart rate, waiting for a reading"
        )
    }

    /// A bar per zone and a word. Which zone you are in is the whole of what a zone is for,
    /// and the bar is there so it can be read at a glance rather than counted.
    private func zoneBar(_ zones: HeartRateZones) -> some View {
        let current = model.workout.heartRate.map { zones.number(for: $0) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(1 ... zones.count, id: \.self) { number in
                    Capsule()
                        .fill(Self.zoneColor(number, of: zones.count))
                        .opacity(number <= (current ?? 0) ? 1 : 0.2)
                        .frame(height: 5)
                }
            }
            Text(current.map { zoneLabel(zones, current: $0) } ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// Both ends open, the way the Workout app writes them: "Zone 1 · under 134" and
    /// "Zone 5 · 170+", with the ones between reading as a range.
    private func zoneLabel(_ zones: HeartRateZones, current: Int) -> String {
        switch (zones.lowerBound(of: current), zones.upperBound(of: current)) {
        case (nil, let upper?): "Zone \(current) · under \(Int(upper) + 1)"
        case (let lower?, nil): "Zone \(current) · \(Int(lower))+"
        case (let lower?, let upper?): "Zone \(current) · \(Int(lower))–\(Int(upper))"
        case (nil, nil): "Zone \(current)"
        }
    }

    /// What the workout has come to. Each line only once there is something in it: a zero
    /// where Health has not answered is a worse answer than no line at all.
    @ViewBuilder
    private var figures: some View {
        VStack(spacing: 3) {
            if let energy = model.workout.activeEnergyKilocalories {
                figure("Active", WorkoutFormat.energy(energy), systemImage: "flame.fill", tint: .orange)
            }
            if let average = model.workout.heartRateAverage {
                figure("Average", WorkoutFormat.beats(average), systemImage: "waveform.path.ecg", tint: .pink)
            }
            if let maximum = model.workout.heartRateMaximum {
                figure("Highest", WorkoutFormat.beats(maximum), systemImage: "arrow.up.heart.fill", tint: .pink)
            }
        }
    }

    private static func zoneColor(_ number: Int, of count: Int) -> Color {
        guard count > 1 else { return zoneColors[0] }
        let position = Double(number - 1) / Double(count - 1) * Double(zoneColors.count - 1)
        return zoneColors[Int(position.rounded())]
    }

    private func figure(
        _ title: String,
        _ value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}
