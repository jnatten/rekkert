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
        var idleCheck: Duration = .seconds(30)
        /// Jumps over stretches with nothing on the radio's clock instead of stepping through them.
        var skipsIdleTime = false
    }

    /// The radios a phone has on. Watches only ever have Bluetooth.
    enum Radios {
        case bluetooth
        /// Its only link stands in for the local network, as on a phone with Bluetooth off.
        case wifi
        case both
    }

    @MainActor
    final class Device {
        let name: String
        let id = DeviceID()
        let isWatch: Bool
        let radio: SimulatedRadio
        /// The second link of a phone on both radios.
        let wifiRadio: SimulatedRadio?
        /// This device's clock against the radio's: offset, and drift as a fraction.
        let clockOffset: TimeInterval
        let drift: Double
        let directory: URL
        /// What the Keychain would hold: it outlives the app being ended.
        let keeper = MemoryCodeKeeper()
        /// The sharing record, which is on disk and outlives it too.
        fileprivate(set) var recorder: LinkRecorder!
        fileprivate(set) var store: MatchStore!
        fileprivate(set) var sharing: SharedSession!
        fileprivate(set) var core: RadioCore!
        fileprivate(set) var wifiCore: RadioCore?
        fileprivate(set) var links: FanOutTransport!
        fileprivate(set) var standIn: WatchStandIn?
        fileprivate var pairLink: LoopbackTransport?
        fileprivate var pairToken: ObjectIdentifier?
        fileprivate var tasks: [Task<Void, Never>] = []

        fileprivate init(
            name: String, isWatch: Bool, radio: SimulatedRadio, wifiRadio: SimulatedRadio? = nil,
            clockOffset: TimeInterval = 0, drift: Double = 0
        ) {
            self.name = name
            self.isWatch = isWatch
            self.radio = radio
            self.wifiRadio = wifiRadio
            self.clockOffset = clockOffset
            self.drift = drift
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
    /// The air the second links share, when any phone has one.
    let wifiAir: Airwaves?
    let timing: Timing
    let code: SessionCode
    let guestLimit: Int
    private(set) var players: [Player] = []
    private var scored: [EventID: Duration] = [:]
    private var scorer: [EventID: ObjectIdentifier] = [:]
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
        timing: Timing = Timing(), air: Airwaves? = nil, code: SessionCode = SessionCode("482915")!,
        guestRadios: (Int) -> Radios = { _ in .bluetooth },
        wifiSettings: Airwaves.Settings = Airwaves.Settings(),
        clockSkew: (_ index: Int, _ isWatch: Bool) -> (offset: TimeInterval, drift: Double) = { _, _ in (0, 0) },
        guestLimit: Int = Participants.limit
    ) {
        self.air = air ?? Airwaves(settings: settings)
        self.timing = timing
        self.code = code
        self.guestLimit = guestLimit
        let usesWifi = guests > 0 && (1 ... guests).contains { guestRadios($0) != .bluetooth }
        wifiAir = usesWifi ? Airwaves(clock: self.air.clock, settings: wifiSettings) : nil
        for index in 0 ... guests {
            let name = index == 0 ? "host" : "guest\(index)"
            let radios = index == 0 ? (usesWifi ? .both : .bluetooth) : guestRadios(index)
            let phoneSkew = clockSkew(index, false)
            let phone = Device(
                name: name, isWatch: false,
                radio: radios == .wifi ? wifiAir!.radio(canHost: true) : self.air.radio(canHost: true),
                wifiRadio: radios == .both ? wifiAir!.radio(canHost: true) : nil,
                clockOffset: phoneSkew.offset, drift: phoneSkew.drift
            )
            let watchSkew = clockSkew(index, true)
            let watch = withWatches
                ? Device(
                    name: "\(name)-watch", isWatch: true, radio: self.air.radio(canHost: false),
                    clockOffset: watchSkew.offset, drift: watchSkew.drift
                )
                : nil
            for device in [phone] + (watch.map { [$0] } ?? []) {
                device.recorder = LinkRecorder(
                    directory: device.directory.appendingPathComponent("record", isDirectory: true),
                    device: device.isWatch ? .watch : .phone,
                    now: deviceClock(of: device)
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
                device.wifiCore?.stop()
            }
        }
    }

    /// What `device` reads as the time: the radio's clock, offset and drifting as its own does.
    private func deviceClock(of device: Device) -> @Sendable () -> Date {
        let (clock, offset, drift) = (air.clock, device.clockOffset, device.drift)
        return { CourtHarness.epoch.addingTimeInterval(clock.now.seconds * (1 + drift) + offset) }
    }

    /// The time `device` shows when the radio's clock reads `instant`.
    func deviceTime(of device: Device, at instant: Duration) -> Date {
        CourtHarness.epoch.addingTimeInterval(instant.seconds * (1 + device.drift) + device.clockOffset)
    }

    private func boot(_ device: Device, pairLink: LoopbackTransport) {
        let core = RadioCore(radio: device.radio)
        let links = FanOutTransport()
        device.pairToken = links.attach(pairLink, as: .pairedDevice)
        links.attach(core, as: .sharedSession)
        let wifiCore = device.wifiRadio.map { RadioCore(radio: $0) }
        if let wifiCore { links.attach(wifiCore, as: .sharedSession) }
        let persistence = SessionStore(directory: device.directory)
        let clock = air.clock
        let now = deviceClock(of: device)
        let store = MatchStore(
            device: device.id,
            transport: links,
            store: persistence,
            session: try? persistence.loadActive(),
            snapshotInterval: 0,
            sendTimeout: timing.sendTimeout,
            retryInterval: timing.retryInterval,
            keepsHistory: !device.isWatch,
            now: now,
            participantTick: .milliseconds(20),
            guestLimit: guestLimit
        )
        store.recorder = device.recorder
        let sharing = SharedSession(
            store: store, link: LocalNetworkTransport(),
            bluetooth: wifiCore.map { TwinLink(bluetooth: core, wifi: $0) as any SharedLink } ?? core,
            graceBeforeNotice: timing.graceBeforeNotice, radioGrace: timing.radioGrace,
            keeper: device.keeper, now: now,
            idleCheck: timing.idleCheck,
            // Woken by the clock rather than polling it: a court of sixteen devices, each with
            // timers asleep for minutes, would otherwise spend its time asking what time it is.
            sleep: { duration in
                let (woken, wake) = AsyncStream<Void>.makeStream()
                let timer = clock.run(after: duration) { wake.finish() }
                await withTaskCancellationHandler {
                    for await _ in woken {}
                } onCancel: {
                    timer.cancel()
                    wake.finish()
                }
            }
        )
        device.core = core
        device.wifiCore = wifiCore
        device.links = links
        device.store = store
        device.sharing = sharing
        device.pairLink = pairLink
        device.tasks = [Task { await store.run() }]
        if device.isWatch {
            let standIn = WatchStandIn(store: store, sharing: sharing, timing: timing.standIn, tick: timing.standInTick)
            device.standIn = standIn
            store.onSharing = { [standIn] signal in standIn.heard(signal) }
            store.participantCount = { [standIn] in standIn.hosting?.participants.count ?? 0 }
            device.tasks.append(Task { await standIn.run() })
        } else {
            sharing.publish = { [store] state in Task { await store.send(.state(state)) } }
            sharing.onStandby = { [store] standby in Task { await store.send(.standby(standby)) } }
            sharing.onStoppedByHost = { [store] host, reason in Task { await store.sendDurably(.hostStoppedSharing(host: host, reason: reason)) } }
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
                case .state, .standby, .hostingStatus, .hostStoppedSharing, .answered, .newMatch: break
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

    func finish(on device: Device) {
        device.store.finish()
    }

    func discard(on device: Device) {
        device.store.discardSession()
    }

    /// As the views answer: through the one entry point each device has.
    func answer(_ choice: BetweenMatchesAnswer.Choice, on device: Device) {
        if let standIn = device.standIn { standIn.answer(choice) } else { device.sharing.answer(choice) }
    }

    func betweenMatches(of device: Device) -> BetweenMatches {
        device.store.betweenMatches
    }

    func isWaiting(_ device: Device) -> Bool {
        device.store.role == .guest && device.store.log.isEmpty
    }

    func canScore(on device: Device) -> Bool {
        device.store.canScore
    }

    /// Taps a point on `device` and starts timing how long it takes to reach everybody else.
    @discardableResult
    func score(on device: Device, court: Int = 0, team: TeamSide = .a) -> EventID? {
        let before = Set(device.store.log.events.keys)
        device.store.tap(court: court, team: team)
        let new = device.store.log.events.keys.first { !before.contains($0) }
        if let new {
            scored[new] = clock.now
            scorer[new] = ObjectIdentifier(device)
        }
        return new
    }

    // MARK: - Time

    /// Moves the radio's clock on by `duration`, a step at a time, letting every store catch up
    /// between steps.
    func run(for duration: Duration) async {
        var elapsed = Duration.zero
        while elapsed < duration {
            elapsed += await step(atMost: duration - elapsed)
        }
    }

    /// Long stretches of radio time in coarse steps, for timers measured in minutes.
    func fastForward(by duration: Duration, step: Duration = .seconds(1)) async {
        var elapsed = Duration.zero
        while elapsed < duration {
            clock.advance(by: step)
            for _ in 0 ..< 4 { await Task.yield() }
            try? await Task.sleep(for: .milliseconds(2))
            elapsed += step
        }
        noteArrivals()
    }

    /// Steps until `condition` holds, or `limit` of radio time has gone by. Whether it held.
    @discardableResult
    func until(within limit: Duration, _ condition: () -> Bool) async -> Bool {
        var elapsed = Duration.zero
        while elapsed <= limit {
            if condition() { return true }
            elapsed += await step(atMost: max(timing.step, limit - elapsed))
        }
        return condition()
    }

    /// One step of radio time, or with `skipsIdleTime` a longer one up to whatever is next due.
    private func step(atMost limit: Duration) async -> Duration {
        var delta = timing.step
        if timing.skipsIdleTime, let due = clock.nextDue {
            delta = max(timing.step, min(due - clock.now, limit))
        }
        clock.advance(by: delta)
        for _ in 0 ..< 4 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(1))
        noteArrivals()
        return delta
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

    struct Arrival {
        let event: EventID
        /// `nil` for a point that never got there.
        let delay: Duration?
        let nothingWrong: Bool
    }

    /// Every point tapped elsewhere, as it reached `device`: the scorer's own phone or watch
    /// counts, the device that tapped does not (spec 005, FR-010).
    func arrivals(on device: Device) -> [Arrival] {
        let key = ObjectIdentifier(device)
        let entries = device.recorder.read().entries.filter { $0.device == (device.isWatch ? .watch : .phone) }
        let pair = counterpart(of: device)
        let pairEntries = device.isWatch ? pair?.recorder.read().entries.filter { $0.device == .phone } : nil
        return scored.compactMap { event, tapped -> Arrival? in
            guard let by = scorer[event], by != key else { return nil }
            let landed = arrived[event]?[key]
            let instant = landed ?? clock.now
            let fromPair = pair.map { ObjectIdentifier($0) == by } ?? false
            let fromGuest = device === host.phone ? scoringPhone(of: by)?.id : nil
            let fine = ArrivalConditions.nothingWrong(
                arrivalAt: deviceTime(of: device, at: instant),
                on: device.isWatch ? .watch : .phone,
                from: fromGuest,
                fromPairedDevice: fromPair,
                entries: entries,
                pairEntries: fromPair ? nil : pairEntries
            )
            return Arrival(event: event, delay: landed.map { $0 - tapped }, nothingWrong: fine)
        }
    }

    private func scoringPhone(of key: ObjectIdentifier) -> Device? {
        players.first { ObjectIdentifier($0.phone) == key || $0.watch.map(ObjectIdentifier.init) == key }?.phone
    }

    /// Delays on one device, or on many, where a point that never arrived counts as later than
    /// any limit.
    struct DelayStats {
        let delays: [Duration?]

        init(_ arrivals: [Arrival]) { delays = arrivals.map(\.delay) }
        init(delays: [Duration?]) { self.delays = delays }

        var count: Int { delays.count }
        private var sorted: [Duration] {
            delays.map { $0 ?? .seconds(3_600) }.sorted()
        }
        var median: Duration? { percentile(0.5) }
        var p95: Duration? { percentile(0.95) }
        var slowest: Duration? { sorted.last }

        func percentile(_ share: Double) -> Duration? {
            let sorted = sorted
            guard !sorted.isEmpty else { return nil }
            return sorted[min(sorted.count - 1, Int((Double(sorted.count) * share).rounded(.up)) - 1)]
        }

        func share(within limit: Duration) -> Double {
            guard !delays.isEmpty else { return 0 }
            return Double(delays.count { $0.map { $0 <= limit } ?? false }) / Double(delays.count)
        }

        /// FR-010 can be judged only on at least 100 timed points.
        var isJudgeable: Bool { count >= 100 }
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

    func outOfRange(_ device: Device) {
        device.radio.walkAway()
        device.wifiRadio?.walkAway()
    }

    func backInRange(_ device: Device) {
        device.radio.comeBack()
        device.wifiRadio?.comeBack()
    }

    /// The second links of every guest on both radios, for a `Flapper`.
    var secondLinks: [SimulatedRadio] { guests.compactMap(\.phone.wifiRadio) }

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
        device.sharing?.close()
        for task in device.tasks { task.cancel() }
        device.tasks = []
        device.radio.end()
        device.wifiRadio?.end()
        device.pairLink?.disconnect()
        // WatchConnectivity says so on the other wrist or phone: an app that is not running is not reachable.
        counterpart(of: device)?.pairLink?.setReachable(false)
        device.store = nil
        device.sharing = nil
        device.core = nil
        device.wifiCore = nil
        device.links = nil
        device.standIn = nil
    }

    /// Runs the app again, as a fresh process: rebuilt from what it kept on disk, and paired
    /// with its watch or phone anew.
    func relaunch(_ device: Device) {
        device.radio.relaunch()
        device.wifiRadio?.relaunch()
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
