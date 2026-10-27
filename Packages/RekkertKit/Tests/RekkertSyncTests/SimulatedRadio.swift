import Foundation
@testable import RekkertSync

/// The air between simulated devices: who is in range, how fast a host's transmit queue empties,
/// and what an app being suspended or ended does to the links it holds.
///
/// Every event reaches a radio's listener through the clock, never from inside a call, so the
/// order things happen in is the order the clock runs them.
nonisolated final class Airwaves: @unchecked Sendable {
    struct Settings {
        var latency: Duration = .milliseconds(30)
        /// Shared by everything one host sends, and by everything one guest writes.
        var bytesPerSecond = 4_000
        /// How many chunks a host's queue holds before `update` refuses.
        var queueSlots = 8
        /// How many slots have to come free before the host is told it may send again.
        var slotsPerReady = 1
        var maximumChunk = 182
        var connectionLimit = Int.max
        /// The share of host-to-guest chunks that never arrive.
        var loss = 0.0
        /// Whether a guest scanning with its screen off finds a host advertising from the background.
        var findsBackgroundedHostsInBackground = true
    }

    let clock: TestClock
    private let lock = NSLock()
    private var _settings: Settings
    private final class Weak {
        weak var radio: SimulatedRadio?
        init(_ radio: SimulatedRadio) { self.radio = radio }
    }
    private var tuned: [Weak] = []
    private var radios: [SimulatedRadio] { tuned.compactMap(\.radio) }
    private var connections: [Connection] = []
    private var random = SplitMix(seed: 0x5EED)

    init(clock: TestClock = TestClock(), settings: Settings = Settings()) {
        self.clock = clock
        _settings = settings
    }

    var settings: Settings {
        get { lock.withLock { _settings } }
        set { lock.withLock { _settings = newValue } }
    }

    func radio(canHost: Bool = true) -> SimulatedRadio {
        let radio = SimulatedRadio(air: self, canHost: canHost)
        lock.withLock { tuned.append(Weak(radio)) }
        return radio
    }

    // MARK: - Links

    final class Connection: @unchecked Sendable {
        let host: SimulatedRadio
        let guest: SimulatedRadio
        let hostAddress: UUID
        let central: RadioPeer
        let peripheral: RadioPeer
        var isConnected = false
        var isSubscribed = false
        var guestWriteBusyUntil: Duration = .zero

        init(host: SimulatedRadio, guest: SimulatedRadio, hostAddress: UUID, central: RadioPeer, peripheral: RadioPeer) {
            self.host = host
            self.guest = guest
            self.hostAddress = hostAddress
            self.central = central
            self.peripheral = peripheral
        }
    }

    private struct Transmission {
        let chunk: Data
        let connection: Connection
    }

    private var transmitting: [ObjectIdentifier: [Transmission]] = [:]
    private var freedSinceRefusal: [ObjectIdentifier: Int] = [:]
    private var refused: Set<ObjectIdentifier> = []
    private var delivered: [ObjectIdentifier: Int] = [:]

    /// Everything a host has got through to `radio` so far, in bytes.
    func bytesDelivered(to radio: SimulatedRadio) -> Int {
        lock.withLock { delivered[ObjectIdentifier(radio), default: 0] }
    }

    private func canTalk(_ one: SimulatedRadio, _ other: SimulatedRadio) -> Bool {
        one.isAlive && other.isAlive && one.isInRange && other.isInRange && one.isRadioOn && other.isRadioOn
    }

    private func airtime(_ bytes: Int) -> Duration {
        .nanoseconds(Int64(bytes) * 1_000_000_000 / Int64(max(1, settings.bytesPerSecond)))
    }

    private func connection(guest: SimulatedRadio, peripheral: RadioPeer) -> Connection? {
        lock.withLock { connections.first { $0.guest === guest && $0.peripheral == peripheral } }
    }

    private func connection(host: SimulatedRadio, central: RadioPeer) -> Connection? {
        lock.withLock { connections.first { $0.host === host && $0.central == central && $0.isConnected } }
    }

    // MARK: - Advertising and scanning

    func advertisingChanged(_ host: SimulatedRadio) {
        for guest in lock.withLock({ radios }) where guest.isScanning { offerHosts(to: guest) }
        completePendingConnects()
    }

    func offerHosts(to guest: SimulatedRadio) {
        let findsBackgrounded = settings.findsBackgroundedHostsInBackground
        for host in lock.withLock({ radios }) where host !== guest && host.isAdvertising && canTalk(host, guest) {
            if !findsBackgrounded, host.isBackgrounded, guest.isBackgrounded { continue }
            guest.found(hostAt: host.address)
        }
    }

    // MARK: - Connecting

    private var pending: [(guest: SimulatedRadio, peripheral: RadioPeer)] = []

    /// A connect with no timeout, which CoreBluetooth holds until the peer is there to take it.
    func connect(_ guest: SimulatedRadio, to peripheral: RadioPeer) {
        lock.withLock {
            let asked = connections.contains { $0.guest === guest && $0.peripheral == peripheral }
                || pending.contains { $0.guest === guest && $0.peripheral == peripheral }
            if !asked { pending.append((guest, peripheral)) }
        }
        completePendingConnects()
    }

    func forgetPending(of guest: SimulatedRadio) {
        lock.withLock { pending.removeAll { $0.guest === guest } }
    }

    /// Connects whatever has been asked for and can be now: the host is advertising at the
    /// address the guest dialled, both are in range, and the host has room.
    func completePendingConnects() {
        let hosts = lock.withLock { radios }
        let found = lock.withLock { () -> [(SimulatedRadio, SimulatedRadio, RadioPeer)] in
            var found: [(SimulatedRadio, SimulatedRadio, RadioPeer)] = []
            pending.removeAll { request in
                guard let host = hosts.first(where: { $0 !== request.guest && $0.address == request.peripheral.address })
                else { return false }
                found.append((host, request.guest, request.peripheral))
                return true
            }
            return found
        }
        for (host, guest, peripheral) in found {
            let connection = Connection(
                host: host, guest: guest, hostAddress: peripheral.address,
                central: host.centralHandle(for: guest), peripheral: peripheral
            )
            lock.withLock { connections.append(connection) }
        }
        let limit = settings.connectionLimit
        let ready = lock.withLock { () -> [Connection] in
            var made: [Connection] = []
            for connection in connections where !connection.isConnected {
                let host = connection.host
                guard host.address == connection.hostAddress, host.isAdvertising,
                      canTalk(host, connection.guest) else { continue }
                let held = connections.count { $0.host === host && $0.isConnected }
                guard held < limit else { continue }
                connection.isConnected = true
                made.append(connection)
            }
            return made
        }
        let latency = settings.latency
        for connection in ready {
            let session = connection.guest.centralSession
            clock.run(after: latency) {
                connection.guest.tell { $0.connected(connection.peripheral, session: session ?? -1) }
            }
        }
    }

    func cancel(_ guest: SimulatedRadio, _ peripheral: RadioPeer) {
        lock.withLock { pending.removeAll { $0.guest === guest && $0.peripheral == peripheral } }
        guard let connection = connection(guest: guest, peripheral: peripheral) else { return }
        drop(connection, guestFailed: false)
    }

    /// Takes a link down, and tells both ends the way CoreBluetooth would: the guest that its
    /// peripheral went, the host that its central unsubscribed.
    func drop(_ connection: Connection, guestFailed: Bool) {
        let (wasConnected, wasSubscribed) = lock.withLock { () -> (Bool, Bool) in
            connections.removeAll { $0 === connection }
            defer {
                connection.isConnected = false
                connection.isSubscribed = false
            }
            return (connection.isConnected, connection.isSubscribed)
        }
        let session = connection.guest.centralSession
        clock.run {
            if wasConnected || guestFailed {
                connection.guest.tell { $0.disconnected(connection.peripheral, failed: !wasConnected, session: session ?? -1) }
            }
            if wasSubscribed { connection.host.tell { $0.unsubscribed(connection.central) } }
        }
        // A connect with no timeout outlives the link: CoreBluetooth holds the request until the
        // peer is back, which is what the core relies on for its reconnect.
    }

    func dropAll(involving radio: SimulatedRadio) {
        let affected = lock.withLock { connections.filter { $0.host === radio || $0.guest === radio } }
        for connection in affected { drop(connection, guestFailed: false) }
    }

    func isConnected(_ guest: SimulatedRadio, _ peripheral: RadioPeer) -> Bool {
        lock.withLock { connections.contains { $0.guest === guest && $0.peripheral == peripheral && $0.isConnected } }
    }

    // MARK: - The service

    func discover(_ guest: SimulatedRadio, _ peripheral: RadioPeer) {
        guard let connection = connection(guest: guest, peripheral: peripheral), connection.isConnected else { return }
        let host = connection.host
        clock.run(after: settings.latency) {
            guard connection.isConnected, host.isPublished else { return }
            guest.tell { $0.foundInbox(on: peripheral) }
            let value = host.listener?.greeting(session: host.peripheralSession ?? -1)
            guest.tell { $0.greeted(value, failed: value == nil, by: peripheral) }
        }
    }

    func subscribe(_ guest: SimulatedRadio, _ peripheral: RadioPeer) {
        guard let connection = connection(guest: guest, peripheral: peripheral), connection.isConnected else { return }
        let host = connection.host
        clock.run(after: settings.latency) {
            guard connection.isConnected else { return }
            self.lock.withLock { connection.isSubscribed = true }
            host.tell { $0.subscribed(connection.central, session: host.peripheralSession ?? -1) }
            guest.tell { $0.notifying(true, on: peripheral) }
        }
    }

    // MARK: - Moving bytes

    func update(_ host: SimulatedRadio, _ chunk: Data, to central: RadioPeer) -> Bool {
        guard let connection = connection(host: host, central: central), connection.isSubscribed else { return false }
        let token = ObjectIdentifier(host)
        let slots = settings.queueSlots
        let (accepted, startsNow) = lock.withLock { () -> (Bool, Bool) in
            var queue = transmitting[token, default: []]
            guard queue.count < slots else {
                refused.insert(token)
                freedSinceRefusal[token] = 0
                return (false, false)
            }
            queue.append(Transmission(chunk: chunk, connection: connection))
            transmitting[token] = queue
            return (true, queue.count == 1)
        }
        if startsNow { transmitNext(from: host) }
        return accepted
    }

    private func transmitNext(from host: SimulatedRadio) {
        let token = ObjectIdentifier(host)
        guard let head = lock.withLock({ transmitting[token]?.first }) else { return }
        clock.run(after: airtime(head.chunk.count)) {
            let (freedEnough, latency, lost) = self.lock.withLock { () -> (Bool, Duration, Bool) in
                if !(self.transmitting[token]?.isEmpty ?? true) { self.transmitting[token]?.removeFirst() }
                var freedEnough = false
                if self.refused.contains(token) {
                    self.freedSinceRefusal[token, default: 0] += 1
                    if self.freedSinceRefusal[token, default: 0] >= self._settings.slotsPerReady {
                        self.refused.remove(token)
                        freedEnough = true
                    }
                }
                let lost = self.random.next() < self._settings.loss || head.connection.guest.missesIncoming
                return (freedEnough, self._settings.latency, lost)
            }
            let connection = head.connection
            if !lost {
                self.clock.run(after: latency) {
                    guard connection.isConnected, connection.isSubscribed else { return }
                    self.lock.withLock { self.delivered[ObjectIdentifier(connection.guest), default: 0] += head.chunk.count }
                    connection.guest.tell { $0.received(head.chunk, from: connection.peripheral) }
                }
            }
            if freedEnough { host.tell { $0.readyToUpdate() } }
            self.transmitNext(from: host)
        }
    }

    func write(_ guest: SimulatedRadio, _ chunk: Data, to peripheral: RadioPeer) {
        guard let connection = connection(guest: guest, peripheral: peripheral), connection.isConnected else {
            clock.run { guest.tell { $0.wrote(to: peripheral, failed: true) } }
            return
        }
        let (latency, airtime) = (settings.latency, airtime(chunk.count))
        let arrives = lock.withLock { () -> Duration in
            let start = max(clock.now, connection.guestWriteBusyUntil)
            connection.guestWriteBusyUntil = start + airtime
            return connection.guestWriteBusyUntil + latency
        }
        let host = connection.host
        let goesMissing = guest.losesWrites
        clock.run(after: arrives - clock.now) {
            guard connection.isConnected else {
                return guest.tell { $0.wrote(to: peripheral, failed: true) }
            }
            guard !goesMissing else {
                return guest.tell { $0.wrote(to: peripheral, failed: false) }
            }
            let accepted = host.listener?.received(
                writes: [(central: connection.central, offset: 0, value: chunk)],
                session: host.peripheralSession ?? -1
            ) ?? false
            self.clock.run(after: latency) { guest.tell { $0.wrote(to: peripheral, failed: !accepted) } }
        }
    }
}

