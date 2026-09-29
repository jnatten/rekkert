import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

private func seeded() -> MatchLog {
    var log = MatchLog()
    log.append(.configure(counting), from: DeviceID())
    return log
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .pointCount(let session) = store.state else { return nil }
    return session.score.points
}

/// Counts what went down it, and can stand in for a peer that never answers or a link that
/// keeps snapshots to itself the way Bluetooth does.
private final class Link: PeerTransport, @unchecked Sendable {
    let inner: LoopbackTransport
    private let answers: Bool
    private let delay: Duration
    private let carriesSnapshots: Bool
    private let lock = NSLock()
    private var eventSends = 0
    private var queues = 0

    init(_ inner: LoopbackTransport, answers: Bool = true, delay: Duration = .zero, carriesSnapshots: Bool = true) {
        self.inner = inner
        self.answers = answers
        self.delay = delay
        self.carriesSnapshots = carriesSnapshots
    }

    var eventsSent: Int { lock.withLock { eventSends } }
    var queued: Int { lock.withLock { queues } }

    var inbound: AsyncStream<InboundPacket> { inner.inbound }
    var reachability: AsyncStream<Bool> { inner.reachability }
    var isReachable: Bool { inner.isReachable }
    func activate() {}

    func sendLive(_ payload: Data) async -> Data? {
        if case .events? = try? Wire.decode(payload) { lock.withLock { eventSends += 1 } }
        guard answers else {
            try? await Task.sleep(for: delay)
            return nil
        }
        return await inner.sendLive(payload)
    }

    func publishSnapshot(_ payload: Data) {
        if carriesSnapshots { inner.publishSnapshot(payload) }
    }

    func queue(_ payload: Data) {
        lock.withLock { queues += 1 }
        inner.queue(payload)
    }
}

@Suite("A peer that is there but does not answer", .serialized)
@MainActor
struct QuietPeerTests {
    @Test func aGuestThatHasEverythingIsNotSentItAgainAndAgain() async throws {
        let (hostToGuest, guestToHost) = LoopbackTransport.pair()
        let (hostToQuiet, _) = LoopbackTransport.pair()
        let (hostToWatch, _) = LoopbackTransport.pair()
        hostToWatch.setReachable(false)

        let toGuest = Link(hostToGuest, carriesSnapshots: false)
        let toWatch = Link(hostToWatch)
        let fan = FanOutTransport()
        fan.attach(toWatch, as: .pairedDevice)
        fan.attach(toGuest, as: .sharedSession)
        fan.attach(Link(hostToQuiet, answers: false), as: .sharedSession)

        let host = MatchStore(
            device: DeviceID(), transport: fan,
            session: ActiveSession(log: seeded(), role: .host),
            snapshotInterval: 0, sendTimeout: .milliseconds(300), retryInterval: .milliseconds(100)
        )
        let guest = MatchStore(device: DeviceID(), transport: guestToHost, snapshotInterval: 0)
        let tasks = [host, guest].map { store in Task { await store.run() } }
        defer { tasks.forEach { $0.cancel() } }
        await eventually { guest.log.sessionID == host.log.sessionID }
        await quietPeriod()

        for _ in 0 ..< 5 { host.tap(team: .a) }
        await eventually { guest.log.vector == host.log.vector && toWatch.queued >= 5 }
        let sent = toGuest.eventsSent
        let queued = toWatch.queued
        try await Task.sleep(for: .seconds(2))

        #expect(toGuest.eventsSent - sent <= 5, "retried, but backing off rather than every tick")
        #expect(toWatch.queued - queued <= 5, "and the watch's queue is not filled with copies")
    }

    @Test func aPointReachesEveryoneElseWithoutWaitingOnAQuietPeer() async throws {
        let (hostToGuest, guestToHost) = LoopbackTransport.pair()
        let (hostToQuiet, _) = LoopbackTransport.pair()
        let fan = FanOutTransport()
        fan.attach(Link(hostToGuest, carriesSnapshots: false), as: .sharedSession)
        fan.attach(Link(hostToQuiet, answers: false, delay: .seconds(3)), as: .sharedSession)

        let host = MatchStore(
            device: DeviceID(), transport: fan,
            session: ActiveSession(log: seeded(), role: .host), snapshotInterval: 0
        )
        let guest = MatchStore(device: DeviceID(), transport: guestToHost, snapshotInterval: 0)
        let tasks = [host, guest].map { store in Task { await store.run() } }
        defer { tasks.forEach { $0.cancel() } }
        await eventually { guest.log.sessionID == host.log.sessionID }

        host.tap(team: .a)
        await eventually { points(guest)?.a == 1 }
        host.tap(team: .a)
        let start = ContinuousClock.now
        await eventually(within: 1.5) { points(guest)?.a == 2 }

        #expect(points(guest)?.a == 2)
        #expect(ContinuousClock.now - start < .milliseconds(1500), "not held behind the quiet peer's three seconds")
    }
}
