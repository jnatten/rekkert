import Foundation
import RekkertCore
@testable import RekkertSync

/// A court with no Wi-Fi: a host and its guests, each a phone with its watch, wired the way
/// `AppModel` wires them, over one `SimulatedRadio`.
///
/// The radio runs on a `TestClock` that the harness moves forward in steps, letting the stores
/// catch up between them. The stores' own waits are real, and kept short.
@MainActor
final class CourtHarness {
    struct Timing {
        var step: Duration = .milliseconds(50)
        var sendTimeout: Duration = .seconds(2)
        var retryInterval: Duration = .milliseconds(200)
        var graceBeforeNotice: Duration = .seconds(1)
        var radioGrace: Duration = .seconds(30)
        var standIn = StandInPolicy.Timing()
        var standInTick: Duration = .milliseconds(100)
    }

    @MainActor
    final class Device {
        let name: String
        let id = DeviceID()
        let isWatch: Bool
        let radio: SimulatedRadio
        let directory: URL
        /// What the Keychain would hold: it outlives the app being ended.
        let keeper = MemoryCodeKeeper()
        /// The sharing record, which is on disk and outlives it too.
        fileprivate(set) var recorder: LinkRecorder!
        fileprivate(set) var store: MatchStore!
        fileprivate(set) var sharing: SharedSession!
        fileprivate(set) var core: RadioCore!
        fileprivate(set) var links: FanOutTransport!
        fileprivate(set) var standIn: WatchStandIn?
        fileprivate var pairLink: LoopbackTransport?
        fileprivate var pairToken: ObjectIdentifier?
        fileprivate var tasks: [Task<Void, Never>] = []

