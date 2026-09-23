import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

private func seeded(_ device: DeviceID, points: Int = 0) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(counting), from: device)
    for _ in 0 ..< points { log.append(.point(round: 0, court: 0, team: .a), from: device) }
    return log
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .pointCount(let session) = store.state else { return nil }
    return session.score.points
}

/// Records everything the store publishes on the snapshot channel and lets the test deliver
/// packets to it, as a peer would.
nonisolated private final class SnapshotRecorder: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability = AsyncStream<Bool> { _ in }
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let lock = NSLock()
    private var _snapshots: [MatchLog] = []

    init() {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
    }

    var snapshots: [MatchLog] { lock.withLock { _snapshots } }

    var isReachable: Bool { true }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func queue(_ payload: Data) {}

    func publishSnapshot(_ payload: Data) {
        guard case .snapshot(let log)? = try? Wire.decode(payload) else { return }
        lock.withLock { _snapshots.append(log) }
    }

    func deliver(_ wire: Wire) throws {
        packets.yield(InboundPacket(payload: try wire.encoded()))
    }
}

/// A phone's link to a watch whose app is not in front: nothing is reachable live, the
/// durable queue has not got round to delivering yet, and the application context is the one
/// thing the watch will read the moment it wakes.
nonisolated private final class ContextOnlyLink: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability = AsyncStream<Bool> { _ in }
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let lock = NSLock()
    private var peer: ContextOnlyLink?

    init() {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
    }

    static func pair() -> (ContextOnlyLink, ContextOnlyLink) {
        let one = ContextOnlyLink(), two = ContextOnlyLink()
        one.peer = two
        two.peer = one
        return (one, two)
    }

    var isReachable: Bool { false }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func queue(_ payload: Data) {}

    func publishSnapshot(_ payload: Data) {
        lock.withLock { peer }?.packets.yield(InboundPacket(payload: payload))
    }
}

/// Reachable, and never answers: a send parked on a continuation nothing will ever resume,
/// which is what WatchConnectivity looks like when it does not call back. `Task.sleep` would
/// not do — it sees a cancellation, and the point is a send that cannot.
nonisolated private final class HangingTransport: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { _ in }
    let reachability = AsyncStream<Bool> { _ in }
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Data?, Never>] = []
    private var _queued: [Data] = []

    var queued: [Data] { lock.withLock { _queued } }

    var isReachable: Bool { true }
    func activate() {}
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) { lock.withLock { _queued.append(payload) } }

    func sendLive(_ payload: Data) async -> Data? {
        await withCheckedContinuation { continuation in
            lock.withLock { parked.append(continuation) }
        }
    }

    /// Lets the parked sends go, so nothing is left hanging when the test is over.
    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Data?, Never>] in
            defer { parked.removeAll() }
            return parked
        }
        for continuation in waiting { continuation.resume(returning: nil) }
    }
}

@Suite("A guest's point on the host's own watch")
@MainActor
struct RelayedPointTests {
    /// A point tapped on the host's phone went out on the snapshot channel; one that arrived
    /// from a guest and was passed on did not, though the watch reads the two the same way.
    @Test func aPointPassedOnFromAGuestIsPublishedAsASnapshot() async throws {
        let hostDevice = DeviceID(), guestDevice = DeviceID()
        let transport = SnapshotRecorder()
        let host = MatchStore(
            device: hostDevice, transport: transport,
            session: ActiveSession(log: seeded(hostDevice), role: .host),
            snapshotInterval: 0, sendTimeout: .milliseconds(50), retryInterval: .seconds(60)
        )
        let task = Task { await host.run() }
        defer { task.cancel() }
        await eventually { !transport.snapshots.isEmpty }
        let before = transport.snapshots.count

        var guestsCopy = host.log
        let scored = guestsCopy.append(.point(round: 0, court: 0, team: .b), from: guestDevice)
        try transport.deliver(.events(sessionID: host.log.sessionID, events: [scored]))

        await eventually { transport.snapshots.count > before }
        #expect(points(host) == BySide(a: 0, b: 1), "the host took the point")
        #expect(
            transport.snapshots.last?.events[scored.id] != nil,
            "and put it on the snapshot channel, as it would one of its own"
        )
    }

    /// The whole road, with the watch unreachable and the durable queue yet to deliver: the
    /// application context has to carry the guest's point, or the wrist shows the score as it
    /// stood before the host last touched the phone.
    @Test func aGuestsPointReachesAWatchThatCanOnlyReadTheContext() async throws {
        let (phoneToWatch, watchToPhone) = ContextOnlyLink.pair()
        let (hostToGuest, guestToHost) = LoopbackTransport.pair()

        let hostFan = FanOutTransport()
        hostFan.attach(phoneToWatch, as: .pairedDevice)
        hostFan.attach(hostToGuest, as: .sharedSession)
        let host = MatchStore(
            device: DeviceID(), transport: hostFan,
            session: ActiveSession(log: seeded(DeviceID()), role: .host), snapshotInterval: 0
        )
        let watch = MatchStore(device: DeviceID(), transport: watchToPhone, snapshotInterval: 0, keepsHistory: false)
        let guestFan = FanOutTransport()
        guestFan.attach(guestToHost, as: .sharedSession)
        let guest = MatchStore(device: DeviceID(), transport: guestFan, snapshotInterval: 0)
        let tasks = [Task { await host.run() }, Task { await watch.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }

        await eventually { watch.log.sessionID == host.log.sessionID && points(guest) != nil }
        #expect(points(watch) == BySide(a: 0, b: 0), "the watch was handed the match by the context")

        guest.tap(team: .b)
        await eventually { points(watch) == BySide(a: 0, b: 1) }
        #expect(points(host) == BySide(a: 0, b: 1), "the host has it")
        #expect(points(watch) == BySide(a: 0, b: 1), "and so does the watch, with nothing else reaching it")
    }
}

