import SwiftUI
import UIKit

/// Keeps the screen awake while anything still needs it to be.
///
/// Two things want this and they overlap: a full-screen scoreboard propped at the side of the
/// court, and hosting, which the system stops the moment the app is suspended. Whichever
/// finishes first must not switch it off under the other, so they hold a reason each and the
/// screen is only let go when the last one does.
@MainActor
enum ScreenSleep {
    private static var reasons: Set<String> = []

    static func hold(_ reason: String) {
        reasons.insert(reason)
        apply()
    }

    static func release(_ reason: String) {
        reasons.remove(reason)
        apply()
    }

    private static func apply() {
        UIApplication.shared.isIdleTimerDisabled = !reasons.isEmpty
    }
}
