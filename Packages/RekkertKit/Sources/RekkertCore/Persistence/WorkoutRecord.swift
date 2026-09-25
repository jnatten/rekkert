import Foundation

/// How long a workout spent in one heart rate zone.
///
/// Carries its own edges rather than pointing at a configuration. The zones can be moved in
/// Health Settings at any time, and a record that only knew "zone 3" would quietly start
/// meaning something else the day they were; these numbers are what zone 3 was on the day
/// it was played.
public struct HeartRateZoneTime: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { zone }
    /// 1 upwards, lowest first.
    public var zone: Int
    /// The beat this zone begins at. Nil for zone 1, which has no floor.
    public var lowerBound: Double?
    /// The last beat that still counts as it. Nil for the top zone, which has no ceiling.
    public var upperBound: Double?
    public var duration: TimeInterval

    public init(zone: Int, lowerBound: Double?, upperBound: Double?, duration: TimeInterval) {
        self.zone = zone
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.duration = duration
    }
}

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
    /// The resting burn over the same stretch. Nil on every record written before it was
    /// kept, and on any workout whose resting samples Health never attached.
    public var basalEnergyKilocalories: Double?
    public var heartRateAverage: Double?
    public var heartRateMaximum: Double?
    /// Time in each heart rate zone, lowest first, as Health worked it out. Empty on a watch
    /// too old to be asked and on every record written before this existed.
    public var heartRateZoneTimes: [HeartRateZoneTime]

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        activeEnergyKilocalories: Double? = nil,
        basalEnergyKilocalories: Double? = nil,
        heartRateAverage: Double? = nil,
        heartRateMaximum: Double? = nil,
        heartRateZoneTimes: [HeartRateZoneTime] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.basalEnergyKilocalories = basalEnergyKilocalories
        self.heartRateAverage = heartRateAverage
        self.heartRateMaximum = heartRateMaximum
        self.heartRateZoneTimes = heartRateZoneTimes
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, duration
        case activeEnergyKilocalories, basalEnergyKilocalories, heartRateAverage, heartRateMaximum
        case heartRateZoneTimes
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
        basalEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .basalEnergyKilocalories)
        heartRateAverage = try container.decodeIfPresent(Double.self, forKey: .heartRateAverage)
        heartRateMaximum = try container.decodeIfPresent(Double.self, forKey: .heartRateMaximum)
        heartRateZoneTimes = try container.decodeIfPresent(
            [HeartRateZoneTime].self, forKey: .heartRateZoneTimes
        ) ?? []
    }

    /// What Health calls total calories. Only when both halves are there: active alone is
    /// already shown as active, and passing it off as a total is the bug this replaced.
    public var totalEnergyKilocalories: Double? {
        guard let activeEnergyKilocalories, let basalEnergyKilocalories else { return nil }
        return activeEnergyKilocalories + basalEnergyKilocalories
    }

    /// Whether a finished session was played while this workout was running.
    ///
    /// Worked out from the two clocks rather than from a key stored on either side: a
    /// workout has no id until Health saves it, which is after the match it covers has
    /// already been filed, so there is no moment at which a foreign key could honestly be
    /// written. Bounds are inclusive, so a record from before start times were kept — which
    /// is an instant rather than a stretch — still lands inside one.
    public func covers(_ record: HistoryRecord) -> Bool {
        record.playedFrom <= endedAt && record.playedTo >= startedAt
    }
}