@Suite("Sends that are never answered", .serialized)
@MainActor
struct HangingSendTests {
    /// The timeout has to be a timeout. A task group waits for a child that cannot see it
    /// was cancelled, so a send WatchConnectivity never called back on held the outbox for
    /// as long as the framework felt like it.
    @Test func aSendThatIsNeverAnsweredIsGivenUpOnAndQueued() async throws {
        let transport = HangingTransport()
        defer { transport.release() }
        let store = MatchStore(
            device: DeviceID(), transport: transport,
            snapshotInterval: 0, sendTimeout: .milliseconds(80), retryInterval: .seconds(60)
        )
        let task = Task { await store.run() }
        defer { task.cancel() }

        store.configure(counting)
        store.tap(team: .a)

        await eventually(within: 2) { !transport.queued.isEmpty }
        #expect(!transport.queued.isEmpty, "the durable queue got it once the live send was given up on")
    }

    /// Anti-entropy is awaited by the reachability loop, so a hello that hangs stops every
    /// later reconnect from being noticed — including the one that would have caught the
    /// watch up.
    @Test func aHelloThatIsNeverAnsweredDoesNotStallSynchronising() async throws {
        let transport = HangingTransport()
        defer { transport.release() }
        let store = MatchStore(
            device: DeviceID(), transport: transport,
            session: ActiveSession(log: seeded(DeviceID(), points: 1)),
            snapshotInterval: 0, sendTimeout: .milliseconds(80), retryInterval: .seconds(60)
        )

        var finished = false
        let synchronising = Task {
            await store.synchronise()
            finished = true
        }
        defer { synchronising.cancel() }

        await eventually(within: 2) { finished }
        #expect(finished, "it gave up on the hello rather than waiting for ever")
    }
}

@Suite("The snapshot throttle across a match ending", .serialized)
@MainActor
struct SnapshotThrottleTests {
    /// A publish held back by the throttle woke to find the match over and did nothing —
    /// correctly — but left itself marked as pending, so every throttled publish afterwards
    /// was dropped until something forced one. The next match's first points never reached
    /// the context.
    @Test func aThrottledPublishThatFindsTheMatchOverDoesNotBlockTheNextOne() async throws {
        let transport = SnapshotRecorder()
        let store = MatchStore(
            device: DeviceID(), transport: transport,
            snapshotInterval: 0.4, sendTimeout: .milliseconds(50), retryInterval: .seconds(60)
        )
        let task = Task { await store.run() }
        defer { task.cancel() }
        // Starting up forces a publish of its own, which would clear the flag this is about.
        try await Task.sleep(for: .milliseconds(100))

        let quick = SessionSetup.pointCount(
            rules: PointCountRules(target: 2), teams: BySide(a: .home, b: .away)
        )
        store.configure(quick)
        store.tap(team: .a)
        // Inside the throttle window, so the publish for that point is held back. The match
        // then ends before it fires.
        try await Task.sleep(for: .milliseconds(250))
        store.tap(team: .a)
        #expect(store.state == nil, "two points was the match")
        // Past the held-back publish waking, and still inside the window from the ending.
        try await Task.sleep(for: .milliseconds(250))

        store.startNewSession()
        store.configure(counting)
        let next = store.log.sessionID
        store.tap(team: .b)

        await eventually(within: 3) { transport.snapshots.last?.sessionID == next }
        #expect(transport.snapshots.last?.sessionID == next, "the new match reached the snapshot channel")
    }
}
