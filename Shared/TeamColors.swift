import RekkertCore
import SwiftUI

extension Color {
    static let teamA = Color("TeamA")
    static let teamB = Color("TeamB")

    static func team(_ side: TeamSide) -> Color {
        side == .a ? .teamA : .teamB
    }
}

/// Which of the two colours each side is drawn in. Read from the environment rather than
/// called directly, so one preference reaches every screen that paints a team.
struct TeamPalette: Sendable, Hashable {
    var isSwapped = false

    func color(_ side: TeamSide) -> Color {
        Color.team(isSwapped ? side.other : side)
    }
}

extension EnvironmentValues {
    @Entry var teamPalette = TeamPalette()
}
