import Foundation
import RekkertCore
@testable import RekkertSync

/// A court with no Wi-Fi: a host and its guests, each a phone with its watch, wired the way
/// `AppModel` wires them, over one `SimulatedRadio`.
///
/// The radio runs on a `TestClock` that the harness moves forward in steps, letting the stores
/// catch up between them. The stores' waits, and the watch stand-in's, run on that clock too.
@MainActor
final class CourtHarness {
    struct Timing {
        var step: Duration = .milliseconds(50)
        /// The app's own: these waits run on the radio's clock, not the machine's.
        var sendTimeout: Duration = .seconds(6)
        var retryInterval: Duration = .seconds(4)
        var participantTick: Duration = .seconds(1)
        var graceBeforeNotice: Duration = .seconds(1)
        var radioGrace: Duration = .seconds(30)
        var standIn = StandInPolicy.Timing()
        var standInTick: Duration = .seconds(1)
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
        let skew: ClockSkew
        var clockOffset: TimeInterval { skew.offset }
        var drift: Double { skew.drift }
        let directory: URL
        let wakefulness: Wakefulness
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
            wakefulness = Wakefulness(clock: radio.air.clock)
            radio.wakefulness = wakefulness
            skew = ClockSkew(offset: clockOffset, drift: drift)
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
        let (clock, skew) = (air.clock, device.skew)
        return { CourtHarness.epoch.addingTimeInterval(clock.now.seconds * (1 + skew.drift) + skew.offset) }
    }

    private nonisolated static let instantEpoch = ContinuousClock.now

    /// The monotonic clock the stand-in times its waits by, run off the radio's clock so its waits
    /// and the stores' come out in the same order however busy the machine is.
    private var monotonicClock: () -> ContinuousClock.Instant {
        let clock = air.clock
        return { CourtHarness.instantEpoch.advanced(by: clock.now) }
    }

    /// Sets `device`'s clock forward or back, and tells its store, as the system would.
    func jumpClock(of device: Device, by seconds: TimeInterval) {
        device.skew.offset += seconds
        device.store.clockChanged()
    }

    /// Each delay `device` recorded, beside the true one: from the tap to when the store noted it.
    func recordedDelays(on device: Device) -> [(recorded: TimeInterval?, truth: TimeInterval)] {
        let key = ObjectIdentifier(device)
        let kind: LinkRecordEntry.Device = device.isWatch ? .watch : .phone
        return device.recorder.read().entries.compactMap { entry in
            guard entry.device == kind, case .pointArrived(let latency) = entry.kind else { return nil }
            let instant = (entry.time.timeIntervalSince(CourtHarness.epoch) - device.clockOffset) / (1 + device.drift)
            let nearest = scored.filter { arrived[$0.key]?[key] != nil }
                .min { abs(arrived[$0.key]![key]!.seconds - instant) < abs(arrived[$1.key]![key]!.seconds - instant) }
            guard let nearest, abs(arrived[nearest.key]![key]!.seconds - instant) < 1 else { return nil }
            return (latency, instant - nearest.value.seconds)
        }
    }

    /// Each `link` or `hop` `device` recorded, beside the true one: from when the scorer's phone
    /// had the point, or from when this watch's own phone did (spec 005, FR-010, FR-010a).
    func recordedLegs(on device: Device) -> [(leg: LinkRecordEntry.Leg, truth: TimeInterval)] {
        let key = ObjectIdentifier(device)
        let kind: LinkRecordEntry.Device = device.isWatch ? .watch : .phone
        return device.recorder.read().entries.compactMap { entry in
            guard entry.device == kind, case .pointArrived = entry.kind, let leg = entry.leg else { return nil }
            let instant = (entry.time.timeIntervalSince(CourtHarness.epoch) - device.clockOffset) / (1 + device.drift)
            let nearest = scored.filter { arrived[$0.key]?[key] != nil }
                .min { abs(arrived[$0.key]![key]!.seconds - instant) < abs(arrived[$1.key]![key]!.seconds - instant) }
            guard let nearest, abs(arrived[nearest.key]![key]!.seconds - instant) < 1 else { return nil }
            let from: Device? = switch leg {
            case .link: scorer[nearest.key].flatMap(scoringPhone(of:))
            case .hop: counterpart(of: device)
            }
            guard let from, let had = arrived[nearest.key]?[ObjectIdentifier(from)] else { return nil }
            return (leg, instant - had.seconds)
        }
    }

    /// The time `device` shows when the radio's clock reads `instant`.
    func deviceTime(of device: Device, at instant: Duration) -> Date {
        CourtHarness.epoch.addingTimeInterval(instant.seconds * (1 + device.drift) + device.clockOffset)
    }

