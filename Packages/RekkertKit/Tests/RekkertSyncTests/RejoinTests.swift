import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
}

private func seeded(_ device: DeviceID, points: Int = 0) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(setup), from: device)
    for _ in 0 ..< points { log.append(.point(round: 0, court: 0, team: .a), from: device) }
    return log
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .traditional(let session) = store.state else { return nil }
    return session.score.points
}

/// Stands in for the Bluetooth link, which needs a radio. Only what the coordinator reads.
private final class RadioStandIn: SharedLink, @unchecked Sendable {
    let reachability: AsyncStream<Bool>
    private let updates: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var count = 0

    init() {
        var continuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { continuation = $0 }
        updates = continuation
    }

    var reachableCount: Int { lock.withLock { count } }

    func present(_ peers: Int) {
        lock.withLock { count = peers }
        updates.yield(peers > 0)
    }

    func startHosting(code: SessionCode, share: UUID) {}
    func resumeHosting(code: SessionCode, share: UUID) {}
    func startJoining(code: SessionCode) {}
    func resumeJoining(code: SessionCode) {}
    func stop() { lock.withLock { count = 0 } }
}

/// A guest that types the code for a match it is already holding — back from a relaunch, or
/// reaching the host again after the "still looking" notice.
@Suite("Walking back in")
@MainActor
struct RejoinTests {
    /// The first thing the host's link hands a guest is a snapshot, and a guest that was still
    /// joining used to adopt it: the live match was filed to History as displaced, the
    /// "switched to the newer match" notice went up over it, and whatever had been scored
    /// here while out of reach went with the outbox.
    @Test func aGuestWalkingBackInKeepsWhatItScoredWhileAway() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionStore(directory: directory)

        let hostDevice = DeviceID()
        let match = seeded(hostDevice, points: 1)
        let (one, two) = LoopbackTransport.pair()
        // Apart, so nothing is exchanged until the test says so.
        one.setReachable(false)
        two.setReachable(false)
        let hostFan = FanOutTransport()
        hostFan.attach(one, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(two, as: .sharedSession)
        let host = MatchStore(
            device: hostDevice, transport: hostFan,
            session: ActiveSession(log: match, role: .host), snapshotInterval: 0
        )
        let guest = MatchStore(
            device: DeviceID(), transport: guestFan, store: persistence,
            session: ActiveSession(log: match, role: .guest), snapshotInterval: 0
        )
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }

        guest.tap(team: .b)
        await eventually { points(guest) == BySide(a: 1, b: 1) }

        guest.beginJoining()
        #expect(guest.isJoining)
        // The host's copy, as its link coming up hands it over before any hello is answered.
        one.queue(try Wire.snapshot(host.log).encoded())
        await eventually { !guest.isJoining }

        #expect(guest.isJoining == false, "the join concluded on the match it already held")
        #expect(guest.role == .guest)
        #expect(guest.log.sessionID == match.sessionID)
        #expect(points(guest) == BySide(a: 1, b: 1), "the point scored while away is still there")
        #expect(guest.replacedSessionTitle == nil, "nothing was switched")
        #expect(try persistence.history().isEmpty, "and the live match was not filed as displaced")

