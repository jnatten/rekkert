#if DEBUG
import Foundation

/// `-rekkert-demo-watch-page menu|standings|controls|workout` opens straight onto a page that
/// otherwise needs a swipe, so screens can be captured from `simctl`.
enum WatchDemoLaunch {
    static var page: String? { value(after: "-rekkert-demo-watch-page") }

    /// `-rekkert-demo-watch-sides fixed|followPhone|manual` picks the side mode, which
    /// otherwise takes a tap on the menu page.
    static var sides: String? { value(after: "-rekkert-demo-watch-sides") }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
