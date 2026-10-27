import Foundation

/// When the wrist is told that the match has gone out of reach, and that it is back (FR-032).
///
/// Once each way: a match that comes and goes inside the patience says nothing, and one that
/// was never said to be gone is not said to be back.
public struct ReachCue: Sendable, Equatable {
    public enum Cue: Sendable, Equatable {
        case outOfReach
        case backInStep
    }

    public static let patience: TimeInterval = 15

    private var outSince: Date?
    private var hasSaidOut = false

    public init() {}

    public mutating func observe(isInReach: Bool, at now: Date) -> Cue? {
        guard !isInReach else {
            outSince = nil
            guard hasSaidOut else { return nil }
            hasSaidOut = false
            return .backInStep
        }
        let since = outSince ?? now
        outSince = since
        guard !hasSaidOut, now.timeIntervalSince(since) >= Self.patience else { return nil }
        hasSaidOut = true
        return .outOfReach
    }
}
