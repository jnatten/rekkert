import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let winnerCourt = SessionSetup.winnerCourt(
    rules: WinnerCourtRules(),
    teams: BySide(a: .home, b: .away)
)

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(120))
}

@Suite("Finishing a session")
@MainActor
struct FinishTests {
    private func pair(_ directory: URL) -> (MatchStore, MatchStore, LoopbackTransport, LoopbackTransport) {
        let (one, two) = LoopbackTransport.pair()
        let phone = MatchStore(
            device: DeviceID(), transport: one,
            store: SessionStore(directory: directory), snapshotInterval: 0
        )
        let watch = MatchStore(device: DeviceID(), transport: two, snapshotInterval: 0, keepsHistory: false)
        return (phone, watch, one, two)
    }

    @Test func finishingOnOneDeviceClearsBoth() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(winnerCourt)
        for _ in 0 ..< 4 { phone.tap(team: .a) }
        try await settle()
        #expect(watch.state != nil)

        phone.finish()
        try await settle()

        #expect(phone.state == nil, "the phone is back to a clean slate")
        #expect(watch.state == nil, "and so is the watch")
    }

    @Test func aFinishedSessionIsNotResurrectedOnTheNextReconnect() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(winnerCourt)
        for _ in 0 ..< 4 { phone.tap(team: .a) }
        try await settle()

        phone.finish()
        try await settle()

        // Everything that wakes the pair up later: reconnects, wrist raises, the retry loop.
        await watch.synchronise()
        await phone.synchronise()
        try await settle()

        #expect(phone.state == nil, "the finished session stays finished")
        #expect(watch.state == nil)
    }

    @Test func aFinishedSessionWithResultsIsArchivedOnceOnThePhoneOnly() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(winnerCourt)
        for _ in 0 ..< 4 { phone.tap(team: .a) }
        try await settle()

        // Finished from the watch, to prove the phone still keeps the record.
        watch.finish()
        try await settle()
        await phone.synchronise()
        try await settle()

        #expect(try store.history().count == 1, "archived once, by the device that keeps history")
        #expect(phone.state == nil)
        #expect(watch.state == nil)
    }

    @Test func aSessionWithNothingPlayedIsNotKept() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(winnerCourt)
        try await settle()
        phone.finish()
        try await settle()

        #expect(try store.history().isEmpty, "nothing was played, so there is nothing to keep")
        #expect(phone.state == nil)
    }

    @Test func startingSomethingNewRetiresWhatCameBefore() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(winnerCourt)
        for _ in 0 ..< 4 { phone.tap(team: .a) }
        try await settle()

        phone.startNewSession()
        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        try await settle()
        await watch.synchronise()
        try await settle()

        #expect(phone.state?.isTournament == false)
        if case .traditional? = phone.state {} else { Issue.record("the phone lost the new session") }
        if case .traditional? = watch.state {} else { Issue.record("the watch did not follow to the new session") }
    }
}
