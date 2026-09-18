import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

private func points(_ store: MatchStore) -> BySide<Int>? {
    if case .pointCount(let session)? = store.state { return session.score.points }
    return nil
}

/// The escape hatch for a merge nobody in front of it recognises.
@Suite("Settling the score")
@MainActor
struct SettleScoreTests {
    private func pair() -> (host: MatchStore, guest: MatchStore, link: LoopbackTransport) {
        let (hostSide, guestSide) = LoopbackTransport.pair()
        let host = MatchStore(device: DeviceID(), transport: hostSide, snapshotInterval: 0)
        let guest = MatchStore(device: DeviceID(), transport: guestSide, snapshotInterval: 0)
        host.startSharing()
        return (host, guest, hostSide)
    }

    @Test func onlyTheHostMaySettleIt() {
        let (host, guest, _) = pair()
        host.configure(counting)
        host.tap(team: .a)

        #expect(host.canSettleScore, "the match belongs to whoever started it")
        #expect(guest.canSettleScore == false)
    }

    @Test func thereIsNothingToSettleBeforeAMatchStarts() {
        let (host, _, _) = pair()
        #expect(host.canSettleScore == false)
    }

    @Test func everybodyEndsUpOnTheHostsNumber() async throws {
        let (host, guest, link) = pair()
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }

        host.configure(counting)
        await eventually { points(guest) != nil }

        // Apart, and each of them scoring — the union that comes back is four, which is the
        // honest answer and may still not be the one the people on court recognise.
        link.setReachable(false)
        for _ in 0 ..< 2 { host.tap(team: .a) }
        for _ in 0 ..< 2 { guest.tap(team: .a) }
        link.setReachable(true)
        await eventually { points(host) == BySide(a: 4, b: 0) && points(guest) == BySide(a: 4, b: 0) }

        // The host says it was two.
        for _ in 0 ..< 2 { host.undoLast() }
        await eventually { points(host) == BySide(a: 2, b: 0) }
        host.settleScore()

        await eventually { points(guest) == BySide(a: 2, b: 0) }
        #expect(points(guest) == BySide(a: 2, b: 0), "the guest replays to the host's number")
        #expect(host.state == guest.state)
    }

    /// Settling is a correction inside the match, not the end of it. Retiring the session and
    /// starting another would file away the match everyone is playing.
    @Test func theMatchCarriesOnUnderTheSameSession() async throws {
        let (host, guest, _) = pair()
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }

        host.configure(counting)
        host.tap(team: .b)
        await eventually { points(guest) == BySide(a: 0, b: 1) }
        let session = guest.log.sessionID

        host.settleScore()
        await eventually { guest.log.events.count == host.log.events.count }

        #expect(guest.log.sessionID == session, "the same match, still in play")
        #expect(guest.state != nil)
        #expect(guest.lastResult == nil, "nobody was shown a result")
        #expect(guest.replacedSessionTitle == nil, "and nothing was archived behind them")
    }

    /// Scoring goes on afterwards from where it was settled, rather than being pinned there.
    @Test func aPointAfterItStillCounts() async throws {
        let (host, guest, _) = pair()
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }

        host.configure(counting)
        host.tap(team: .a)
        await eventually { points(guest) == BySide(a: 1, b: 0) }

        host.settleScore()
        // Waited for on purpose. A tap made before the line was drawn sorts behind it and is
        // overridden, which is the whole meaning of the thing — so what this asserts is that
        // scoring goes on afterwards, not that the ordering can be ignored.
        await eventually { guest.log.events.count == host.log.events.count }
        guest.tap(team: .b)

        await eventually { points(host) == BySide(a: 1, b: 1) }
        #expect(points(host) == BySide(a: 1, b: 1), "a line in the sand, not a lock")
    }

    /// The restore replays over everything before it, so an undo reaching past it would spend
    /// the undo and change nothing on the board.
    @Test func undoReachesNoFurtherBackThanTheSettlement() {
        let (host, _, _) = pair()
        host.configure(counting)
        for _ in 0 ..< 3 { host.tap(team: .a) }
        host.settleScore()

        #expect(host.canUndo == false, "nothing before the line can be taken back")
        host.undoLast()
        #expect(points(host) == BySide(a: 3, b: 0))

        host.tap(team: .b)
        #expect(host.canUndo)
        host.undoLast()
        #expect(points(host) == BySide(a: 3, b: 0), "a point after it can still be taken back")
    }
}
