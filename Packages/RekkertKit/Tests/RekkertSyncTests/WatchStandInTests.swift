import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let code = SessionCode("482915")!

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

/// Generous where the test waits for something to succeed, since the whole suite shares the
/// main actor; short only where running out is the point.
private let quick = StandInPolicy.Timing(
    phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(150)
)

private func seeded(points: Int = 0) -> MatchLog {
    let device = DeviceID()
    var log = MatchLog()
    log.append(.configure(counting), from: device)
    for _ in 0 ..< points { log.append(.point(round: 0, court: 0, team: .a), from: device) }
    return log
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .pointCount(let session) = store.state else { return nil }
    return session.score.points
}

/// The watch's Bluetooth: a loopback to the host that is only up between a join and a stop,
/// the way a dialled central is.
private final class Radio: SharedLink, @unchecked Sendable {
    let watchEnd: LoopbackTransport
    let hostEnd: LoopbackTransport
    let reachability: AsyncStream<Bool>
    private let updates: AsyncStream<Bool>.Continuation
    private let hostIsThere: Bool
    private let lock = NSLock()
    private var up = false
    private var dialled: SessionCode?
    private var stopCount = 0

    init(hostIsThere: Bool = true) {
        (watchEnd, hostEnd) = LoopbackTransport.pair()
        watchEnd.setReachable(false)
        hostEnd.setReachable(false)
        self.hostIsThere = hostIsThere
        var continuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { continuation = $0 }
        updates = continuation
    }

    var joined: SessionCode? { lock.withLock { dialled } }
    var stops: Int { lock.withLock { stopCount } }
    var reachableCount: Int { lock.withLock { up ? 1 : 0 } }

    func startHosting(code: SessionCode, share: UUID) {}
    func resumeHosting(code: SessionCode, share: UUID) {}
    func resumeJoining(code: SessionCode) {}

    func startJoining(code: SessionCode) {
        lock.withLock { dialled = code }
        guard hostIsThere else { return }
        lock.withLock { up = true }
        watchEnd.setReachable(true)
        hostEnd.setReachable(true)
        updates.yield(true)
    }

    func stop() {
        lock.withLock { stopCount += 1 }
        drop()
    }

    /// The host out of range: the link goes without anybody here hanging up.
    func drop() {
        lock.withLock { up = false }
        watchEnd.setReachable(false)
        hostEnd.setReachable(false)
        updates.yield(false)
    }
}

/// A host, a guest's phone and the guest's watch. The phone reaches the host over one link and
/// its watch over another; the watch can reach the host over its own radio when it dials.
@MainActor
private final class Court {
    let host: MatchStore
    let phone: MatchStore
    let watch: MatchStore
    let radio: Radio
    let sharing: SharedSession
    let standIn: WatchStandIn
    let phoneToHost: LoopbackTransport
    let hostToPhone: LoopbackTransport
    let phoneToWatch: LoopbackTransport
    let watchToPhone: LoopbackTransport
    private(set) var heardOnThePhone: [SharingSignal] = []
    private var tasks: [Task<Void, Never>] = []

    init(
        hostLog: MatchLog = seeded(points: 1),
        hostIsThere: Bool = true,
        hostRole: SessionRole = .host,
        timing: StandInPolicy.Timing = quick
    ) {
        (hostToPhone, phoneToHost) = LoopbackTransport.pair()
        (phoneToWatch, watchToPhone) = LoopbackTransport.pair()
        radio = Radio(hostIsThere: hostIsThere)

        let hostFan = FanOutTransport()
        hostFan.attach(hostToPhone, as: .sharedSession)
        hostFan.attach(radio.hostEnd, as: .sharedSession)
        host = MatchStore(
            device: DeviceID(), transport: hostFan,
            session: ActiveSession(log: hostLog, role: hostRole), snapshotInterval: 0
        )

        let phoneFan = FanOutTransport()
        phoneFan.attach(phoneToWatch, as: .pairedDevice)
        phoneFan.attach(phoneToHost, as: .sharedSession)
        phone = MatchStore(device: DeviceID(), transport: phoneFan, snapshotInterval: 0)

        let watchFan = FanOutTransport()
        watchFan.attach(watchToPhone, as: .pairedDevice)
        watchFan.attach(radio.watchEnd, as: .sharedSession)
        watch = MatchStore(device: DeviceID(), transport: watchFan, snapshotInterval: 0, keepsHistory: false)
        sharing = SharedSession(store: watch, link: LocalNetworkTransport(), bluetooth: radio)
        standIn = WatchStandIn(store: watch, sharing: sharing, timing: timing, tick: .milliseconds(20))

        phone.onSharing = { [weak self] in self?.heardOnThePhone.append($0) }
        watch.onSharing = { [standIn] in standIn.heard($0) }
    }

