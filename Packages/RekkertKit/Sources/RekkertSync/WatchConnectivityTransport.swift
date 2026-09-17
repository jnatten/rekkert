#if canImport(WatchConnectivity)
import Foundation
import RekkertCore
// Deliberately not `@preconcurrency`: combining that with an isolated WCSessionDelegate
// and reply handlers is a known "Incorrect actor executor assumption" crash.
import WatchConnectivity

private nonisolated enum Key {
    static let payload = "payload"
    static let revision = "revision"
}

/// The only nonisolated type in the app. Delegate callbacks arrive on WCSession's private
/// non-main serial queue, so `[String: Any]` is narrowed to `Data` right here, before
/// anything crosses an isolation boundary.
nonisolated private final class WCShim: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onPacket: @Sendable (InboundPacket) -> Void
    private let onReachability: @Sendable (Bool) -> Void

    init(
        onPacket: @escaping @Sendable (InboundPacket) -> Void,
        onReachability: @escaping @Sendable (Bool) -> Void
    ) {
        self.onPacket = onPacket
        self.onReachability = onReachability
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        onReachability(session.isReachable)
        if let data = session.receivedApplicationContext[Key.payload] as? Data {
            onPacket(InboundPacket(payload: data))
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        onReachability(session.isReachable)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[Key.payload] as? Data else { return }
        onPacket(InboundPacket(payload: data))
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let data = message[Key.payload] as? Data else { return replyHandler([:]) }
        let sendable = UncheckedReply(replyHandler)
        onPacket(InboundPacket(payload: data) { reply in sendable.send(reply) })
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Key.payload] as? Data else { return }
        onPacket(InboundPacket(payload: data))
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[Key.payload] as? Data else { return }
        onPacket(InboundPacket(payload: data))
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        onReachability(session.isReachable)
    }
    #endif
}

nonisolated private final class UncheckedReply: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
    func send(_ data: Data) { handler([Key.payload: data]) }
}

nonisolated public final class WatchConnectivityTransport: PeerTransport, @unchecked Sendable {
    public let inbound: AsyncStream<InboundPacket>
    public let reachability: AsyncStream<Bool>

    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation
    private let shim: WCShim
    private let revision = Revision()

    public init() {
        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation

        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        reachabilityUpdates = reachabilityContinuation

        let sendPacket = packetContinuation!
        let sendReachability = reachabilityContinuation!
        shim = WCShim(
            onPacket: { sendPacket.yield($0) },
            onReachability: { sendReachability.yield($0) }
        )
    }

    public static var isSupported: Bool { WCSession.isSupported() }

    public var isReachable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isReachable
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = shim
        if session.activationState != .activated {
            session.activate()
        }
    }

    public func sendLive(_ payload: Data) async -> Data? {
        guard isReachable else { return nil }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            WCSession.default.sendMessage([Key.payload: payload]) { reply in
                once.resume(reply[Key.payload] as? Data)
            } errorHandler: { _ in
                once.resume(nil)
            }
        }
    }

    /// Queued and guaranteed, and the only channel that reaches a watch whose app is not
    /// running — a phone cannot wake its counterpart the way a watch can. Unsupported on
    /// the Simulator, where it simply does nothing.
    public func queue(_ payload: Data) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([Key.payload: payload])
    }

    /// The application context is coalescing and is skipped entirely when the new
    /// dictionary equals the old one, so every publish carries a fresh revision.
    public func publishSnapshot(_ payload: Data) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext([
            Key.payload: payload,
            Key.revision: revision.next(),
        ])
    }
}

nonisolated private final class Revision: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
#endif
