import Foundation
import Testing

@testable import RekkertCore

@Suite("Workout records")
struct WorkoutRecordTests {
    private func store() -> SessionStore {
        SessionStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
    }

    private func workout(
        from start: Date,
        to end: Date,
        id: UUID = UUID()
    ) -> WorkoutRecord {
        WorkoutRecord(
            id: id, startedAt: start, endedAt: end, duration: end.timeIntervalSince(start)
        )
    }

    private func match(from start: Date?, to end: Date) -> HistoryRecord {
        HistoryRecord(
            finishedAt: end,
            title: "Us vs Them",
            state: .traditional(TraditionalSession(rules: TraditionalRules(), teams: BySide(a: .home, b: .away))),
            startedAt: start
        )
    }

    // MARK: - The migration

    /// The whole point of hand-rolling `HistoryRecord.init(from:)`: every record already on
    /// somebody's phone is missing this key, and `history()` drops what it cannot read
    /// without saying so — so getting it wrong empties the history rather than crashing.
    ///
    /// The old bytes are made by taking the key back out rather than by pasting a literal,
    /// which would go stale the next time `SessionState` gained a case. The assertion that
    /// it was there to remove is what stops this going vacuous if the field is renamed.
    @Test func aRecordWrittenBeforeStartTimesExistedStillDecodes() throws {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let current = match(from: start, to: start.addingTimeInterval(3_600))
        var fields = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(current)) as? [String: Any]
        )
        #expect(fields.removeValue(forKey: "startedAt") != nil)
        let legacy = try JSONSerialization.data(withJSONObject: fields)

        let record = try JSONCoding.decoder.decode(HistoryRecord.self, from: legacy)

        #expect(record.startedAt == nil)
        #expect(record.title == "Us vs Them")
        #expect(record.state == current.state)
        // Standing in for the stretch it was played over, so it can still fall inside a
        // workout that was running at the time.
        #expect(record.playedFrom == record.finishedAt)
    }

    @Test func aStartTimeSurvivesTheRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let original = match(from: start, to: start.addingTimeInterval(3_600))

        let data = try JSONCoding.encoder.encode(original)
        let decoded = try JSONCoding.decoder.decode(HistoryRecord.self, from: data)

        #expect(decoded.startedAt == start)
        #expect(decoded == original)
    }

    @Test func aWorkoutWrittenWithoutADurationFallsBackToItsSpan() throws {
        let json = """
        {"endedAt":768003600,"id":"1B4E28BA-2FA1-11D2-883F-0016D3CCD886","startedAt":768000000}
        """
        let record = try JSONCoding.decoder.decode(WorkoutRecord.self, from: Data(json.utf8))

        #expect(record.duration == 3_600)
        #expect(record.activeEnergyKilocalories == nil)
    }

    // MARK: - Which matches a workout covers

    @Test func aMatchPlayedInsideTheWorkoutIsCovered() {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let session = workout(from: start, to: start.addingTimeInterval(3_600))

        #expect(session.covers(match(
            from: start.addingTimeInterval(600), to: start.addingTimeInterval(1_800)
        )))
    }

    /// Pressing start in the second game should still gather that game up. This is the case
    /// that decides the whole design: a stored link would orphan it permanently.
    @Test func aMatchAlreadyUnderwayWhenTheWorkoutStartedIsCovered() {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let session = workout(from: start, to: start.addingTimeInterval(3_600))

        #expect(session.covers(match(
            from: start.addingTimeInterval(-600), to: start.addingTimeInterval(900)
        )))
    }

    @Test func aMatchStillRunningWhenTheWorkoutStoppedIsCovered() {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let session = workout(from: start, to: start.addingTimeInterval(3_600))

        #expect(session.covers(match(
            from: start.addingTimeInterval(3_000), to: start.addingTimeInterval(4_200)
        )))
    }

    @Test func aMatchPlayedAtAnotherTimeIsNotCovered() {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let session = workout(from: start, to: start.addingTimeInterval(3_600))

        #expect(!session.covers(match(
            from: start.addingTimeInterval(-7_200), to: start.addingTimeInterval(-3_600)
        )))
        #expect(!session.covers(match(
            from: start.addingTimeInterval(7_200), to: start.addingTimeInterval(10_800)
        )))
    }

    @Test func aRecordWithNoStartTimeIsWeighedAtTheMomentItFinished() {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let session = workout(from: start, to: start.addingTimeInterval(3_600))

        #expect(session.covers(match(from: nil, to: start.addingTimeInterval(1_800))))
        #expect(!session.covers(match(from: nil, to: start.addingTimeInterval(9_000))))
    }

    /// A match spanning two workouts shows under both. That is the answer, not a bug — you
    /// were playing it during each of them.
    @Test func aMatchSpanningTwoWorkoutsIsCoveredByBoth() {
        let start = Date(timeIntervalSince1970: 768_000_000)
        let first = workout(from: start, to: start.addingTimeInterval(1_800))
        let second = workout(from: start.addingTimeInterval(2_400), to: start.addingTimeInterval(4_200))
        let played = match(from: start.addingTimeInterval(1_200), to: start.addingTimeInterval(3_000))

        #expect(first.covers(played))
        #expect(second.covers(played))
    }

    // MARK: - Storage

    @Test func aWorkoutIsFiledAndReadBack() throws {
        let store = store()
        let start = Date(timeIntervalSince1970: 768_000_000)
        let record = WorkoutRecord(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            duration: 3_540,
            activeEnergyKilocalories: 420,
            heartRateAverage: 128,
            heartRateMaximum: 171
        )

        #expect(!store.hasWorkouts())
        try store.archive(record)

        #expect(store.hasWorkouts())
        #expect(try store.workouts() == [record])
    }

    /// Filed under the workout's own id, so the watch sending it live and queueing it lands
    /// as one row rather than two.
    @Test func filingTheSameWorkoutTwiceReplacesRatherThanDuplicates() throws {
        let store = store()
        let start = Date(timeIntervalSince1970: 768_000_000)
        let id = UUID()
        try store.archive(workout(from: start, to: start.addingTimeInterval(600), id: id))
        try store.archive(workout(from: start, to: start.addingTimeInterval(3_600), id: id))

        let filed = try store.workouts()
        #expect(filed.count == 1)
        #expect(filed.first?.endedAt == start.addingTimeInterval(3_600))
    }

    @Test func workoutsAreListedNewestFirst() throws {
        let store = store()
        let start = Date(timeIntervalSince1970: 768_000_000)
        let older = workout(from: start, to: start.addingTimeInterval(600))
        let newer = workout(from: start.addingTimeInterval(86_400), to: start.addingTimeInterval(87_000))
        try store.archive(older)
        try store.archive(newer)

        #expect(try store.workouts().map(\.id) == [newer.id, older.id])
    }

    @Test func aWorkoutIsDeleted() throws {
        let store = store()
        let start = Date(timeIntervalSince1970: 768_000_000)
        let record = workout(from: start, to: start.addingTimeInterval(600))
        try store.archive(record)

        try store.deleteWorkout(record.id)

        #expect(try store.workouts().isEmpty)
        #expect(!store.hasWorkouts())
    }
}