        one.setReachable(true)
        two.setReachable(true)
        await eventually { points(host) == BySide(a: 1, b: 1) }
        #expect(points(host) == BySide(a: 1, b: 1), "and the host is told about it")
    }

    /// The join sheet's Cancel, and the "try again" on a failed search, used to go through
    /// `stop()`, which for a guest means leaving. A guest back from a relaunch who mistyped the
    /// code lost the match it was holding.
    @Test func aFailedSearchDoesNotThrowAwayTheMatchAGuestAlreadyHolds() throws {
        let store = MatchStore(
            device: DeviceID(), transport: LoopbackTransport(),
            session: ActiveSession(log: seeded(DeviceID(), points: 1), role: .guest), snapshotInterval: 0
        )
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())

        sharing.join(try #require(SessionCode("K9M4PT")))
        sharing.apply(.failed(.notFound))
        #expect(sharing.phase == .failed(.notFound), "a search that never found anything still says so")

        sharing.dismissFailure()
        #expect(sharing.phase == .off)
        #expect(store.state != nil, "the match it already held is kept")
        #expect(store.role == .guest)
    }

    @Test func cancellingASearchIsNotLeaving() throws {
        let store = MatchStore(
            device: DeviceID(), transport: LoopbackTransport(),
            session: ActiveSession(log: seeded(DeviceID(), points: 1), role: .guest), snapshotInterval: 0
        )
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        sharing.join(try #require(SessionCode("K9M4PT")))

        sharing.cancelJoining()
        #expect(sharing.phase == .off)
        #expect(store.isJoining == false)
        #expect(store.state != nil, "still on the match")
        #expect(store.role == .guest)

        // Whereas stopping is stepping off, as it always was.
        sharing.join(try #require(SessionCode("K9M4PT")))
        sharing.stop()
        #expect(store.state == nil)
        #expect(store.role == .solo)
    }

    /// A host whose phone is locked is off the network altogether, so the network search finds
    /// nothing and gives up — while Bluetooth has already handed the match over. That used to
    /// be reported as "nothing found": the badge went, the network was never looked for
    /// again, and dismissing the failure left the match.
    @Test func aMatchFoundOverBluetoothIsNotANetworkFailure() async throws {
        let (one, two) = LoopbackTransport.pair()
        let guestFan = FanOutTransport()
        guestFan.attach(two, as: .sharedSession)
        let store = MatchStore(device: DeviceID(), transport: guestFan, snapshotInterval: 0)
        let radio = RadioStandIn()
        let sharing = SharedSession(store: store, link: LocalNetworkTransport(), bluetooth: radio)
        let running = Task { await store.run() }
        defer { running.cancel() }

        sharing.join(try #require(SessionCode("H7K3MR")))
        // The host's match, arriving over the radio.
        radio.present(1)
        one.queue(try Wire.snapshot(seeded(DeviceID(), points: 2)).encoded())
        await eventually { !store.isJoining && sharing.reachablePeers == 1 }
        #expect(store.role == .guest)

        sharing.apply(.failed(.notFound))

        #expect(sharing.phase == .searching, "the network is something to keep looking for")
        #expect(sharing.isSharing)
        #expect(sharing.isReconnecting == false, "the radio has it, so nothing is being reconnected")
        #expect(sharing.reachablePeers == 1)
        #expect(store.state != nil)
        #expect(store.role == .guest)
        #expect(sharing.revival == .joining(SessionCode("H7K3MR")!), "and coming to the front looks again")

        sharing.dismissFailure()
        #expect(store.state != nil, "there was no failure to dismiss")
    }

    /// The radio has a peer but the match itself has not landed yet when the network gives up.
    /// Still not a failure: the store is left waiting for what the radio is about to bring.
    @Test func aRadioPeerHoldsOffTheNetworkGivingUp() async throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let radio = RadioStandIn()
        let sharing = SharedSession(store: store, link: LocalNetworkTransport(), bluetooth: radio)

        sharing.join(try #require(SessionCode("H7K3MR")))
        radio.present(1)
        await eventually { sharing.reachablePeers == 1 }

        sharing.apply(.failed(.notFound))

        #expect(sharing.phase == .searching)
        #expect(store.isJoining, "still waiting to be handed the match")
    }

    @Test func nothingFoundOnEitherLinkIsStillAFailure() throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let radio = RadioStandIn()
        let sharing = SharedSession(store: store, link: LocalNetworkTransport(), bluetooth: radio)

        sharing.join(try #require(SessionCode("H7K3MR")))
        sharing.apply(.failed(.notFound))

        #expect(sharing.phase == .failed(.notFound))
        #expect(store.isJoining == false)
    }

    /// The network went first and the radio carried the match for a while; when the radio goes
    /// too, that is when the match is lost — and it used to go unremarked, because the notice
    /// was only ever armed by the network dropping.
    @Test func theLossIsNoticedWhenTheRadioGoesAfterTheNetworkDid() async throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let radio = RadioStandIn()
        let sharing = SharedSession(
            store: store, link: LocalNetworkTransport(), bluetooth: radio,
            graceBeforeNotice: .milliseconds(60)
        )
        sharing.join(try #require(SessionCode("H7K3MR")))
        sharing.apply(.joined(peers: 1))
        radio.present(1)
        await eventually { sharing.reachablePeers == 1 }

        sharing.apply(.searching)
        try await Task.sleep(for: .milliseconds(200))
        #expect(sharing.hasLostTheMatch == false, "the radio still has it")

        radio.present(0)
        await eventually { sharing.hasLostTheMatch }
        #expect(sharing.hasLostTheMatch, "and now it is gone")
    }
}

/// A search left running underneath something else.
@Suite("A join that was never finished")
@MainActor
struct AbandonedJoinTests {
    /// The join sheet swiped away mid-search, then "share this match". The search was still
    /// waiting to conclude, and did so on the first guest to say hello — making the host a
    /// guest on its own match, with no way to end it.
    @Test func sharingDoesNotLetAStaleJoinConcludeOnAGuest() async throws {
        let hostDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()
        let fan = FanOutTransport()
        fan.attach(two, as: .sharedSession)
        let store = MatchStore(
            device: hostDevice, transport: fan,
            session: ActiveSession(log: seeded(hostDevice, points: 1)), snapshotInterval: 0
        )
        let running = Task { await store.run() }
        defer { running.cancel() }

        store.beginJoining()
        store.startSharing()
        #expect(store.isJoining == false, "hosting is the end of looking")

        // A guest that was handed the match repeats it back, as the first one always does.
        one.queue(try Wire.snapshot(store.log).encoded())
        try await settle()

        #expect(store.role == .host, "still the host of its own match")
        #expect(store.canEndSession)
    }

    @Test func theCoordinatorGivesUpTheSearchBeforeHosting() throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        store.configure(setup)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())

        sharing.join(try #require(SessionCode("K9M4PT")))
        #expect(store.isJoining)

        sharing.host()

        #expect(store.isJoining == false)
        #expect(store.role == .host)
        if case .hosting = sharing.phase {} else { Issue.record("hosting, not searching") }
        #expect(sharing.revival != .joining(SessionCode("K9M4PT")!), "and nothing puts the search back")
    }

    /// Joining somebody else's match from a phone that is hosting one is the end of hosting.
    @Test func joiningWhileHostingStopsHostingFirst() throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        store.configure(setup)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        sharing.host()
        #expect(store.role == .host)

        sharing.join(try #require(SessionCode("K9M4PT")))

        #expect(store.role == .solo, "no longer the host of anything")
        #expect(store.isJoining)
        #expect(sharing.phase == .searching)
        #expect(sharing.revival == .joining(SessionCode("K9M4PT")!))
    }

    /// Starting a match of your own while a search is running is giving up on the search, and
    /// the coordinator has to be told so the link comes down with it.
    @Test func startingAMatchDuringASearchLetsGoOfTheLink() {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        var letGo = false
        store.onLeft = { letGo = true }

        store.beginJoining()
        store.startNewSession()
        store.configure(setup)

        #expect(store.isJoining == false)
        #expect(letGo, "the search was abandoned, and whoever held the link was told")
        #expect(store.role == .solo)
    }
}
