import Foundation
import RekkertCore

/// Everything `BluetoothTransport` decides, apart from the radio it decides it over, so it runs
/// where the tests do.
nonisolated public final class RadioCore: PeerTransport, RadioListener, @unchecked Sendable {
    /// What the host publishes about itself so a guest can work out whether it was told this
    /// code, and derive the key if it was.
    struct Greeting: Codable, Equatable {
        var v: Int
        var share: UUID
        var fp: String

        /// 3 since each connection is proved afresh and its frames numbered. An older build cannot
        /// open anything sealed now, so the two refuse each other at the greeting rather than
        /// half-connecting.
        static let version = 3
    }

    public let inbound: AsyncStream<InboundPacket>
    /// A stream of its own for every caller: the fan-out and the coordinator both listen.
    public var reachability: AsyncStream<Bool> { reachabilityUpdates.stream() }
    public var linkChanges: AsyncStream<LinkChange> { linkUpdates.stream() }

    /// One peer's end of the conversation. Unchecked for the same reason `Link` is: every field
    /// is only ever touched under `lock`.
    private final class Peer: @unchecked Sendable {
        let reassembler = Chunking.Reassembler()
        /// Frames the link would not take yet. Bluetooth refuses rather than buffers, and a
        /// refused chunk that is dropped is a frame that will never open on the other side.
        var backlog: [Outgoing] = []
        /// Only once it has proved itself on this connection, and while it goes on answering.
        /// Anybody in range can connect and subscribe, and one byte of fingerprint agrees by
        /// accident now and again.
        var isReady = false
        var seal: LinkSeal
        var health = LinkHealth()
        /// Guest side only. A write is answered before the next one goes out: CoreBluetooth
        /// will take more than it can carry and then drop the overflow, and a dropped chunk is
        /// a frame that never opens at the far end and a reply somebody waits the timeout out
        /// for. The host's side of the same problem is `updateValue` refusing, which it says so.
        var isWriting = false
        /// Only a host has one of these, and only to answer the right central.
        let central: RadioPeer?
        let link = LinkID()
        var liveness: LinkLiveness
        /// Past the limit: told so, and never counted as there again on this connection.
        var isRefused = false

        init(seal: LinkSeal, central: RadioPeer? = nil, now: Duration) {
            self.seal = seal
            self.central = central
            liveness = LinkLiveness(now: now)
        }
    }

    /// Whole frames, so one nobody is waiting for any more can be dropped before its first
    /// chunk goes out, never halfway through, which would take the frame after it down too.
    private struct Outgoing {
        /// Sealed only when its turn comes, so frames are numbered in the order they go out: the
        /// far end refuses one numbered below a frame it has already opened. `nil` for the
        /// handshake, which is sealed already and carries no number.
        var frame: Frame?
        var chunks: [Data]
        var sent = 0
        let expires: Duration?
        /// The question this is, when it is one.
        let correlation: UInt32?
        let priority: HubScheduler<RadioPeer>.Priority

        /// Sealed, or partly sent: past the point where anything may go ahead of it.
        var isStarted: Bool { sent > 0 || (frame != nil && !chunks.isEmpty) }
    }

    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates = Broadcast<Bool>()
    private let linkUpdates = Broadcast<LinkChange>()

    private let radio: any Radio
    private var scheduler: any RadioScheduler { radio.scheduler }
    private let lock = NSLock()

    private var nextSession = 1
    private var peripheralSession: Int?
    private var centralSession: Int?
    private var isPublished = false
    private var server: RadioPeer?
    private var serverHasInbox = false
    private var peers: [RadioPeer: Peer] = [:]
    private var turns = HubScheduler<RadioPeer>()
    private var waiting: [UInt32: ResumeOnce] = [:]
    /// Questions whose last chunk went out, so one dropped unsent does not count against the peer.
    private var askedWhole: Set<UInt32> = []
    private var nextCorrelation: UInt32 = 1
    private var intent: Intent = .none
    /// Hosts that turned out to be somebody else's court. A scan reports each peripheral once,
    /// so one of these checked first would otherwise be checked again and again while the
    /// right one, found in the meantime, was dropped for being second.
    private var rejected: Set<UUID> = []
    /// Whether a host has proved itself during this join. Hung up on or gone quiet, it is still
    /// the right host: looked for wherever it has gone, and never written off for being slow to
    /// prove itself again. Not kept per peripheral: an iPhone's address moves on, and the same
    /// host found again under another identifier is the same host.
    private var hasProven = false
    /// When the host being dialled is let go of, unless it has proved itself by then.
    private var candidateDeadline: (any RadioTimer)?
    /// A host this was on has gone, and is being dialled again as well as looked for afresh.
    private var isRedialling = false
    private var tick: (any RadioTimer)?
    private var lastRescan: Duration?
    private static var rescanEvery: Duration { .seconds(20) }
    private var _availability = RadioAvailability.unknown
    private let availabilityUpdates = Broadcast<RadioAvailability>()

    public var availability: RadioAvailability { lock.withLock { _availability } }
    public var availabilityChanges: AsyncStream<RadioAvailability> { availabilityUpdates.stream() }

    private func noteAvailability(_ availability: RadioAvailability) {
        let changed = lock.withLock { () -> Bool in
            defer { _availability = availability }
            return _availability != availability
        }
        if changed { availabilityUpdates.yield(availability) }
    }

    private enum Intent: Sendable {
        case none
        case hosting(code: SessionCode, share: UUID)
        case joining(SessionCode)
    }

    private let replyTimeout: Duration
    private let replySeconds: Int
    /// How long a host that passed the greeting has to prove it holds the key.
    private let proofTimeout: Duration
    /// How long a host that has only been found has to get as far as the greeting.
    private let candidateTimeout: Duration
    /// What a write will carry when nothing better is known. `maximumWriteValueLength` is asked
    /// for the moment there is a peripheral to ask, and this only covers the gap before that.
    private static let conservativeMTU = 20

    public init(radio: any Radio, replyTimeout: Int = 4, proofTimeout: Int = 10, candidateTimeout: Int = 15) {
        self.radio = radio
        self.replyTimeout = .seconds(replyTimeout)
        replySeconds = replyTimeout
        self.proofTimeout = .seconds(proofTimeout)
        self.candidateTimeout = .seconds(candidateTimeout)

        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation

        radio.attach(self)
    }

    // MARK: - Opening and closing

    public func startHosting(code: SessionCode, share: UUID) {
        guard radio.canHost else { return }
        stop()
        let session = lock.withLock { () -> Int in
            intent = .hosting(code: code, share: share)
            defer { nextSession += 1 }
            peripheralSession = nextSession
            return nextSession
        }
        radio.openPeripheral(session: session)
        startTicking()
    }

    public func startJoining(code: SessionCode) {
        stop()
        let session = lock.withLock { () -> Int in
            intent = .joining(code)
            defer { nextSession += 1 }
            centralSession = nextSession
            return nextSession
        }
        radio.openCentral(session: session)
        startTicking()
    }

    /// Putting it back after the app has been away is usually putting nothing back at all: a
    /// Bluetooth link is the one thing here the system did not take down. Kept so the
    /// coordinator can treat both transports alike, and so a transport that never got going —
    /// the radio was off, the app was launched cold — gets another chance.
    public func resumeHosting(code: SessionCode, share: UUID) {
        let standing = lock.withLock { if case .hosting = intent { true } else { false } }
        guard !standing else { return }
        startHosting(code: code, share: share)
    }

    public func resumeJoining(code: SessionCode) {
        // Whatever was turned away last time is worth asking again.
        let standing = lock.withLock { () -> Bool in
            rejected = []
            if case .joining = intent { return true } else { return false }
        }
        guard !standing else { return }
        startJoining(code: code)
    }

    public func stop() {
        let (hadPeripheral, hadCentral, connected, pending, deadline, wereUp) = lock.withLock {
            let values = (
                peripheralSession != nil, centralSession != nil, server, Array(waiting.values), candidateDeadline,
                peers.values.filter(\.isReady).map(\.link)
            )
            tick?.cancel()
            tick = nil
            candidateDeadline = nil
            isRedialling = false
            peripheralSession = nil
            centralSession = nil
            isPublished = false
            server = nil
            serverHasInbox = false
            peers = [:]
            turns = HubScheduler()
            waiting = [:]
            askedWhole = []
            intent = .none
            rejected = []
            hasProven = false
            return values
        }
        deadline?.cancel()
        if hadPeripheral { radio.closePeripheral() }
        if hadCentral {
            radio.stopScan()
            if let connected { radio.cancelConnection(connected) }
            radio.closeCentral()
        }
        for resume in pending { resume.resume(nil) }
        for link in wereUp { linkUpdates.yield(.down(link, .hungUp)) }
        reachabilityUpdates.yield(false)
    }

    // MARK: - Liveness

    private func startTicking() {
        let timer = scheduler.run(after: .seconds(1)) { [weak self] in
            guard let self else { return }
            let isOn = self.lock.withLock { if case .none = self.intent { false } else { true } }
            guard isOn else { return }
            self.checkLiveness()
            self.startTicking()
        }
        let previous = lock.withLock { () -> (any RadioTimer)? in
            defer { tick = timer }
            return tick
        }
        previous?.cancel()
    }

    private func checkLiveness() {
        let now = scheduler.now
        // The host this was on has gone and is still being looked for. A scan reports each
        // peripheral once, and its address moves on, so the scan is started over from time to time.
        let rescan = lock.withLock { () -> Bool in
            guard isRedialling, centralSession != nil else {
                lastRescan = nil
                return false
            }
            guard let last = lastRescan else {
                lastRescan = now
                return false
            }
            guard now - last >= Self.rescanEvery else { return false }
            lastRescan = now
            return true
        }
        if rescan {
            radio.stopScan()
            radio.scan()
        }
        let (nudge, probes) = lock.withLock { () -> (Bool, [Peer]) in
            var nudge = false
            var probes: [Peer] = []
            for peer in peers.values {
                if peer.central == nil {
                    if peer.isReady, peer.liveness.shouldNudge(now: now) { nudge = true }
                } else if peer.seal.isProven, !peer.isReady, !peer.isRefused, peer.liveness.shouldProbe(now: now) {
                    probes.append(peer)
                }
            }
            return (nudge, probes)
        }
        // The store says hello whenever it hears the link is up, which is the question a quiet
        // guest needs to ask: what has been going on while it said nothing.
        if nudge { reachabilityUpdates.yield(true) }
        for peer in probes { Task { [weak self] in await self?.probe(peer) } }
    }

    /// Something a guest given up on has to answer. Every build answers a message it cannot read
    /// with a hello, which brings the link back and says how far that guest has got.
    private func probe(_ peer: Peer) async {
        guard let reply = await ask(Data(), of: peer) else { return }
        lock.withLock { peer.liveness.answered() }
        packets.yield(InboundPacket(payload: reply, link: peer.link))
    }

    // MARK: - PeerTransport

    public func activate() {}

    public var isReachable: Bool {
        lock.withLock { peers.values.contains { $0.isReady } }
    }

    public var reachableCount: Int {
        lock.withLock { peers.values.count { $0.isReady } }
    }

    public var links: [LinkID] {
        lock.withLock { peers.values.filter(\.isReady).map(\.link) }
    }

    public func sendLive(_ payload: Data) async -> Data? {
        let ready = lock.withLock { peers.values.filter(\.isReady) }
        guard !ready.isEmpty else { return nil }

        let replies = await withTaskGroup(of: (LinkID, Data?).self) { group in
            for peer in ready {
                group.addTask { (peer.link, await self.ask(payload, of: peer)) }
            }
            var collected: [(LinkID, Data?)] = []
            for await reply in group { collected.append(reply) }
            return collected
        }

        // Handed on under the link they came back on, so whatever they bring is not sent back to it.
        for case let (link, reply?) in replies where !LinkReplies.isAcknowledgement(reply) {
            packets.yield(InboundPacket(payload: reply, link: link))
        }
        return ReplyFold.fold(replies.map(\.1), expected: ready.count).acknowledgement
    }

    public func sendLive(_ payload: Data, on link: LinkID) async -> Data? {
        guard let peer = lock.withLock({ peers.values.first { $0.isReady && $0.link == link } }) else { return nil }
        return await ask(payload, of: peer)
    }

    /// No durable queue out here, the same as the local network: a peer that is not connected
    /// simply is not there, and what stands in for a queue is the log itself — whoever comes
    /// back asks what they missed and is answered from it.
    public func queue(_ payload: Data) {
        broadcast(payload)
    }

    /// Not carried at all. `MatchStore` publishes a whole log on every scoring change, which is a
    /// sensible thing to push over a socket and a hopeless one over Bluetooth. Handed only to each
    /// peer as it connected, it still went both ways on every reconnect, ahead of everything else;
    /// each end says hello when a link comes up instead, and is sent only what it is missing.
    public func publishSnapshot(_ payload: Data) {}

    public func forgetSnapshot() {}

    // MARK: - Talking

    private func ask(_ payload: Data, of peer: Peer) async -> Data? {
        let correlation = lock.withLock { () -> UInt32 in
            let value = nextCorrelation
            nextCorrelation &+= 1
            return value
        }
        let reply = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            lock.withLock { waiting[correlation] = once }
            send(Frame(kind: .request, correlation: correlation, payload: payload), to: peer)
            // Has to be shorter than `MatchStore`'s own six seconds, or the store gives up
            // first and the outbox is never acknowledged — which looks exactly like one-way
            // sync. Every child of the fan-out is waited on, so a quiet peer here is a pause
            // for everybody.
            scheduler.run(after: replyTimeout) { [weak self] in
                self?.lock.withLock { _ = self?.waiting.removeValue(forKey: correlation) }
                once.resume(nil)
            }
        }
        let wentOut = lock.withLock { askedWhole.remove(correlation) != nil }
        if reply != nil {
            lock.withLock { peer.health.answered() }
        } else if wentOut, lock.withLock({ peer.backlog.isEmpty }) {
            missed(peer)
        }
        return reply
    }

    /// A question that went out whole and was never answered, or a write that failed. Enough of
    /// them in a row and the peer is not counted as there: a host is hung up on, so the reconnect
    /// dials it afresh, and a guest waits to prove itself again with its next frame.
    private func missed(_ peer: Peer) {
        let givenUp = lock.withLock { () -> Bool in
            guard peer.isReady, peer.health.missed() else { return false }
            peer.isReady = false
            peer.health = LinkHealth()
            return true
        }
        guard givenUp else { return }
        linkUpdates.yield(.down(peer.link, .timeout))
        reachabilityUpdates.yield(isReachable)
        guard peer.central == nil else { return }
        let target = lock.withLock { () -> RadioPeer? in
            guard let server, peers[server] === peer, centralSession != nil else { return nil }
            return server
        }
        if let target { radio.cancelConnection(target) }
    }

    private func broadcast(_ payload: Data) {
        let ready = lock.withLock { peers.values.filter(\.isReady) }
        for peer in ready { send(Frame(kind: .oneway, payload: payload), to: peer) }
    }

    private func send(_ frame: Frame, to peer: Peer) {
        let mtu = mtu(for: peer)
        let expires = LinkReplies.patience(for: frame.kind, replyTimeout: replySeconds).map { scheduler.now + .seconds($0) }
        guard FrameCodec.fits(frame) else { return }
        let estimate = (FrameCodec.headerSize + frame.payload.count + 64) / max(1, mtu - Chunking.headerSize) + 1
        lock.withLock {
            place(Outgoing(
                frame: frame, chunks: [], expires: expires,
                correlation: frame.kind == .request ? frame.correlation : nil,
                priority: HubScheduler.priority(chunks: estimate)
            ), on: peer)
        }
        wake(peer)
    }

    /// The proof, which is sealed already.
    private func enqueue(_ sealed: Data, to peer: Peer) {
        let mtu = mtu(for: peer)
        lock.withLock {
            place(Outgoing(
                frame: nil, chunks: Chunking.split(sealed, mtu: mtu), expires: nil, correlation: nil, priority: .handshake
            ), on: peer)
        }
        wake(peer)
    }

    /// Under `lock`.
    private func place(_ outgoing: Outgoing, on peer: Peer) {
        let index = HubScheduler<RadioPeer>.position(
            for: outgoing.priority, in: peer.backlog.map { ($0.priority, $0.isStarted) }
        )
        peer.backlog.insert(outgoing, at: index)
    }

    /// Drained on the one queue the radio already calls back on, so a send from a reply
    /// closure, a send from the store and the "ready again" callback never drain the same
    /// backlog at once — two of them would put the same chunk on the air and skip the next.
    /// A host's guests share one transmit queue, so a send to any of them is a turn for all.
    private func wake(_ peer: Peer) {
        if peer.central != nil {
            scheduler.run { [weak self] in self?.drainHost() }
        } else {
            scheduler.run { [weak self] in self?.drain(peer) }
        }
    }

    private func mtu(for peer: Peer) -> Int {
        if let central = peer.central {
            return Chunking.packetLength(reportedMaximum: radio.maximumUpdate(for: central))
        }
        if let server = lock.withLock({ self.server }) {
            // One packet's worth, though the write waits for its response: `.withResponse`
            // reports 512, and anything past one packet goes as a long write in pieces.
            return Chunking.packetLength(reportedMaximum: radio.maximumWrite(for: server))
        }
        return Self.conservativeMTU
    }

    /// Bluetooth refuses rather than buffers, so a chunk it will not take has to be kept and
    /// offered again — dropping one is a frame that never opens on the other side and a reply
    /// somebody waits out the timeout for.
    private func drain(_ peer: Peer) {
        while step(peer) == .sent {}
    }

    private enum Step { case sent, blocked, done }

    /// One chunk of the peer's next frame, if the link will take it.
    private func step(_ peer: Peer) -> Step {
        let mtu = mtu(for: peer)
        let next = lock.withLock { () -> Data? in
            let now = scheduler.now
            while let first = peer.backlog.first {
                if !first.isStarted, let expires = first.expires, expires < now {
                    peer.backlog.removeFirst()
                    continue
                }
                guard first.chunks.isEmpty, let frame = first.frame else { break }
                // Sealed here, as it goes out, so the numbering follows the order on the air.
                guard let sealed = peer.seal.seal(frame) else {
                    peer.backlog.removeFirst()
                    continue
                }
                peer.backlog[0].chunks = Chunking.split(sealed, mtu: mtu)
                break
            }
            return peer.backlog.first.map { $0.chunks[$0.sent] }
        }
        guard let next else { return .done }
        guard deliver(next, to: peer) else { return .blocked }
        lock.withLock {
            guard !peer.backlog.isEmpty else { return }
            peer.backlog[0].sent += 1
            guard peer.backlog[0].sent == peer.backlog[0].chunks.count else { return }
            if let correlation = peer.backlog[0].correlation { askedWhole.insert(correlation) }
            peer.backlog.removeFirst()
        }
        // A guest may only have one write outstanding, so the acknowledgement is what
        // fetches the next chunk rather than this loop.
        return lock.withLock({ peer.isWriting }) ? .blocked : .sent
    }

    private func deliver(_ chunk: Data, to peer: Peer) -> Bool {
        if let central = peer.central {
            let (published, isCurrent) = lock.withLock {
                (peripheralSession != nil && isPublished, peers[central] === peer)
            }
            // The same central subscribed again, and is another peer now: written into its new
            // connection, this would break whatever frame that one is in the middle of.
            guard isCurrent else {
                lock.withLock { peer.backlog.removeAll() }
                return false
            }
            guard published else { return false }
            let taken = radio.update(chunk, to: central)
            if taken { lock.withLock { peer.liveness.sent(at: scheduler.now) } }
            return taken
        }
        let (server, hasInbox, isCurrent) = lock.withLock { () -> (RadioPeer?, Bool, Bool) in
            guard let server = self.server else { return (nil, false, false) }
            return (server, serverHasInbox, peers[server] === peer)
        }
        // What was waiting for a peer since dropped belongs to a link that is gone. Written into
        // the one that replaced it, it breaks whatever frame that one is in the middle of.
        guard isCurrent, let server, hasInbox else { return false }
        guard lock.withLock({ !peer.isWriting }) else { return false }
        lock.withLock {
            peer.isWriting = true
            peer.liveness.sent(at: scheduler.now)
        }
        radio.write(chunk, to: server)
        return true
    }

    public func wrote(to peripheral: RadioPeer, failed: Bool) {
        guard let peer = lock.withLock({ peers[peripheral] }) else { return }
        lock.withLock { peer.isWriting = false }
        if failed { missed(peer) }
        drain(peer)
    }

    /// The host took its service away — it stopped sharing, or its app went — and Bluetooth kept
    /// the connection up with nothing on the other end of it. Hung up on, the reconnect finds
    /// the service when it comes back, or finds that it is somebody else's now.
    public func servicesChanged(on peripheral: RadioPeer, invalidatedOurs: Bool) {
        guard invalidatedOurs else {
            // Put up rather than taken away, which names nothing invalidated: a host back from its
            // radio going off and on, on a connection that came back before its service did.
            if lock.withLock({ server == peripheral && !serverHasInbox }) {
                radio.discover(peripheral)
            }
            return
        }
        let hasCentral = lock.withLock { () -> Bool in
            guard server == peripheral else { return false }
            serverHasInbox = false
            return centralSession != nil
        }
        guard hasCentral else { return }
        forget(peripheral, because: .closedByPeer)
        radio.cancelConnection(peripheral)
    }

    /// A chunk from each in turn. Drained one at a time, whoever came first filled the queue with
    /// a long frame every time it had room, and everybody else's replies waited until too late.
    /// The turn carries on from one callback to the next: started over from the same guest
    /// every time, the queue freeing one slot served that guest and nobody after it.
    private func drainHost() {
        while true {
            var progressed = false
            for key in lock.withLock({ turns.turns() }) {
                guard let peer = lock.withLock({ peers[key] }), peer.central != nil else { continue }
                switch step(peer) {
                case .sent:
                    lock.withLock { turns.served(key) }
                    progressed = true
                case .done:
                    continue
                // A host's queue is one queue for every subscriber: full for one, full for all.
                // One cleared for a guest that came back as another is not a refusal.
                case .blocked:
                    if lock.withLock({ !peer.backlog.isEmpty }) { return }
                }
            }
            guard progressed else { return }
        }
    }

    private func receive(_ chunk: Data, from peer: Peer) {
        // Anything arriving is the peer still there. Behind a long answer the next ones queue at
        // the far end and run out of time, and counting those as unanswered hung up on a host
        // part way through sending, which then started over on the reconnect.
        lock.withLock { if peer.seal.isProven { peer.health.answered() } }
        let whole: Data?
        do {
            whole = try lock.withLock { try peer.reassembler.accept(chunk) }
        } catch {
            lock.withLock { peer.reassembler.reset() }
            return
        }
        guard let whole else { return }
        guard let opened = lock.withLock({ peer.seal.open(whole) }) else {
            return refusedKey(whole, from: peer)
        }

        switch opened {
        case .answer(let answer):
            // A guest starting over on this connection is not on the match until it confirms.
            let wasReady = lock.withLock { () -> Bool in
                defer { peer.isReady = false }
                return peer.isReady
            }
            if wasReady { reachabilityUpdates.yield(isReachable) }
            enqueue(answer, to: peer)
        case .proven(let confirmation):
            // Ahead of anything the store sends once it hears the link is up.
            if let confirmation { enqueue(confirmation, to: peer) }
            // The host, proven: from here a drop is a reconnect, which waits as long as it takes.
            if peer.central == nil {
                let deadline = lock.withLock { () -> (any RadioTimer)? in
                    if let server, peers[server] === peer { hasProven = true }
                    return candidateDeadline
                }
                deadline?.cancel()
            }
            ready(peer)
        case .frame(let frame):
            // Proven on this connection already, and back from having gone quiet.
            if lock.withLock({ !peer.isReady }) { ready(peer) }
            handOn(frame, from: peer)
        }
    }

    /// Silence from a host says nothing about the code: it may only be busy. So a host told a key
    /// it cannot open says so, and that refusal is the one thing that turns a guest away from it.
    private func refusedKey(_ sealed: Data, from peer: Peer) {
        let (isHostSide, isUnproven) = lock.withLock { (peer.central != nil, !peer.seal.isProven) }
        guard isUnproven else { return }
        if isHostSide {
            guard sealed != LinkSeal.refusal else { return }
            return enqueue(LinkSeal.refusal, to: peer)
        }
        let candidate = lock.withLock { () -> RadioPeer? in
            guard !hasProven, let server, peers[server] === peer else { return nil }
            return server
        }
        if let candidate { reject(candidate) }
    }

    private func handOn(_ frame: Frame, from peer: Peer) {
        switch frame.kind {
        case .reply:
            if let pending = lock.withLock({ waiting.removeValue(forKey: frame.correlation) }) {
                pending.resume(frame.payload)
            } else if LinkReplies.isWorthHandingOn(late: frame.payload) {
                packets.yield(InboundPacket(payload: frame.payload, link: peer.link))
            }
        case .request:
            let correlation = frame.correlation
            packets.yield(InboundPacket(payload: frame.payload, reply: { [weak self, weak peer] answer in
                guard let self, let peer else { return }
                self.send(Frame(kind: .reply, correlation: correlation, payload: answer), to: peer)
            }, link: peer.link))
        case .oneway:
            guard !frame.payload.isEmpty else { return }
            packets.yield(InboundPacket(payload: frame.payload, link: peer.link))
        }
    }

    /// Counted from here, and said: each end's store says hello when it hears, which is what
    /// catches either side up.
    private func ready(_ peer: Peer) {
        let wasReady = lock.withLock { () -> Bool? in
            guard !peer.isRefused else { return nil }
            defer { peer.isReady = true }
            return peer.isReady
        }
        guard let wasReady else { return }
        if !wasReady { linkUpdates.yield(.up(peer.link)) }
        reachabilityUpdates.yield(true)
    }

    public func refuse(_ link: LinkID) {
        let wasReady = lock.withLock { () -> Bool? in
            guard let peer = peers.values.first(where: { $0.link == link }), peer.central != nil else { return nil }
            defer {
                peer.isRefused = true
                peer.isReady = false
            }
            return peer.isReady
        }
        guard wasReady == true else { return }
        linkUpdates.yield(.down(link, .refused))
        reachabilityUpdates.yield(isReachable)
    }

    private func forget(_ token: RadioPeer, because reason: LinkDropReason) {
        let peer = lock.withLock { () -> Peer? in
            turns.leave(token)
            return peers.removeValue(forKey: token)
        }
        guard let peer else { return }
        if lock.withLock({ peer.isReady }) { linkUpdates.yield(.down(peer.link, reason)) }
        reachabilityUpdates.yield(isReachable)
    }

    /// The radio switched off, Airplane mode, bluetoothd starting over: every connection goes with
    /// it, and CoreBluetooth says so once, here, rather than peer by peer. Everything about them
    /// is let go of — kept, a peer went on counting as there and a host still on the books kept
    /// the scan from ever finding it again — so the radio coming back starts afresh.
    private func lostTheRadio() {
        let (pending, deadline, hadPeers, wereUp) = lock.withLock {
            let values = (Array(waiting.values), candidateDeadline, !peers.isEmpty, peers.values.filter(\.isReady).map(\.link))
            peers = [:]
            turns = HubScheduler()
            waiting = [:]
            askedWhole = []
            server = nil
            serverHasInbox = false
            candidateDeadline = nil
            rejected = []
            hasProven = false
            isRedialling = false
            return values
        }
        deadline?.cancel()
        for resume in pending { resume.resume(nil) }
        for link in wereUp { linkUpdates.yield(.down(link, .radioOff)) }
        if hadPeers { reachabilityUpdates.yield(false) }
    }

    // MARK: - Hosting

    public func peripheralState(_ availability: RadioAvailability, session: Int) {
        guard lock.withLock({ peripheralSession == session }) else { return }
        noteAvailability(availability)
        guard availability == .on else { return lostTheRadio() }
        guard case .hosting = lock.withLock({ intent }) else { return }
        lock.withLock { isPublished = true }
        radio.publish()
    }

    public func greeting(session: Int) -> Data? {
        guard lock.withLock({ peripheralSession == session }),
              case .hosting(let code, let share) = lock.withLock({ intent })
        else { return nil }
        return try? JSONCoding.encoder.encode(Greeting(
            v: Greeting.version, share: share, fp: SessionKey.fingerprint(for: code, share: share)
        ))
    }

    public func subscribed(_ central: RadioPeer, session: Int) {
        guard lock.withLock({ peripheralSession == session }),
              case .hosting(let code, let share) = lock.withLock({ intent })
        else { return }
        let peer = Peer(seal: LinkSeal(role: .host, code: code, share: share), central: central, now: scheduler.now)
        // Not ready until it has proved itself. Counted on subscribing, a central with the
        // wrong code — or any Bluetooth tool at all — was waited on by every send, answered
        // none of them, and kept the outbox from ever being acknowledged.
        lock.withLock {
            peers[central] = peer
            turns.join(central)
        }
        // A subscriber that never proves itself is nobody's guest, and holds a place in the turn.
        scheduler.run(after: Self.proofLimit) { [weak self] in
            guard let self else { return }
            let unproven = self.lock.withLock { self.peers[central] === peer && !peer.seal.isProven }
            if unproven { self.forget(central, because: .refused) }
        }
    }

    private static var proofLimit: Duration { .seconds(15) }

    public func unsubscribed(_ central: RadioPeer) {
        forget(central, because: .closedByPeer)
    }

    public func received(writes: [(central: RadioPeer, offset: Int, value: Data)], session: Int) -> Bool {
        guard lock.withLock({ peripheralSession == session }) else { return false }
        var writers: [Peer] = []
        var grouped: [ObjectIdentifier: [(offset: Int, value: Data)]] = [:]
        for write in writes {
            guard let peer = lock.withLock({ peers[write.central] }) else { continue }
            let token = ObjectIdentifier(peer)
            if grouped[token] == nil { writers.append(peer) }
            grouped[token, default: []].append((write.offset, write.value))
        }
        for peer in writers {
            for chunk in Chunking.chunks(fromWrites: grouped[ObjectIdentifier(peer)] ?? []) {
                receive(chunk, from: peer)
            }
        }
        return true
    }

    public func readyToUpdate() {
        drainHost()
    }

    // MARK: - Joining

    public func centralState(_ availability: RadioAvailability, session: Int) {
        guard lock.withLock({ centralSession == session }) else { return }
        noteAvailability(availability)
        guard availability == .on else { return lostTheRadio() }
        guard case .joining = lock.withLock({ intent }) else { return }
        radio.scan()
    }

    public func discovered(_ peripheral: RadioPeer, session: Int) {
        // Checked under the lock that takes the peripheral: checked apart, a `stop()` and the next
        // join in between left this one's host in the new join's place.
        let (take, stale) = lock.withLock { () -> (Bool, RadioPeer?) in
            guard centralSession == session, !rejected.contains(peripheral.address) else { return (false, nil) }
            guard let current = server else {
                server = peripheral
                return (true, nil)
            }
            // The host this was on went, and is being dialled where it was. Found again — its
            // address moved on, as an iPhone's does, or it came back as another peripheral — it
            // is dialled where it is now. Waiting on the old one alone waited for ever.
            guard isRedialling, current != peripheral, !radio.isConnected(current) else { return (false, nil) }
            server = peripheral
            serverHasInbox = false
            isRedialling = false
            return (true, current)
        }
        guard take else { return }
        if let stale { radio.cancelConnection(stale) }
        // No timeout, which is the reconnect: the system holds the request and wakes the app
        // when the peer comes back, whether that is thirty seconds or the rest of the set.
        radio.connect(peripheral)
        letGoUnlessGreeted(peripheral)
    }

    /// No timeout is right for reaching a host this has been on, and wrong for one it has only
    /// found: there is one place for a host, and one that walked off mid-connect, or never finished
    /// saying what it was, held it while the right one went unheard. Once connected, either has
    /// only so long to get as far as the greeting. Let go of rather than refused — it may be the
    /// right one, back in range — and the scan started over for the rest.
    ///
    /// A host that did get as far as the greeting is `awaitProof`'s to settle.
    private func letGoUnlessGreeted(_ token: RadioPeer) {
        let deadline = scheduler.run(after: candidateTimeout) { [weak self] in
            guard let self else { return }
            let (stale, hasCentral) = self.lock.withLock { () -> (RadioPeer?, Bool) in
                guard let server = self.server, server == token,
                      self.peers[token] == nil else { return (nil, false) }
                self.server = nil
                self.serverHasInbox = false
                return (server, self.centralSession != nil)
            }
            guard let stale, hasCentral else { return }
            self.radio.cancelConnection(stale)
            self.radio.stopScan()
            self.radio.scan()
        }
        let previous = lock.withLock { () -> (any RadioTimer)? in
            let previous = candidateDeadline
            candidateDeadline = deadline
            return previous
        }
        previous?.cancel()
    }

    public func connected(_ peripheral: RadioPeer, session: Int) {
        // One given up on for another, that got there anyway.
        guard lock.withLock({ centralSession == session && server == peripheral }) else {
            return radio.cancelConnection(peripheral)
        }
        // A reconnect as much as a first connect. The phone can be back before its service is,
        // and a connection that never gets as far as a greeting carried nothing, for good.
        letGoUnlessGreeted(peripheral)
        radio.discover(peripheral)
    }

    /// `failed` for a connection that never came up. Dialled again at once, one that fails at once
    /// does so as fast as the radio can go round.
    public func disconnected(_ peripheral: RadioPeer, failed: Bool, session: Int) {
        guard lock.withLock({ centralSession == session }) else { return }
        // Proven at any point in this join, rather than ready now: one hung up on for not answering
        // is not ready any more, one whose service went has been forgotten already, and either is
        // just as likely to have moved.
        let wasProven = lock.withLock { hasProven }
        forget(peripheral, because: .closedByPeer)
        let reconnects = lock.withLock { () -> Bool in
            guard server == peripheral else { return false }
            serverHasInbox = false
            guard !rejected.contains(peripheral.address), case .joining = intent else {
                server = nil
                return false
            }
            if wasProven { isRedialling = true }
            return true
        }
        // Only the host being dialled. The hang-up after a wrong greeting lands here too, and so
        // does one let go of, and neither is a link to put back: dialled again, it would take the
        // place of whichever host is being dialled now.
        guard reconnects else { return }
        if wasProven { radio.scan() }
        guard failed else { return radio.connect(peripheral) }
        scheduler.run(after: .seconds(1)) { [weak self] in
            guard let self else { return }
            let (server, current) = self.lock.withLock { (self.server, self.centralSession) }
            guard let server, server == peripheral, current == session else { return }
            self.radio.connect(server)
        }
    }

    public func foundInbox(on peripheral: RadioPeer) {
        lock.withLock { if server == peripheral { serverHasInbox = true } }
    }

    public func greeted(_ value: Data?, failed: Bool, by peripheral: RadioPeer) {
        // A read that failed says nothing about which court this is, and reading it as a wrong
        // greeting refused the host for the rest of the join. Hanging up is what reads it
        // again: the reconnect asks afresh, and one that never answers is let go of in time.
        guard !failed else {
            if lock.withLock({ centralSession != nil }) { radio.cancelConnection(peripheral) }
            return
        }
        greeted(value, on: peripheral)
    }

    public func received(_ chunk: Data, from peripheral: RadioPeer) {
        // The value is still the last one that arrived, and taking it again would put that
        // chunk into the message twice.
        guard let peer = lock.withLock({ peers[peripheral] }) else { return }
        receive(chunk, from: peer)
    }

    /// Where a wrong code is found out, and the only place it can be: the advertisement could
    /// not carry enough to tell, so the question is asked of the host itself. The fingerprint
    /// settles it cheaply, and the seal settles it for good — a peer that agreed on one byte
    /// by accident still cannot produce a frame this end will open.
    private func greeted(_ value: Data?, on peripheral: RadioPeer) {
        guard lock.withLock({ server == peripheral }) else { return }
        guard case .joining(let code) = lock.withLock({ intent }),
              let value,
              let greeting = try? JSONCoding.decoder.decode(Greeting.self, from: value),
              greeting.v == Greeting.version,
              greeting.fp == SessionKey.fingerprint(for: code, share: greeting.share)
        else { return reject(peripheral) }

        lock.withLock { isRedialling = false }
        let peer = Peer(seal: LinkSeal(role: .guest, code: code, share: greeting.share), now: scheduler.now)
        // Proved afresh on a greeting read again — the host's service back after its radio went
        // off and on — so one that was counted as there is not, until it is.
        let wasReady = lock.withLock { () -> Bool in
            defer { peers[peripheral] = peer }
            return peers[peripheral]?.isReady == true
        }
        if wasReady { reachabilityUpdates.yield(isReachable) }
        // Nothing left to look for. The connection carries its own reconnect from here — the
        // request handed to `connect` outlives the link — and a scan left running is a radio
        // kept awake for the length of a match.
        if lock.withLock({ centralSession != nil }) { radio.stopScan() }

        // Not ready yet. The host only learns of this peer when the subscription lands, and
        // anything written before that is answered "success" and dropped on the floor — so the
        // challenge waits for `notifying(_:on:)`, which the host has seen first.
        radio.subscribe(peripheral)
    }

    public func notifying(_ isNotifying: Bool, on peripheral: RadioPeer) {
        guard let peer = lock.withLock({ peers[peripheral] }) else { return }
        guard isNotifying else {
            // A subscription the host would not take is a link that will never carry anything
            // back. Hanging up is what puts the reconnect in motion.
            if lock.withLock({ centralSession != nil }) { radio.cancelConnection(peripheral) }
            return
        }
        guard lock.withLock({ !peer.isReady }), let challenge = lock.withLock({ peer.seal.challenge() }) else { return }
        enqueue(challenge, to: peer)
        awaitProof(from: peripheral, peer)
    }

    /// A host that agreed on the one byte of fingerprint by accident was told another code, and
    /// nothing it seals will ever open here. Held on to, it stopped the scan that would have found
    /// the right host, and a wrong code was never called one: it looked like a match found.
    private func awaitProof(from token: RadioPeer, _ peer: Peer) {
        scheduler.run(after: proofTimeout) { [weak self] in
            guard let self else { return }
            let (unproven, hasCentral, provedBefore) = self.lock.withLock { () -> (RadioPeer?, Bool, Bool) in
                guard self.peers[token] === peer, !peer.isReady,
                      let server = self.server, server == token else { return (nil, false, false) }
                return (server, self.centralSession != nil, self.hasProven)
            }
            guard let unproven else { return }
            if provedBefore {
                // Slow over a poor link, not somebody else's court: hung up on, so the reconnect
                // asks again.
                if hasCentral { self.radio.cancelConnection(unproven) }
            } else {
                // Said nothing in time, which a busy host does: let go of and looked for again,
                // never turned away. Only a refused key says it is another court.
                self.dropCandidate(unproven)
            }
        }
    }

    private func dropCandidate(_ peripheral: RadioPeer) {
        let hasCentral = lock.withLock { () -> Bool in
            peers.removeValue(forKey: peripheral)
            if server == peripheral {
                server = nil
                serverHasInbox = false
            }
            return centralSession != nil
        }
        guard hasCentral else { return }
        radio.cancelConnection(peripheral)
        radio.stopScan()
        radio.scan()
    }

    /// Somebody else's court: hung up on, and not dialled again for the rest of this join.
    ///
    /// The scan is started over rather than left running: whatever else was found while this one
    /// was being checked was reported once and dropped, and only a fresh scan says it again.
    private func reject(_ peripheral: RadioPeer) {
        let (hasCentral, refused) = lock.withLock { () -> (Bool, LinkID?) in
            rejected.insert(peripheral.address)
            let refused = peers.removeValue(forKey: peripheral).flatMap { $0.isReady ? $0.link : nil }
            if server == peripheral {
                server = nil
                serverHasInbox = false
            }
            return (centralSession != nil, refused)
        }
        if let refused { linkUpdates.yield(.down(refused, .refused)) }
        guard hasCentral else { return }
        radio.cancelConnection(peripheral)
        radio.stopScan()
        radio.scan()
    }
}