    /// Woken by the clock rather than polling it: a court of sixteen devices, each with timers
    /// asleep for minutes, would otherwise spend its time asking what time it is. The stores'
    /// waits run on it too, so a retry is as late in radio time however busy the machine is.
    private func clockSleep(for device: Device) -> @Sendable (Duration) async -> Void {
        let (clock, wakefulness) = (air.clock, device.wakefulness)
        return { duration in
            let (woken, wake) = AsyncStream<Void>.makeStream()
            let timer = clock.run(after: duration) { wakefulness.whenAwake { wake.finish() } }
            await withTaskCancellationHandler {
                for await _ in woken {}
            } onCancel: {
                timer.cancel()
                wake.finish()
            }
        }
    }

    private func boot(_ device: Device, pairLink: LoopbackTransport) {
        let core = RadioCore(radio: device.radio, linkRadio: device.radio.air === wifiAir ? .wifi : .bluetooth)
        let links = FanOutTransport(sleep: clockSleep(for: device))
        device.pairToken = links.attach(pairLink, as: .pairedDevice)
        links.attach(core, as: .sharedSession)
        let wifiCore = device.wifiRadio.map { RadioCore(radio: $0, linkRadio: .wifi) }
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
            participantTick: timing.participantTick,
            guestLimit: guestLimit,
            sleep: clockSleep(for: device)
        )
        store.recorder = device.recorder
        let sharing = SharedSession(
            store: store, link: LocalNetworkTransport(),
            bluetooth: wifiCore.map { TwinLink(bluetooth: core, wifi: $0) as any SharedLink } ?? core,
            graceBeforeNotice: timing.graceBeforeNotice, radioGrace: timing.radioGrace,
            keeper: device.keeper, now: now,
            idleCheck: timing.idleCheck,
            sleep: clockSleep(for: device)
        )
        device.core = core
        device.wifiCore = wifiCore
        device.links = links
        device.store = store
        device.sharing = sharing
        device.pairLink = pairLink
        device.tasks = [Task { await store.run() }]
        if device.isWatch {
            let standIn = WatchStandIn(
                store: store, sharing: sharing, timing: timing.standIn, tick: timing.standInTick,
                now: monotonicClock, sleep: clockSleep(for: device)
            )
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

    /// FR-010: every point that reached `device` on the shared link, timed from when it was first
    /// there: the tap, or for a point tapped on a watch following its phone, that phone having it.
    /// A watch following its phone has none, and nor does the device the point was first on.
    func arrivals(on device: Device) -> [Arrival] {
        let key = ObjectIdentifier(device)
        let entries = ownEntries(of: device)
        let onHost = device === host.phone || device === host.watch
        return scored.compactMap { event, tapped -> Arrival? in
            guard let by = scorer[event], by != key, let start = firstOnTheSharedLink(event, tappedAt: tapped),
                  start.device !== device
            else { return nil }
            let landed = arrived[event]?[key]
            let time = deviceTime(of: device, at: landed ?? clock.now)
            guard isOnTheSharedLink(device, entries: entries, at: time) else { return nil }
            let fine = ArrivalConditions.nothingWrong(
                arrivalAt: time, from: onHost ? scoringPhone(of: by)?.id : nil, entries: entries
            )
            return Arrival(event: event, delay: landed.map { $0 - start.at }, nothingWrong: fine)
        }
    }

    /// FR-010a: the hops between `device` and its own phone or watch. On a phone, its watch's taps
    /// reaching it; on a watch following its phone, every other point, from when the phone had it.
    func hops(on device: Device) -> [Arrival] {
        let key = ObjectIdentifier(device)
        guard let other = counterpart(of: device) else { return [] }
        let otherKey = ObjectIdentifier(other)
        let entries = ownEntries(of: device)
        return scored.compactMap { event, tapped -> Arrival? in
            guard let by = scorer[event], by != key else { return nil }
            let landed = arrived[event]?[key]
            let time = deviceTime(of: device, at: landed ?? clock.now)
            let from: Duration?
            if device.isWatch {
                guard !isOnTheSharedLink(device, entries: entries, at: time) else { return nil }
                from = by == otherKey ? tapped : arrived[event]?[otherKey]
            } else {
                guard by == otherKey, firstOnTheSharedLink(event, tappedAt: tapped)?.device === device else { return nil }
                from = tapped
            }
            guard let from else { return nil }
            return Arrival(
                event: event, delay: landed.map { $0 - from },
                nothingWrong: ArrivalConditions.hopNothingWrong(arrivalAt: time, entries: entries)
            )
        }
    }

    /// FR-011: every point tapped elsewhere, from the tap, as spec 001's times count it.
    func fromTheTap(on device: Device) -> DelayStats {
        let key = ObjectIdentifier(device)
        return DelayStats(delays: scored.compactMap { event, tapped -> Duration?? in
            guard let by = scorer[event], by != key else { return nil }
            return .some(arrived[event]?[key].map { $0 - tapped })
        })
    }

    private func ownEntries(of device: Device) -> [LinkRecordEntry] {
        device.recorder.read().entries.filter { $0.device == (device.isWatch ? .watch : .phone) }
    }

    /// A phone, or a watch standing in for it on its own link to the host.
    private func isOnTheSharedLink(_ device: Device, entries: [LinkRecordEntry], at time: Date) -> Bool {
        guard device.isWatch else { return true }
        var open = 0
        for entry in entries where entry.time <= time {
            guard case .host = entry.link else { continue }
            switch entry.kind {
            case .proven: open += 1
            case .dropped, .wroteOff, .redialled: open = max(0, open - 1)
            default: break
            }
        }
        return open > 0
    }

    private func firstOnTheSharedLink(_ event: EventID, tappedAt tapped: Duration) -> (device: Device, at: Duration)? {
        guard let by = scorer[event], let tapper = devices.first(where: { ObjectIdentifier($0) == by }) else { return nil }
        if isOnTheSharedLink(tapper, entries: ownEntries(of: tapper), at: deviceTime(of: tapper, at: tapped)) {
            return (tapper, tapped)
        }
        guard let phone = counterpart(of: tapper), let had = arrived[event]?[ObjectIdentifier(phone)] else { return nil }
        return (phone, had)
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

/// A device's clock against the radio's, which a test can set forward or back.
nonisolated final class ClockSkew: @unchecked Sendable {
    private let lock = NSLock()
    private var _offset: TimeInterval
    let drift: Double

    init(offset: TimeInterval, drift: Double) {
        _offset = offset
        self.drift = drift
    }

    var offset: TimeInterval {
        get { lock.withLock { _offset } }
        set { lock.withLock { _offset = newValue } }
    }
}

// MARK: - Friendlies

extension CourtHarness {
    /// Sets up a friendly on the host's phone and draws its first round, as `NewSessionView` does.
    func startFriendly(
        players names: [String] = ["Ada", "Bob", "Cy", "Dan"],
        rules: (([RekkertCore.Player]) -> [PairingRule])? = nil
    ) {
        let players = names.map { RekkertCore.Player(name: $0) }
        host.phone.store.configure(.friendly(FriendlySession(
            name: "Friendly", players: players, pairingRules: rules?(players) ?? []
        )))
        host.phone.store.nextRound()
    }

    /// One point in the round in play, the round called off there, and the next one drawn.
    func playFriendlyRound(on device: Device) {
        guard let session = friendly(on: device) else { return }
        device.store.tap(round: session.currentIndex, court: 0, team: .a)
        device.store.endRound()
        device.store.nextRound()
    }

    func friendly(on device: Device) -> FriendlySession? {
        guard case .friendly(let session)? = device.store.state else { return nil }
        return session
    }
}

// MARK: - Tournaments

extension CourtHarness {
    /// Sets up an Americano or Mexicano on the host's phone and draws its first round, as
    /// `NewSessionView` does. Players are named "P0"… in roster order; `away` names by index
    /// whoever is to start the tournament with an absence already folded in.
    func startTournament(
        _ format: TournamentFormat = .americano,
        players count: Int = 9,
        courts: Int = 2,
        away: [(player: Int, from: Int)] = []
    ) {
        let players = (0 ..< count).map { RekkertCore.Player(name: "P\($0)") }
        host.phone.store.configure(.tournament(Tournament(
            name: "Thursday", format: format, players: players,
            config: TournamentConfig(courtCount: courts),
            absences: away.map { TournamentAbsence(player: players[$0.player].id, from: $0.from) }
        )))
        host.phone.store.nextRound()
    }

    /// Every court of the round in play played out, then the next round drawn on `device`.
    func playTournamentRound(on device: Device) {
        guard let tournament = tournament(on: device), let round = tournament.currentRound else { return }
        let target = tournament.config.pointRules.target
        for match in round.matches {
            device.store.setScore(round: round.index, court: match.courtIndex, points: BySide(a: target, b: 0))
        }
        device.store.nextRound()
    }

    func tournament(on device: Device) -> Tournament? {
        guard case .tournament(let tournament)? = device.store.state else { return nil }
        return tournament
    }

    /// The roster's id for "P\(index)" on the host's phone.
    func tournamentPlayer(_ index: Int) -> PlayerID? {
        tournament(on: host.phone)?.players.first { $0.name == "P\(index)" }?.id
    }
}
