import RekkertCore
import SwiftUI

/// The corrections you reach for mid-match: who is serving, which way round the
/// scoreboard reads, and whether the score is read out loud.
struct MatchOptionsMenu: View {
    @Environment(AppModel.self) private var model
    var round = 0
    var court = 0

    var body: some View {
        @Bindable var announcer = model.announcer
        Menu {
            Toggle(isOn: $announcer.isEnabled) {
                Label("Call the score", systemImage: "speaker.wave.2")
            }
            Button("Swap serving team", systemImage: "arrow.left.arrow.right") {
                model.store.swapServingTeam(round: round, court: court)
            }
            Button("Swap sides", systemImage: "rectangle.2.swap") {
                model.store.toggleScoreboardMirrored()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Match options")
    }
}
