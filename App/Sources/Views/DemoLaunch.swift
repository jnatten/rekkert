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

    /// Turns the phone on its side. simctl cannot rotate and Xcode ships no Simulator app
    /// to do it from, so landscape has to be asked for at launch like everything else here.
    static var isLandscape: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-landscape")
    }

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

    /// Seeds a couple of workouts and opens the list. Nothing can start a real one on a
    /// simulator — there is no wrist — so the only way to photograph the screen is to put
    /// the records there directly.
    static var openWorkouts: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-workouts")
    }

    /// With a value, the detail for that row: -rekkert-demo-workouts 0
    static var openWorkoutRecord: Int? {
        value(for: "-rekkert-demo-workouts").flatMap(Int.init)
    }

    /// Opens the voice picker, which otherwise takes a toggle and a tap to reach.
    static var openVoices: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-voices")
    }

    /// Opens the settings screen.
    static var openSettings: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-settings")
    }

    /// Opens a friendly's rounds-and-standings sheet.
    static var openRounds: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-rounds-sheet")
    }

    /// Opens the sheet for putting a filed match's names right.
    static var editNames: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-edit-names")
    }

    /// Opens the sheet for running a past tournament's players again.
    static var rematch: Bool {
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo-rematch")
    }

    /// `-rekkert-demo-sit-outs` puts a ninth player in the demo tournament so somebody sits
    /// out, and with a name opens the sheet for changing who, that player already picked.
    static var sitOutPick: String? { value(for: "-rekkert-demo-sit-outs") }

    /// `-rekkert-share-host 482915` starts sharing on a pinned code, and
    /// `-rekkert-share-join 482915` opens the join sheet with it already filled in. Between
    /// them two simulators can be driven through the whole flow without a tap.
    static var hostCode: String? { value(for: "-rekkert-share-host") }
    static var joinCode: String? { value(for: "-rekkert-share-join") }

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
