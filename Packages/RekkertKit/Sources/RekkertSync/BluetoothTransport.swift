import Foundation
import RekkertCore

#if os(iOS) || os(watchOS)
import CoreBluetooth
import CryptoKit

/// The same match, over the one radio iOS will let an app keep open with the screen off.
///
/// `LocalNetworkTransport` is the better link by every measure except the one that matters on a
/// court: the system takes its listener and browser away the moment the app stops being in
/// front of somebody, so a phone in a pocket stops carrying the score. Bluetooth is slower and
/// fiddlier, and it keeps working — a connection survives backgrounding, the app is woken for
/// traffic on it, and a connect with no timeout is honoured until the peer comes back.
///
/// Deliberately the same star as the local network: the host advertises and the guests dial, so
/// `MatchStore` relays between them exactly as it already does. Both transports run at once and
/// a peer on both hears everything twice, which the log does not mind — merging is a union by
/// event id, so a duplicate costs bytes and nothing else.
///
/// The session code cannot travel in the advertisement. A backgrounded iOS peripheral drops its
/// local name and service data and moves its service UUIDs into an overflow area that is only
/// found by a central scanning for that exact UUID, so the service UUID is fixed and app-wide —
/// the direct counterpart of `_rekkert-score._tcp`. Deriving it from the code instead would be
/// worse than saying nothing: the code carries twenty bits, and a hash of it broadcast in the
/// clear is worked back to the code offline in seconds, which is the whole reason
/// `SessionKey.fingerprint` publishes eight bits and not more. So the code is checked after
/// connecting instead, against a greeting the host publishes, and every frame is sealed.
///
/// A watch builds only the guest half. watchOS lets an app dial a peripheral but never be one,
/// so a watch can reach a host's phone on its own and can never host.
nonisolated public final class BluetoothTransport: PeerTransport, @unchecked Sendable {
    /// Built on demand rather than stored: `CBUUID` is not `Sendable`, and a shared one would
    /// be a global with a lock's worth of doubt over it for no gain — these are four bytes of
    /// parsing each.
    public static var serviceUUID: CBUUID { CBUUID(string: "7B63F774-3D1F-4011-807E-85119A4CBAC8") }
    /// Read in the clear: which share this is, and one byte to tell it from the court next
    /// door. Neither is a secret — both already travel in the open in the Bonjour TXT record.
    private static var greetingUUID: CBUUID { CBUUID(string: "B5BA2B7E-A912-48FC-A3CB-92B18234753E") }
    /// Guest to host.
    private static var inboxUUID: CBUUID { CBUUID(string: "DF665064-97C0-42D0-9D34-3F2643B7C55B") }
    /// Host to guest.
    private static var outboxUUID: CBUUID { CBUUID(string: "ED139EC2-90FC-462C-B600-84F425782C1E") }

    /// What the host publishes about itself so a guest can work out whether it was told this
    /// code, and derive the key if it was.
    struct Greeting: Codable, Equatable {
        var v: Int
        var share: UUID
        var fp: String

        /// 2 since each way has its own key. A build on 1 cannot open anything sealed now, so
        /// the two refuse each other at the greeting rather than half-connecting.
        static let version = 2
    }

    public let inbound: AsyncStream<InboundPacket>
    public let reachability: AsyncStream<Bool>

    /// One peer's end of the conversation. Unchecked for the same reason `Link` is: every field
    /// is only ever touched under `lock`.
    private final class Peer: @unchecked Sendable {
        let reassembler = Chunking.Reassembler()
        /// Frames the link would not take yet. Bluetooth refuses rather than buffers, and a
        /// refused chunk that is dropped is a frame that will never open on the other side.
        var backlog: [Outgoing] = []
        /// Only once something it sealed has opened here. Anybody in range can connect and
        /// subscribe, and one byte of fingerprint agrees by accident now and again.
        var isReady = false
        /// This end's frames are sealed with one, the other end's opened with the other.
        var sealing: SymmetricKey?
        var opening: SymmetricKey?
        /// Guest side only. A write is answered before the next one goes out: CoreBluetooth
        /// will take more than it can carry and then drop the overflow, and a dropped chunk is
        /// a frame that never opens at the far end and a reply somebody waits the timeout out
        /// for. The host's side of the same problem is `updateValue` refusing, which it says so.
        var isWriting = false
        /// Only a host has one of these, and only to answer the right central.
        let central: CBCentral?

        init(central: CBCentral? = nil) { self.central = central }
    }

    /// Whole frames, so one nobody is waiting for any more can be dropped before its first
    /// chunk goes out, never halfway through, which would take the frame after it down too.
    private struct Outgoing {
        let chunks: [Data]
        var sent = 0
        let expires: DispatchTime?
    }

    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation

    private let queue = DispatchQueue(label: "dev.natten.rekkert.bluetooth")
    private let lock = NSLock()

    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var outbox: CBMutableCharacteristic?
    private var server: CBPeripheral?
    private var serverInbox: CBCharacteristic?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var waiting: [UInt32: ResumeOnce] = [:]
    private var nextCorrelation: UInt32 = 1
    private var intent: Intent = .none
    private var lastSnapshot: Data?
    /// Hosts that turned out to be somebody else's court. A scan reports each peripheral once,
    /// so one of these checked first would otherwise be checked again and again while the
    /// right one, found in the meantime, was dropped for being second.
    private var rejected: Set<UUID> = []
    /// When the host being dialled is let go of, unless it has proved itself by then.
    private var candidateDeadline: DispatchWorkItem?

    private enum Intent: Sendable {
        case none
        case hosting(code: SessionCode, share: UUID)
        case joining(SessionCode)
    }

    private let replyTimeout: DispatchTimeInterval
    /// How long a host that passed the greeting has to prove it holds the key.
    private let proofTimeout: DispatchTimeInterval
    /// How long a host that has only been found has to get as far as the greeting.
    private let candidateTimeout: DispatchTimeInterval
    /// What a write will carry when nothing better is known. `maximumWriteValueLength` is asked
    /// for the moment there is a peripheral to ask, and this only covers the gap before that.
    private static let conservativeMTU = 20

    private var shim: Shim?

    public init(replyTimeout: Int = 4, proofTimeout: Int = 10, candidateTimeout: Int = 15) {
        self.replyTimeout = .seconds(replyTimeout)
        self.proofTimeout = .seconds(proofTimeout)
        self.candidateTimeout = .seconds(candidateTimeout)

        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation

        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        reachabilityUpdates = reachabilityContinuation

        shim = Shim(self)
    }

    // MARK: - Opening and closing

    public func startHosting(code: SessionCode, share: UUID) {
        #if os(iOS)
        stop()
        lock.withLock { intent = .hosting(code: code, share: share) }
        let manager = CBPeripheralManager(delegate: shim, queue: queue, options: nil)
        lock.withLock { peripheralManager = manager }
        #endif
    }

    public func startJoining(code: SessionCode) {
        stop()
        lock.withLock { intent = .joining(code) }
        let manager = CBCentralManager(delegate: shim, queue: queue, options: nil)
        lock.withLock { centralManager = manager }
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
        let standing = lock.withLock { if case .joining = intent { true } else { false } }
        guard !standing else { return }
        startJoining(code: code)
    }

    public func stop() {
        let (peripheral, central, connected, pending, deadline) = lock.withLock {
            let values = (peripheralManager, centralManager, server, Array(waiting.values), candidateDeadline)
            candidateDeadline = nil
            peripheralManager = nil
            centralManager = nil
            outbox = nil
            server = nil
            serverInbox = nil
            peers = [:]
            waiting = [:]
            intent = .none
            lastSnapshot = nil
            rejected = []
            return values
        }
        deadline?.cancel()
        peripheral?.stopAdvertising()
        peripheral?.removeAllServices()
        central?.stopScan()
        if let connected { central?.cancelPeripheralConnection(connected) }
        for resume in pending { resume.resume(nil) }
        reachabilityUpdates.yield(false)
    }

    // MARK: - PeerTransport

    public func activate() {}

    public var isReachable: Bool {
        lock.withLock { peers.values.contains { $0.isReady } }
    }

    public var reachableCount: Int {
        lock.withLock { peers.values.count { $0.isReady } }
    }

    public func forgetSnapshot() {
        lock.withLock { lastSnapshot = nil }
    }

    public func sendLive(_ payload: Data) async -> Data? {
        let ready = lock.withLock { peers.values.filter(\.isReady) }
        guard !ready.isEmpty else { return nil }

        let replies = await withTaskGroup(of: Data?.self) { group in
            for peer in ready {
                group.addTask { await self.ask(payload, of: peer) }
            }
            var collected: [Data?] = []
            for await reply in group { collected.append(reply) }
            return collected
        }

        let folded = ReplyFold.fold(replies, expected: ready.count)
        for extra in folded.unsolicited { packets.yield(InboundPacket(payload: extra)) }
        return folded.acknowledgement
    }

    /// No durable queue out here, the same as the local network: a peer that is not connected
    /// simply is not there, and what stands in for a queue is the log itself — whoever comes
    /// back asks what they missed and is answered from it.
    public func queue(_ payload: Data) {
        broadcast(payload)
    }

    /// Kept, and handed to each peer as it arrives — and to nobody else.
    ///
    /// Deliberately not a broadcast, which is what the local network does with it. `MatchStore`
    /// publishes a whole log on every scoring change, and that is a sensible thing to push over
    /// a socket and a hopeless one to push over Bluetooth every second for two hours. The
    /// ordinary traffic here is the much smaller event deltas, with the hello and its version
    /// vector catching up anything that went missing.
    public func publishSnapshot(_ payload: Data) {
        lock.withLock { lastSnapshot = payload }
    }

    // MARK: - Talking

    private func ask(_ payload: Data, of peer: Peer) async -> Data? {
        let correlation = lock.withLock { () -> UInt32 in
            let value = nextCorrelation
            nextCorrelation &+= 1
            return value
        }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            lock.withLock { waiting[correlation] = once }
            send(Frame(kind: .request, correlation: correlation, payload: payload), to: peer)
            // Has to be shorter than `MatchStore`'s own six seconds, or the store gives up
            // first and the outbox is never acknowledged — which looks exactly like one-way
            // sync. Every child of the fan-out is waited on, so a quiet peer here is a pause
            // for everybody.
            queue.asyncAfter(deadline: .now() + replyTimeout) { [weak self] in
                self?.lock.withLock { _ = self?.waiting.removeValue(forKey: correlation) }
                once.resume(nil)
            }
        }
    }

    private func broadcast(_ payload: Data) {
        let ready = lock.withLock { peers.values.filter(\.isReady) }
        for peer in ready { send(Frame(kind: .oneway, payload: payload), to: peer) }
    }

    private func send(_ frame: Frame, to peer: Peer) {
        guard let key = lock.withLock({ peer.sealing }),
              let sealed = SealedFrame.seal(frame, with: key)
        else { return }

        let chunks = Chunking.split(sealed, mtu: mtu(for: peer))
        let expires: DispatchTime? = frame.kind == .oneway ? nil : .now() + replyTimeout
        lock.withLock { peer.backlog.append(Outgoing(chunks: chunks, expires: expires)) }
        // Drained on the one queue CoreBluetooth already calls back on, so a send from a reply
        // closure, a send from the store and the "ready again" callback never drain the same
        // backlog at once — two of them would put the same chunk on the air and skip the next.
        queue.async { [weak self] in self?.drain(peer) }
    }

    private func mtu(for peer: Peer) -> Int {
        if let central = peer.central {
            return central.maximumUpdateValueLength
        }
        if let server = lock.withLock({ self.server }) {
            // One packet's worth, though the write waits for its response: `.withResponse`
            // reports 512, and anything past one packet goes as a long write in pieces.
            return server.maximumWriteValueLength(for: .withoutResponse)
        }
        return Self.conservativeMTU
    }

    /// Bluetooth refuses rather than buffers, so a chunk it will not take has to be kept and
    /// offered again — dropping one is a frame that never opens on the other side and a reply
    /// somebody waits out the timeout for.
    private func drain(_ peer: Peer) {
        while true {
            let next = lock.withLock { () -> Data? in
                let now = DispatchTime.now()
                while let first = peer.backlog.first, first.sent == 0, let expires = first.expires, expires < now {
                    peer.backlog.removeFirst()
                }
                return peer.backlog.first.map { $0.chunks[$0.sent] }
            }
            guard let next else { return }
            guard deliver(next, to: peer) else { return }
            lock.withLock {
                guard !peer.backlog.isEmpty else { return }
                peer.backlog[0].sent += 1
                if peer.backlog[0].sent == peer.backlog[0].chunks.count { peer.backlog.removeFirst() }
            }
            // A guest may only have one write outstanding, so the acknowledgement is what
            // fetches the next chunk rather than this loop.
            if lock.withLock({ peer.isWriting }) { return }
        }
    }

    private func deliver(_ chunk: Data, to peer: Peer) -> Bool {
        if let central = peer.central {
            let (manager, characteristic) = lock.withLock { (peripheralManager, outbox) }
            guard let manager, let characteristic else { return false }
            return manager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central])
        }
        let (server, inbox) = lock.withLock { (self.server, serverInbox) }
        guard let server, let inbox else { return false }
        guard lock.withLock({ !peer.isWriting }) else { return false }
        lock.withLock { peer.isWriting = true }
        // With a response rather than without: the point of this link is that it goes on
        // working while nobody is watching, and an unacknowledged write is the one that goes
        // missing then.
        server.writeValue(chunk, for: inbox, type: .withResponse)
        return true
    }

    fileprivate func wroteChunk(to peripheral: CBPeripheral) {
        guard let peer = lock.withLock({ peers[ObjectIdentifier(peripheral)] }) else { return }
        lock.withLock { peer.isWriting = false }
        drain(peer)
    }

    private func drainEverybody() {
        for peer in lock.withLock({ Array(peers.values) }) { drain(peer) }
    }

    private func receive(_ chunk: Data, from peer: Peer) {
        let whole: Data?
        do {
            whole = try lock.withLock { try peer.reassembler.accept(chunk) }
        } catch {
            lock.withLock { peer.reassembler.reset() }
            return
        }
        guard let whole,
              let key = lock.withLock({ peer.opening }),
              let frame = SealedFrame.open(whole, with: key)
        else { return }

        // The first thing that opens is the proof this peer was given the same code. A host
        // answers it at once, so the guest has its proof whatever the store gets round to saying.
        if lock.withLock({ !peer.isReady }) {
            if peer.central != nil {
                ready(peer, opening: LinkReplies.opening(snapshot: lock.withLock { lastSnapshot }, probe: Self.probe))
            } else {
                ready(peer, opening: lock.withLock { lastSnapshot }.map { [Frame(kind: .oneway, payload: $0)] } ?? [])
                // The host, proven: from here a drop is a reconnect, which waits as long as it takes.
                lock.withLock { candidateDeadline }?.cancel()
            }
        }

        switch frame.kind {
        case .reply:
            if let pending = lock.withLock({ waiting.removeValue(forKey: frame.correlation) }) {
                pending.resume(frame.payload)
            } else if LinkReplies.isWorthHandingOn(late: frame.payload) {
                packets.yield(InboundPacket(payload: frame.payload))
            }
        case .request:
            let correlation = frame.correlation
            packets.yield(InboundPacket(payload: frame.payload) { [weak self, weak peer] answer in
                guard let self, let peer else { return }
                self.send(Frame(kind: .reply, correlation: correlation, payload: answer), to: peer)
            })
        case .oneway:
            guard !frame.payload.isEmpty else { return }
            packets.yield(InboundPacket(payload: frame.payload))
        }
    }

    /// Says nothing but that it was sealed with the key. An older build hands it on as a
    /// packet the store cannot read, and drops it.
    private static let probe = Frame(kind: .oneway, payload: Data())

    /// The snapshot is handed only to whoever has just turned up, which is the whole snapshot
    /// policy: a phone joining mid-match sees the score without a round trip, and nobody else
    /// pays for it.
    private func ready(_ peer: Peer, opening: [Frame]) {
        lock.withLock { peer.isReady = true }
        reachabilityUpdates.yield(true)
        for frame in opening { send(frame, to: peer) }
    }

    private func forget(_ token: ObjectIdentifier) {
        let peer = lock.withLock { peers.removeValue(forKey: token) }
        guard peer != nil else { return }
        reachabilityUpdates.yield(isReachable)
    }

    /// The radio switched off, Airplane mode, bluetoothd starting over: every connection goes with
    /// it, and CoreBluetooth says so once, here, rather than peer by peer. Everything about them
    /// is let go of — kept, a peer went on counting as there and a host still on the books kept
    /// the scan from ever finding it again — so the radio coming back starts afresh.
    private func lostTheRadio() {
        let (pending, deadline, hadPeers) = lock.withLock {
            let values = (Array(waiting.values), candidateDeadline, !peers.isEmpty)
            peers = [:]
            waiting = [:]
            server = nil
            serverInbox = nil
            candidateDeadline = nil
            rejected = []
            return values
        }
        deadline?.cancel()
        for resume in pending { resume.resume(nil) }
        if hadPeers { reachabilityUpdates.yield(false) }
    }

    // MARK: - Hosting

    fileprivate func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        #if os(iOS)
        guard manager.state == .poweredOn else { return lostTheRadio() }
        guard case .hosting = lock.withLock({ intent }) else { return }

        let greeting = CBMutableCharacteristic(
            type: Self.greetingUUID, properties: [.read], value: nil, permissions: [.readable]
        )
        let inbox = CBMutableCharacteristic(
            type: Self.inboxUUID, properties: [.write], value: nil, permissions: [.writeable]
        )
        let outbox = CBMutableCharacteristic(
            type: Self.outboxUUID, properties: [.notify], value: nil, permissions: [.readable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [greeting, inbox, outbox]

        lock.withLock { self.outbox = outbox }
        manager.removeAllServices()
        manager.add(service)
        // Only the service uuid: everything else is dropped from the advertisement the moment
        // the app is backgrounded, which is exactly when this link has to still be findable.
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
        #endif
    }

    fileprivate func answerGreeting(_ request: CBATTRequest, on manager: CBPeripheralManager) {
        guard case .hosting(let code, let share) = lock.withLock({ intent }),
              let body = try? JSONCoding.encoder.encode(Greeting(
                  v: Greeting.version, share: share, fp: SessionKey.fingerprint(for: code, share: share)
              ))
        else { return manager.respond(to: request, withResult: .attributeNotFound) }

        guard request.offset <= body.count else {
            return manager.respond(to: request, withResult: .invalidOffset)
        }
        request.value = body.subdata(in: request.offset ..< body.count)
        manager.respond(to: request, withResult: .success)
    }

    fileprivate func subscribed(_ central: CBCentral) {
        guard case .hosting(let code, let share) = lock.withLock({ intent }) else { return }
        let peer = Peer(central: central)
        peer.sealing = SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest)
        peer.opening = SessionKey.sealingKey(for: code, share: share, direction: .guestToHost)
        // Not ready until something it sent opens. Counted on subscribing, a central with the
        // wrong code — or any Bluetooth tool at all — was waited on by every send, answered
        // none of them, and kept the outbox from ever being acknowledged.
        lock.withLock { peers[ObjectIdentifier(central)] = peer }
    }

    fileprivate func unsubscribed(_ central: CBCentral) {
        forget(ObjectIdentifier(central))
    }

    fileprivate func wrote(_ requests: [CBATTRequest], on manager: CBPeripheralManager) {
        var writers: [Peer] = []
        var writes: [ObjectIdentifier: [(offset: Int, value: Data)]] = [:]
        for request in requests {
            guard let peer = lock.withLock({ peers[ObjectIdentifier(request.central)] }),
                  let value = request.value
            else { continue }
            let token = ObjectIdentifier(peer)
            if writes[token] == nil { writers.append(peer) }
            writes[token, default: []].append((request.offset, value))
        }
        for peer in writers {
            for chunk in Chunking.chunks(fromWrites: writes[ObjectIdentifier(peer)] ?? []) {
                receive(chunk, from: peer)
            }
        }
        if let first = requests.first { manager.respond(to: first, withResult: .success) }
    }

    fileprivate func readyToSendAgain() {
        drainEverybody()
    }

    // MARK: - Joining

    fileprivate func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        guard manager.state == .poweredOn else { return lostTheRadio() }
        guard case .joining = lock.withLock({ intent }) else { return }
        manager.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
    }

    fileprivate func discovered(_ peripheral: CBPeripheral, on manager: CBCentralManager) {
        guard lock.withLock({ server == nil && !rejected.contains(peripheral.identifier) }) else { return }
        lock.withLock { server = peripheral }
        peripheral.delegate = shim
        // No timeout, which is the reconnect: the system holds the request and wakes the app
        // when the peer comes back, whether that is thirty seconds or the rest of the set.
        manager.connect(peripheral, options: nil)
        letGoUnlessGreeted(ObjectIdentifier(peripheral))
    }

    /// No timeout is right for a host this has been on, and wrong for one it has only found:
    /// there is one place for a host, and one that walked off mid-connect, or never finished
    /// saying what it was, held it while the right one went unheard. Let go of rather than
    /// refused — it may be the right one, back in range — and the scan started over for the rest.
    ///
    /// A host that did get as far as the greeting is `awaitProof`'s to settle.
    private func letGoUnlessGreeted(_ token: ObjectIdentifier) {
        let deadline = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let (stale, manager) = self.lock.withLock { () -> (CBPeripheral?, CBCentralManager?) in
                guard let server = self.server, ObjectIdentifier(server) == token,
                      self.peers[token] == nil else { return (nil, nil) }
                self.server = nil
                self.serverInbox = nil
                return (server, self.centralManager)
            }
            guard let stale, let manager else { return }
            manager.cancelPeripheralConnection(stale)
            manager.stopScan()
            manager.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
        }
        let previous = lock.withLock { () -> DispatchWorkItem? in
            let previous = candidateDeadline
            candidateDeadline = deadline
            return previous
        }
        previous?.cancel()
        queue.asyncAfter(deadline: .now() + candidateTimeout, execute: deadline)
    }

    fileprivate func connected(_ peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    fileprivate func disconnected(_ peripheral: CBPeripheral, on manager: CBCentralManager) {
        forget(ObjectIdentifier(peripheral))
        let reconnects = lock.withLock { () -> Bool in
            guard server === peripheral else { return false }
            serverInbox = nil
            guard !rejected.contains(peripheral.identifier), case .joining = intent else {
                server = nil
                return false
            }
            return true
        }
        // Only the host being dialled. The hang-up after a wrong greeting lands here too, and so
        // does one let go of, and neither is a link to put back: dialled again, it would take the
        // place of whichever host is being dialled now.
        guard reconnects else { return }
        manager.connect(peripheral, options: nil)
    }

    fileprivate func discoveredServices(_ peripheral: CBPeripheral) {
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(
                [Self.greetingUUID, Self.inboxUUID, Self.outboxUUID], for: service
            )
        }
    }

    fileprivate func discoveredCharacteristics(_ service: CBService, on peripheral: CBPeripheral) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.greetingUUID: peripheral.readValue(for: characteristic)
            case Self.inboxUUID: lock.withLock { serverInbox = characteristic }
            default: break
            }
        }
    }

    fileprivate func updated(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral, failed: Bool) {
        switch characteristic.uuid {
        case Self.greetingUUID:
            // A read that failed says nothing about which court this is, and reading it as a wrong
            // greeting refused the host for the rest of the join. Hanging up is what reads it
            // again: the reconnect asks afresh, and one that never answers is let go of in time.
            guard !failed else {
                lock.withLock { centralManager }?.cancelPeripheralConnection(peripheral)
                return
            }
            greeted(characteristic.value, on: peripheral)
        case Self.outboxUUID:
            // The value is still the last one that arrived, and taking it again would put that
            // chunk into the message twice.
            guard !failed,
                  let peer = lock.withLock({ peers[ObjectIdentifier(peripheral)] }),
                  let value = characteristic.value
            else { return }
            receive(value, from: peer)
        default:
            break
        }
    }

    /// Where a wrong code is found out, and the only place it can be: the advertisement could
    /// not carry enough to tell, so the question is asked of the host itself. The fingerprint
    /// settles it cheaply, and the seal settles it for good — a peer that agreed on one byte
    /// by accident still cannot produce a frame this end will open.
    private func greeted(_ value: Data?, on peripheral: CBPeripheral) {
        guard case .joining(let code) = lock.withLock({ intent }),
              let value,
              let greeting = try? JSONCoding.decoder.decode(Greeting.self, from: value),
              greeting.v == Greeting.version,
              greeting.fp == SessionKey.fingerprint(for: code, share: greeting.share)
        else { return reject(peripheral) }

        let peer = Peer()
        peer.sealing = SessionKey.sealingKey(for: code, share: greeting.share, direction: .guestToHost)
        peer.opening = SessionKey.sealingKey(for: code, share: greeting.share, direction: .hostToGuest)
        lock.withLock { peers[ObjectIdentifier(peripheral)] = peer }
        // Nothing left to look for. The connection carries its own reconnect from here — the
        // request handed to `connect` outlives the link — and a scan left running is a radio
        // kept awake for the length of a match.
        lock.withLock { centralManager }?.stopScan()

        // Not ready yet. The host only learns of this peer when the subscription lands, and
        // anything written before that is answered "success" and dropped on the floor — so the
        // probe waits for `subscribed(to:on:)`, which the host has seen first.
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            for characteristic in service.characteristics ?? []
            where characteristic.uuid == Self.outboxUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    fileprivate func subscribed(to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        guard characteristic.uuid == Self.outboxUUID,
              let peer = lock.withLock({ peers[ObjectIdentifier(peripheral)] })
        else { return }
        guard characteristic.isNotifying else {
            // A subscription the host would not take is a link that will never carry anything
            // back. Hanging up is what puts the reconnect in motion.
            lock.withLock { centralManager }?.cancelPeripheralConnection(peripheral)
            return
        }
        guard lock.withLock({ !peer.isReady }) else { return }
        send(Self.probe, to: peer)
        awaitProof(from: ObjectIdentifier(peripheral), peer)
    }

    /// A host that agreed on the one byte of fingerprint by accident was told another code, and
    /// nothing it seals will ever open here. Held on to, it stopped the scan that would have found
    /// the right host, and a wrong code was never called one: it looked like a match found.
    private func awaitProof(from token: ObjectIdentifier, _ peer: Peer) {
        queue.asyncAfter(deadline: .now() + proofTimeout) { [weak self] in
            guard let self else { return }
            let unproven = self.lock.withLock { () -> CBPeripheral? in
                guard self.peers[token] === peer, !peer.isReady,
                      let server = self.server, ObjectIdentifier(server) == token else { return nil }
                return server
            }
            if let unproven { self.reject(unproven) }
        }
    }

    /// Somebody else's court: hung up on, and not dialled again for the rest of this join.
    ///
    /// The scan is started over rather than left running: whatever else was found while this one
    /// was being checked was reported once and dropped, and only a fresh scan says it again.
    private func reject(_ peripheral: CBPeripheral) {
        let manager = lock.withLock { () -> CBCentralManager? in
            rejected.insert(peripheral.identifier)
            peers.removeValue(forKey: ObjectIdentifier(peripheral))
            if server === peripheral {
                server = nil
                serverInbox = nil
            }
            return centralManager
        }
        manager?.cancelPeripheralConnection(peripheral)
        manager?.stopScan()
        manager?.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
    }
}

