import RekkertCore
import SwiftUI

/// Which way round the two halves are drawn.
///
/// Two things decide it, and either alone swaps them. The flip is a local preference rather
/// than a synced event: it describes where you happen to be standing relative to this
/// screen, so flipping the phone must not move the watch. The changeover is the court
/// itself turning over, read off the score, and is the same on every device looking at it.
struct ScoreboardLayout {
    var isMirrored: Bool

    /// Left to right, as drawn.
    var order: [TeamSide] { isMirrored ? [.b, .a] : [.a, .b] }

    /// Reads a `BySide` the way round the screen shows it, so a games line reads the same
    /// direction as the numbers above it.
    func asShown<Value>(_ value: BySide<Value>) -> (left: Value, right: Value) {
        isMirrored ? (value.b, value.a) : (value.a, value.b)
    }
}

extension ScoreboardLayout {
    /// The phone's board: where this phone is standing, and which end the court has turned
    /// to. Both together read the way the match started.
    ///
    /// A factory rather than a second initialiser, which inside the struct would take the
    /// memberwise one away from the callers that still want to say only one of the two.
    static func phone(_ snapshot: ScoreboardSnapshot?, _ display: DisplayPreferences) -> ScoreboardLayout {
        ScoreboardLayout(isMirrored: display.isMirrored != (snapshot?.endsSwapped ?? false))
    }
}
