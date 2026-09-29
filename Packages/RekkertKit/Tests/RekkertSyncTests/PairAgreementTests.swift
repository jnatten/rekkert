import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let code = SessionCode("482915")!

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

private func seeded(startedAt: Date = .now, points: Int = 0) -> MatchLog {
    let device = DeviceID()
    var log = MatchLog(createdAt: startedAt)
    log.append(.configure(counting), from: device)
    for _ in 0 ..< points { log.append(.point(round: 0, court: 0, team: .a), from: device) }
    return log
}

private final class Counted: PeerTransport, @unchecked Sendable {
    let inner: LoopbackTransport
    private let lock = NSLock()
    private var queues = 0

    init(_ inner: LoopbackTransport) { self.inner = inner }

    var queued: Int { lock.withLock { queues } }
    var inbound: AsyncStream<InboundPacket> { inner.inbound }
    var reachability: AsyncStream<Bool> { inner.reachability }
    var isReachable: Bool { inner.isReachable }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { await inner.sendLive(payload) }
    func publishSnapshot(_ payload: Data) { inner.publishSnapshot(payload) }
    func queue(_ payload: Data) {
        lock.withLock { queues += 1 }
        inner.queue(payload)
    }
}

private final class Radio: SharedLink, @unchecked Sendable {
    let watchEnd: LoopbackTransport
    let hostEnd: LoopbackTransport
    let reachability: AsyncStream<Bool>
    private let updates: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var up = false

    init() {
        (watchEnd, hostEnd) = LoopbackTransport.pair()
        watchEnd.setReachable(false)
        hostEnd.setReachable(false)
        var continuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { continuation = $0 }
        updates = continuation
    }

    var reachableCount: Int { lock.withLock { up ? 1 : 0 } }
    func startHosting(code: SessionCode, share: UUID) {}
    func resumeHosting(code: SessionCode, share: UUID) {}
    func resumeJoining(code: SessionCode) {}
    func startJoining(code: SessionCode) { set(true) }
    func stop() { set(false) }

    private func set(_ value: Bool) {
        lock.withLock { up = value }
        watchEnd.setReachable(value)
        hostEnd.setReachable(value)
        updates.yield(value)
    }
}

/// A phone and its watch, each through a fan-out on the paired scope as in the app.
@MainActor
private func pocket(phone phoneSession: ActiveSession?, watch watchSession: ActiveSession?)
    -> (phone: MatchStore, watch: MatchStore, toWatch: Counted, toPhone: Counted)
{
    let (phoneEnd, watchEnd) = LoopbackTransport.pair()
    let toWatch = Counted(phoneEnd)
    let toPhone = Counted(watchEnd)
    let phoneFan = FanOutTransport()
    phoneFan.attach(toWatch, as: .pairedDevice)
    let watchFan = FanOutTransport()
    watchFan.attach(toPhone, as: .pairedDevice)
    return (
        MatchStore(device: DeviceID(), transport: phoneFan, session: phoneSession, snapshotInterval: 0),
        MatchStore(device: DeviceID(), transport: watchFan, session: watchSession, snapshotInterval: 0, keepsHistory: false),
        toWatch, toPhone
    )
}

@Suite("A phone and its watch agree on one match", .serialized)
@MainActor
struct PairAgreementTests {
    /// Left behind by a stand-in on an earlier build: a watch that took itself for a guest,
    /// still holding a match from before.
    @Test func aHostsWatchLeftAGuestGivesWayToThePhonesMatch() async throws {
        let hosted = seeded(startedAt: .now.addingTimeInterval(-600), points: 2)
        let old = seeded(startedAt: .now, points: 1)
        let (phone, watch, _, _) = pocket(
            phone: ActiveSession(log: hosted, role: .host),
            watch: ActiveSession(log: old, role: .guest)
        )
        let tasks = [phone, watch].map { store in Task { await store.run() } }
        defer { tasks.forEach { $0.cancel() } }

        await eventually { watch.log.sessionID == hosted.sessionID && watch.role == .solo }

        #expect(watch.log.sessionID == hosted.sessionID, "the wrist shows the match the phone is hosting")
        #expect(watch.role == .solo)
        #expect(phone.log.sessionID == hosted.sessionID, "and the host was never taken over")
        #expect(phone.canEndSession, "and it can still end its own match")
    }

    @Test func twoGuestsOnDifferentMatchesSettleOnOne() async throws {
        let older = seeded(startedAt: .now.addingTimeInterval(-600), points: 1)
        let newer = seeded(startedAt: .now, points: 2)
        let (phone, watch, toWatch, toPhone) = pocket(
            phone: ActiveSession(log: older, role: .guest),
            watch: ActiveSession(log: newer, role: .guest)
        )
        let tasks = [phone, watch].map { store in Task { await store.run() } }
        defer { tasks.forEach { $0.cancel() } }

        await eventually { phone.log.sessionID == watch.log.sessionID }
        #expect(phone.log.sessionID == newer.sessionID)
        #expect(watch.log.sessionID == newer.sessionID)

        await quietPeriod()
        let queued = (toWatch.queued, toPhone.queued)
        try await Task.sleep(for: .seconds(1))
        #expect(toWatch.queued - queued.0 < 5, "not pushing sessions at each other")
        #expect(toPhone.queued - queued.1 < 5)
    }

