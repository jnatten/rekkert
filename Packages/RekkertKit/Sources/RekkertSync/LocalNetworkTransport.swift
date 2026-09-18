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
        /// Which advertised match this dialled, so it is not dialled twice. `nil` when accepted.
        let share: UUID?
        var buffer = Data()
        var isReady = false
        init(_ connection: NWConnection, share: UUID? = nil) {
            self.connection = connection
            self.share = share
        }
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
    /// What this has been asked to be, as against what it currently is. The system takes the
    /// listener and the browser away with the app, so something has to remember what to put
    /// back — and the code has to be kept anyway, because the browser only speaks up when the
    /// advertisements *change*, and a host that never went away is not a change.
    private enum Intent: Sendable {
        case none
        case hosting(code: SessionCode, share: UUID)
        case joining(SessionCode)
    }
    private var intent: Intent = .none
    /// Whether any link has reached ready since the code was typed in. Until one has, a
    /// connection that fails is the only evidence there is that the code was wrong;
    /// afterwards it is only evidence that a phone went into a pocket.
    private var hasEverJoined = false
    private var lastSnapshot: Data?
    private var searchDeadline: DispatchWorkItem?
    private var redialTimer: DispatchSourceTimer?
    /// Per link, so a dial that never arrives can be given up on. Keyed the same way `links` is.
    private var dialDeadlines: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var listenerAttempts = 0

    /// Only ever read with `lock` already held.
    private var isHosting: Bool {
        if case .hosting = intent { return true }
        return false
    }

    private let replyTimeout: DispatchTimeInterval
    private let searchTimeout: DispatchTimeInterval
    private let dialTimeout: DispatchTimeInterval
    private let redialInterval: DispatchTimeInterval

    /// How many times a listener the system took away is put back before the honest answer is
    /// that something else is wrong.
    private static let rebuildAttempts = 5

    public init(
        replyTimeout: Int = 4,
        searchTimeout: Int = 10,
        dialTimeout: Int = 6,
        redialInterval: Int = 2
    ) {
        self.replyTimeout = .seconds(replyTimeout)
        self.searchTimeout = .seconds(searchTimeout)
        self.dialTimeout = .seconds(dialTimeout)
        self.redialInterval = .seconds(redialInterval)

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
        lock.withLock { intent = .hosting(code: code, share: share) }
        standUpListener(code: code, share: share)
    }

    /// Puts hosting back after the app has been in a pocket, without disturbing anyone already
    /// on it.
    ///
    /// Deliberately not `startHosting`, which begins by stopping: that cancels every link, so a
    /// host who glanced at a notification and came back would drop every guest on the way past.
    /// The listener is only replaced when it is actually gone — a working one is left alone
    /// rather than torn down and re-advertised.
    public func resumeHosting(code: SessionCode, share: UUID) {
        sweepDeadLinks()
        let needed = lock.withLock { () -> Bool in
            intent = .hosting(code: code, share: share)
            return listener == nil || listener?.state != .ready
        }
        guard needed else { return announce() }

        let old = lock.withLock { () -> NWListener? in
            let previous = listener
            listener = nil
            return previous
        }
        old?.cancel()
        standUpListener(code: code, share: share)
    }

    /// A listener that fails after the app has been away is the system having taken it, not a
    /// permission somebody refused — so put it back rather than telling a host mid-match that
    /// they cannot see their own network. Only so many times: a failure that keeps coming back
    /// is a real one, and saying nothing at all about it would be worse than saying the wrong
    /// thing once.
    private func standUpListenerAgain() {
        let (intent, attempts) = lock.withLock { () -> (Intent, Int) in
            listenerAttempts += 1
            return (self.intent, listenerAttempts)
        }
        guard case .hosting(let code, let share) = intent else { return }
        guard attempts <= Self.rebuildAttempts else { return publish(.failed(.blocked)) }

        queue.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            guard let self, case .hosting = self.lock.withLock({ self.intent }) else { return }
            self.standUpListener(code: code, share: share)
        }
    }

    private func standUpListener(code: SessionCode, share: UUID) {
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
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.withLock { self.listenerAttempts = 0 }
            case .failed:
                self.lock.withLock { self.listener = nil }
                self.standUpListenerAgain()
            case .cancelled:
                // iOS takes the listener away when the app goes into the background. Letting
                // go of it here is what lets `resume()` know there is something to rebuild.
                self.lock.withLock { self.listener = nil }
            default:
                break
            }
        }
        lock.withLock { self.listener = listener }
        listener.start(queue: queue)
        publish(.hosting(peers: reachableCount))
    }

    /// Looks for the match that code belongs to. Every advertisement whose fingerprint matches
    /// is dialled, not just the first: two bytes will agree by accident now and again, and a
    /// refused handshake costs nothing.
    public func startJoining(code: SessionCode) {
        stop()
        lock.withLock { intent = .joining(code) }
        standUpBrowser(code: code)
        startRedialling()

        // Nothing reports a declined local-network permission, and nothing reports an absent
        // host either, so the honest answer to both is the same one after a decent wait. Armed
        // here and nowhere else: this is the search that follows somebody typing a code, and it
        // is the only one entitled to give up. A search that follows a link going away has a
        // score on the screen and has to go on looking.
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !self.isReachable else { return }
            self.publish(.failed(.notFound))
        }
        lock.withLock { searchDeadline = deadline }
        queue.asyncAfter(deadline: .now() + searchTimeout, execute: deadline)
    }

    /// Goes back to looking after the app has been in a pocket.
    ///
    /// No `stop()`, so a link that survived is kept; no deadline, so a guest whose host is still
    /// away is not told its code was wrong ten seconds later; and `hasEverJoined` is left
    /// standing, so a dial that misses is still read as a host in a pocket.
    public func resumeJoining(code: SessionCode) {
        sweepDeadLinks()
        let needed = lock.withLock { () -> Bool in
            intent = .joining(code)
            return browser == nil || browser?.state != .ready
        }
        if needed {
            let old = lock.withLock { () -> NWBrowser? in
                let previous = browser
                browser = nil
                return previous
            }
            old?.cancel()
            standUpBrowser(code: code)
        }
        startRedialling()
        redial()
        announce()
    }

    private func standUpBrowser(code: SessionCode) {
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
            guard let self else { return }
            switch state {
            case .failed:
                let joinedBefore = self.lock.withLock { () -> Bool in
                    self.browser = nil
                    return self.hasEverJoined
                }
                // Before anything has ever worked, a browser that fails really is the refused
                // permission. Afterwards it is the system having taken it away with the app,
                // and the redial timer puts it back without troubling anybody about it.
                if !joinedBefore { self.publish(.failed(.blocked)) }
            case .cancelled:
                self.lock.withLock { self.browser = nil }
            default:
                break
            }
        }
        lock.withLock { self.browser = browser }
        browser.start(queue: queue)
        publish(.searching)
    }

    public func stop() {
        stopRedialling()
        let (oldListener, oldBrowser, oldLinks, pending, deadline, dials) = lock.withLock {
            let values = (
                listener, browser, Array(links.values), Array(waiting.values),
                searchDeadline, Array(dialDeadlines.values)
            )
            listener = nil
            browser = nil
            links = [:]
            waiting = [:]
            searchDeadline = nil
            dialDeadlines = [:]
            listenerAttempts = 0
            intent = .none
            hasEverJoined = false
            lastSnapshot = nil
            return values
        }
        for dial in dials { dial.cancel() }
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

    public func forgetSnapshot() {
        lock.withLock { lastSnapshot = nil }
    }

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
            // The browser reports everything it can see every time anything changes, and it
            // is rebuilt each time the app comes back — so a host this is already on comes
            // round again, and dialling it again would hold two links to one phone.
            guard !lock.withLock({ links.values.contains { $0.share == share } }) else { continue }

            let connection = NWConnection(
                to: result.endpoint,
                using: parameters(key: SessionKey.presharedKey(for: code, share: share))
            )
            adopt(connection, share: share)
        }
    }

    private func accept(_ connection: NWConnection) {
        adopt(connection, share: nil)
    }

    private func adopt(_ connection: NWConnection, share: UUID?) {
        let link = Link(connection, share: share)
        let token = ObjectIdentifier(connection)
        lock.withLock { links[token] = link }
        if share != nil { giveUpOnDial(token, link) }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.forgetDialDeadline(token)
                self.lock.withLock {
                    link.isReady = true
                    self.hasEverJoined = true
                }
                self.receive(on: link)
                if let snapshot = self.lock.withLock({ self.lastSnapshot }) {
                    self.send(Frame(kind: .oneway, payload: snapshot), on: link)
                }
                self.reachabilityUpdates.yield(true)
                self.announce()
            case .failed:
                self.close(token, refusable: true)
            case .cancelled:
                // Never a rejection: a wrong pre-shared key surfaces as a failure, and a
                // cancel is somebody hanging up — usually this end.
                self.close(token, refusable: false)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Lets go of links the system has already taken away.
    ///
    /// `Link.isReady` is a cache written by a callback on this class's own queue, and coming
    /// back to the front is exactly the moment that callback may not have arrived yet. So ask
    /// each connection what it is rather than what we last heard it was — a sweep is this end
    /// hanging up on something already gone, not a loss with anything to read into it.
    private func sweepDeadLinks() {
        let dead = lock.withLock { () -> [Link] in
            var removed: [Link] = []
            for (token, link) in links {
                switch link.connection.state {
                case .ready, .preparing, .setup:
                    continue
                default:
                    links.removeValue(forKey: token)
                    removed.append(link)
                }
            }
            return removed
        }
        guard !dead.isEmpty else { return }
        for link in dead {
            forgetDialDeadline(ObjectIdentifier(link.connection))
            link.connection.cancel()
        }
        reachabilityUpdates.yield(isReachable)
    }

    /// An `NWConnection` to an endpoint that is no longer there sits in `.waiting` rather than
    /// failing, and `redial` will not dial while any link is on the books — so one of these
    /// would quietly block every future attempt for the rest of the match.
    private func giveUpOnDial(_ token: ObjectIdentifier, _ link: Link) {
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.lock.withLock({ !link.isReady }) else { return }
            self.close(token, refusable: false)
        }
        lock.withLock { dialDeadlines[token] = deadline }
        queue.asyncAfter(deadline: .now() + dialTimeout, execute: deadline)
    }

    private func forgetDialDeadline(_ token: ObjectIdentifier) {
        lock.withLock { dialDeadlines.removeValue(forKey: token) }?.cancel()
    }

    private func close(_ token: ObjectIdentifier, refusable: Bool) {
        forgetDialDeadline(token)
        let link = lock.withLock { links.removeValue(forKey: token) }
        guard let link else { return }
        link.connection.cancel()

        // Gathered under the lock, `isReady` included: it is written by a callback on this
        // class's own queue and nothing orders that against whoever is closing the link.
        let circumstances = lock.withLock {
            ReconnectPolicy.Circumstances(
                everGotThere: link.isReady,
                hasEverJoined: hasEverJoined,
                isHosting: isHosting,
                linksRemain: !links.isEmpty,
                refusable: refusable
            )
        }
        reachabilityUpdates.yield(isReachable)

        switch ReconnectPolicy.loss(circumstances) {
        case .refused:
            // It was there and it would not have us, which is what a wrong code looks like.
            publish(.failed(.rejected))
        case .keepLooking:
            // It was working and went away — the host walked off, or a phone went in a
            // pocket. Go back to looking rather than sitting there with nothing.
            announce()
            redial()
        case .carryOn:
            announce()
        }
    }

    /// Looks again on a timer, for as long as this is meant to be joined to something.
    ///
    /// `browseResultsChangedHandler` fires on a *change*, and a host that never stopped
    /// advertising is not a change — so a guest with nothing to dial at the moment it happened
    /// to look has nothing that would ever make it look a second time. This is what makes it
    /// look. It is also what puts the browser back when the system has taken it away.
    private func startRedialling() {
        stopRedialling()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + redialInterval, repeating: redialInterval)
        timer.setEventHandler { [weak self] in self?.lookAgain() }
        lock.withLock { redialTimer = timer }
        timer.resume()
    }

    private func stopRedialling() {
        let timer = lock.withLock { () -> DispatchSourceTimer? in
            let old = redialTimer
            redialTimer = nil
            return old
        }
        timer?.cancel()
    }

    private func lookAgain() {
        let (intent, browser) = lock.withLock { (self.intent, self.browser) }
        guard case .joining(let code) = intent else { return }
        guard browser == nil || browser?.state != .ready else { return redial() }

        let old = lock.withLock { () -> NWBrowser? in
            let previous = self.browser
            self.browser = nil
            return previous
        }
        old?.cancel()
        standUpBrowser(code: code)
    }

    /// Dials whatever the browser can currently see again.
    ///
    /// Needed because `browseResultsChangedHandler` only fires on a change: a host that never
    /// stopped advertising produces no new event, so a guest whose link dropped would wait
    /// for one that never comes.
    private func redial() {
        let (intent, browser, count) = lock.withLock { (self.intent, self.browser, links.count) }
        guard case .joining(let code) = intent, count == 0, let browser else { return }
        consider(browser.browseResults, code: code)
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
                if broken { return self.close(ObjectIdentifier(link.connection), refusable: false) }
                for frame in frames { self.deliver(frame, on: link) }
            }
            if isComplete || error != nil {
                return self.close(ObjectIdentifier(link.connection), refusable: false)
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
        if case .failed = value { lock.withLock { searchDeadline }?.cancel() }
        statusUpdates.yield(value)
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
    public func forgetSnapshot() {}
    public func sendLive(_ payload: Data) async -> Data? { nil }
    public func publishSnapshot(_ payload: Data) {}
    public func queue(_ payload: Data) {}
    public func startHosting(code: SessionCode, share: UUID) {}
    public func resumeHosting(code: SessionCode, share: UUID) {}
    public func startJoining(code: SessionCode) {}
    public func resumeJoining(code: SessionCode) {}
    public func stop() {}
}

#endif
