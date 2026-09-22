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

    /// Which of the two the wearer said they were, on each board they said it on.
    ///
    /// Kept per board rather than as one answer for the watch. A friendly redraws the
    /// partnerships every round and a tournament shows a page per court, so an answer given
    /// for one board is not an answer for another — and an answer given for a match that is
    /// over is not an answer for the next one, which is why the session is in the key and why
    /// writing throws the other sessions away.
    private var chosen: [String: String] {
        didSet {
            guard chosen != oldValue else { return }
            UserDefaults.standard.set(chosen, forKey: Self.mineKey)
        }
    }

    /// Which team is the wearer's on this board: the blue one, unless they have said
    /// otherwise. Their end of the court is the near one, and the serve is drawn the way they
    /// see it from there.
    ///
    /// Blue is the default rather than the first team because staying the blue one is already
    /// how this app answers "which of these am I" — so anyone using the colour swap for that
    /// is telling the board which end they are at without knowing it.
    func nearTeam(display: DisplayPreferences, board: Board) -> TeamSide {
        #if DEBUG
        if let demo = WatchDemoLaunch.isMineSwapped {
            return demo ? display.blueSide.other : display.blueSide
        }
        #endif
        return chosen[board.key].flatMap(TeamSide.init(rawValue:)) ?? display.blueSide
    }

    /// Moves the wearer to the other team on this board.
    ///
    /// Stored as the side itself rather than as "the one that is not blue": having said out
    /// loud which of the two they are, a later colour swap should recolour the board without
    /// walking them to the other end of the court.
    func chooseOtherSide(display: DisplayPreferences, board: Board) {
        let next = nearTeam(display: display, board: board).other
        var kept = chosen.filter { $0.key.hasPrefix(board.sessionPrefix) }
        kept[board.key] = next.rawValue
        chosen = kept
    }

    /// The board an answer belongs to: this match, this round, this court.
    struct Board: Hashable {
        var session: UUID
        var round: Int
        var court: Int

        var sessionPrefix: String { "\(session.uuidString):" }
        var key: String { "\(sessionPrefix)\(round):\(court)" }
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
    private static let mineKey = "watchSidesChosen"

    init() {
        let defaults = UserDefaults.standard
        mode = defaults.string(forKey: Self.modeKey).flatMap(Mode.init(rawValue:)) ?? .fixed
        flippedFor = defaults.string(forKey: Self.flippedKey)
        chosen = defaults.dictionary(forKey: Self.mineKey) as? [String: String] ?? [:]
        #if DEBUG
        if let picked = WatchDemoLaunch.sides.flatMap(Mode.init(rawValue:)) { mode = picked }
        #endif
    }
}
