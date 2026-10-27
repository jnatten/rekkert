import Foundation
import RekkertCore

#if os(iOS) || os(watchOS)
import CoreBluetooth

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

    private let core: RadioCore
    private let radio: CoreBluetoothRadio

    public init(replyTimeout: Int = 4, proofTimeout: Int = 10, candidateTimeout: Int = 15) {
        radio = CoreBluetoothRadio()
        core = RadioCore(
            radio: radio,
            replyTimeout: replyTimeout, proofTimeout: proofTimeout, candidateTimeout: candidateTimeout
        )
    }

    /// The system ran the app again to hand back a link it had been keeping.
    public var onRestored: (@Sendable () -> Void)? {
        get { radio.onRestored }
        set { radio.onRestored = newValue }
    }

    public var inbound: AsyncStream<InboundPacket> { core.inbound }
    public var reachability: AsyncStream<Bool> { core.reachability }
    public var linkChanges: AsyncStream<LinkChange> { core.linkChanges }
    public var availabilityChanges: AsyncStream<RadioAvailability> { core.availabilityChanges }
    public var links: [LinkID] { core.links }
    public func sendLive(_ payload: Data, on link: LinkID) async -> Data? { await core.sendLive(payload, on: link) }
    public func refuse(_ link: LinkID) { core.refuse(link) }

    public func startHosting(code: SessionCode, share: UUID) { core.startHosting(code: code, share: share) }
    public func startJoining(code: SessionCode) { core.startJoining(code: code) }
    public func resumeHosting(code: SessionCode, share: UUID) { core.resumeHosting(code: code, share: share) }
    public func resumeJoining(code: SessionCode) { core.resumeJoining(code: code) }
    public func stop() { core.stop() }
    public var availability: RadioAvailability { core.availability }

    public func activate() {}
    public var isReachable: Bool { core.isReachable }
    public var reachableCount: Int { core.reachableCount }
    public func sendLive(_ payload: Data) async -> Data? { await core.sendLive(payload) }
    public func queue(_ payload: Data) { core.queue(payload) }
    public func publishSnapshot(_ payload: Data) { core.publishSnapshot(payload) }
    public func forgetSnapshot() { core.forgetSnapshot() }
}

nonisolated private struct DispatchScheduler: RadioScheduler {
    let queue: DispatchQueue
    private let start = ContinuousClock.now

    var now: Duration { start.duration(to: .now) }

    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    func run(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> any RadioTimer {
        let item = DispatchWorkItem(block: work)
        let (seconds, attoseconds) = delay.components
        let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
        queue.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds), execute: item)
        return DispatchTimer(item: item)
    }
}

nonisolated private struct DispatchTimer: RadioTimer, @unchecked Sendable {
    let item: DispatchWorkItem
    func cancel() { item.cancel() }
}

