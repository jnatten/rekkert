import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let winnerCourt = SessionSetup.winnerCourt(
    rules: WinnerCourtRules(),
    teams: BySide(a: .home, b: .away)
)

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
}

@Suite("Finishing a session", .serialized)
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

    @Test func aTraditionalMatchCanBeStoppedBeforeAnyoneWinsIt() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 5 { phone.tap(team: .a) }
        try await settle()
        #expect(phone.state?.isFinished == false, "nobody has won it")

        phone.finish()
        try await settle()

        #expect(phone.state == nil, "stopping it ends it all the same")
        #expect(watch.state == nil)
        #expect(try store.history().count == 1, "and how far it got is kept")
    }

    @Test func stoppingATraditionalMatchFromTheWatchEndsItOnBoth() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 3 { phone.tap(team: .b) }
        try await settle()

        watch.finish()
        try await settle()

        #expect(watch.state == nil)
        #expect(phone.state == nil)
    }

    @Test func aCancelledMatchIsNotKept() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 5 { phone.tap(team: .a) }
        try await settle()

        phone.discardSession()
        try await settle()

        #expect(phone.state == nil)
        #expect(try store.history().isEmpty, "cancelling throws it away rather than filing it")
    }

    @Test func cancellingFromTheWatchStopsThePhoneFilingItEither() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 5 { phone.tap(team: .a) }
        try await settle()

        watch.discardSession()
        try await settle()

        #expect(try store.history().isEmpty, "the decision travels with the event")
        #expect(phone.state == nil)
    }

    @Test func aMatchPlayedOutIsKeptWithoutBeingAsked() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 48 { phone.tap(team: .a) }   // two straight sets
        try await settle()

        #expect(phone.state == nil, "it ends itself")
        #expect(try store.history().count == 1)
    }

    @Test func aFinishedMatchIsHeldOntoForTheResultScreen() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 48 { phone.tap(team: .a) }
        try await settle()

        #expect(phone.state == nil, "the session is over")
        #expect(phone.lastResult != nil, "but there is something to show for it")
        #expect(watch.lastResult != nil, "on both devices")

        phone.acknowledgeResult()
        #expect(phone.lastResult == nil)
    }

    @Test func aCancelledMatchHasNoResultToShow() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 5 { phone.tap(team: .a) }
        phone.discardSession()
        try await settle()

        #expect(phone.state == nil)
        #expect(phone.lastResult == nil, "it was thrown away, so there is nothing to celebrate")
    }

    @Test func startingSomethingNewClearsTheResultScreen() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 48 { phone.tap(team: .a) }
        try await settle()
        #expect(phone.lastResult != nil)

        phone.startNewSession()
        #expect(phone.lastResult == nil)
    }

    @Test func aResumedSessionCarriesItsScoreToBothDevices() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 8 { phone.tap(team: .a) }   // two games
        phone.finish()
        try await settle()
        #expect(phone.state == nil)
        #expect(watch.state == nil, "cleared on both")

        let archived = try #require(try store.history().first).state
        phone.resume(archived)
        try await settle()

        guard case .traditional(let resumed)? = watch.state else {
            Issue.record("the watch should be holding the resumed match")
            return
        }
        #expect(resumed.score.games == BySide(a: 2, b: 0), "with the games it was stopped on")
        #expect(watch.state == phone.state)
        #expect(phone.lastResult == nil, "and the result screen steps aside")
    }

    @Test func aResumedSessionCanBeScoredOnFromTheOtherDevice() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 4 { phone.tap(team: .a) }
        phone.finish()
        try await settle()

        phone.resume(try #require(try store.history().first).state)
        try await settle()
        watch.tap(team: .b)
        try await settle()

        guard case .traditional(let session)? = phone.state else {
            Issue.record("expected a traditional session")
            return
        }
        #expect(session.score.games == BySide(a: 1, b: 0))
        #expect(session.score.points == BySide(a: 0, b: 1), "the watch's point landed on top")
    }

    @Test func theWinningPointCanBeTakenBackFromTheResultScreen() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 48 { phone.tap(team: .a) }   // two straight sets, so it wins itself
        try await settle()

        #expect(phone.state == nil)
        #expect(try store.history().count == 1, "filed on the way out")
        let rewind = try #require(phone.resultRewind)
        #expect(rewind.undoesAPoint, "it was a point that ended it, not a deliberate finish")

        phone.undoResult()
        try await settle()

        guard case .traditional(let session)? = phone.state else {
            Issue.record("the match should be in play again")
            return
        }
        #expect(session.score.winner == nil, "nobody has won it any more")
        #expect(session.score.completedSets.count == 1, "the first set still stands")
        #expect(session.score.games == BySide(a: 5, b: 0))
        #expect(session.score.points == BySide(a: 3, b: 0), "back to 40-love in the sixth game")
        #expect(try store.history().isEmpty, "and the record it filed is taken back out")
        #expect(phone.lastResult == nil)
        #expect(watch.state == phone.state, "the watch is back in the match too")
    }

    @Test func takingBackAResultKeepsTheMatchTheColourItWasBeingReadIn() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, watch, _, _) = pair(directory)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        phone.toggleTeamColors()
        for _ in 0 ..< 48 { phone.tap(team: .a) }
        try await settle()

        phone.undoResult()
        try await settle()

        #expect(phone.display.areColorsSwapped, "the same match is back on, not a new one")
        #expect(watch.display.areColorsSwapped)
    }

    @Test func takingBackADeliberateEndingReopensTheSession() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 5 { phone.tap(team: .a) }
        phone.finish()
        try await settle()

        let rewind = try #require(phone.resultRewind)
        #expect(rewind.undoesAPoint == false, "what ended it was the ending, not a point")

        phone.undoResult()
        try await settle()

        guard case .traditional(let session)? = phone.state else {
            Issue.record("the match should be in play again")
            return
        }
        #expect(session.isStopped == false)
        #expect(session.score.games == BySide(a: 1, b: 0))
        #expect(session.score.points == BySide(a: 1, b: 0), "with every point it had")
    }

    @Test func aDiscardedSessionOffersNoWayBack() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 3 { phone.tap(team: .a) }
        phone.discardSession()
        try await settle()

        #expect(phone.lastResult == nil, "nothing is shown for it")
        #expect(phone.resultRewind == nil, "and so nothing offers a way back into it")
    }

    @Test func acknowledgingTheResultClosesTheWayBack() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (phone, _, _, _) = pair(directory)
        let task = Task { await phone.run() }
        defer { task.cancel() }

        phone.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        for _ in 0 ..< 48 { phone.tap(team: .a) }
        try await settle()

        phone.acknowledgeResult()
        #expect(phone.resultRewind == nil)
        phone.undoResult()
        #expect(phone.state == nil, "and undoing afterwards does nothing")
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
