import RekkertCore
import SwiftUI

extension Color {
    static let teamA = Color("TeamA")
    static let teamB = Color("TeamB")

    static func team(_ side: TeamSide) -> Color {
        side == .a ? .teamA : .teamB
    }
}

/// Both of a court's colours, left half and right half.
struct CourtSwatch: View {
    @Environment(\.teamPalette) private var palette
    let index: Int
    var size: CGFloat = 10

    var body: some View {
        let court = palette.court(index)
        HStack(spacing: 0) {
            court.color(.a)
            court.color(.b)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.25))
    }
}

/// Which of the two colours each side is drawn in. Read from the environment rather than
/// called directly, so one preference reaches every screen that paints a team.
struct TeamPalette: Sendable, Hashable {
    var isSwapped = false
    /// Each court of a tournament has a pair of its own, picked by index alone so every device
    /// agrees. Everything else is court 0, which is blue and orange.
    var court = 0

    func court(_ index: Int) -> TeamPalette {
        var palette = self
        palette.court = index
        return palette
    }

    func color(_ side: TeamSide) -> Color {
        team(side).color
    }

    func name(_ side: TeamSide) -> String {
        team(side).name
    }

    private func team(_ side: TeamSide) -> (color: Color, name: String) {
        let pair = Self.pairs[court % Self.pairs.count]
        return (isSwapped ? side.other : side) == .a ? pair.a : pair.b
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }

    /// None lighter than the orange, so white digits read on all of them.
    private static let pairs: [(a: (color: Color, name: String), b: (color: Color, name: String))] = [
        ((.teamA, "blue"), (.teamB, "orange")),
        ((rgb(0.62, 0.36, 0.92), "purple"), (rgb(0.18, 0.66, 0.32), "green")),
        ((rgb(0.93, 0.33, 0.60), "pink"), (rgb(0.00, 0.62, 0.66), "teal")),
        ((rgb(0.90, 0.24, 0.24), "red"), (rgb(0.36, 0.38, 0.88), "indigo")),
        ((rgb(0.62, 0.44, 0.28), "brown"), (rgb(0.12, 0.70, 0.58), "mint")),
        ((rgb(0.85, 0.65, 0.00), "gold"), (rgb(0.00, 0.62, 0.85), "cyan")),
        ((rgb(0.80, 0.22, 0.78), "magenta"), (rgb(0.52, 0.60, 0.12), "olive")),
        ((rgb(0.20, 0.30, 0.62), "navy"), (rgb(0.95, 0.45, 0.40), "coral")),
    ]
}

extension EnvironmentValues {
    @Entry var teamPalette = TeamPalette()
}
