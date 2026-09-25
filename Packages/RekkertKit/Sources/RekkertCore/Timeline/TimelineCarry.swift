import Foundation

/// What a session had been through before its log began, kept for when it is filed.
///
/// Taking a result back, or picking a filed session up again, starts a fresh log with the
/// score restored onto it, and the points that led there are not in it. This is them.
public struct TimelineCarry: Codable, Sendable, Hashable {
    public enum Reason: String, Codable, Sendable, Hashable {
        case takenBack
        case resumed
    }

    /// The session this carries into.
    public var sessionID: UUID
    public var reason: Reason
    /// When the session carried from began, for a result taken back — which is the same match
    /// going on, so its record should start where the match did.
    public var startedAt: Date?
    public var timeline: MatchTimeline

    public init(sessionID: UUID, reason: Reason, startedAt: Date? = nil, timeline: MatchTimeline) {
        self.sessionID = sessionID
        self.reason = reason
        self.startedAt = startedAt
        self.timeline = timeline
    }

    /// Everything up to a result, less the last thing that made it one: what the continuation
    /// of a taken-back result starts from. `ended` is the log the result was reached in, and
    /// `before` whatever that log itself carried.
    public static func takingBack(
        _ ended: MatchLog, into sessionID: UUID, carried before: TimelineCarry?, me: PlayerID?
    ) -> TimelineCarry {
        TimelineCarry(
            sessionID: sessionID,
            reason: .takenBack,
            startedAt: before?.startedAt ?? ended.playedSpan?.lowerBound,
            timeline: MatchTimeline.make(from: ended.takingBackTheResult(), continuing: before, me: me)
        )
    }
}

extension MatchLog {
    /// The log as it would be with its last undoable event taken back: the result undone.
    public func takingBackTheResult(from device: DeviceID = DeviceID()) -> MatchLog {
        var rewound = self
        if let target = lastUndoableEvent() {
            rewound.append(.undo(target.id), from: device)
        }
        return rewound
    }
}
