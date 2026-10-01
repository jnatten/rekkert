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

/// Delegate callbacks arrive on WCSession's private non-main serial queue, so `[String: Any]`
/// is narrowed to `Data` right here, before anything crosses an isolation boundary.
nonisolated private final class WCShim: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onPacket: @Sendable (InboundPacket) -> Void
    private let onReachability: @Sendable (Bool) -> Void
    private let onActivated: @Sendable () -> Void

    init(
        onPacket: @escaping @Sendable (InboundPacket) -> Void,
        onReachability: @escaping @Sendable (Bool) -> Void,
        onActivated: @escaping @Sendable () -> Void
    ) {
        self.onPacket = onPacket
        self.onReachability = onReachability
        self.onActivated = onActivated
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if activationState == .activated { onActivated() }
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

    /// Read before returning: the file is gone once this does.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        onPacket(InboundPacket(payload: data))
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
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

    /// Too big to go back as a reply, it is answered with nothing and follows as a file: the
    /// asker hears it as though it had been sent unasked.
    func send(_ data: Data) {
        guard WatchPayloadRoute.forMessage(data.count) == .inline else {
            handler([:])
            return WatchFiles.send(data)
        }
        handler([Key.payload: data])
    }
}

nonisolated private final class WatchFiles: @unchecked Sendable {
    static let shared = WatchFiles()

    private let lock = NSLock()
    private var lastSent: (payload: Data, at: Date)?
    private var waitingSnapshot: Data?

    /// A live send that went as a file is queued straight after by whoever sent it, as every live
    /// send that did not land is. It has already gone the durable way once.
    static func send(_ data: Data) {
        let repeated = shared.lock.withLock { () -> Bool in
            if let last = shared.lastSent, last.payload == data, Date().timeIntervalSince(last.at) < 10 { return true }
            shared.lastSent = (data, Date())
            return false
        }
        guard !repeated, WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let directory = FileManager.default.temporaryDirectory.appending(path: "rekkert-watch", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        WCSession.default.transferFile(url, metadata: nil)
    }

    /// A snapshot too big for the context goes as a file, but not every second of a match: the
    /// newest one, half a minute after the first that would not fit.
    static func sendSnapshot(_ data: Data) {
        let isFirst = shared.lock.withLock { () -> Bool in
            defer { shared.waitingSnapshot = data }
            return shared.waitingSnapshot == nil
        }
        guard isFirst else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            guard let newest = shared.lock.withLock({ () -> Data? in
                defer { shared.waitingSnapshot = nil }
                return shared.waitingSnapshot
            }) else { return }
            send(newest)
        }
    }
}

nonisolated public final class WatchConnectivityTransport: PeerTransport, @unchecked Sendable {
    public let inbound: AsyncStream<InboundPacket>
    public let reachability: AsyncStream<Bool>

    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation
    private let shim: WCShim
    private let revision = Revision()
    private let held: Held

    public init() {
        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation

        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        reachabilityUpdates = reachabilityContinuation

        let sendPacket = packetContinuation!
        let sendReachability = reachabilityContinuation!
        let held = Held()
        self.held = held
        shim = WCShim(
            onPacket: { sendPacket.yield($0) },
            onReachability: { sendReachability.yield($0) },
            onActivated: { for payload in held.release() { Self.transfer(payload) } }
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
        guard WatchPayloadRoute.forMessage(payload.count) == .inline else {
            WatchFiles.send(payload)
            return nil
        }
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
        guard WCSession.isSupported(), !held.keepIfInactive(payload) else { return }
        Self.transfer(payload)
    }

    private static func transfer(_ payload: Data) {
        guard WatchPayloadRoute.forMessage(payload.count) == .inline else { return WatchFiles.send(payload) }
        WCSession.default.transferUserInfo([Key.payload: payload])
    }

    /// The application context is coalescing and is skipped entirely when the new
    /// dictionary equals the old one, so every publish carries a fresh revision.
    public func publishSnapshot(_ payload: Data) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard WatchPayloadRoute.forContext(payload.count) == .inline else { return WatchFiles.sendSnapshot(payload) }
        try? WCSession.default.updateApplicationContext([
            Key.payload: payload,
            Key.revision: revision.next(),
        ])
    }
}

/// What was handed to the queue before the session was up to take it. Dropped, it never went at
/// all: each event goes on the queue once, so nothing offers it again.
nonisolated private final class Held: @unchecked Sendable {
    private static let limit = 500
    private let lock = NSLock()
    private var payloads: [Data] = []

    /// Kept for later, unless the session can take it now. Asked under the lock `release` takes,
    /// so nothing kept in the moment the session comes up is left behind.
    func keepIfInactive(_ payload: Data) -> Bool {
        lock.withLock {
            guard WCSession.default.activationState != .activated else { return false }
            payloads.append(payload)
            if payloads.count > Self.limit { payloads.removeFirst(payloads.count - Self.limit) }
            return true
        }
    }

    func release() -> [Data] {
        lock.withLock {
            defer { payloads = [] }
            return payloads
        }
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
