import RekkertCore
import RekkertSync
import SwiftUI

/// The corrections you reach for mid-match: who is serving, which way round the
/// scoreboard reads, which side is blue, and whether the score is read out loud.
struct MatchOptionsMenu: View {
    @Environment(AppModel.self) private var model
    @State private var settling = false
    var round = 0
    var court = 0
    /// For the modes that play several rounds and have something to look back at. Here
    /// rather than in the toolbar, which is full: one more button squeezes the title down to an
    /// ellipsis on every screen that has one.
    var onShowRounds: (() -> Void)?

    var body: some View {
        @Bindable var announcer = model.announcer
        Menu {
            if let onShowRounds {
                Button("Rounds and standings", systemImage: "list.bullet.rectangle", action: onShowRounds)
            }
            if model.store.role == .host {
                Button("Show the code", systemImage: "person.2.wave.2") {
                    model.showingShareCode = true
                }
                // Only while somebody is there to hear it, which is also the only moment the
                // two logs have caught up enough for it to be the last word.
                if model.store.canSettleScore, model.sharing.reachablePeers > 0 {
                    Button("Use my score everywhere", systemImage: "checkmark.circle") {
                        settling = true
                    }
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
                if model.workout.isTracking {
                    Button(
                        model.workout.isPaused ? "Resume workout" : "Pause workout",
                        systemImage: model.workout.isPaused ? "play.circle" : "pause.circle"
                    ) {
                        model.workout.isPaused ? model.workout.resume() : model.workout.pause()
                    }
                }
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
        .confirmationDialog(
            "Use this phone's score?",
            isPresented: $settling,
            titleVisibility: .visible
        ) {
            Button("Use my score", role: .destructive) { model.store.settleScore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The score itself is on the screen behind this, which is a better place for it
            // than a line of text that would have to guess at which court is meant.
            Text("Every phone on this match will be set to the score shown here. Anything scored elsewhere that has not reached this phone yet will be replaced.")
        }
    }
}
