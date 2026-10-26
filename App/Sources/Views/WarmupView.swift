import RekkertCore
import SwiftUI

struct WarmupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingEnd = false
    let since: Date

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Label("Warm-up", systemImage: "figure.run")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(timerInterval: min(since, Date()) ... .distantFuture, countsDown: false)
                    .font(.system(size: 88, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if model.workout.isTracking {
                    workout
                }
                Spacer()
                start
            }
            .padding()
            .navigationTitle(model.store.state?.modeName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    ConnectionBadge()
                    SharingBadge()
                    WorkoutBadge()
                    if sizeClass == .regular { TVButton() }
                }
                if sizeClass == .regular {
                    ToolbarItem(placement: .topBarTrailing) { BoardButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MatchOptionsMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EndSessionButton { showingEnd = true }
                }
            }
            .confirmationDialog("Call this off?", isPresented: $showingEnd, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { model.discard() }
                Button("Keep warming up", role: .cancel) {}
            }
        }
    }

    private var workout: some View {
        Label {
            Text(model.workout.isPaused ? "Workout paused" : "Heart rate is on your watch")
        } icon: {
            Image(systemName: model.workout.isPaused ? "pause.fill" : "heart.fill")
                .foregroundStyle(model.workout.isPaused ? Color.secondary : .pink)
                .symbolEffect(.pulse, isActive: !model.workout.isPaused)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var start: some View {
        if model.store.canRunRounds {
            Button {
                model.store.endWarmup()
            } label: {
                Label("Start game", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Text("The game starts when the host starts it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
