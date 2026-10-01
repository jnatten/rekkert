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

/// Nobody there, and every queued payload kept.
private final class AwayTransport: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { _ in }
    let reachability = AsyncStream<Bool> { _ in }
    private let lock = NSLock()
    private var _queued: [Data] = []
    var queued: [Data] { lock.withLock { _queued } }

    var isReachable: Bool { false }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) { lock.withLock { _queued.append(payload) } }

    func queuedEvents(for session: UUID) -> Bool {
        queued.contains { payload in
            if case .events(session, _)? = try? Wire.decode(payload) { true } else { false }
        }
    }
}

@Suite("Sync resilience", .serialized)
@MainActor
struct ResilienceTests {
    /// Event ids start again at one in every match. The queue remembered the ids it had last
    /// handed over and not the match they belonged to, so the next match's first events read as
    /// already queued and never went.
    @Test func theNextMatchsFirstEventsStillGoOnTheDurableQueue() async throws {
        let transport = AwayTransport()
        let store = MatchStore(
            device: DeviceID(), transport: transport, snapshotInterval: 0, retryInterval: .milliseconds(30)
        )
        let task = Task { await store.run() }
        defer { task.cancel() }

        store.configure(setup)
        let first = store.log.sessionID
        await eventually { transport.queuedEvents(for: first) }
        store.startNewSession()
        store.configure(setup)
        let second = store.log.sessionID
        await eventually { transport.queuedEvents(for: second) }

        #expect(transport.queuedEvents(for: first))
        #expect(transport.queuedEvents(for: second), "the next match's opening event is queued too")
    }

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
        await eventually { transport.attempts > 1 && !transport.queued.isEmpty }

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
        await eventually {
            guard case .traditional(let session)? = watch.state else { return false }
            return session.score.points == BySide(a: 2, b: 0)
        }

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
        await eventually {
            guard case .traditional(let session)? = watch.state else { return false }
            return session.score.points == BySide(a: 3, b: 0)
        }

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
        await eventually { points(watch) == BySide(a: 1, b: 0) }
        #expect(points(watch) == BySide(a: 1, b: 0), "the watch was following along")

        phoneLink.setQuiet(true)
        watchLink.setQuiet(true)
        watch.finish()
        await eventually { watch.state == nil }
        #expect(watch.state == nil, "the watch ended and retired the session")
        #expect(phone.state != nil, "the phone never heard, and is still in the match")

        phoneLink.setQuiet(false)
        watchLink.setQuiet(false)
        phone.tap(team: .b)
        await eventually { phone.state == nil }

        #expect(phone.state == nil, "the phone is told the match ended rather than scoring alone")
        #expect(phone.lastResult != nil, "and is shown how it went instead of losing it")

        // The real test of recovery: the two can start again and find each other.
        phone.startNewSession()
        phone.configure(setup)
        phone.tap(team: .b)
        await eventually { points(watch) == BySide(a: 0, b: 1) }
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

        phone.configure(setup)
        phone.tap(team: .a)
        phone.tap(team: .a)
        await eventually {
            watch.log.sessionID == phone.log.sessionID && points(watch) == BySide(a: 2, b: 0)
        }

        #expect(watch.log.sessionID == phone.log.sessionID, "the watch came over to the phone's session")
        #expect(points(watch) == BySide(a: 2, b: 0))
    }
}

/// A link whose reachability the test flips, and whose answers take a moment.
private final class FlappingTransport: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { _ in }
    let reachability: AsyncStream<Bool>
    private let flips: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var _hellos = 0
    var hellos: Int { lock.withLock { _hellos } }

    init() {
        var continuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { continuation = $0 }
        flips = continuation
    }

    func flip() { flips.yield(true) }

    var isReachable: Bool { true }
    func activate() {}

    func sendLive(_ payload: Data) async -> Data? {
        if case .hello? = try? Wire.decode(payload) { lock.withLock { _hellos += 1 } }
        try? await Task.sleep(for: .milliseconds(100))
        return nil
    }

    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) {}
}

@Suite("A link that keeps coming back")
@MainActor
struct FlappingLinkTests {
    /// Every child of the fan-out says so when it changes, and the radio on every proof. A whole
    /// round of anti-entropy for each one waited on the slowest peer every time, and said the
    /// presets and the rest again every time.
    @Test func aBurstOfReconnectsIsOneRoundAndOneMore() async throws {
        let transport = FlappingTransport()
        let store = MatchStore(device: DeviceID(), transport: transport, snapshotInterval: 0, retryInterval: .seconds(60))
        let task = Task { await store.run() }
        defer { task.cancel() }
        await eventually { transport.hellos == 1 }

        for _ in 0 ..< 10 { transport.flip() }
        await eventually { transport.hellos >= 2 }
        await quietPeriod()
        await quietPeriod()

        #expect(transport.hellos <= 3, "one round for the first, one more for the rest")
    }
}
