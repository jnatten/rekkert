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
        /// Whether the counterpart is this device's own watch or phone. Its packets are marked
        /// as such on the way in, because they repeat what this device already holds rather
        /// than offering anything, and a join must not conclude on one.
        public var isPairedDevice: Bool
        /// Personal things — saved setups, which side is blue — are dropped rather than sent
        /// to a phone that belongs to somebody else, where adopting them would overwrite
        /// what is already on it.
        public var carries: @Sendable (Wire) -> Bool

        public init(
            isDurable: Bool,
            isPairedDevice: Bool = false,
            carries: @escaping @Sendable (Wire) -> Bool = { _ in true }
        ) {
            self.isDurable = isDurable
            self.isPairedDevice = isPairedDevice
            self.carries = carries
        }

        /// This device's own watch: the whole conversation, and the only durable channel.
        public static let pairedDevice = Scope(isDurable: true, isPairedDevice: true)

        /// Somebody else's phone: the match, and nothing personal.
        public static let sharedSession = Scope(isDurable: false) { wire in
            switch wire {
            case .hello, .events, .snapshot, .retired: true
            // Saved setups and which side is blue belong to whoever's phone this is. The
            // whistle is between a phone and its own watch, and says nothing to anyone else.
            // Neither does what somebody's heart is doing: a workout is between a wrist and
            // the phone in the same pocket, and goes no further. Nor does stepping off: a
            // guest leaving is telling its own watch, not the host. Nor how hard somebody
            // likes their own wrist tapped.
            // And least of all the code to a match: a peer that was handed it could let
            // anybody else in. It goes to the phone in the same pocket as the wrist that
            // typed it, and stops there.
            case .presets, .display, .role, .workout, .left, .haptics, .sharing: false
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
                self.packets.yield(InboundPacket(
                    payload: packet.payload, reply: packet.reply, isFromPairedDevice: scope.isPairedDevice
                ))
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

        let answers = await withTaskGroup(of: (Data?, Bool).self) { group in
            for child in recipients {
                group.addTask {
                    let reply = await child.transport.sendLive(payload)
                    // A live send that did not land still has to reach a channel that
                    // survives the counterpart not running, or attaching a second child
                    // would quietly switch the watch's durable fallback off.
                    if reply == nil, child.scope.isDurable { child.transport.queue(payload) }
                    return (reply, child.scope.isPairedDevice)
                }
            }
            var collected: [(Data?, Bool)] = []
            for await answer in group { collected.append(answer) }
            return collected
        }

        // Answers that were not acknowledgements — a snapshot, a retirement notice — reach the
        // store as packets, marked with where they came from, since the store cannot tell.
        var acknowledgements: [Data?] = []
        for (reply, paired) in answers {
            if let reply, case .hello? = try? Wire.decode(reply) {
                acknowledgements.append(reply)
            } else if let reply {
                packets.yield(InboundPacket(payload: reply, isFromPairedDevice: paired))
            } else {
                acknowledgements.append(nil)
            }
        }

        // The whole room folded together, the watch included. Letting the watch answer for
        // everybody — it is the one with a durable queue behind it — meant a guest whose reply
        // timed out was acknowledged past, and the outbox forgot the event it never got.
        return ReplyFold.fold(acknowledgements, expected: present).acknowledgement
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
