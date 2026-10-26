import Foundation

/// Rings once when a timed ladder round runs out. A snooze moves the end and so rings again
/// at the new one; a pause or the whistle leaves nothing to ring for.
public struct RoundAlarm: Equatable, Sendable {
    public struct Bell: Hashable, Sendable {
        public var session: UUID
        public var round: Int
        public var endsAt: Date
    }

    /// A round found already over by more than this, by a device joining late or opened again,
    /// is not rung for.
    public static let stale: TimeInterval = 60

    public private(set) var armed: Bell?
    private var rung: Bell?

    public init() {}

    public var nextDeadline: Date? {
        guard let armed, armed != rung else { return nil }
        return armed.endsAt
    }

    public mutating func heard(_ state: SessionState?, session: UUID, at now: Date) {
        armed = Self.bell(for: state, session: session)
        if let armed, now.timeIntervalSince(armed.endsAt) > Self.stale { rung = armed }
    }

    public mutating func tick(at now: Date) -> Bool {
        guard let armed, armed != rung, now >= armed.endsAt else { return false }
        rung = armed
        return true
    }

    public static func bell(for state: SessionState?, session: UUID) -> Bell? {
        guard case .tournament(let tournament)? = state, !tournament.isFinished, tournament.warmupStartedAt == nil,
              let round = tournament.currentRound, !round.isCancelled, !round.isEnded,
              let endsAt = round.clock?.endsAt else { return nil }
        return Bell(session: session, round: round.index, endsAt: endsAt)
    }
}
