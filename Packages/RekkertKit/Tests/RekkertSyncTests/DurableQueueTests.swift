import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(setsToWin: 3),
    teams: BySide(a: .home, b: .away)
)

/// Nobody there, and every queued payload kept.
nonisolated private final class Away: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { _ in }
    let reachability = AsyncStream<Bool> { _ in }
    private let lock = NSLock()
    private var payloads: [Data] = []
    var queued: [Data] { lock.withLock { payloads } }

    var isReachable: Bool { false }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) { lock.withLock { payloads.append(payload) } }
}

/// A watch that is there and answers, with every queued payload counted on the way past.
nonisolated private final class CountedWatch: PeerTransport, @unchecked Sendable {
    let end: LoopbackTransport
    private let lock = NSLock()
    private var payloads: [Data] = []
    var queued: [Data] { lock.withLock { payloads } }

    init(_ end: LoopbackTransport) { self.end = end }
    var inbound: AsyncStream<InboundPacket> { end.inbound }
    var reachability: AsyncStream<Bool> { end.reachability }
    var isReachable: Bool { end.isReachable }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { await end.sendLive(payload) }
    func publishSnapshot(_ payload: Data) { end.publishSnapshot(payload) }
    func queue(_ payload: Data) {
        lock.withLock { payloads.append(payload) }
        end.queue(payload)
    }
}

/// Somebody else's phone that is on the match and never answers in time.
nonisolated private final class SlowGuest: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { _ in }
    let reachability = AsyncStream<Bool> { _ in }
    var isReachable: Bool { true }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? {
        try? await Task.sleep(for: .milliseconds(15))
        return nil
    }
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) {}
}

nonisolated private func queuedEventCount(_ payloads: [Data]) -> Int {
    payloads.reduce(0) { total, payload in
        guard case .events(_, let events)? = try? Wire.decode(payload) else { return total }
        return total + events.count
    }
}

@Suite("The durable queue", .serialized)
@MainActor
struct DurableQueueTests {
    /// The whole unacknowledged outbox went on the queue again every time it grew, so a match
    /// scored with the watch away handed it every point once for every point after it.
    @Test func aPointScoredWithTheWatchAwayIsQueuedOnce() async {
        let transport = Away()
        let store = MatchStore(
            device: DeviceID(), transport: transport, snapshotInterval: 0, retryInterval: .milliseconds(20)
        )
        let task = Task { await store.run() }
        defer { task.cancel() }

        store.configure(setup)
        for index in 0 ..< 40 {
            store.tap(team: index.isMultiple(of: 2) ? .a : .b)
            try? await Task.sleep(for: .milliseconds(30))
        }
        await eventually { queuedEventCount(transport.queued) == store.log.events.count }

        #expect(queuedEventCount(transport.queued) == store.log.events.count)
    }

    /// One guest that does not answer holds back everybody's acknowledgement, and every failed
    /// send used to queue the whole outbox for the host's own watch — which was answering.
    @Test func aSlowGuestDoesNotFillTheWatchsQueue() async {
        let (phoneEnd, watchEnd) = LoopbackTransport.pair()
        let toWatch = CountedWatch(phoneEnd)
        let links = FanOutTransport(childTimeout: .milliseconds(40))
        links.attach(toWatch, as: .pairedDevice)
        links.attach(SlowGuest(), as: .sharedSession)

        let host = MatchStore(
            device: DeviceID(), transport: links, snapshotInterval: 0,
            sendTimeout: .milliseconds(80), retryInterval: .milliseconds(20)
        )
        let watch = MatchStore(device: DeviceID(), transport: watchEnd, snapshotInterval: 0, keepsHistory: false)
        let hostTask = Task { await host.run() }
        let watchTask = Task { await watch.run() }
        defer { hostTask.cancel(); watchTask.cancel() }

        host.configure(setup)
        host.startSharing()
        for index in 0 ..< 30 {
            host.tap(team: index.isMultiple(of: 2) ? .a : .b)
            try? await Task.sleep(for: .milliseconds(40))
        }
        await eventually { inStep(host, watch) }

        #expect(inStep(host, watch))
        #expect(queuedEventCount(toWatch.queued) <= host.log.events.count)
    }
}