    @Test func aWatchLaunchedAsAGuestFollowsItsPhoneAgain() async throws {
        let own = seeded(startedAt: .now, points: 3)
        let old = seeded(startedAt: .now.addingTimeInterval(-600), points: 1)
        let (phone, watch, _, _) = pocket(
            phone: ActiveSession(log: own),
            watch: ActiveSession(log: old, role: .guest)
        )
        let sharing = SharedSession(store: watch, link: LocalNetworkTransport())
        _ = WatchStandIn(store: watch, sharing: sharing)
        let tasks = [phone, watch].map { store in Task { await store.run() } }
        defer { tasks.forEach { $0.cancel() } }

        await eventually { watch.log.sessionID == own.sessionID }

        #expect(watch.role == .solo)
        #expect(watch.log.sessionID == own.sessionID)
        #expect(phone.log.sessionID == own.sessionID, "the phone keeps its own match")
        #expect(phone.canEndSession)
    }

    @Test func aWatchThatStoodInFollowsItsPhoneToTheNextHost() async throws {
        let (host1ToPhone, phoneToHost1) = LoopbackTransport.pair()
        let (host2ToPhone, phoneToHost2) = LoopbackTransport.pair()
        let (phoneToWatch, watchToPhone) = LoopbackTransport.pair()
        host2ToPhone.setReachable(false)
        phoneToHost2.setReachable(false)
        let radio = Radio()

        let host1Fan = FanOutTransport()
        host1Fan.attach(host1ToPhone, as: .sharedSession)
        host1Fan.attach(radio.hostEnd, as: .sharedSession)
        let host1 = MatchStore(
            device: DeviceID(), transport: host1Fan,
            session: ActiveSession(log: seeded(points: 1), role: .host), snapshotInterval: 0
        )
        let host2 = MatchStore(
            device: DeviceID(), transport: host2ToPhone,
            session: ActiveSession(log: seeded(points: 3), role: .host), snapshotInterval: 0
        )

        let toWatch = Counted(phoneToWatch)
        let phoneFan = FanOutTransport()
        phoneFan.attach(toWatch, as: .pairedDevice)
        phoneFan.attach(phoneToHost1, as: .sharedSession)
        phoneFan.attach(phoneToHost2, as: .sharedSession)
        let phone = MatchStore(device: DeviceID(), transport: phoneFan, snapshotInterval: 0)

        let watchFan = FanOutTransport()
        watchFan.attach(watchToPhone, as: .pairedDevice)
        watchFan.attach(radio.watchEnd, as: .sharedSession)
        let watch = MatchStore(device: DeviceID(), transport: watchFan, snapshotInterval: 0, keepsHistory: false)
        let sharing = SharedSession(store: watch, link: LocalNetworkTransport(), bluetooth: radio)
        let standIn = WatchStandIn(
            store: watch, sharing: sharing,
            timing: StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(150)),
            tick: .milliseconds(20)
        )
        watch.onSharing = { standIn.heard($0) }

        let tasks = [
            Task { await host1.run() }, Task { await host2.run() }, Task { await phone.run() },
            Task { await watch.run() }, Task { await standIn.run() },
        ]
        defer { tasks.forEach { $0.cancel() } }

        phone.beginJoining()
        await eventually { phone.role == .guest && watch.log.sessionID == host1.log.sessionID }
        await phone.send(.standby(SharingStandby(code: code, isThrough: true)))
        await eventually { sharing.standbyCode == code }

        for link in [phoneToHost1, host1ToPhone, phoneToWatch, watchToPhone] { link.setReachable(false) }
        await eventually { sharing.reachablePeers > 0 }
        for link in [phoneToHost1, host1ToPhone, phoneToWatch, watchToPhone] { link.setReachable(true) }
        await phone.send(.standby(SharingStandby(code: code, isThrough: true)))
        await eventually { !sharing.isSharing }

        for link in [phoneToHost1, host1ToPhone] { link.setReachable(false) }
        await quietPeriod()
        for link in [phoneToHost2, host2ToPhone] { link.setReachable(true) }
        await quietPeriod()
        phone.beginJoining()
        await eventually { watch.log.sessionID == host2.log.sessionID }

        #expect(phone.log.sessionID == host2.log.sessionID)
        #expect(watch.log.sessionID == host2.log.sessionID, "the wrist follows the phone")
        let queued = toWatch.queued
        try await Task.sleep(for: .seconds(1))
        #expect(toWatch.queued - queued < 5, "and the two are not pushing sessions at each other")
    }
}
