#if DEBUG
import Foundation

/// Lets a launch argument put the UI into a state that normally needs tapping, so screens
/// can be captured from `simctl`, which has no way to touch the screen.
///
///     -rekkert-demo-browse-round 0
///     -rekkert-demo-open-court 0,1        // round, court
enum DemoLaunch {
    /// Opens the new-session sheet: -rekkert-demo-new americano
    static var newSession: String? { value(for: "-rekkert-demo-new") }

    /// Opens straight into the full-screen scoreboard.
    static var fullscreen: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-fullscreen")
    }

    /// Opens History, and with a value the detail for that row: -rekkert-demo-history 0
    static var openHistory: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-history")
    }

    static var openHistoryRecord: Int? {
        value(for: "-rekkert-demo-history").flatMap(Int.init)
    }

    /// Opens the sheet for running a past tournament's players again.
    static var rematch: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-rematch")
    }

    static var browseRound: Int? {
        value(for: "-rekkert-demo-browse-round").flatMap(Int.init)
    }

    static var openCourt: CourtRef? {
        guard let raw = value(for: "-rekkert-demo-open-court") else { return nil }
        let parts = raw.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return CourtRef(round: parts[0], court: parts[1])
    }

    private static func value(for flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
