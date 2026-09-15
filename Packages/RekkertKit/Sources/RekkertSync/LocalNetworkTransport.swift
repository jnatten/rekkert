import Foundation
import RekkertCore

#if os(iOS)
import CryptoKit
import Network
import Security

/// The other phones at the court.
///
/// A host advertises a Bonjour service and listens; everyone else browses for it and dials in.
/// The session code is the key: it is derived into a TLS pre-shared key, so a wrong code is
/// refused during the handshake rather than after, and nothing about the match ever travels to
/// somebody who was not told it. See `scripts/psk-spike.swift` for why the TLS version is not
/// pinned to 1.3 — external pre-shared keys are not available there.
///
/// Deliberately a star: guests hold one link, to the host, and the host holds all of them.
nonisolated public final class LocalNetworkTransport: PeerTransport, @unchecked Sendable {
    /// Thirteen characters, inside Bonjour's limit of fifteen.
    public static let serviceType = "_rekkert-score._tcp"

    public enum Failure: Sendable, Equatable {
        /// Nothing was advertising that code within the time we were willing to wait. From
        /// inside the app a mistyped code and an absent host are the same observation.
        case notFound
        /// Something was there and would not have us, which means the code was wrong.
        case rejected
        /// The local network is not ours to look at.
        case blocked
    }

    public enum Status: Sendable, Equatable {
        case idle
        case hosting(peers: Int)
        case searching
        case joined(peers: Int)
        case failed(Failure)
    }

    public let inbound: AsyncStream<InboundPacket>
    public let reachability: AsyncStream<Bool>
    public let status: AsyncStream<Status>

    /// Unchecked because every mutable field on it is only ever touched under `lock`, and the
    /// connection's own callbacks arrive on one serial queue.
    private final class Link: @unchecked Sendable {
        let connection: NWConnection
        var buffer = Data()
        var isReady = false
        init(_ connection: NWConnection) { self.connection = connection }
    }

    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation
    private let statusUpdates: AsyncStream<Status>.Continuation

    private let queue = DispatchQueue(label: "dev.natten.rekkert.localnetwork")
    private let lock = NSLock()

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var links: [ObjectIdentifier: Link] = [:]
    private var waiting: [UInt32: ResumeOnce] = [:]
    private var nextCorrelation: UInt32 = 1
    private var isHosting = false
    private var lastSnapshot: Data?
    private var searchDeadline: DispatchWorkItem?

    private let replyTimeout: DispatchTimeInterval
    private let searchTimeout: DispatchTimeInterval

    public init(replyTimeout: Int = 4, searchTimeout: Int = 10) {
        self.replyTimeout = .seconds(replyTimeout)
        self.searchTimeout = .seconds(searchTimeout)

        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation

        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        reachabilityUpdates = reachabilityContinuation

        var statusContinuation: AsyncStream<Status>.Continuation!
        status = AsyncStream { statusContinuation = $0 }
        statusUpdates = statusContinuation
    }

    // MARK: - Opening and closing

    /// Advertises the match. The instance name is the share id rather than the device name:
    /// everyone on a club's Wi-Fi can read a service name, and it is no business of theirs
    /// whose phone is on court three.
    public func startHosting(code: SessionCode, share: UUID) {
        stop()
        lock.withLock { isHosting = true }

        var txt = NWTXTRecord()
        txt["v"] = "1"
        txt["id"] = share.uuidString.lowercased()
        txt["fp"] = SessionKey.fingerprint(for: code, share: share)

        guard let listener = try? NWListener(
            using: parameters(key: SessionKey.presharedKey(for: code, share: share))
        ) else {
            return publish(.failed(.blocked))
        }
        listener.service = NWListener.Service(
            name: String(share.uuidString.prefix(8)).lowercased(),
            type: Self.serviceType,
            txtRecord: txt
        )
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            self?.publish(.failed(.blocked))
        }
        lock.withLock { self.listener = listener }
        listener.start(queue: queue)
        publish(.hosting(peers: 0))
    }

    /// Looks for the match that code belongs to. Every advertisement whose fingerprint matches
    /// is dialled, not just the first: two bytes will agree by accident now and again, and a
    /// refused handshake costs nothing.
    public func startJoining(code: SessionCode) {
        stop()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
            using: parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.consider(results, code: code)
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            self?.publish(.failed(.blocked))
        }
        lock.withLock { self.browser = browser }
        browser.start(queue: queue)
        publish(.searching)

        // Nothing reports a declined local-network permission, and nothing reports an absent
        // host either, so the honest answer to both is the same one after a decent wait.
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !self.isReachable else { return }
            self.publish(.failed(.notFound))
        }
        lock.withLock { searchDeadline = deadline }
        queue.asyncAfter(deadline: .now() + searchTimeout, execute: deadline)
    }

    public func stop() {
        let (oldListener, oldBrowser, oldLinks, pending, deadline) = lock.withLock {
            let values = (listener, browser, Array(links.values), Array(waiting.values), searchDeadline)
            listener = nil
            browser = nil
            links = [:]
            waiting = [:]
            searchDeadline = nil
            isHosting = false
            lastSnapshot = nil
            return values
        }
        deadline?.cancel()
        oldListener?.cancel()
        oldBrowser?.cancel()
        for link in oldLinks { link.connection.cancel() }
        for resume in pending { resume.resume(nil) }
        publish(.idle)
        reachabilityUpdates.yield(false)
    }

    // MARK: - PeerTransport

    public func activate() {}

    public var isReachable: Bool {
        lock.withLock { links.values.contains { $0.isReady } }
    }

    public var reachableCount: Int {
        lock.withLock { links.values.count { $0.isReady } }
    }

    public func sendLive(_ payload: Data) async -> Data? {
        let ready = lock.withLock { links.values.filter(\.isReady) }
        guard !ready.isEmpty else { return nil }

        let replies = await withTaskGroup(of: Data?.self) { group in
            for link in ready {
                group.addTask { await self.ask(payload, on: link) }
            }
            var collected: [Data?] = []
            for await reply in group { collected.append(reply) }
            return collected
        }

        let folded = ReplyFold.fold(replies, expected: ready.count)
        for extra in folded.unsolicited { packets.yield(InboundPacket(payload: extra)) }
        return folded.acknowledgement
    }

    /// WatchConnectivity's durable queue has no counterpart here: a peer that is not connected
    /// simply is not there. What stands in for it is the store's own persisted outbox and the
    /// hello every connection opens with — a peer that comes back asks for what it missed,
    /// which is a better guarantee than a queue this class would have to keep itself.
    public func queue(_ payload: Data) {
        broadcast(payload)
    }

    /// Kept, and handed to each connection as it becomes ready, so a phone joining mid-match
    /// sees the score without waiting for a round trip of its own.
    public func publishSnapshot(_ payload: Data) {
        lock.withLock { lastSnapshot = payload }
        broadcast(payload)
    }

    // MARK: - Connections

    private func parameters(key: SymmetricKey) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        // Not 1.3: external pre-shared keys are not available there and the handshake fails
        // outright, which scripts/psk-spike.swift demonstrates.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        // DHE first, which is a pre-shared-key suite that also gives forward secrecy.
        for suite in [0x00AA, 0x00AB] {
            if let value = tls_ciphersuite_t(rawValue: UInt16(suite)) {
                sec_protocol_options_append_tls_ciphersuite(options, value)
            }
        }
        sec_protocol_options_add_pre_shared_key(
            options,
            key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
            SessionKey.pskIdentity.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
        )

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        // A phone that went into a pocket has to be noticed in seconds rather than minutes.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3

        let parameters = NWParameters(tls: tls, tcp: tcp)
        // Works with no network at all: straight from one radio to the other.
        parameters.includePeerToPeer = true
        return parameters
    }

    private func consider(_ results: Set<NWBrowser.Result>, code: SessionCode) {
        for result in results {
            guard case .bonjour(let txt) = result.metadata,
                  txt["v"] == "1",
                  let raw = txt["id"], let share = UUID(uuidString: raw),
                  txt["fp"] == SessionKey.fingerprint(for: code, share: share)
            else { continue }

            let connection = NWConnection(
                to: result.endpoint,
                using: parameters(key: SessionKey.presharedKey(for: code, share: share))
            )
            adopt(connection)
        }
    }

    private func accept(_ connection: NWConnection) {
        adopt(connection)
    }

    private func adopt(_ connection: NWConnection) {
        let link = Link(connection)
        let token = ObjectIdentifier(connection)
        lock.withLock { links[token] = link }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.withLock { link.isReady = true }
                self.receive(on: link)
                if let snapshot = self.lock.withLock({ self.lastSnapshot }) {
                    self.send(Frame(kind: .oneway, payload: snapshot), on: link)
                }
                self.reachabilityUpdates.yield(true)
                self.announce()
            case .failed, .cancelled:
                self.close(token, rejected: true)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func close(_ token: ObjectIdentifier, rejected: Bool) {
        let link = lock.withLock { links.removeValue(forKey: token) }
        guard let link else { return }
        link.connection.cancel()

        let everGotThere = link.isReady
        reachabilityUpdates.yield(isReachable)
        if !everGotThere, rejected, lock.withLock({ !isHosting && links.isEmpty }) {
            // It was there and it would not have us, which is what a wrong code looks like.
            publish(.failed(.rejected))
        } else {
            announce()
        }
    }

    private func receive(on link: Link) {
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                var frames: [Frame] = []
                var broken = false
                self.lock.withLock {
                    link.buffer.append(data)
                    do { frames = try FrameCodec.decode(from: &link.buffer) } catch { broken = true }
                }
                if broken { return self.close(ObjectIdentifier(link.connection), rejected: false) }
                for frame in frames { self.deliver(frame, on: link) }
            }
            if isComplete || error != nil {
                return self.close(ObjectIdentifier(link.connection), rejected: false)
            }
            self.receive(on: link)
        }
    }

    private func deliver(_ frame: Frame, on link: Link) {
        switch frame.kind {
        case .reply:
            let pending = lock.withLock { waiting.removeValue(forKey: frame.correlation) }
            pending?.resume(frame.payload)
        case .request:
            let correlation = frame.correlation
            packets.yield(InboundPacket(payload: frame.payload) { [weak self, weak link] answer in
                guard let self, let link else { return }
                self.send(Frame(kind: .reply, correlation: correlation, payload: answer), on: link)
            })
        case .oneway:
            packets.yield(InboundPacket(payload: frame.payload))
        }
    }

    private func ask(_ payload: Data, on link: Link) async -> Data? {
        let correlation = lock.withLock { () -> UInt32 in
            let value = nextCorrelation
            nextCorrelation &+= 1
            return value
        }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            lock.withLock { waiting[correlation] = once }
            send(Frame(kind: .request, correlation: correlation, payload: payload), on: link)
            // Resolved here rather than left to the store's own timeout, so a silent peer
            // never holds up the answer the others already gave.
            queue.asyncAfter(deadline: .now() + replyTimeout) { [weak self] in
                self?.lock.withLock { self?.waiting.removeValue(forKey: correlation) }
                once.resume(nil)
            }
        }
    }

    private func send(_ frame: Frame, on link: Link) {
        link.connection.send(
            content: FrameCodec.encode(frame),
            completion: .contentProcessed { _ in }
        )
    }

    private func broadcast(_ payload: Data) {
        let ready = lock.withLock { links.values.filter(\.isReady) }
        for link in ready { send(Frame(kind: .oneway, payload: payload), on: link) }
    }

    private func announce() {
        let peers = reachableCount
        publish(lock.withLock { isHosting } ? .hosting(peers: peers) : (peers > 0 ? .joined(peers: peers) : .searching))
    }

    private func publish(_ value: Status) {
        if case .failed = value { searchDeadline?.cancel() }
        statusUpdates.yield(value)
    }
}

