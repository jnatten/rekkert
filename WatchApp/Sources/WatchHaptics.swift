import Foundation
import Observation
import RekkertCore
import WatchKit

/// Taps the wrist when a point goes on the board.
///
/// It holds no preference of its own — how it should buzz is set on either device and travels
/// with the match — and it does no filtering: the store announces a point only when one was
/// really played, and `HapticPreferences.buzz(forTeam:mine:scoredHere:)` decides what it is
/// worth. Both of those are somewhere a test can reach them, which matters more here than
/// usual: a buzz leaves nothing behind for a screenshot to catch.
@MainActor
@Observable
final class WatchHaptics {
    /// Whose wrist this is, per board — the same answer the serve badge is drawn from, so a
    /// point for your team taps once whichever side of the draw put you there.
    @ObservationIgnored var sides: WatchSidePreferences?
    @ObservationIgnored var preferences: () -> HapticPreferences = { HapticPreferences() }
    @ObservationIgnored var display: () -> DisplayPreferences = { DisplayPreferences() }
    @ObservationIgnored var state: () -> SessionState? = { nil }
    @ObservationIgnored var me: () -> PlayerID? = { nil }
    /// Whether that point was entered on one of this person's own two devices.
    @ObservationIgnored var isOurs: (DeviceID) -> Bool = { _ in false }

    /// Whether a tap on this watch's own scoreboard should still click.
    ///
    /// Only silent when a buzz is certain to take its place. With the filter on — which is
    /// the default — a point tapped here is exactly the one that will not buzz, and a
    /// scoreboard that answers nothing at all reads as a fault rather than as a setting.
    var clicksOnTap: Bool {
        let now = preferences()
        return now.mode == .off || now.onlyWhenSomeoneElseScores
    }

    func heard(_ point: ScoredPoint) {
        let board = WatchSidePreferences.Board(
            session: point.session, round: point.round, court: point.court
        )
        var mine = sides?.nearTeam(display: display(), board: board) ?? .a
        // Somebody who has said who they are in a tournament is only told about their own court.
        if let me = me(), case .tournament(let tournament)? = state() {
            guard let side = tournament.side(of: me, round: point.round, court: point.court) else { return }
            mine = side
        }

        guard let buzz = preferences().buzz(
            forTeam: point.team,
            mine: mine,
            scoredHere: isOurs(point.scoredBy)
        ) else { return }
        play(buzz)
    }

    /// One sequence at a time. A fast exchange would otherwise overlap two of them and the
    /// watch would roll the lot into one long shudder — the very thing the pause is for.
    @ObservationIgnored private var sequence: Task<Void, Never>?

    private func play(_ buzz: Buzz) {
        sequence?.cancel()
        let type = Self.pattern(buzz.strength)
        WKInterfaceDevice.current().play(type)
        guard buzz.taps > 1 else { return }
        sequence = Task {
            // Two plays together are rolled into one by the haptic server, so the second has
            // to wait long enough to land as a second tap rather than a longer first.
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(type)
        }
    }

    /// Single-event patterns at all three strengths, so one tap and two stay tellable apart.
    /// `.success` and `.retry` are firmer but are themselves a double and a triple, which
    /// would make "two" unreadable.
    private static func pattern(_ strength: HapticStrength) -> WKHapticType {
        switch strength {
        case .light: .click
        case .medium: .start
        case .strong: .notification
        }
    }
}
