import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

/// The coordinator on its own. On macOS the local-network transport compiles to an inert
/// stub, which is exactly what is wanted here: what is under test is the bookkeeping between
/// the screens and the store, not the sockets.
@Suite("Hosting and joining")
@MainActor
struct SharedSessionTests {
    private func make() -> (SharedSession, MatchStore) {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        return (SharedSession(store: store, link: LocalNetworkTransport()), store)
    }

    @Test func thereIsNothingToShareBeforeAMatchStarts() {
        let (sharing, _) = make()
        sharing.host()

        #expect(sharing.isSharing == false)
        #expect(sharing.code == nil)
    }

    @Test func hostingGivesOutACodeAndTakesTheRole() throws {
        let (sharing, store) = make()
        store.configure(setup)

        sharing.host()
        let code = try #require(sharing.code)

        #expect(sharing.isSharing)
        #expect(store.role == .host)
        #expect(code.letters.count == SessionCode.length)
        #expect(store.canEndSession, "the host keeps the whistle")
    }

    @Test func theCodeIsPinnedWhenOneIsGiven() throws {
        let (sharing, store) = make()
        store.configure(setup)

        let chosen = try #require(SessionCode("730264"))
        sharing.host(code: chosen)
        #expect(sharing.code == chosen)
    }

    @Test func stoppingPutsTheMatchBackInYourOwnHands() throws {
        let (sharing, store) = make()
        store.configure(setup)
        sharing.host()

        sharing.stop()

        #expect(sharing.isSharing == false)
        #expect(sharing.peers == 0)
        #expect(store.role == .solo)
        #expect(store.state != nil, "stopping sharing does not end the match")
    }