        fileprivate init(name: String, isWatch: Bool, radio: SimulatedRadio) {
            self.name = name
            self.isWatch = isWatch
            self.radio = radio
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("court-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    struct Player {
        let phone: Device
        let watch: Device?
    }

    /// What the stores take for the moment the radio's clock started.
    nonisolated static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    let air: Airwaves
    let timing: Timing
    let code: SessionCode
    private(set) var players: [Player] = []
    private var scored: [EventID: Duration] = [:]
    private var arrived: [EventID: [ObjectIdentifier: Duration]] = [:]

    var clock: TestClock { air.clock }
    /// The radio's clock as the stores read it.
    var wallClock: Date { CourtHarness.epoch.addingTimeInterval(clock.now.seconds) }
    var host: Player { players[0] }
    var guests: ArraySlice<Player> { players.dropFirst() }
    var devices: [Device] { players.flatMap { [$0.phone] + ($0.watch.map { [$0] } ?? []) } }

    /// `air` from another court puts both within range of each other, as two courts at one club are.
    init(
        guests: Int, withWatches: Bool = true, settings: Airwaves.Settings = Airwaves.Settings(),
        timing: Timing = Timing(), air: Airwaves? = nil, code: SessionCode = SessionCode("482915")!
    ) {
        self.air = air ?? Airwaves(settings: settings)
        self.timing = timing
        self.code = code
        for index in 0 ... guests {
            let name = index == 0 ? "host" : "guest\(index)"
            let phone = Device(name: name, isWatch: false, radio: self.air.radio(canHost: true))
            let watch = withWatches ? Device(name: "\(name)-watch", isWatch: true, radio: self.air.radio(canHost: false)) : nil
            let clock = self.air.clock
            for device in [phone] + (watch.map { [$0] } ?? []) {
                device.recorder = LinkRecorder(
                    directory: device.directory.appendingPathComponent("record", isDirectory: true),
                    device: device.isWatch ? .watch : .phone,
                    now: { CourtHarness.epoch.addingTimeInterval(clock.now.seconds) }
                )
            }
            // What `transferFile` does: gets there whether or not the phone's app is running.
            watch?.recorder.send = { [recorder = phone.recorder!] day, contents in
                recorder.receive(watchDay: day, contents: contents)
            }
            if let watch {
                let (phoneSide, watchSide) = LoopbackTransport.pair()
                boot(phone, pairLink: phoneSide)
                boot(watch, pairLink: watchSide)
            } else {
                // No watch paired: the link to one is there and never reachable, as WatchConnectivity's is.
                boot(phone, pairLink: LoopbackTransport(reachable: false))
            }
            players.append(Player(phone: phone, watch: watch))
        }
    }

    deinit {
        for device in players.flatMap({ [$0.phone] + ($0.watch.map { [$0] } ?? []) }) {
            MainActor.assumeIsolated {
                for task in device.tasks { task.cancel() }
                device.core?.stop()
            }
        }
    }

    private func boot(_ device: Device, pairLink: LoopbackTransport) {
        let core = RadioCore(radio: device.radio)
        let links = FanOutTransport()
        device.pairToken = links.attach(pairLink, as: .pairedDevice)
        links.attach(core, as: .sharedSession)
        let persistence = SessionStore(directory: device.directory)
        let clock = air.clock
        let store = MatchStore(
            device: device.id,
            transport: links,
            store: persistence,
            session: try? persistence.loadActive(),
            snapshotInterval: 0,
            sendTimeout: timing.sendTimeout,
            retryInterval: timing.retryInterval,
            keepsHistory: !device.isWatch,
            now: { CourtHarness.epoch.addingTimeInterval(clock.now.seconds) },
            participantTick: .milliseconds(20)
        )
        store.recorder = device.recorder
        let sharing = SharedSession(
            store: store, link: LocalNetworkTransport(), bluetooth: core,
            graceBeforeNotice: timing.graceBeforeNotice, radioGrace: timing.radioGrace,
            keeper: device.keeper, now: { CourtHarness.epoch.addingTimeInterval(clock.now.seconds) },
            sleep: { duration in
                let until = clock.now + duration
                while clock.now < until, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(1)) }
            }
        )
        device.core = core
        device.links = links
        device.store = store
        device.sharing = sharing
        device.pairLink = pairLink
        device.tasks = [Task { await store.run() }]
        if device.isWatch {
            let standIn = WatchStandIn(store: store, sharing: sharing, timing: timing.standIn, tick: timing.standInTick)
            device.standIn = standIn
            store.onSharing = { [standIn] signal in standIn.heard(signal) }
            device.tasks.append(Task { await standIn.run() })
        } else {
            sharing.publish = { [store] state in Task { await store.send(.state(state)) } }
            sharing.onStandby = { [store] standby in Task { await store.send(.standby(standby)) } }
            sharing.onHostingStatus = { [store] status, isNews in
                Task { if isNews { await store.sendDurably(.hostingStatus(status)) } else { await store.send(.hostingStatus(status)) } }
            }
            store.onSharing = { [sharing] signal in
                switch signal {
                case .join(let code): sharing.join(code, forTheWatch: true)
                case .cancel: sharing.cancelJoiningFromTheWatch()
                case .followPhone: store.offerToThePair()
                case .startHosting: sharing.startHostingFromTheWatch()
                case .stopHosting: sharing.stopHostingFromTheWatch()
                case .state, .standby, .hostingStatus: break
                }
            }
        }
        sharing.restore()
    }

    // MARK: - Playing

