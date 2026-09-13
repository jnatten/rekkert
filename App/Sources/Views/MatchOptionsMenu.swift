import RekkertCore
import SwiftUI

/// The corrections you reach for mid-match: who is serving, and which way round the
/// scoreboard reads.
struct MatchOptionsMenu: View {
    @Environment(AppModel.self) private var model
    var round = 0
    var court = 0

    var body: some View {
        Menu {
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
