import Foundation

/// A workout as it stood when Health saved it, kept by whichever device keeps things —
/// which is the phone, and never the watch that recorded it.
///
/// Deliberately a copy rather than a pointer into Health. Reading it back would need the
/// phone to hold a read authorisation of its own, and a permission the user said no to
/// would empty this list while the workouts themselves went on existing. The summary is a
/// handful of numbers; Health keeps the real thing, and is welcome to it.
public struct WorkoutRecord: Codable, Sendable, Hashable, Identifiable {
    /// The `HKWorkout`'s own id. Filed under it, so a delivery that arrives twice replaces
    /// rather than duplicates — the same trick history plays with the session id.
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    /// What Health itself shows, which is not `endedAt - startedAt` if the session was ever
    /// interrupted.
    public var duration: TimeInterval
    /// Kilocalories, named for the unit so nothing here has to know about `HKUnit`.
    public var activeEnergyKilocalories: Double?
    public var heartRateAverage: Double?
    public var heartRateMaximum: Double?

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        activeEnergyKilocalories: Double? = nil,
        heartRateAverage: Double? = nil,
        heartRateMaximum: Double? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.heartRateAverage = heartRateAverage
        self.heartRateMaximum = heartRateMaximum
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, duration
        case activeEnergyKilocalories, heartRateAverage, heartRateMaximum
    }

    /// Hand-rolled from the first day rather than the second. `HistoryRecord` was written
    /// with the synthesised one and could not be added to afterwards without a migration;
    /// there is no reason to learn that twice.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            ?? endedAt.timeIntervalSince(startedAt)
        activeEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
        heartRateAverage = try container.decodeIfPresent(Double.self, forKey: .heartRateAverage)
        heartRateMaximum = try container.decodeIfPresent(Double.self, forKey: .heartRateMaximum)
    }

    /// Whether a finished session was played while this workout was running.
    ///
    /// Worked out from the two clocks rather than from a key stored on either side: a
    /// workout has no id until Health saves it, which is after the match it covers has
    /// already been filed, so there is no moment at which a foreign key could honestly be
    /// written. Bounds are inclusive, so a record from before start times were kept — which
    /// is an instant rather than a stretch — still lands inside one.
    public func covers(_ record: HistoryRecord) -> Bool {
        record.playedFrom <= endedAt && record.finishedAt >= startedAt
    }
}
