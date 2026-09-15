import Foundation
import RekkertCore

/// One `PeerTransport` made of several, so `MatchStore` goes on talking to "the peer" while
/// the peer is in fact a watch and a handful of other people's phones.
///
/// It deliberately keeps no per-peer sync state and makes no delivery promise to the children
/// it broadcasts to. What makes that safe is that the log never forgets: a peer that missed a
/// push asks for what it is missing the next time it says hello, and is answered from the log
/// rather than from anybody's outbox.
nonisolated public final class FanOutTransport: PeerTransport, @unchecked Sendable {
    /// What a child is allowed to carry and what its answers mean.
    public struct Scope: Sendable {
        /// Whether `queue` reaches it. Only a channel that survives the counterpart not
        /// running is worth those bytes.
        public var isDurable: Bool
        /// Whether its reply is the one `sendLive` hands back, and so whether it is allowed
        /// to acknowledge the outbox.
        public var acknowledges: Bool
        /// Personal things — saved setups, which side is blue — are dropped rather than sent
        /// to a phone that belongs to somebody else, where adopting them would overwrite
        /// what is already on it.
        public var carries: @Sendable (Wire) -> Bool

        public init(
            isDurable: Bool,
            acknowledges: Bool,
            carries: @escaping @Sendable (Wire) -> Bool = { _ in true }
        ) {
            self.isDurable = isDurable
            self.acknowledges = acknowledges
            self.carries = carries
        }

        /// This device's own watch: the whole conversation, and the only durable channel.
        public static let pairedDevice = Scope(isDurable: true, acknowledges: true)

        /// Somebody else's phone: the match, and nothing personal.
        public static let sharedSession = Scope(isDurable: false, acknowledges: false) { wire in
            switch wire {
            case .hello, .events, .snapshot, .retired: true
            // Saved setups and which side is blue belong to whoever's phone this is. The
            // whistle is between a phone and its own watch, and says nothing to anyone else.
            case .presets, .display, .role: false
            }
        }
    }

    public let inbound: AsyncStream<InboundPacket>
    public let reachability: AsyncStream<Bool>

    private struct Child {
        let transport: any PeerTransport
        let scope: Scope
        let drain: Task<Void, Never>
        let watch: Task<Void, Never>
    }

    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var children: [ObjectIdentifier: Child] = [:]
    /// Handed to each child as it arrives, the way an application context greets a watch that
    /// has just woken: a peer joining mid-match sees the score without waiting for its own
    /// round trip to come back.
    private var lastSnapshot: Data?

    public init() {
        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation

        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        reachabilityUpdates = reachabilityContinuation
    }

    @discardableResult
    public func attach(_ transport: any PeerTransport, as scope: Scope) -> ObjectIdentifier {
        let token = ObjectIdentifier(transport as AnyObject)
        let drain = Task { [weak self] in
            for await packet in transport.inbound {
                guard let self else { return }
                self.packets.yield(packet)
            }
        }
        let watch = Task { [weak self] in
            for await _ in transport.reachability {
                self?.reachabilityChanged()
            }
        }
        lock.withLock {
            children[token] = Child(transport: transport, scope: scope, drain: drain, watch: watch)
        }
        transport.activate()
        if let snapshot = lock.withLock({ lastSnapshot }) { transport.publishSnapshot(snapshot) }
        reachabilityChanged()
        return token
    }

    public func detach(_ token: ObjectIdentifier) {
        let child = lock.withLock { children.removeValue(forKey: token) }
        child?.drain.cancel()
        child?.watch.cancel()
        reachabilityChanged()
    }

    /// How many counterparts are reachable. `isReachable` stays "is anyone there", because
    /// that is what decides whether a live send is worth attempting; this is what a UI counts.
    public var reachableCount: Int {
        lock.withLock { children.values.count { $0.transport.isReachable } }
    }

    public var isReachable: Bool {
        lock.withLock { children.values.contains { $0.transport.isReachable } }
    }

    public func activate() {
        for child in snapshotOfChildren() { child.transport.activate() }
    }

    public func sendLive(_ payload: Data) async -> Data? {
        guard let wire = try? Wire.decode(payload) else { return nil }
        let recipients = snapshotOfChildren().filter { $0.scope.carries(wire) }
        // Only a child that was there counts towards "everybody answered". One that is not
        // connected was never really sent to, and holding the acknowledgement for it would
        // stop a phone with no watch paired from ever draining its outbox.
        let present = recipients.filter(\.transport.isReachable).count
        guard present > 0 else { return nil }

        let answers = await withTaskGroup(of: (Bool, Data?).self) { group in
            for child in recipients {
                group.addTask {
                    let reply = await child.transport.sendLive(payload)
                    // A live send that did not land still has to reach a channel that
                    // survives the counterpart not running, or attaching a second child
                    // would quietly switch the watch's durable fallback off.
                    if reply == nil, child.scope.isDurable { child.transport.queue(payload) }
                    return (child.scope.acknowledges, reply)
                }
            }
            var collected: [(Bool, Data?)] = []
            for await answer in group { collected.append(answer) }
            return collected
        }

        // A paired device speaks for itself: its own reply is the acknowledgement, because it
        // is the one channel with a durable queue behind it. Otherwise fold the room together.
        let fromPaired = answers.first { $0.0 }?.1
        let folded = ReplyFold.fold(answers.map(\.1), expected: present)
        for payload in folded.unsolicited { packets.yield(InboundPacket(payload: payload)) }
        return fromPaired ?? folded.acknowledgement
    }

    public func publishSnapshot(_ payload: Data) {
        guard let wire = try? Wire.decode(payload) else { return }
        lock.withLock { lastSnapshot = payload }
        for child in snapshotOfChildren() where child.scope.carries(wire) {
            child.transport.publishSnapshot(payload)
        }
    }

    public func queue(_ payload: Data) {
        guard let wire = try? Wire.decode(payload) else { return }
        for child in snapshotOfChildren() where child.scope.isDurable && child.scope.carries(wire) {
            child.transport.queue(payload)
        }
    }

    /// Cleared when a session ends, so a phone attaching afterwards is not handed the
    /// farewell and does not file a result for a match it never played.
    public func forgetSnapshot() {
        lock.withLock { lastSnapshot = nil }
    }

    private func snapshotOfChildren() -> [Child] {
        lock.withLock { Array(children.values) }
    }

    /// Yields on *any* child's change rather than only when the aggregate flips.
    ///
    /// One peer coming back is a reason to run anti-entropy even while another was there the
    /// whole time — and the aggregate would not have moved, so nothing would have asked. What
    /// it prompts is `synchronise()`, which is cheap and idempotent by design.
    private func reachabilityChanged() {
        reachabilityUpdates.yield(isReachable)
    }
}
