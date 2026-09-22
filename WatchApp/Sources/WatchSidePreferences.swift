import Foundation
import Observation
import RekkertCore

/// Which way round this watch draws the court, kept on this wrist alone.
///
/// It never travels. The phone's `DisplayPreferences` answer where a screen propped at the
/// side of the court is standing, which is not a question a wrist has; and two people on one
/// match should each be free to read their own the way they are facing. Local defaults are
/// what make that true by construction rather than by agreement.
@MainActor
@Observable
final class WatchSidePreferences {
    /// `static` is a keyword, so the case that never moves is spelled `fixed`.
    enum Mode: String, CaseIterable, Identifiable {
        case fixed
        case followPhone
        case manual

        var id: Self { self }

        var title: String {
            switch self {
            case .fixed: "Static"
            case .followPhone: "Follow phone"
            case .manual: "Manual"
            }
        }

        var symbol: String {
            switch self {
            case .fixed: "lock"
            case .followPhone: "iphone.radiowaves.left.and.right"
            case .manual: "hand.tap"
            }
        }

        var next: Mode {
            let all = Mode.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        }
    }

    /// Read only in `.manual`. Kept against the match it was made for: turning the watch
    /// round answers where you are standing today, the same way the phone's own flip does,
    /// and the phone drops that at the start of a new match.
    private var flippedFor: String? {
        didSet {
            guard flippedFor != oldValue else { return }
            let defaults = UserDefaults.standard
            if let flippedFor {
                defaults.set(flippedFor, forKey: Self.flippedKey)
            } else {
                defaults.removeObject(forKey: Self.flippedKey)
            }
        }
    }

    /// The court as this wrist wants it, given which end the match says the sides are at.
    ///
    /// `.fixed` is blue on the left whatever the court does — the wrist is glanced at rather
    /// than studied, and the colour you are is the thing you are looking for. `.followPhone`
    /// reads the phone's whole board, its flip as well as the court. `.manual` is `.fixed`
    /// turned round by hand and left there: somebody who wanted it to follow the court would
    /// have picked the middle one.
    func layout(court endsSwapped: Bool, display: DisplayPreferences, session: UUID) -> ScoreboardLayout {
        switch mode {
        case .fixed:
            ScoreboardLayout(isMirrored: display.areColorsSwapped)
        case .followPhone:
            ScoreboardLayout(isMirrored: display.isMirrored != endsSwapped)
        case .manual:
            ScoreboardLayout(isMirrored: display.areColorsSwapped != isFlipped(in: session))
        }
    }

    func isFlipped(in session: UUID) -> Bool { flippedFor == session.uuidString }

    /// Whatever the mode, the button means this wrist: it moves to `.manual` and turns the
    /// board from whatever is on the screen now, so nothing has to be explained first.
    func flip(from shown: ScoreboardLayout, display: DisplayPreferences, session: UUID) {
        let wanted = !shown.isMirrored
        mode = .manual
        flippedFor = wanted != display.areColorsSwapped ? session.uuidString : nil
    }

    private static let modeKey = "watchSideMode"
    private static let flippedKey = "watchSidesFlippedFor"

    init() {
        let defaults = UserDefaults.standard
        mode = defaults.string(forKey: Self.modeKey).flatMap(Mode.init(rawValue:)) ?? .fixed
        flippedFor = defaults.string(forKey: Self.flippedKey)
        #if DEBUG
        if let chosen = WatchDemoLaunch.sides.flatMap(Mode.init(rawValue:)) { mode = chosen }
        #endif
    }
}
