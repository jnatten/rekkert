import RekkertCore
import SwiftUI

/// One workout opened up: how long it ran, what Health made of it, and what you played
/// while it did.
struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    let workout: WorkoutRecord

    private var matches: [HistoryRecord] { model.matches(during: workout) }

    @State private var efforts: [UUID: WorkoutSeries.Effort] = [:]

    var body: some View {
        List {
            Section { headline }

            Section("Workout") {
                if let energy = workout.activeEnergyKilocalories {
                    LabeledContent("Active energy", value: WorkoutFormat.energy(energy))
                }
                if let energy = workout.totalEnergyKilocalories {
                    LabeledContent("Total energy", value: WorkoutFormat.energy(energy))
                }
                if let average = workout.heartRateAverage {
                    LabeledContent("Average heart rate", value: WorkoutFormat.beats(average))
                }
                if let maximum = workout.heartRateMaximum {
                    LabeledContent("Highest heart rate", value: WorkoutFormat.beats(maximum))
                }
                LabeledContent("Saved as", value: "Tennis, indoor")
            }

            zones

            Section {
                if matches.isEmpty {
                    Text("No matches were scored during this one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { record in
                        NavigationLink(value: HomeRoute.record(record.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title).font(.headline)
                                HStack(spacing: 4) {
                                    Image(systemName: record.state.modeSymbol)
                                    Text(record.state.modeName)
                                    Text("·")
                                    Text(record.finishedAt.formatted(date: .omitted, time: .shortened))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let effort = efforts[record.id], let line = Self.summary(of: effort) {
                                    Text(line)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Matches")
            } footer: {
                Text("Anything you scored while the workout was running is listed here, matched up by the clock. A match that spanned two of them shows under both.")
            }
        }
        .navigationTitle(workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workout.id) { efforts = measure() }
    }

    /// What each match cost, from the stretch of the workout it was played in: its first
    /// point to its last where it kept them, or its record's start and end where it did not.
    private func measure() -> [UUID: WorkoutSeries.Effort] {
        guard let series = model.series(workout.id) else { return [:] }
        var efforts: [UUID: WorkoutSeries.Effort] = [:]
        for record in matches {
            let played = model.timeline(record.id)?.span
                ?? (record.playedFrom <= record.playedTo ? record.playedFrom ... record.playedTo : nil)
            guard let played else { continue }
            let from = max(played.lowerBound, workout.startedAt)
            let to = min(played.upperBound, workout.endedAt)
            guard from < to else { continue }
            efforts[record.id] = series.effort(over: from ... to)
        }
        return efforts
    }

    private static func summary(of effort: WorkoutSeries.Effort) -> String? {
        var parts: [String] = []
        if let average = effort.heartRateAverage { parts.append("avg \(WorkoutFormat.beats(average))") }
        if effort.activeEnergyKilocalories > 0 { parts.append(WorkoutFormat.energy(effort.activeEnergyKilocalories)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Where the hour went, as Health scored it against the zones that were in force while
    /// it was being played. Absent where there is nothing to show: a workout recorded on a
    /// watch too old to be asked, or one from before this was kept.
    @ViewBuilder
    private var zones: some View {
        if !workout.heartRateZoneTimes.isEmpty {
            Section {
                ForEach(workout.heartRateZoneTimes) { zone in
                    zoneRow(zone)
                }
            } header: {
                Text("Time in zones")
            } footer: {
                Text("Worked out by Health from the zones you were on. Changing them later leaves this as it was on the day.")
            }
        }
    }

    private func zoneRow(_ zone: HeartRateZoneTime) -> some View {
        let total = workout.heartRateZoneTimes.reduce(0) { $0 + $1.duration }
        let share = total > 0 ? zone.duration / total : 0
        let color = HeartRateZoneStyle.color(zone.zone, of: workout.heartRateZoneTimes.count)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Zone \(zone.zone)")
                    .font(.subheadline.weight(.semibold))
                Text(WorkoutFormat.zoneRange(lower: zone.lowerBound, upper: zone.upperBound))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(WorkoutFormat.duration(zone.duration))
                    .font(.subheadline.monospacedDigit())
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    // A zone with nothing in it draws nothing rather than a stub, because
                    // the row above it already says "0:00" and a stub would read as some.
                    Capsule()
                        .fill(color)
                        .frame(width: max(proxy.size.width * share, share > 0 ? 4 : 0))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WorkoutFormat.duration(workout.duration))
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(
                "\(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month())) · "
                    + "\(workout.startedAt.formatted(date: .omitted, time: .shortened))–"
                    + "\(workout.endedAt.formatted(date: .omitted, time: .shortened))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