/// The delegate, kept apart from the transport the way `WCShim` is: CoreBluetooth wants an
/// `NSObject` and calls back on the queue it was handed, and the transport itself has no
/// business being either.
nonisolated private final class CoreBluetoothRadio: NSObject, Radio,
                                                    CBPeripheralManagerDelegate, CBCentralManagerDelegate,
                                                    CBPeripheralDelegate, @unchecked Sendable {
    private static var serviceUUID: CBUUID { BluetoothTransport.serviceUUID }
    /// Read in the clear: which share this is, and one byte to tell it from the court next
    /// door. Neither is a secret — both already travel in the open in the Bonjour TXT record.
    private static var greetingUUID: CBUUID { CBUUID(string: "B5BA2B7E-A912-48FC-A3CB-92B18234753E") }
    /// Guest to host.
    private static var inboxUUID: CBUUID { CBUUID(string: "DF665064-97C0-42D0-9D34-3F2643B7C55B") }
    /// Host to guest.
    private static var outboxUUID: CBUUID { CBUUID(string: "ED139EC2-90FC-462C-B600-84F425782C1E") }
    private static let unknownMaximum = 20
    /// The system keeps advertising, the published service and pending connections under these
    /// after it ends the app, and launches the app again when somebody uses them.
    private static let hostRestoration = "dev.natten.rekkert.bluetooth.host"
    private static let guestRestoration = "dev.natten.rekkert.bluetooth.guest"

    private let queue = DispatchQueue(label: "dev.natten.rekkert.bluetooth")
    let scheduler: any RadioScheduler
    private let lock = NSLock()

    private weak var listener: (any RadioListener)?
    private var peripheralManager: (manager: CBPeripheralManager, session: Int)?
    private var centralManager: (manager: CBCentralManager, session: Int)?
    private var outbox: CBMutableCharacteristic?
    private var centrals: [ObjectIdentifier: CBCentral] = [:]
    private var peripherals: [ObjectIdentifier: CBPeripheral] = [:]
    private var inboxes: [ObjectIdentifier: CBCharacteristic] = [:]
    private var restoredPeripherals: [CBPeripheral] = []
    private var _onRestored: (@Sendable () -> Void)?

    var onRestored: (@Sendable () -> Void)? {
        get { lock.withLock { _onRestored } }
        set { lock.withLock { _onRestored = newValue } }
    }

    override init() {
        scheduler = DispatchScheduler(queue: queue)
        super.init()
    }

    var canHost: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    func attach(_ listener: any RadioListener) {
        lock.withLock { self.listener = listener }
    }

    private var events: (any RadioListener)? { lock.withLock { listener } }

    // MARK: - Hosting

    func openPeripheral(session: Int) {
        #if os(iOS)
        let manager = CBPeripheralManager(
            delegate: self, queue: queue,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.hostRestoration]
        )
        lock.withLock { peripheralManager = (manager, session) }
        #endif
    }

    func publish() {
        #if os(iOS)
        guard let manager = lock.withLock({ peripheralManager?.manager }) else { return }
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

    func closePeripheral() {
        let manager = lock.withLock { () -> CBPeripheralManager? in
            defer {
                peripheralManager = nil
                outbox = nil
                centrals = [:]
            }
            return peripheralManager?.manager
        }
        manager?.stopAdvertising()
        manager?.removeAllServices()
    }

    func update(_ chunk: Data, to central: RadioPeer) -> Bool {
        let (manager, characteristic, target) = lock.withLock {
            (peripheralManager?.manager, outbox, centrals[central.key])
        }
        guard let manager, let characteristic, let target else { return false }
        return manager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [target])
    }

    func maximumUpdate(for central: RadioPeer) -> Int {
        lock.withLock { centrals[central.key] }?.maximumUpdateValueLength ?? Self.unknownMaximum
    }

    private func session(of manager: CBPeripheralManager) -> Int {
        lock.withLock { peripheralManager.flatMap { $0.manager === manager ? $0.session : nil } ?? -1 }
    }

    private func remember(_ central: CBCentral) -> RadioPeer {
        let peer = RadioPeer(key: ObjectIdentifier(central), address: central.identifier)
        lock.withLock { centrals[peer.key] = central }
        return peer
    }

    private static func availability(_ state: CBManagerState) -> RadioAvailability {
        switch state {
        case .poweredOn: .on
        case .poweredOff: .off
        case .unauthorized: .denied
        default: .unknown
        }
    }

    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        events?.peripheralState(Self.availability(manager.state), session: session(of: manager))
    }

    /// Nothing to take over: publishing again replaces the service the system kept, and the
    /// guests on it reconnect and prove themselves to this process afresh.
    func peripheralManager(_ manager: CBPeripheralManager, willRestoreState state: [String: Any]) {
        onRestored?()
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard let body = events?.greeting(session: session(of: manager)) else {
            return manager.respond(to: request, withResult: .attributeNotFound)
        }
        guard request.offset <= body.count else {
            return manager.respond(to: request, withResult: .invalidOffset)
        }
        request.value = body.subdata(in: request.offset ..< body.count)
        manager.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        let writes = requests.compactMap { request -> (central: RadioPeer, offset: Int, value: Data)? in
            guard let value = request.value else { return nil }
            return (remember(request.central), request.offset, value)
        }
        let current = events?.received(writes: writes, session: session(of: manager)) ?? false
        if let first = requests.first { manager.respond(to: first, withResult: current ? .success : .attributeNotFound) }
    }

    func peripheralManager(
        _ manager: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        events?.subscribed(remember(central), session: session(of: manager))
    }

    func peripheralManager(
        _ manager: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        let peer = RadioPeer(key: ObjectIdentifier(central), address: central.identifier)
        events?.unsubscribed(peer)
        lock.withLock { _ = centrals.removeValue(forKey: peer.key) }
    }

    func peripheralManagerIsReady(toUpdateSubscribers manager: CBPeripheralManager) {
        events?.readyToUpdate()
    }

    // MARK: - Joining

    func openCentral(session: Int) {
        #if os(iOS)
        let options: [String: Any]? = [CBCentralManagerOptionRestoreIdentifierKey: Self.guestRestoration]
        #else
        let options: [String: Any]? = nil
        #endif
        let manager = CBCentralManager(delegate: self, queue: queue, options: options)
        lock.withLock { centralManager = (manager, session) }
    }

    func closeCentral() {
        lock.withLock {
            centralManager = nil
            peripherals = [:]
            inboxes = [:]
            restoredPeripherals = []
        }
    }

    func scan() {
        lock.withLock { centralManager?.manager }?.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
    }

    func stopScan() {
        lock.withLock { centralManager?.manager }?.stopScan()
    }

    func connect(_ peripheral: RadioPeer) {
        let (manager, target) = lock.withLock { (centralManager?.manager, peripherals[peripheral.key]) }
        guard let manager, let target else { return }
        target.delegate = self
        manager.connect(target, options: nil)
    }

    func cancelConnection(_ peripheral: RadioPeer) {
        let (manager, target) = lock.withLock { (centralManager?.manager, peripherals[peripheral.key]) }
        guard let manager, let target else { return }
        manager.cancelPeripheralConnection(target)
    }

    func isConnected(_ peripheral: RadioPeer) -> Bool {
        lock.withLock { peripherals[peripheral.key] }?.state == .connected
    }

    func discover(_ peripheral: RadioPeer) {
        lock.withLock { peripherals[peripheral.key] }?.discoverServices([Self.serviceUUID])
    }

    func subscribe(_ peripheral: RadioPeer) {
        guard let target = lock.withLock({ peripherals[peripheral.key] }) else { return }
        for service in target.services ?? [] where service.uuid == Self.serviceUUID {
            for characteristic in service.characteristics ?? []
            where characteristic.uuid == Self.outboxUUID {
                target.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func write(_ chunk: Data, to peripheral: RadioPeer) {
        let (target, inbox) = lock.withLock { (peripherals[peripheral.key], inboxes[peripheral.key]) }
        guard let target, let inbox else { return }
        // With a response rather than without: the point of this link is that it goes on
        // working while nobody is watching, and an unacknowledged write is the one that goes
        // missing then.
        target.writeValue(chunk, for: inbox, type: .withResponse)
    }

    func maximumWrite(for peripheral: RadioPeer) -> Int {
        lock.withLock { peripherals[peripheral.key] }?.maximumWriteValueLength(for: .withoutResponse) ?? Self.unknownMaximum
    }

    private func session(of manager: CBCentralManager) -> Int {
        lock.withLock { centralManager.flatMap { $0.manager === manager ? $0.session : nil } ?? -1 }
    }

    private func remember(_ peripheral: CBPeripheral) -> RadioPeer {
        let peer = RadioPeer(key: ObjectIdentifier(peripheral), address: peripheral.identifier)
        lock.withLock { peripherals[peer.key] = peripheral }
        return peer
    }

    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        let session = session(of: manager)
        events?.centralState(Self.availability(manager.state), session: session)
        guard manager.state == .poweredOn else { return }
        // A host the system kept this app connected to while it was ended is not found by a scan
        // again, so it is handed over as found.
        let kept = lock.withLock { () -> [CBPeripheral] in
            defer { restoredPeripherals = [] }
            return restoredPeripherals
        }
        let connected = manager.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
        var seen = Set<ObjectIdentifier>()
        for peripheral in kept + connected where seen.insert(ObjectIdentifier(peripheral)).inserted {
            events?.discovered(remember(peripheral), session: session)
        }
    }

    #if os(iOS)
    func centralManager(_ manager: CBCentralManager, willRestoreState state: [String: Any]) {
        let kept = state[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        lock.withLock { restoredPeripherals = kept }
        onRestored?()
    }
    #endif

    func centralManager(
        _ manager: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        events?.discovered(remember(peripheral), session: session(of: manager))
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let session = session(of: manager)
        guard session != -1 else { return manager.cancelPeripheralConnection(peripheral) }
        events?.connected(remember(peripheral), session: session)
    }

    func centralManager(
        _ manager: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        events?.disconnected(remember(peripheral), failed: false, session: session(of: manager))
    }

    func centralManager(
        _ manager: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        events?.disconnected(remember(peripheral), failed: true, session: session(of: manager))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(
                [Self.greetingUUID, Self.inboxUUID, Self.outboxUUID], for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        let peer = remember(peripheral)
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.greetingUUID:
                peripheral.readValue(for: characteristic)
            case Self.inboxUUID:
                lock.withLock { inboxes[peer.key] = characteristic }
                events?.foundInbox(on: peer)
            default:
                break
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        let peer = remember(peripheral)
        switch characteristic.uuid {
        case Self.greetingUUID:
            events?.greeted(characteristic.value, failed: error != nil, by: peer)
        case Self.outboxUUID:
            guard error == nil, let value = characteristic.value else { return }
            events?.received(value, from: peer)
        default:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        events?.wrote(to: remember(peripheral), failed: error != nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        let peer = remember(peripheral)
        let invalidatedOurs = invalidatedServices.contains { $0.uuid == Self.serviceUUID }
        if invalidatedOurs { lock.withLock { _ = inboxes.removeValue(forKey: peer.key) } }
        events?.servicesChanged(on: peer, invalidatedOurs: invalidatedOurs)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == Self.outboxUUID else { return }
        events?.notifying(characteristic.isNotifying, on: remember(peripheral))
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
