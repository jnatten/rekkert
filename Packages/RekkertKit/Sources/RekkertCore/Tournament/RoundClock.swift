import Foundation

/// Kept as a length and how much of it has run rather than as an end time, because a paused
/// round has no end.
public struct RoundClock: Codable, Sendable, Hashable {
    public var length: TimeInterval
    public var runningSince: Date?
    public var banked: TimeInterval

    public init(length: TimeInterval, runningSince: Date? = nil, banked: TimeInterval = 0) {
        self.length = length
        self.runningSince = runningSince
        self.banked = banked
    }

    public var isPaused: Bool { runningSince == nil }

    public var endsAt: Date? {
        runningSince.map { $0.addingTimeInterval(length - banked) }
    }

    /// Clamped, because the start is another device's stamp and this one's clock may run behind.
    public func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public func remaining(at now: Date) -> TimeInterval {
        length - elapsed(at: now)
    }

    public func hasRunOut(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    public func pausing(at now: Date) -> RoundClock {
        guard runningSince != nil else { return self }
        return RoundClock(length: length, runningSince: nil, banked: elapsed(at: now))
    }

    public func resuming(at now: Date) -> RoundClock {
        guard runningSince == nil else { return self }
        return RoundClock(length: length, runningSince: now, banked: banked)
    }

    /// A round that has already run out gets the extra time from now.
    public func snoozing(by extra: TimeInterval, at now: Date) -> RoundClock {
        var next = self
        next.length = max(length, elapsed(at: now)) + extra
        return next
    }
}