nonisolated private final class ResumeOnce: @unchecked Sendable {
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

#else

/// Not built on watchOS — a watch reaches a shared match through its own iPhone, which is
/// already the only thing it talks to — nor on macOS, which is a platform here only so the
/// tests run without a simulator. The type still exists so nothing above it needs an `#if`.
nonisolated public final class LocalNetworkTransport: PeerTransport, @unchecked Sendable {
    public enum Failure: Sendable, Equatable { case notFound, rejected, blocked }
    public enum Status: Sendable, Equatable {
        case idle, hosting(peers: Int), searching, joined(peers: Int), failed(Failure)
    }

    public let inbound = AsyncStream<InboundPacket> { $0.finish() }
    public let reachability = AsyncStream<Bool> { $0.finish() }
    public let status = AsyncStream<Status> { $0.finish() }

    public init(replyTimeout: Int = 4, searchTimeout: Int = 10) {}

    public var isReachable: Bool { false }
    public var reachableCount: Int { 0 }
    public func activate() {}
    public func sendLive(_ payload: Data) async -> Data? { nil }
    public func publishSnapshot(_ payload: Data) {}
    public func queue(_ payload: Data) {}
    public func startHosting(code: SessionCode, share: UUID) {}
    public func startJoining(code: SessionCode) {}
    public func stop() {}
}

#endif
