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

@Suite("Sync resilience")
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
