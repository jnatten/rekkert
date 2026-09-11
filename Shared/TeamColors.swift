import RekkertCore
import SwiftUI

extension Color {
    static let teamA = Color("TeamA")
    static let teamB = Color("TeamB")

    static func team(_ side: TeamSide) -> Color {
        side == .a ? .teamA : .teamB
    }
}
