import Foundation
import RekkertCore

/// An in-process peer. Used by the tests to cover convergence on macOS, where the real
/// WatchConnectivity transport cannot run, and by SwiftUI previews.
nonisolated public final class LoopbackTransport: PeerTransport, @unchecked Sendable {
    public let inbound: AsyncStream<InboundPacket>
    public let reachability: AsyncStream<Bool>

    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var peer: LoopbackTransport?
    private var connected: Bool
    /// Messages dropped on the way out, to exercise the outbox.
    private var dropOutgoing = false
    /// Live sends and snapshots that go nowhere while the link still counts as up — the
    /// counterpart's app suspended mid-request, which is a timeout rather than an unreachable
    /// peer. The durable queue still gets through, as it would.
    private var swallowing = false
    private var unanswered = 0
    /// The durable queue held back, as `transferUserInfo` is when the system is in no hurry.
    private var holdingQueue = false
    private var heldQueue: [Data] = []

    public init(reachable: Bool = true) {
        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation

        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        reachabilityUpdates = reachabilityContinuation

        connected = reachable
    }

    public static func pair() -> (LoopbackTransport, LoopbackTransport) {
        let one = LoopbackTransport()
        let two = LoopbackTransport()
        one.peer = two
        two.peer = one
        return (one, two)
    }

    public var isReachable: Bool {
        lock.withLock { connected && !dropOutgoing && peer != nil }
    }

    public func setReachable(_ value: Bool) {
        lock.withLock { connected = value }
        reachabilityUpdates.yield(value)
    }

    public func setDroppingOutgoing(_ value: Bool) {
        lock.withLock { dropOutgoing = value }
        reachabilityUpdates.yield(isReachable)
    }

    public func setSwallowing(_ value: Bool) {
        lock.withLock { swallowing = value }
    }

    public func activate() {}

    /// Counted under the same lock as `setReachable`, so once a link is cut this only goes down:
    /// no answer is left to cross the cut once it reads false.
    public var isAwaitingAnswers: Bool {
        lock.withLock { unanswered > 0 }
    }

    public func sendLive(_ payload: Data) async -> Data? {
        let peer = lock.withLock { () -> LoopbackTransport? in
            guard connected, !dropOutgoing, !swallowing, let peer else { return nil }
            unanswered += 1
            return peer
        }
        guard let peer else { return nil }
        return await withCheckedContinuation { continuation in
            let once = SingleResume(continuation) { [weak self] in
                guard let self else { return }
                lock.withLock { unanswered -= 1 }
            }
            peer.packets.yield(InboundPacket(payload: payload) { once.resume($0) })
        }
    }

    /// Stands in for a durable queue: delivered even when the peer is "unreachable",
    /// which is what transferUserInfo does on a real device.
    public func queue(_ payload: Data) {
        let peer = lock.withLock { () -> LoopbackTransport? in
            guard !holdingQueue else {
                heldQueue.append(payload)
                return nil
            }
            return self.peer
        }
        peer?.packets.yield(InboundPacket(payload: payload))
    }

    public func setHoldingQueue(_ value: Bool) {
        let released = lock.withLock { () -> [Data] in
            holdingQueue = value
            guard !value else { return [] }
            defer { heldQueue = [] }
            return heldQueue
        }
        for payload in released { queue(payload) }
    }

    public func publishSnapshot(_ payload: Data) {
        guard isReachable, let peer = lock.withLock({ self.peer }) else { return }
        guard !lock.withLock({ swallowing }) else { return }
        peer.packets.yield(InboundPacket(payload: payload))
    }

    public func disconnect() {
        lock.withLock { peer = nil }
        packets.finish()
        reachabilityUpdates.finish()
    }
}

nonisolated private final class SingleResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private let onResume: () -> Void

    init(_ continuation: CheckedContinuation<Data?, Never>, onResume: @escaping () -> Void = {}) {
        self.continuation = continuation
        self.onResume = onResume
    }

    func resume(_ value: Data?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        onResume()
        pending.resume(returning: value)
    }
}
