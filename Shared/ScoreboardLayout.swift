import RekkertCore
import SwiftUI

/// Which way round the two halves are drawn. Deliberately a local preference rather than a
/// synced event: it describes where you happen to be standing relative to this screen, so
/// flipping the phone must not move the watch.
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
    static let storageKey = "dev.natten.rekkert.mirroredScoreboard"
}
