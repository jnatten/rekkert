import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let oneSet = SessionSetup.traditional(rules: TraditionalRules(setsToWin: 1), teams: BySide(a: .home, b: .away))

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
}

private func scratch() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
}

@Suite("Filing a match with its timeline", .serialized)
@MainActor
struct TimelineFilingTests {
    private func pair(_ directory: URL, session: ActiveSession? = nil, watchDirectory: URL? = nil) -> (MatchStore, MatchStore) {
        let (one, two) = LoopbackTransport.pair()
        let phone = MatchStore(
            device: DeviceID(), transport: one, store: SessionStore(directory: directory),
            session: session, snapshotInterval: 0
        )
        let watch = MatchStore(
            device: DeviceID(), transport: two, store: watchDirectory.map(SessionStore.init(directory:)),
            snapshotInterval: 0, keepsHistory: false
        )
        return (phone, watch)
    }

    /// Six straight games: the last tap wins it, and the phone files it on the way out.
    private func winASet(on store: MatchStore) {
        store.configure(oneSet)
        for _ in 0 ..< 24 { store.tap(team: .a) }
    }

    @Test func aWonMatchIsFiledWithItsTimeline() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        let before = Date()
        winASet(on: phone)
        try await settle()

        let record = try #require(try store.history().first)
        let timeline = try #require(store.timeline(record.id))
        guard case .traditional(let session) = record.state else { Issue.record("not a match"); return }

        #expect(timeline.entries.count == 24)
        #expect(timeline.entries.last?.board.sets == session.score.completedSets.map(\.games))
        #expect(timeline.entries.last?.ended == .match(.a))
        let started = try #require(record.startedAt)
        let until = try #require(record.playedUntil)
        #expect(started >= before.addingTimeInterval(-1))
        #expect(until >= started)
    }

    @Test func deletingARecordTakesItsTimelineWithIt() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        winASet(on: phone)
        try await settle()
        let record = try #require(try store.history().first)
        try store.deleteHistory(record.id)

        #expect(store.timeline(record.id) == nil)
    }

    @Test func aResultTakenBackOnThePhoneRunsOnFromWhereItWas() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        winASet(on: phone)
        try await settle()
        let started = try #require(try store.history().first?.startedAt)

        phone.undoResult()
        phone.tap(team: .b)
        phone.tap(team: .b)
        phone.finish()
        try await settle()

        let records = try store.history()
        let timeline = try #require(records.first.flatMap { store.timeline($0.id) })
        #expect(records.count == 1)
        #expect(timeline.entries.count == 23 + 2, "everything but the point taken back")
        #expect(!timeline.entries.contains { $0.kind == .settled })
        #expect(timeline.entries.last?.board.points == BySide(a: "40", b: "30"))
        #expect(records.first?.startedAt == started, "the same match, started when it did")
    }

    @Test func aResultTakenBackOnTheWatchTakesThePhonesRecordWithIt() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        winASet(on: phone)
        try await settle()
        #expect(try store.history().count == 1)

        watch.undoResult()
        try await settle()
        #expect(try store.history().isEmpty, "the phone's record of a result nobody holds any more")

        watch.tap(team: .b)
        try await settle()
        phone.finish()
        try await settle()

        let records = try store.history()
        let timeline = try #require(records.first.flatMap { store.timeline($0.id) })
        #expect(records.count == 1)
        #expect(timeline.entries.count == 23 + 1)
        #expect(timeline.entries.last?.winner == .b)
    }

    @Test func aResultTakenBackTwiceStillReadsAsOneMatch() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        winASet(on: phone)
        try await settle()
        phone.undoResult()
        phone.tap(team: .a)
        try await settle()
        #expect(try store.history().count == 1, "won again")

        phone.undoResult()
        phone.tap(team: .b)
        phone.finish()
        try await settle()

        let records = try store.history()
        let timeline = try #require(records.first.flatMap { store.timeline($0.id) })
        #expect(records.count == 1)
        #expect(timeline.entries.count == 23 + 1)
        #expect(timeline.entries.last?.winner == .b)
    }

    @Test func aResumedSessionIsFiledWithEverythingItWasThrough() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(oneSet)
        for _ in 0 ..< 8 { phone.tap(team: .a) }
        phone.finish()
        try await settle()
        let first = try #require(try store.history().first)

        phone.resume(first.state, from: first.id)
        phone.tap(team: .b)
        phone.finish()
        try await settle()

        let second = try #require(try store.history().first { $0.id != first.id })
        let timeline = try #require(store.timeline(second.id))
        #expect(timeline.entries.count == 8 + 1)
        #expect(timeline.resumedAt.count == 1)
        #expect(store.timeline(first.id)?.entries.count == 8, "and the first record keeps its own")
    }

    @Test func aDiscardedSessionLeavesNoTimeline() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(oneSet)
        for _ in 0 ..< 5 { phone.tap(team: .a) }
        let session = phone.log.sessionID
        phone.discardSession()
        try await settle()

        #expect(SessionStore(directory: directory).timeline(session) == nil)
    }

    @Test func theWatchKeepsNoTimelineOfItsOwn() async throws {
        let directory = scratch()
        let watchDirectory = scratch()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: watchDirectory)
        }
        let (phone, watch) = pair(directory, watchDirectory: watchDirectory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        winASet(on: watch)
        try await settle()

        let timelines = watchDirectory.appending(path: "timelines")
        #expect(!FileManager.default.fileExists(atPath: timelines.path()))
        #expect(try SessionStore(directory: directory).history().count == 1)
    }

    /// The log a match is played in can have been lying empty since the last one ended; the
    /// record says when this one began.
    @Test func aMatchStartsWhenItWasSetUpNotWhenItsLogWasMade() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let stale = ActiveSession(log: MatchLog(createdAt: Date().addingTimeInterval(-7200)))
        let (phone, _) = pair(directory, session: stale)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        winASet(on: phone)
        try await settle()

        let started = try #require(try store.history().first?.startedAt)
        #expect(started > Date().addingTimeInterval(-60))
    }
}
