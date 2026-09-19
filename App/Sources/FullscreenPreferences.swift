import Foundation
import Observation

/// How the full-screen board is drawn, kept on this phone alone: the watch has no full
/// screen, and the other phones on a shared match sit in their own light.
@MainActor
@Observable
final class FullscreenPreferences {
    /// Both halves black, the names in the team colours: white on black is what still reads
    /// on a phone propped up in the sun.
    var isBlackout: Bool {
        didSet {
            guard isBlackout != oldValue else { return }
            UserDefaults.standard.set(isBlackout, forKey: Self.blackoutKey)
        }
    }

    private static let blackoutKey = "fullscreenBlackout"

    init() {
        isBlackout = UserDefaults.standard.bool(forKey: Self.blackoutKey)
    }
}
