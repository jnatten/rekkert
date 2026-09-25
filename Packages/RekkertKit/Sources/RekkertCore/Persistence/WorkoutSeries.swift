import Foundation

/// How a workout's heart rate and energy went over its length, in equal steps. Read out of
/// Health once the workout has ended, and sent to the one phone paired with the watch that
/// recorded it, so each match played during it can say what it cost.
public struct WorkoutSeries: Codable, Sendable, Hashable {
    public var workoutID: UUID
    public var start: Date
    public var interval: TimeInterval
    /// Average beats per minute in each step; `nil` where nothing was read, which is every
    /// step the workout was held for.
    public var heartRate: [Int?]
    public var heartRateMax: [Int?]
    /// Active energy burned in each step, to a tenth of a kilocalorie.
    public var activeEnergy: [Double]
    public var pauses: [DateInterval]

    public init(
        workoutID: UUID, start: Date, interval: TimeInterval,
        heartRate: [Int?], heartRateMax: [Int?], activeEnergy: [Double], pauses: [DateInterval] = []
    ) {
        self.workoutID = workoutID
        self.start = start
        self.interval = interval
        self.heartRate = heartRate
        self.heartRateMax = heartRateMax
        self.activeEnergy = activeEnergy.map { ($0 * 10).rounded() / 10 }
        self.pauses = pauses
    }

    /// Fifteen seconds, stretched for a long workout so the whole of it stays a few hundred
    /// steps: one forgotten on the wrist overnight would otherwise not fit on the wire.
    public static func interval(forSpan span: TimeInterval) -> TimeInterval {
        max(15, (span / 720 / 15).rounded(.up) * 15)
    }

    public var count: Int { heartRate.count }
    public var end: Date { start.addingTimeInterval(interval * Double(count)) }

    public func startOfStep(_ index: Int) -> Date {
        start.addingTimeInterval(interval * Double(index))
    }

    public struct Effort: Sendable, Hashable {
        public var heartRateAverage: Double?
        public var heartRateMaximum: Int?
        public var activeEnergyKilocalories: Double
    }

    /// What a stretch of the workout cost: each step counted for as much of it as falls in
    /// the stretch, and none of those the workout was held for. `nil` where the two do not
    /// meet at all.
    public func effort(over window: ClosedRange<Date>) -> Effort? {
        var weighted = 0.0
        var weight = 0.0
        var maximum: Int?
        var energy = 0.0
        var met = false

        for index in 0 ..< count {
            let from = startOfStep(index)
            let overlap = min(from.addingTimeInterval(interval), window.upperBound)
                .timeIntervalSince(max(from, window.lowerBound))
            guard overlap > 0 else { continue }
            met = true
            if pauses.contains(where: { $0.contains(from.addingTimeInterval(interval / 2)) }) { continue }

            let share = overlap / interval
            energy += (activeEnergy[safe: index] ?? 0) * share
            if let bpm = heartRate[index] {
                weighted += Double(bpm) * share
                weight += share
            }
            if let peak = heartRateMax[safe: index] ?? heartRate[index] {
                maximum = max(maximum ?? peak, peak)
            }
        }
        guard met else { return nil }
        return Effort(
            heartRateAverage: weight > 0 ? weighted / weight : nil,
            heartRateMaximum: maximum,
            activeEnergyKilocalories: energy
        )
    }
}
