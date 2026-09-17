import RekkertCore
import SwiftUI

/// The workouts the watch recorded, newest first. A list of its own rather than something
/// folded into the match history: a workout is not a match, and one can exist with no
/// matches in it at all.
struct WorkoutsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.workouts) { workout in
                    NavigationLink(value: HomeRoute.workout(workout)) {
                        WorkoutRow(workout: workout, matches: model.matches(during: workout).count)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.deleteWorkout(model.workouts[index].id)
                    }
                }
            } footer: {
                if !model.workouts.isEmpty {
                    Text("Deleting one here removes Rekkert's copy. The workout itself stays in the Health app.")
                }
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.workouts.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "figure.tennis",
                    description: Text("Start one from your Apple Watch and it shows up here.")
                )
            }
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutRecord
    let matches: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.headline)

            HStack(spacing: 4) {
                Image(systemName: "figure.tennis")
                Text(workout.startedAt.formatted(date: .omitted, time: .shortened))
                Text("–")
                Text(workout.endedAt.formatted(date: .omitted, time: .shortened))
                Text("·")
                Text(WorkoutFormat.duration(workout.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let summary = WorkoutFormat.summary(of: workout, matches: matches) {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