    func run() -> [Task<Void, Never>] {
        tasks = [
            Task { [host] in await host.run() },
            Task { [phone] in await phone.run() },
            Task { [watch] in await watch.run() },
            Task { [standIn] in await standIn.run() },
        ]
        return tasks
    }

    /// Out of reach of everybody, as a phone in a locker room is.
    func phoneGoesAway() {
        for link in [phoneToHost, hostToPhone, phoneToWatch, watchToPhone] { link.setReachable(false) }
    }

    func phoneComesBack() {
        for link in [phoneToHost, hostToPhone, phoneToWatch, watchToPhone] { link.setReachable(true) }
    }

    /// The phone on the host's match, the watch following it, and the watch told the code.
    func phoneJoins() async {
        phone.beginJoining()
        await eventually { phone.role == .guest && watch.log.sessionID == host.log.sessionID && !watch.canEndSession }
        await phone.send(.standby(SharingStandby(code: code, isThrough: true)))
        await eventually { sharing.standbyCode == code }
    }
}

@Suite("A watch standing in for its phone")
@MainActor
struct WatchStandInTests {
    @Test func aWatchWithNoPhoneJoinsTheHostItself() async throws {
        let court = Court()
        court.phoneGoesAway()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }

        court.standIn.join(code)
        await eventually { court.standIn.joining == .joined }

        #expect(court.radio.joined == code, "dialled the host on its own radio")
        #expect(court.watch.log.sessionID == court.host.log.sessionID)
        #expect(court.watch.role == .guest)
        #expect(court.heardOnThePhone.isEmpty, "a phone that is not there is not asked")

