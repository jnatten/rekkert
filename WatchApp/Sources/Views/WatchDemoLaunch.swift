#if DEBUG
import Foundation

/// `-rekkert-demo-watch-page menu|standings|controls|workout|presets` opens straight onto a page that
/// otherwise needs a swipe, so screens can be captured from `simctl`.
enum WatchDemoLaunch {
    static var page: String? { value(after: "-rekkert-demo-watch-page") }

    /// `-rekkert-demo-watch-sides fixed|followPhone|manual` picks the side mode, which
    /// otherwise takes a tap on the menu page.
    static var sides: String? { value(after: "-rekkert-demo-watch-sides") }

    /// `-rekkert-demo-watch-mine orange|blue` says which of the two the wearer is, which
    /// otherwise takes a tap on the controls page.
    static var isMineSwapped: Bool? {
        switch value(after: "-rekkert-demo-watch-mine") {
        case "orange": true
        case "blue": false
        default: nil
        }
    }

    /// `-rekkert-demo-watch-join CODE` opens the join sheet with the code already in it and
    /// submits, which is the watch counterpart of the phone's `-rekkert-share-join`. `simctl`
    /// cannot tap, so it is the only way the wrist's half of a join gets exercised.
    static var joinCode: String? { value(after: "-rekkert-demo-watch-join") }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
