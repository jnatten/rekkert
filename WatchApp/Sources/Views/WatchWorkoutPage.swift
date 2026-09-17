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
/// whole of it and the crown is free for the page underneath. Holding it lives with
/// stopping it, on the menu.
struct WatchWorkoutPage: View {
    @Environment(AppModel.self) private var model

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
    /// this page spends dimmed on a lowered wrist. It is also why a held clock is a plain
    /// string — the counting one cannot be told to stop. `WorkoutFormat.duration` writes the
    /// same shape, so nothing jumps at the changeover but the colour.
    @ViewBuilder
    private var elapsed: some View {
        Group {
            switch model.workout.clock {
            case .running(let from):
                Text(timerInterval: from ... .distantFuture, countsDown: false)
            case .paused(let at):
                Text(WorkoutFormat.duration(at))
            case nil:
                Text(verbatim: "0:00")
            }
        }
        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(model.workout.isPaused ? Color.secondary : .yellow)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityLabel(model.workout.isPaused ? "Workout time, paused" : "Workout time")
    }

    /// Dashes until the first sample lands, which takes a few seconds. An empty space there
    /// reads as a fault; a dash reads as "not yet", which is what it is.
    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13))
                .symbolEffect(.pulse, isActive: !model.workout.isPaused)
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

    /// A bar per zone, each as wide as the time gone into it, with the one you are in now
    /// lit and the rest held back. Two questions in one row: where you are, and where the
    /// hour went. Below watchOS 27 there is no tally to size them by and they share the
    /// width equally, which still answers the first question.
    private func zoneBar(_ zones: HeartRateZones) -> some View {
        let current = model.workout.heartRate.map { zones.number(for: $0) }
        let times = model.workout.zoneTimes
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let widths = Self.widths(across: proxy.size.width, count: zones.count, times: times)
                HStack(spacing: Self.zoneGap) {
                    ForEach(1 ... zones.count, id: \.self) { number in
                        Capsule()
                            .fill(HeartRateZoneStyle.color(number, of: zones.count))
                            .opacity(number == current ? 1 : 0.3)
                            .frame(width: widths[number - 1])
                    }
                }
            }
            .frame(height: 5)

            HStack(spacing: 4) {
                Text(current.map { zoneLabel(zones, current: $0) } ?? " ")
                Spacer(minLength: 2)
                if let spent = times.first(where: { $0.zone == current })?.duration, spent > 0 {
                    Text(WorkoutFormat.duration(spent))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private static let zoneGap: CGFloat = 2

    /// Every zone keeps a sliver whatever its share, so a bar you have not been in yet reads
    /// as empty rather than as absent — the row has to hold the same shape all the way
    /// through, or the zones appear to move about while you play.
    private static func widths(
        across total: CGFloat,
        count: Int,
        times: [HeartRateZoneTime]
    ) -> [CGFloat] {
        let available = max(total - zoneGap * CGFloat(count - 1), 0)
        let equal = [CGFloat](repeating: available / CGFloat(count), count: count)
        let seconds = times.reduce(0) { $0 + $1.duration }
        let sliver = min(3, available / CGFloat(count))
        let spare = available - sliver * CGFloat(count)
        guard seconds > 0, spare > 0 else { return equal }
        return (1 ... count).map { number in
            let share = times.first { $0.zone == number }?.duration ?? 0
            return sliver + spare * CGFloat(share / seconds)
        }
    }

    private func zoneLabel(_ zones: HeartRateZones, current: Int) -> String {
        let range = WorkoutFormat.zoneRange(
            lower: zones.lowerBound(of: current), upper: zones.upperBound(of: current)
        )
        return "Zone \(current) · \(range)"
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
