#if DEBUG
import Foundation

/// `-rekkert-demo-watch-page menu|standings|controls|workout` opens straight onto a page that
/// otherwise needs a swipe, so screens can be captured from `simctl`.
enum WatchDemoLaunch {
    static var page: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-rekkert-demo-watch-page"),
              index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }
}
#endif
