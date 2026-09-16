import RekkertCore
import SwiftUI

/// One workout opened up: how long it ran, what Health made of it, and what you played
/// while it did.
struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    let workout: WorkoutRecord

    private var matches: [HistoryRecord] { model.matches(during: workout) }

    var body: some View {
        List {
            Section { headline }

            Section("Workout") {
                if let energy = workout.activeEnergyKilocalories {
                    LabeledContent("Active energy", value: WorkoutFormat.energy(energy))
                }
                if let average = workout.heartRateAverage {
                    LabeledContent("Average heart rate", value: WorkoutFormat.beats(average))
                }
                if let maximum = workout.heartRateMaximum {
                    LabeledContent("Highest heart rate", value: WorkoutFormat.beats(maximum))
                }
                LabeledContent("Saved as", value: "Tennis, indoor")
            }

            Section {
                if matches.isEmpty {
                    Text("No matches were scored during this one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { record in
                        NavigationLink(value: HomeRoute.record(record)) {
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