/// One device's radio on the `Airwaves`.
nonisolated final class SimulatedRadio: Radio, @unchecked Sendable {
    private final class Handle {}

    let air: Airwaves
    let canHost: Bool
    var scheduler: any RadioScheduler { air.clock }

    private let lock = NSLock()
    private weak var _listener: (any RadioListener)?
    private var _address = UUID()
    private var _peripheralSession: Int?
    private var _centralSession: Int?
    private var _isPublished = false
    private var _isScanning = false
    private var _availability = RadioAvailability.on
    private var _isInRange = true
    private var _isSuspended = false
    private var _isAlive = true
    private var _isBackgrounded = false
    private var _losesWrites = false
    private var _missesIncoming = false
    private var held: [@Sendable () -> Void] = []
    private var reported: Set<UUID> = []
    private var handles: [UUID: Handle] = [:]
    private var centralHandles: [ObjectIdentifier: Handle] = [:]

    init(air: Airwaves, canHost: Bool) {
        self.air = air
        self.canHost = canHost
    }

    var listener: (any RadioListener)? { lock.withLock { _listener } }
    var address: UUID { lock.withLock { _address } }
    var peripheralSession: Int? { lock.withLock { _peripheralSession } }
    var centralSession: Int? { lock.withLock { _centralSession } }
    var isPublished: Bool { lock.withLock { _isPublished } }
    var isAdvertising: Bool { lock.withLock { _isPublished && _isAlive } }
    var isScanning: Bool { lock.withLock { _isScanning } }
    var isRadioOn: Bool { lock.withLock { _availability == .on } }
    var availability: RadioAvailability { lock.withLock { _availability } }
    var isInRange: Bool { lock.withLock { _isInRange } }
    var isAlive: Bool { lock.withLock { _isAlive } }
    var isBackgrounded: Bool { lock.withLock { _isBackgrounded } }
    /// Writes that report success and never arrive: a link that stays up while what this end
    /// says on it goes nowhere.
    var losesWrites: Bool {
        get { lock.withLock { _losesWrites } }
        set { lock.withLock { _losesWrites = newValue } }
    }
    /// Whatever a host sends this device never arrives, while the link stays up.
    var missesIncoming: Bool {
        get { lock.withLock { _missesIncoming } }
        set { lock.withLock { _missesIncoming = newValue } }
    }

    /// Hands an event to the listener through the clock, or keeps it while the app is suspended.
    func tell(_ event: @escaping @Sendable (any RadioListener) -> Void) {
        let work: @Sendable () -> Void = { [weak self] in
            guard let listener = self?.listener else { return }
            event(listener)
        }
        let deliverNow = lock.withLock { () -> Bool in
            guard _isAlive else { return false }
            if _isSuspended { held.append(work) }
            return !_isSuspended
        }
        if deliverNow { air.clock.run(work) }
    }

    func centralHandle(for guest: SimulatedRadio) -> RadioPeer {
        let handle = lock.withLock { () -> Handle in
            if let existing = centralHandles[ObjectIdentifier(guest)] { return existing }
            let handle = Handle()
            centralHandles[ObjectIdentifier(guest)] = handle
            return handle
        }
        return RadioPeer(key: ObjectIdentifier(handle), address: guest.address)
    }

    func found(hostAt address: UUID) {
        let peer = lock.withLock { () -> RadioPeer? in
            guard _isScanning, reported.insert(address).inserted else { return nil }
            let handle = handles[address] ?? Handle()
            handles[address] = handle
            return RadioPeer(key: ObjectIdentifier(handle), address: address)
        }
        guard let peer else { return }
        let session = centralSession
        air.clock.run(after: air.settings.latency) { [weak self] in
            self?.tell { $0.discovered(peer, session: session ?? -1) }
        }
    }

    // MARK: - Radio

    func attach(_ listener: any RadioListener) {
        lock.withLock { _listener = listener }
    }

    func openPeripheral(session: Int) {
        lock.withLock { _peripheralSession = session }
        let availability = availability
        tell { $0.peripheralState(availability, session: session) }
    }

    func publish() {
        lock.withLock { _isPublished = true }
        air.advertisingChanged(self)
    }

    func closePeripheral() {
        lock.withLock {
            _isPublished = false
            _peripheralSession = nil
            centralHandles = [:]
        }
        air.dropAll(involving: self)
    }

    func update(_ chunk: Data, to central: RadioPeer) -> Bool {
        air.update(self, chunk, to: central)
    }

    func maximumUpdate(for central: RadioPeer) -> Int { air.settings.maximumChunk }

    func openCentral(session: Int) {
        lock.withLock { _centralSession = session }
        let availability = availability
        tell { $0.centralState(availability, session: session) }
    }

    func closeCentral() {
        lock.withLock {
            _centralSession = nil
            _isScanning = false
            reported = []
            handles = [:]
        }
        air.forgetPending(of: self)
    }

    func scan() {
        lock.withLock {
            _isScanning = true
            reported = []
        }
        air.offerHosts(to: self)
    }

    func stopScan() {
        lock.withLock { _isScanning = false }
    }

    func connect(_ peripheral: RadioPeer) { air.connect(self, to: peripheral) }
    func cancelConnection(_ peripheral: RadioPeer) { air.cancel(self, peripheral) }
    func isConnected(_ peripheral: RadioPeer) -> Bool { air.isConnected(self, peripheral) }
    func discover(_ peripheral: RadioPeer) { air.discover(self, peripheral) }
    func subscribe(_ peripheral: RadioPeer) { air.subscribe(self, peripheral) }
    func write(_ chunk: Data, to peripheral: RadioPeer) { air.write(self, chunk, to: peripheral) }
    func maximumWrite(for peripheral: RadioPeer) -> Int { air.settings.maximumChunk }

    // MARK: - What a test does to the device

    func walkAway() {
        lock.withLock { _isInRange = false }
        air.dropAll(involving: self)
    }

    func comeBack() {
        lock.withLock { _isInRange = true }
        rejoinTheAir()
    }

    func switchRadio(on: Bool) {
        set(on ? .on : .off)
    }

    /// Bluetooth permission refused to the app.
    func deny() {
        set(.denied)
    }

    private func set(_ availability: RadioAvailability) {
        lock.withLock { _availability = availability }
        let on = availability == .on
        if !on { air.dropAll(involving: self) }
        let (peripheral, central) = (peripheralSession, centralSession)
        if let peripheral { tell { $0.peripheralState(availability, session: peripheral) } }
        if let central { tell { $0.centralState(availability, session: central) } }
        if on { rejoinTheAir() }
    }

    func suspend() {
        lock.withLock { _isSuspended = true }
    }

    func resume() {
        let pending = lock.withLock { () -> [@Sendable () -> Void] in
            _isSuspended = false
            defer { held = [] }
            return held
        }
        for work in pending { air.clock.run(work) }
    }

    func background(_ backgrounded: Bool) {
        lock.withLock { _isBackgrounded = backgrounded }
        if !backgrounded { rejoinTheAir() }
    }

    /// The app ended: whatever it held on the air goes with it, and nothing reaches it again
    /// until a new listener is attached.
    func end() {
        lock.withLock {
            _isAlive = false
            _isPublished = false
            _isScanning = false
            _peripheralSession = nil
            _centralSession = nil
            _listener = nil
            held = []
        }
        air.forgetPending(of: self)
        air.dropAll(involving: self)
    }

    /// Run again, as a fresh process would be: alive, and empty until somebody opens it.
    func relaunch() {
        lock.withLock {
            _isAlive = true
            reported = []
            handles = [:]
            centralHandles = [:]
        }
    }

    func rotateAddress() {
        lock.withLock { _address = UUID() }
        rejoinTheAir()
    }

    private func rejoinTheAir() {
        if isAdvertising { air.advertisingChanged(self) }
        if isScanning { air.offerHosts(to: self) }
        air.completePendingConnects()
    }
}

/// A seeded generator, so a lossy run loses the same chunks every time.
nonisolated struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
