import RekkertCore
import RekkertSync
import SwiftUI

/// The corrections you reach for mid-match: who is serving, which way round the
/// scoreboard reads, which side is blue, and whether the score is read out loud.
struct MatchOptionsMenu: View {
    @Environment(AppModel.self) private var model
    var round = 0
    var court = 0

    var body: some View {
        @Bindable var announcer = model.announcer
        Menu {
            if model.store.role == .host {
                Button("Show the code", systemImage: "person.2.wave.2") {
                    model.showingShareCode = true
                }
            } else if model.store.canEndSession {
                Button("Share this match", systemImage: "person.2.wave.2") {
                    model.sharing.host()
                    model.showingShareCode = true
                }
                // Whoever is inviting you did not wait for you to have nothing on. Joining
                // files this match away rather than losing it, the way it always has.
                Button("Join someone else's", systemImage: "arrow.right.circle") {
                    model.showingJoin = true
                }
            }
            if model.workout.isAvailable {
                // A button whose title flips rather than a toggle: the state belongs to the
                // watch and arrives a moment later, and a switch that springs back is worse
                // than a button that takes its time.
                Button(
                    model.workout.isTracking ? "Stop workout" : "Start workout",
                    systemImage: model.workout.isTracking ? "stop.circle" : "figure.tennis"
                ) {
                    model.workout.isTracking ? model.workout.stop() : model.workout.start()
                }
            }
            Toggle(isOn: $announcer.isEnabled) {
                Label("Call the score", systemImage: "speaker.wave.2")
            }
            Button("Swap serving team", systemImage: "arrow.left.arrow.right") {
                model.store.swapServingTeam(round: round, court: court)
            }
            Button("Swap sides", systemImage: "rectangle.2.swap") {
                model.store.toggleScoreboardMirrored()
            }
            Button("Swap colours", systemImage: "circle.lefthalf.filled") {
                model.store.toggleTeamColors()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Match options")
    }
}