        court.watch.tap(team: .b)
        await eventually { points(court.host) == BySide(a: 1, b: 1) }
        #expect(points(court.host) == BySide(a: 1, b: 1), "the wrist scores on the host")
        court.host.tap(team: .a)
        await eventually { points(court.watch) == BySide(a: 2, b: 1) }
        #expect(points(court.watch) == BySide(a: 2, b: 1), "and hears the host")
    }

    @Test func aNewCodeTypedWhileOnTheHostsRadioIsTheOneDialled() async throws {
        let court = Court()
        court.phoneGoesAway()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        court.standIn.join(code)
        await eventually { court.standIn.joining == .joined }

        let other = try #require(SessionCode("730264"))
        court.standIn.join(other)
        await eventually { court.radio.joined == other }

        #expect(court.radio.joined == other)
        #expect(court.radio.stops > 0, "the old link was hung up first")
        #expect(court.sharing.standbyCode == other)
    }

    @Test func thePhoneGetsTheFirstGoWhenItIsThere() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await eventually { court.watch.isPairReachable }

        court.standIn.join(code)
        await eventually { court.heardOnThePhone == [.join(code)] }
        #expect(court.heardOnThePhone == [.join(code)])

        await court.phone.send(.state(.joined))
        await eventually { court.standIn.joining == .joined }
        #expect(court.standIn.joining == .joined)
        #expect(court.radio.joined == nil, "the wrist never dialled")
        #expect(court.sharing.standbyCode == code, "but keeps the code in case it has to")
    }

    @Test func aPhoneThatFindsNothingHandsTheJoinToTheWrist() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await eventually { court.watch.isPairReachable }

        court.standIn.join(code)
        await eventually { !court.heardOnThePhone.isEmpty }
        await court.phone.send(.state(.failed(.notFound)))

        await eventually { court.standIn.joining == .joined && court.heardOnThePhone.contains(.cancel) }
        #expect(court.radio.joined == code)
        #expect(court.heardOnThePhone.contains(.cancel), "the phone was told to stop looking")
        #expect(court.watch.log.sessionID == court.host.log.sessionID)
    }

    /// A phone suspended in the middle of looking never says how it went.
    @Test func aPhoneThatSaysNothingIsOnlyWaitedForSoLong() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await eventually { court.watch.isPairReachable }

        court.standIn.join(code)
        await eventually { court.standIn.joining == .joined && court.heardOnThePhone.contains(.cancel) }

        #expect(court.radio.joined == code)
        #expect(court.heardOnThePhone.contains(.cancel))
    }

    @Test func aWrongCodeIsNotTriedAgainOnTheWrist() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await eventually { court.watch.isPairReachable }

        court.standIn.join(code)
        await eventually { !court.heardOnThePhone.isEmpty }
        await court.phone.send(.state(.failed(.rejected)))

        await eventually { court.standIn.joining == .failed(.rejected) }
        #expect(court.standIn.joining == .failed(.rejected))
        #expect(court.radio.joined == nil)
        #expect(court.sharing.standbyCode == nil)
    }

    @Test func aWatchThatFindsNothingSaysSo() async throws {
        var timing = quick
        timing.ownWait = .milliseconds(300)
        let court = Court(hostIsThere: false, timing: timing)
        court.phoneGoesAway()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }

        court.standIn.join(code)
        await eventually { court.standIn.joining == .failed(.notFound) }

        #expect(court.standIn.joining == .failed(.notFound))
        #expect(court.radio.stops > 0, "hung up")
        #expect(court.sharing.standbyCode == nil)
        #expect(court.watch.isJoining == false)
    }

    @Test func theWatchStandsInWhenItsPhoneGoesAwayMidMatch() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await court.phoneJoins()
        try await Task.sleep(for: .milliseconds(300))
        #expect(court.radio.joined == nil, "not while the phone is carrying it")

        court.phoneGoesAway()
        await eventually { court.radio.joined == code }
        #expect(court.radio.joined == code, "the wrist picked it up")

        court.host.tap(team: .b)
        await eventually { points(court.watch) == BySide(a: 1, b: 1) }
        #expect(points(court.watch) == BySide(a: 1, b: 1), "over its own link")
        court.watch.tap(team: .a)
        await eventually { points(court.host) == BySide(a: 2, b: 1) }
        #expect(points(court.host) == BySide(a: 2, b: 1))
    }

    @Test func theWatchHandsBackWhenItsPhoneIsThroughAgain() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await court.phoneJoins()
        court.phoneGoesAway()
        await eventually { court.sharing.reachablePeers > 0 }

        court.phoneComesBack()
        await court.phone.send(.standby(SharingStandby(code: code, isThrough: true)))
        await eventually { court.radio.stops > 0 }

        #expect(court.radio.stops > 0, "hung up its own link")
        #expect(court.sharing.isSharing == false)
        #expect(court.watch.log.sessionID == court.host.log.sessionID, "and kept the match")
        #expect(court.sharing.standbyCode == code, "and the code, for the next time")

        court.host.tap(team: .b)
        await eventually { points(court.watch) == BySide(a: 1, b: 1) }
        #expect(points(court.watch) == BySide(a: 1, b: 1), "the phone carries it again")
    }

    /// Back is not through: the phone may be no nearer the host than it was.
    @Test func aPhoneThatIsBackButNotThroughIsNotHandedTheMatch() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await court.phoneJoins()
        court.phoneGoesAway()
        // Said as it lost the host, as its own coordinator would, and so said again on the way back.
        await court.phone.send(.standby(SharingStandby(code: code, isThrough: false)))
        await eventually { court.sharing.reachablePeers > 0 }

        for link in [court.phoneToWatch, court.watchToPhone] { link.setReachable(true) }
        await eventually { court.watch.isPairReachable }
        try await Task.sleep(for: .milliseconds(300))

        #expect(court.radio.stops == 0)
        #expect(court.sharing.reachablePeers > 0)
    }

    @Test func leavingForgetsTheCode() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await court.phoneJoins()

        court.sharing.leave()
        #expect(court.sharing.standbyCode == nil)
        court.phoneGoesAway()
        try await Task.sleep(for: .milliseconds(400))

        #expect(court.radio.joined == nil, "nothing to stand in for")
        #expect(court.watch.state == nil)
    }

    /// The host's own watch has nobody to reach but the phone it is paired to.
    @Test func aHostsWatchNeverStandsIn() async throws {
        let court = Court(hostLog: MatchLog(), hostRole: .solo)
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        court.phone.configure(counting)
        court.phone.startSharing()
        await eventually { court.watch.state != nil && court.watch.canEndSession }

        court.sharing.keepOnStandby(code)
        court.phoneGoesAway()
        try await Task.sleep(for: .milliseconds(400))

        #expect(court.radio.joined == nil)
        #expect(court.standIn.link == .up, "its own match is never somebody else's to lose")
    }

    // MARK: - Saying so on the wrist

    @Test func theWristSaysSoWhileNothingCarriesTheMatch() async throws {
        var timing = quick
        timing.grace = .seconds(1)
        let court = Court(timing: timing)
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await court.phoneJoins()
        #expect(court.standIn.link == .up, "the phone is carrying it")

        court.phoneGoesAway()
        await eventually { court.standIn.link == .reconnecting }
        #expect(court.standIn.link == .reconnecting, "the phone went and the wrist has not picked it up yet")

        await eventually { court.radio.joined == code && court.standIn.link == .up }
        #expect(court.standIn.link == .up, "on its own link now")

        court.radio.drop()
        await eventually { court.standIn.link == .reconnecting }
        #expect(court.standIn.link == .reconnecting, "and that went too")
    }

    @Test func aPhoneThatIsBackButNotThroughIsStillReconnecting() async throws {
        var timing = quick
        timing.grace = .seconds(10)
        let court = Court(timing: timing)
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await court.phoneJoins()

        await court.phone.send(.standby(SharingStandby(code: code, isThrough: false)))
        await eventually { court.standIn.link == .reconnecting }

        #expect(court.standIn.link == .reconnecting)
    }

    @Test func aWatchWithNoWayBackSaysItIsCutOff() async throws {
        var timing = quick
        timing.grace = .seconds(10)
        let court = Court(timing: timing)
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await court.phoneJoins()

        court.phoneGoesAway()
        // The phone says its standby again whenever it sees the watch reconnect, and one said
        // just before it went can still be on its way in. Only once the watch has seen it go
        // is the code gone for good.
        await eventually { !court.watch.isPairReachable }
        // What a relaunch leaves: the match on disk, the code nowhere.
        court.sharing.keepOnStandby(nil)
        await eventually { court.standIn.link == .down }

        #expect(court.standIn.link == .down)
    }

    @Test func anOlderPhoneThatNeverSaysIsTrustedAsBefore() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        court.phone.beginJoining()
        await eventually { court.watch.log.sessionID == court.host.log.sessionID && !court.watch.canEndSession }

        #expect(court.standIn.link == .up)
        court.phoneGoesAway()
        await eventually { court.standIn.link == .down }
        #expect(court.standIn.link == .down, "and without a code there is no way back")
    }

    @Test func aWatchKnowsItsOwnPhoneFromTheHostsRadio() async throws {
        let (paired, phone) = LoopbackTransport.pair()
        let (radio, host) = LoopbackTransport.pair()
        paired.setReachable(false)
        let links = FanOutTransport()
        links.attach(paired, as: .pairedDevice)
        links.attach(radio, as: .sharedSession)

        #expect(links.isReachable)
        #expect(links.isPairReachable == false)
        _ = (phone, host)
    }
}
