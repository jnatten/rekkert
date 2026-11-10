import Foundation

/// What one device knows of another's clock: the far clock minus the near one lies between
/// `lower` and `upper` (spec 005, D-2).
public struct ClockBounds: Codable, Sendable, Hashable {
    /// How fast two clocks are assumed to drift apart, at most.
    public static let drift = 50e-6
    /// FR-006: a delay more than this out is no delay at all.
    public static let budget: TimeInterval = 0.1
    /// Taps are stamped to the hundredth.
    public static let rounding: TimeInterval = 0.005

    public var lower: TimeInterval
    public var upper: TimeInterval
    /// The near clock when the sample was taken.
    public var sampledAt: Date

    public init(lower: TimeInterval, upper: TimeInterval, sampledAt: Date) {
        self.lower = lower
        self.upper = upper
        self.sampledAt = sampledAt
    }

    /// Asked at `asked` and heard back at `heard` by the near clock, answered with the far
    /// clock reading `farClock` somewhere in between.
    public init(asked: Date, farClock: Date, heard: Date) {
        self.init(lower: farClock.timeIntervalSince(heard), upper: farClock.timeIntervalSince(asked), sampledAt: heard)
    }

    public var estimate: TimeInterval { (lower + upper) / 2 }
    public var halfWidth: TimeInterval { (upper - lower) / 2 }

    public func aged(at now: Date) -> ClockBounds {
        let widening = max(0, now.timeIntervalSince(sampledAt)) * Self.drift
        return ClockBounds(lower: lower - widening, upper: upper + widening, sampledAt: sampledAt)
    }

    public func contradicts(_ other: ClockBounds) -> Bool {
        upper < other.lower || other.upper < lower
    }

    public func narrower(than other: ClockBounds, at now: Date) -> Bool {
        aged(at: now).halfWidth < other.aged(at: now).halfWidth
    }

    /// These bounds on a second device, followed by that device's bounds on a third: the near
    /// device's bounds on the third.
    public func composed(with next: ClockBounds) -> ClockBounds {
        ClockBounds(lower: lower + next.lower, upper: upper + next.upper, sampledAt: sampledAt)
    }

    /// How long after the tap, read on the far clock, a point arrived by the near one. `nil`
    /// when that could be more than a tenth of a second out.
    public func delay(arrivedAt arrival: Date, tappedAt tap: Date) -> TimeInterval? {
        let aged = aged(at: arrival)
        guard aged.halfWidth + Self.rounding <= Self.budget else { return nil }
        return arrival.timeIntervalSince(tap) + aged.estimate
    }
}

/// Bounds as they travel: whole milliseconds, rounded outwards so they never claim more than
/// was known, and no sample time, since the receiver takes them as of their arrival.
public struct ClockSpan: Codable, Sendable, Hashable {
    public var lower: Int
    public var upper: Int

    public init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = upper
    }

    public init(_ bounds: ClockBounds) {
        self.init(lower: Int((bounds.lower * 1_000).rounded(.down)), upper: Int((bounds.upper * 1_000).rounded(.up)))
    }

    public func bounds(at moment: Date) -> ClockBounds {
        ClockBounds(lower: Double(lower) / 1_000, upper: Double(upper) / 1_000, sampledAt: moment)
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        try self.init(lower: container.decode(Int.self), upper: container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lower)
        try container.encode(upper)
    }
}

/// The narrowest recent bounds this device holds on each other device's clock.
public struct ClockBook: Sendable, Hashable {
    public private(set) var bounds: [DeviceID: ClockBounds] = [:]

    public init() {}

    public subscript(device: DeviceID) -> ClockBounds? { bounds[device] }

    /// Keeps the narrower of the two, unless they cannot both be true: then the kept one is
    /// from before that device's clock changed.
    public mutating func learn(_ sample: ClockBounds, for device: DeviceID, at now: Date) {
        if let kept = bounds[device]?.aged(at: now), !sample.contradicts(kept), !sample.narrower(than: kept, at: now) { return }
        bounds[device] = sample
    }

    /// After this device's own clock jumped: nothing learned before it holds.
    public mutating func forget() {
        bounds = [:]
    }
}
