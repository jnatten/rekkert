import Foundation
@testable import RekkertSync

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

/// Two stores holding the same match: the same session, every event on both, and so the same
/// board. What most of these tests mean by the pair having synced.
@MainActor
func inStep(_ one: MatchStore, _ other: MatchStore) -> Bool {
    one.log.sessionID == other.log.sessionID
        && one.log.vector == other.log.vector
        && one.state == other.state
}

/// Before a link is cut: one more round trip from each store, which comes back only once every
/// question that store asked before it has been answered.
///
/// A reply goes back whether or not the link is still up, and the answer to a hello carries the
/// events the asker is missing. A question asked before the cut and answered after it carries
/// across exactly what the cut is keeping apart. Each link delivers in order, so this waits out
/// every such question without guessing how long they take.
@MainActor
func drain(_ stores: MatchStore...) async {
    for store in stores { await store.synchronise() }
}

/// A fixed stretch of time, for when nothing after it depends on how much got done inside it:
/// before a check that something did not happen, or to let the run loops get going as they
/// would have long before in the app.
///
/// The one place a fixed wait belongs. A slow machine gets less done inside it, which can only
/// make "nothing happened" easier to see: it weakens the check that follows, but never fails it.
/// Anything that has to have happened is waited for with `eventually` instead.
func quietPeriod() async {
    try? await Task.sleep(for: .milliseconds(250))
}