    @Test func joiningLooksForItAndTellsTheStoreToExpectOne() throws {
        let (sharing, store) = make()
        sharing.join(try #require(SessionCode("730264")))

        #expect(sharing.phase == .searching)
        #expect(sharing.isSharing, "it counts as sharing while it is looking")
    }

    /// Leaving is not the same as ending: the match goes on without this phone.
    @Test func leavingASharedMatchStepsOffItRatherThanEndingIt() throws {
        let (sharing, store) = make()
        store.configure(setup)
        store.tap(team: .a)
        // Stand in for having joined somebody else's.
        store.beginJoining()
        sharing.join(try #require(SessionCode("730264")))
        store.startSharing()

        #expect(store.role == .host, "startSharing is refused for a guest, allowed here")

        sharing.stop()
        #expect(store.role == .solo)
    }

    /// The watch's Leave reaches the phone as a notice. The store drops the match on it, and
    /// the link to the host has to come down too, or the next snapshot puts the match back.
    @Test func theWatchLeavingTakesSharingDownWithIt() async throws {
        let (phoneToWatch, watchToPhone) = LoopbackTransport.pair()
        var log = MatchLog()
        log.append(.configure(setup), from: DeviceID())
        let store = MatchStore(
            device: DeviceID(), transport: phoneToWatch,
            session: ActiveSession(log: log, role: .guest), snapshotInterval: 0
        )
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        let running = Task { await store.run() }
        defer { running.cancel() }
        sharing.join(try #require(SessionCode("730264")))
        sharing.apply(.joined(peers: 1))
        #expect(sharing.phase == .joined)

        watchToPhone.queue(try Wire.left(sessionID: log.sessionID).encoded())

        await eventually { sharing.phase == .off }
        #expect(sharing.phase == .off)
        #expect(store.state == nil)
        #expect(store.role == .solo)
    }

    @Test func aFailureCanBeDismissedBackToNothing() {
        let (sharing, store) = make()
        store.configure(setup)
        sharing.host()

        sharing.dismissFailure()
        #expect(sharing.isSharing, "there was no failure to dismiss")

        sharing.stop()
        #expect(sharing.phase == .off)
    }

    /// The transport reports on its own queue, so a status from just before `stop()` can be
    /// read just after it. It used to put the phase back to something with nothing behind it.
    @Test func aStatusFromBeforeStoppingIsIgnored() throws {
        let (sharing, store) = make()
        sharing.join(try #require(SessionCode("730264")))
        sharing.stop()

        sharing.apply(.joined(peers: 1))
        #expect(sharing.phase == .off)
        #expect(sharing.isSharing == false)
        #expect(sharing.peers == 0)

        sharing.apply(.failed(.notFound))
        #expect(sharing.phase == .off, "nor is a late refusal shown for a search already cancelled")
        #expect(store.role == .solo)
    }

    /// A listener the system took away and the transport put back reports hosting again, and
    /// the phase has to follow it out of the failure it was in meanwhile.
    @Test func hostingComesBackWhenTheListenerIsPutBack() throws {
        let (sharing, store) = make()
        store.configure(setup)
        sharing.host()
        let code = try #require(sharing.code)

        sharing.apply(.failed(.blocked))
        #expect(sharing.phase == .failed(.blocked))

        sharing.apply(.hosting(peers: 0))
        #expect(sharing.phase == .hosting(code))
        #expect(sharing.code == code, "the same code, which the guests still have")
    }
}

@Suite("Losing the host")
@MainActor
struct LostHostTests {
    private func joined(grace: Duration = .milliseconds(80)) -> SharedSession {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport(), graceBeforeNotice: grace)
        sharing.join(SessionCode("730264")!)
        sharing.apply(.joined(peers: 1))
        return sharing
    }

    @Test func aHostThatGoesAwayIsWorthSayingSo() async {
        let sharing = joined()
        #expect(sharing.hasLostTheMatch == false)

        sharing.apply(.searching)
        await eventually { sharing.hasLostTheMatch }
        #expect(sharing.hasLostTheMatch, "the score on screen stopped being true")
    }

    /// Most drops heal on their own — a phone glanced at, a moment of bad Wi-Fi — and saying
    /// so every time would be worse than saying nothing.
    @Test func aBlipIsNotWorthMentioning() async throws {
        let sharing = joined(grace: .milliseconds(400))

        sharing.apply(.searching)
        try await Task.sleep(for: .milliseconds(50))
        sharing.apply(.joined(peers: 1))

        try await Task.sleep(for: .milliseconds(500))
        #expect(sharing.hasLostTheMatch == false, "it came straight back")
    }

    @Test func comingBackClearsTheNotice() async {
        let sharing = joined()
        sharing.apply(.searching)
        await eventually { sharing.hasLostTheMatch }

        sharing.apply(.joined(peers: 1))
        #expect(sharing.hasLostTheMatch == false)
    }

    @Test func aHostIsNeverToldItLostItself() async throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        let sharing = SharedSession(
            store: store, link: LocalNetworkTransport(), graceBeforeNotice: .milliseconds(80)
        )
        sharing.host()

        // Everybody left, which for a host is ordinary rather than a loss.
        sharing.apply(.searching)
        try await Task.sleep(for: .milliseconds(200))

        #expect(sharing.hasLostTheMatch == false)
        #expect(sharing.isSharing, "still hosting, still waiting")
    }
}

/// A guest's only link to the host, standing in for the radio: up from a join until a stop.
private final class Line: SharedLink, @unchecked Sendable {
    let guestEnd: LoopbackTransport
    let hostEnd: LoopbackTransport
    let reachability: AsyncStream<Bool>
    private let updates: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var up = false

    init() {
        (guestEnd, hostEnd) = LoopbackTransport.pair()
        guestEnd.setReachable(false)
        hostEnd.setReachable(false)
        var continuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { continuation = $0 }
        updates = continuation
    }

    var reachableCount: Int { lock.withLock { up ? 1 : 0 } }

    func startHosting(code: SessionCode, share: UUID) {}
    func resumeHosting(code: SessionCode, share: UUID) {}
    func resumeJoining(code: SessionCode) {}

    func startJoining(code: SessionCode) {
        lock.withLock { up = true }
        guestEnd.setReachable(true)
        hostEnd.setReachable(true)
        updates.yield(true)
    }

    func stop() {
        lock.withLock { up = false }
        guestEnd.setReachable(false)
        hostEnd.setReachable(false)
        updates.yield(false)
    }
}

@Suite("Between two of the host's matches")
@MainActor
struct BetweenMatchesTests {
    /// A guest is still the host's guest once a match ends, and still on the link, which is how
    /// the host's next match reaches it. Starting one of its own there is stepping off, as a
    /// preset always did — but the New screen went straight to `configure`, which left the guest
    /// holding a match it could not end, and a host with nothing on took it up as its own. A
    /// preset stepped off, but only after its first snapshot had gone out to that host.
    @Test(arguments: [false, true])
    func aGuestStartingItsOwnMatchStepsOff(fromPreset: Bool) async throws {
        let line = Line()
        let hostFan = FanOutTransport()
        hostFan.attach(line.hostEnd, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(line.guestEnd, as: .sharedSession)
        let host = MatchStore(device: DeviceID(), transport: hostFan, snapshotInterval: 0)
        let guest = MatchStore(device: DeviceID(), transport: guestFan, snapshotInterval: 0)
        let sharing = SharedSession(store: guest, link: LocalNetworkTransport(), bluetooth: line)
        defer { sharing.close() }
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }

        host.configure(setup)
        host.startSharing()
        sharing.join(try #require(SessionCode("730264")))
        await eventually { guest.role == .guest && guest.state != nil }
        host.tap(team: .a)
        host.finish()
        await eventually { host.state == nil && guest.state == nil }
        guest.acknowledgeResult()

        let own = PresetConfiguration.pointCount(rules: PointCountRules(target: 21), teams: BySide(a: .home, b: .away))
        if fromPreset {
            guest.start(Preset(name: "Our court", configuration: own))
        } else {
            guest.configure(own.makeSetup())
        }
        await quietPeriod()

        #expect(guest.role == .solo, "its own match, not the host's")
        #expect(guest.canEndSession, "and so its own to end")
        #expect(host.state == nil, "the host was not handed it")
        #expect(sharing.phase == .off, "and the link to the host came down")
    }
}
