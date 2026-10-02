import RekkertCore
import SwiftUI

extension Color {
    static let teamA = Color("TeamA")
    static let teamB = Color("TeamB")

    static func team(_ side: TeamSide) -> Color {
        side == .a ? .teamA : .teamB
    }

    /// From the index alone, so every device agrees. No blue or orange: those are the teams'.
    static func court(_ index: Int) -> Color {
        courtColors[index % courtColors.count]
    }

    private static let courtColors: [Color] = [.green, .purple, .yellow, .pink, .teal, .red, .indigo, .brown]
}

struct CourtSwatch: View {
    let index: Int
    var size: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(Color.court(index))
            .frame(width: size, height: size)
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
