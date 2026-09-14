import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

/// Accepts sends and never answers them — the failure WatchConnectivity can produce when
/// the counterpart suspends mid-request.
private final class SilentTransport: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability: AsyncStream<Bool>
    private let lock = NSLock()
    private var _attempts = 0
    private var _queued: [Data] = []

    var attempts: Int { lock.withLock { _attempts } }
    var queued: [Data] { lock.withLock { _queued } }

    init() {
        inbound = AsyncStream { _ in }
        reachability = AsyncStream { _ in }
    }

    var isReachable: Bool { true }
    func activate() {}

    func sendLive(_ payload: Data) async -> Data? {
        lock.withLock { _attempts += 1 }
        try? await Task.sleep(for: .seconds(60))   // never answers
        return nil
    }

    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) { lock.withLock { _queued.append(payload) } }
}

@Suite("Sync resilience", .serialized)
@MainActor
struct ResilienceTests {
    @Test func aReplyThatNeverArrivesDoesNotWedgeTheOutbox() async throws {
        let transport = SilentTransport()
        let store = MatchStore(
            device: DeviceID(), transport: transport,
            snapshotInterval: 0, sendTimeout: .milliseconds(80), retryInterval: .milliseconds(60)
        )
        let task = Task { await store.run() }
        defer { task.cancel() }

        store.configure(setup)
        store.tap(team: .a)
        try await Task.sleep(for: .milliseconds(500))

        #expect(transport.attempts > 1, "it keeps trying instead of hanging on the first send")
        #expect(!transport.queued.isEmpty, "and falls back to the durable queue when a send times out")

        // And the store is still usable rather than frozen.
        store.tap(team: .b)
        guard case .traditional(let session)? = store.state else {
            Issue.record("no session")
            return
        }
        #expect(session.score.points == BySide(a: 1, b: 1))
    }

    @Test func anUnreachablePeerGetsTheBacklogOnTheDurableQueue() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        phoneLink.setReachable(false)

        let phone = MatchStore(
            device: DeviceID(), transport: phoneLink,
            snapshotInterval: 0, retryInterval: .milliseconds(60)
        )
        let watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(setup)
        phone.tap(team: .a)
        phone.tap(team: .a)
        try await Task.sleep(for: .milliseconds(400))

        guard case .traditional(let session)? = watch.state else {
            Issue.record("the watch never received the session")
            return
        }
        #expect(session.score.points == BySide(a: 2, b: 0),
                "delivered even though the phone could not reach the watch live")
    }

    @Test func theNewestStateReachesTheSnapshotChannelEvenWhenThrottled() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        phoneLink.setReachable(false)

        let phone = MatchStore(
            device: DeviceID(), transport: phoneLink,
            snapshotInterval: 0.05, retryInterval: .seconds(30)
        )
        let watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(setup)
        // A burst well inside the throttle window: only the first would publish before,
        // leaving the context holding a stale score.
        for _ in 0 ..< 3 { phone.tap(team: .a) }
        try await Task.sleep(for: .milliseconds(400))

        guard case .traditional(let session)? = watch.state else {
            Issue.record("the watch never received the session")
            return
        }
        #expect(session.score.points == BySide(a: 3, b: 0), "the trailing publish carried the newest state")
    }
}

/// A pair of links that can be silenced on every channel at once — out of range, or the
/// Simulator, where the durable queue does nothing either. `LoopbackTransport` always
/// delivers queued payloads, which hides what happens when even those are lost.
nonisolated private final class QuietableLink: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability: AsyncStream<Bool>
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let lock = NSLock()
    private var peer: QuietableLink?
    private var quiet = false
    /// Switched off to prove convergence without the coalescing application-context
    /// channel, which on a real watch is the slowest and least predictable of the three.
    var carriesSnapshots = true

    init() {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
        reachability = AsyncStream { _ in }
    }

    static func pair() -> (QuietableLink, QuietableLink) {
        let one = QuietableLink(), two = QuietableLink()
        one.peer = two
        two.peer = one
        return (one, two)
    }

    func setQuiet(_ value: Bool) { lock.withLock { quiet = value } }
    var isReachable: Bool { lock.withLock { peer != nil && !quiet } }
    func activate() {}

    private var target: QuietableLink? {
        lock.withLock { quiet ? nil : peer }
    }

    func sendLive(_ payload: Data) async -> Data? {
        guard let peer = target else { return nil }
        return await withCheckedContinuation { continuation in
            let once = SingleAnswer(continuation)
            peer.packets.yield(InboundPacket(payload: payload) { once.resume($0) })
        }
    }

    func queue(_ payload: Data) {
        target?.packets.yield(InboundPacket(payload: payload))
    }

    func publishSnapshot(_ payload: Data) {
        guard carriesSnapshots else { return }
        target?.packets.yield(InboundPacket(payload: payload))
    }
}

nonisolated private final class SingleAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func resume(_ value: Data?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

@Suite("Sessions ending out of earshot", .serialized)
@MainActor
struct RetirementTests {
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    private func points(_ store: MatchStore) -> BySide<Int>? {
        guard case .traditional(let session) = store.state else { return nil }
        return session.score.points
    }

    /// The match is ended from the watch while the phone is out of range, so only the
    /// watch retires the session. The phone must not be left scoring into a match every
    /// packet of which the watch now refuses — a blackout that used to be permanent, and
    /// to survive relaunching both apps, since the retired list is persisted.
    @Test func aMatchEndedOutOfRangeDoesNotBlackOutTheOtherDevice() async throws {
        let (phoneLink, watchLink) = QuietableLink.pair()
        let shared = ActiveSession(log: MatchLog(sessionID: UUID()))
        let phone = MatchStore(device: DeviceID(), transport: phoneLink, session: shared, snapshotInterval: 0)
        let watch = MatchStore(
            device: DeviceID(), transport: watchLink,
            session: shared, snapshotInterval: 0, keepsHistory: false
        )
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(setup)
        phone.tap(team: .a)
        try await settle()
        #expect(points(watch) == BySide(a: 1, b: 0), "the watch was following along")

        phoneLink.setQuiet(true)
        watchLink.setQuiet(true)
        watch.finish()
        try await settle()
        #expect(watch.state == nil, "the watch ended and retired the session")
        #expect(phone.state != nil, "the phone never heard, and is still in the match")

        phoneLink.setQuiet(false)
        watchLink.setQuiet(false)
        phone.tap(team: .b)
        try await settle()

        #expect(phone.state == nil, "the phone is told the match ended rather than scoring alone")
        #expect(phone.lastResult != nil, "and is shown how it went instead of losing it")

        // The real test of recovery: the two can start again and find each other.
        phone.startNewSession()
        phone.configure(setup)
        phone.tap(team: .b)
        try await settle()
        #expect(points(watch) == BySide(a: 0, b: 1), "a fresh match on the phone reaches the watch")
    }

    /// Each install makes its own session id when it has nothing stored, so a phone and a
    /// watch meeting for the first time disagree about which session is being played.
    /// Reconciling that used to rest entirely on the application-context channel.
    @Test func devicesWithDifferentSessionsAgreeWithoutTheSnapshotChannel() async throws {
        let (phoneLink, watchLink) = QuietableLink.pair()
        phoneLink.carriesSnapshots = false
        watchLink.carriesSnapshots = false
        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        let watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        phone.configure(setup)
        phone.tap(team: .a)
        phone.tap(team: .a)
        try await settle()

        #expect(watch.log.sessionID == phone.log.sessionID, "the watch came over to the phone's session")
        #expect(points(watch) == BySide(a: 2, b: 0))
    }
}
