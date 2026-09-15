import Foundation

/// Waits for something to become true, rather than for a fixed stretch of time.
///
/// A fixed settle is a guess about the slowest machine the suite will ever run on. Too short
/// and it fails while something else on the machine is busy — which has happened here, and
/// cost more than once in working out whether a failure was real. Too long and every test pays
/// for the worst case. Polling returns the moment the thing has happened, so the suite is both
/// steadier and quicker, and only waits out the full deadline when something is genuinely wrong.
///
/// It does not assert. The `#expect` that follows does, so a failure still reports the values.
@MainActor
func eventually(within seconds: Double = 5, _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
