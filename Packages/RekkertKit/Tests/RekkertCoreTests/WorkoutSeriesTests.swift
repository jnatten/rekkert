import Foundation
import Testing
@testable import RekkertCore

private let start = Date(timeIntervalSince1970: 768_000_000)
private func seconds(_ count: Double) -> Date { start.addingTimeInterval(count) }

/// Four fifteen-second steps: 100, 120 and 140 bpm, then nothing read.
private func series(pauses: [DateInterval] = []) -> WorkoutSeries {
    WorkoutSeries(
        workoutID: UUID(uuidString: "76767676-0000-0000-0000-000000000000")!,
        start: start, interval: 15,
        heartRate: [100, 120, 140, nil],
        heartRateMax: [110, 130, 150, nil],
        activeEnergy: [1, 2, 3, 4],
        pauses: pauses
    )
}

@Suite("A workout over time")
struct WorkoutSeriesTests {
    @Test func aStepIsFifteenSecondsUntilTheWorkoutRunsLong() {
        #expect(WorkoutSeries.interval(forSpan: 3_600) == 15)
        #expect(WorkoutSeries.interval(forSpan: 5 * 3_600) == 30)
        #expect(WorkoutSeries.interval(forSpan: 12 * 3_600) == 60)
    }

    @Test func eachStepCountsForAsMuchOfItAsTheStretchCovers() throws {
        let effort = try #require(series().effort(over: seconds(7.5) ... seconds(37.5)))

        #expect(effort.heartRateAverage == 120)
        #expect(effort.heartRateMaximum == 150)
        #expect(effort.activeEnergyKilocalories == 0.5 + 2 + 1.5)
    }

    @Test func aStepWithNothingReadCountsForNothing() throws {
        let effort = try #require(series().effort(over: seconds(30) ... seconds(60)))

        #expect(effort.heartRateAverage == 140)
        #expect(effort.activeEnergyKilocalories == 3 + 4)
    }

    @Test func aHeldStretchIsLeftOut() throws {
        let held = series(pauses: [DateInterval(start: seconds(15), duration: 15)])
        let effort = try #require(held.effort(over: seconds(7.5) ... seconds(37.5)))

        #expect(effort.heartRateAverage == 120)
        #expect(effort.activeEnergyKilocalories == 0.5 + 1.5)
    }

    @Test func aStretchOutsideTheWorkoutHasNoEffort() {
        #expect(series().effort(over: seconds(-600) ... seconds(-60)) == nil)
    }

    @Test func energyIsKeptToATenth() {
        let rounded = WorkoutSeries(
            workoutID: UUID(), start: start, interval: 15,
            heartRate: [120], heartRateMax: [125], activeEnergy: [1.23456]
        )
        #expect(rounded.activeEnergy == [1.2])
    }

    @Test func itReadsBackAsItWasWritten() throws {
        let original = series(pauses: [DateInterval(start: seconds(15), duration: 15)])
        let decoded = try JSONCoding.decoder.decode(WorkoutSeries.self, from: JSONCoding.encoder.encode(original))
        #expect(decoded == original)
    }

    /// The whole of it rides one WatchConnectivity message, which has room for tens of
    /// kilobytes rather than hundreds.
    @Test func threeHoursFitsComfortablyOnTheWire() throws {
        let span: TimeInterval = 3 * 3_600
        let interval = WorkoutSeries.interval(forSpan: span)
        let steps = Int(span / interval)
        let long = WorkoutSeries(
            workoutID: UUID(), start: start, interval: interval,
            heartRate: (0 ..< steps).map { 120 + $0 % 60 },
            heartRateMax: (0 ..< steps).map { 130 + $0 % 60 },
            activeEnergy: (0 ..< steps).map { 1.5 + Double($0 % 10) / 10 }
        )
        #expect(try JSONCoding.encoder.encode(Wire.workout(.series(long))).count < 16_000)
    }

    @Test func aSeriesIsKeptBesideItsWorkoutAndGoesWithIt() throws {
        let store = SessionStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        let kept = series()
        try store.archive(WorkoutRecord(id: kept.workoutID, startedAt: start, endedAt: seconds(60), duration: 60))
        try store.archive(kept)

        #expect(store.series(kept.workoutID) == kept)
        #expect(try store.workouts().count == 1, "the list reads the workouts and nothing else")

        try store.deleteWorkout(kept.workoutID)
        #expect(store.series(kept.workoutID) == nil)
    }
}