/// The delegate, kept apart from the transport the way `WCShim` is: CoreBluetooth wants an
/// `NSObject` and calls back on the queue it was handed, and the transport itself has no
/// business being either.
nonisolated private final class Shim: NSObject, CBPeripheralManagerDelegate,
                                      CBCentralManagerDelegate, CBPeripheralDelegate,
                                      @unchecked Sendable {
    private weak var transport: BluetoothTransport?

    init(_ transport: BluetoothTransport) {
        self.transport = transport
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        transport?.peripheralManagerDidUpdateState(peripheral)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        transport?.answerGreeting(request, on: peripheral)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        transport?.wrote(requests, on: peripheral)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        transport?.subscribed(central)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        transport?.unsubscribed(central)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        transport?.readyToSendAgain()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        transport?.centralManagerDidUpdateState(central)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        transport?.discovered(peripheral, on: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        transport?.connected(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        transport?.disconnected(peripheral, on: central)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        transport?.disconnected(peripheral, on: central)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        transport?.discoveredServices(peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        transport?.discoveredCharacteristics(service, on: peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        transport?.updated(characteristic, on: peripheral, failed: error != nil)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        transport?.wroteChunk(to: peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        transport?.subscribed(to: characteristic, on: peripheral)
    }
}

#else

/// Not built on macOS, which is here so the tests run without a simulator. The type still
/// exists so nothing above it needs an `#if`.
nonisolated public final class BluetoothTransport: PeerTransport, @unchecked Sendable {
    public let inbound = AsyncStream<InboundPacket> { $0.finish() }
    public let reachability = AsyncStream<Bool> { $0.finish() }

    public init(replyTimeout: Int = 4, proofTimeout: Int = 10, candidateTimeout: Int = 15) {}

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
