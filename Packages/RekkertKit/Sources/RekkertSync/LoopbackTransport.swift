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

    public func sendLive(_ payload: Data) async -> Data? {
        guard isReachable, let peer = lock.withLock({ self.peer }) else { return nil }
        guard !lock.withLock({ swallowing }) else { return nil }
        return await withCheckedContinuation { continuation in
            let once = SingleResume(continuation)
            peer.packets.yield(InboundPacket(payload: payload) { once.resume($0) })
        }
    }

    /// Stands in for a durable queue: delivered even when the peer is "unreachable",
    /// which is what transferUserInfo does on a real device.
    public func queue(_ payload: Data) {
        guard let peer = lock.withLock({ self.peer }) else { return }
        peer.packets.yield(InboundPacket(payload: payload))
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

    init(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Data?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