    func startMatch(_ setup: SessionSetup = .traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away))) {
        host.phone.store.configure(setup)
    }

    func share() {
        host.phone.sharing.host(code: code)
    }

    func join(_ player: Player) {
        player.phone.sharing.join(code)
    }

    func joinAll() {
        for guest in guests { join(guest) }
    }

    /// Taps a point on `device` and starts timing how long it takes to reach everybody else.
    @discardableResult
    func score(on device: Device, team: TeamSide = .a) -> EventID? {
        let before = Set(device.store.log.events.keys)
        device.store.tap(team: team)
        let new = device.store.log.events.keys.first { !before.contains($0) }
        if let new { scored[new] = clock.now }
        return new
    }

    // MARK: - Time

    /// Moves the radio's clock on by `duration`, a step at a time, letting every store catch up
    /// between steps.
    func run(for duration: Duration) async {
        var elapsed = Duration.zero
        while elapsed < duration {
            await step()
            elapsed += timing.step
        }
    }

    /// Steps until `condition` holds, or `limit` of radio time has gone by. Whether it held.
    @discardableResult
    func until(within limit: Duration, _ condition: () -> Bool) async -> Bool {
        var elapsed = Duration.zero
        while elapsed <= limit {
            if condition() { return true }
            await step()
            elapsed += timing.step
        }
        return condition()
    }

    private func step() async {
        clock.advance(by: timing.step)
        for _ in 0 ..< 4 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(1))
        noteArrivals()
    }

    private func noteArrivals() {
        let now = clock.now
        for (event, _) in scored {
            for device in devices where device.store?.log.events[event] != nil {
                let key = ObjectIdentifier(device)
                if arrived[event, default: [:]][key] == nil { arrived[event, default: [:]][key] = now }
            }
        }
    }

    /// How long each point took to reach each device that has it, counted from the tap.
    func arrivalTimes() -> [Duration] {
        scored.flatMap { event, at in (arrived[event] ?? [:]).values.map { $0 - at } }
    }

    // MARK: - Agreement

    func inStep(_ device: Device, with other: Device) -> Bool {
        guard let mine = device.store, let theirs = other.store else { return false }
        return mine.log.sessionID == theirs.log.sessionID
            && mine.log.vector == theirs.log.vector
            && mine.state == theirs.state
    }

    /// Every device holds the host's match: the same session, every event, the same board.
    func allInStep(includingWatches: Bool = true) -> Bool {
        let everybody = includingWatches ? devices : players.map(\.phone)
        return everybody.allSatisfy { inStep($0, with: host.phone) }
    }

    // MARK: - What happens to a device

    func outOfRange(_ device: Device) { device.radio.walkAway() }
    func backInRange(_ device: Device) { device.radio.comeBack() }

    /// The watch out of reach of its own phone, both still running.
    func separate(_ player: Player) {
        player.phone.pairLink?.setReachable(false)
        player.watch?.pairLink?.setReachable(false)
    }

    /// What a phone and its watch queue for each other arrives only when the system gets round to it.
    func holdQueues(of player: Player, _ holding: Bool = true) {
        player.phone.pairLink?.setHoldingQueue(holding)
        player.watch?.pairLink?.setHoldingQueue(holding)
    }

    func reunite(_ player: Player) {
        player.phone.pairLink?.setReachable(true)
        player.watch?.pairLink?.setReachable(true)
    }

    /// The system ended the app: its process and its links are gone, what it wrote to disk is not.
    func endApp(_ device: Device) {
        for task in device.tasks { task.cancel() }
        device.tasks = []
        device.radio.end()
        device.pairLink?.disconnect()
        // WatchConnectivity says so on the other wrist or phone: an app that is not running is not reachable.
        counterpart(of: device)?.pairLink?.setReachable(false)
        device.store = nil
        device.sharing = nil
        device.core = nil
        device.links = nil
        device.standIn = nil
    }

    /// Runs the app again, as a fresh process: rebuilt from what it kept on disk, and paired
    /// with its watch or phone anew.
    func relaunch(_ device: Device) {
        device.radio.relaunch()
        guard let counterpart = counterpart(of: device) else {
            return boot(device, pairLink: LoopbackTransport(reachable: false))
        }
        let (mine, theirs) = LoopbackTransport.pair()
        if let links = counterpart.links {
            if let token = counterpart.pairToken { links.detach(token) }
            counterpart.pairLink?.disconnect()
            counterpart.pairLink = theirs
            counterpart.pairToken = links.attach(theirs, as: .pairedDevice)
        }
        boot(device, pairLink: mine)
    }

    private func counterpart(of device: Device) -> Device? {
        for player in players {
            if player.phone === device { return player.watch }
            if player.watch === device { return player.phone }
        }
        return nil
    }
}

extension Duration {
    nonisolated var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
