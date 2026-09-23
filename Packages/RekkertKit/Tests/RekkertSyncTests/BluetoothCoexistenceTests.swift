import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

/// Stands in for the Bluetooth link, which needs a radio and so is never there where the tests
/// are. What is under test is the coordinator's bookkeeping, not the radio.
private final class FakeLink: SharedLink, @unchecked Sendable {
    let reachability: AsyncStream<Bool>
    private let updates: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var count = 0
    private(set) var hosted: (code: SessionCode, share: UUID)?
    private(set) var joined: SessionCode?
    private(set) var revivals = 0
    private(set) var stops = 0

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

    func startHosting(code: SessionCode, share: UUID) { hosted = (code, share) }
    func resumeHosting(code: SessionCode, share: UUID) { revivals += 1 }
    func startJoining(code: SessionCode) { joined = code }
    func resumeJoining(code: SessionCode) { revivals += 1 }
    func stop() {
        stops += 1
        lock.withLock { count = 0 }
    }
}

@Suite("Two links, one match")
@MainActor
struct BluetoothCoexistenceTests {
    private func make() -> (SharedSession, MatchStore, FakeLink) {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let radio = FakeLink()
        let sharing = SharedSession(
            store: store, link: LocalNetworkTransport(), bluetooth: radio,
            graceBeforeNotice: .milliseconds(60)
        )
        return (sharing, store, radio)
    }

    @Test func hostingOpensBothLinksOnTheOneCode() throws {
        let (sharing, store, radio) = make()
        store.configure(setup)
        let code = try #require(SessionCode("482915"))

        sharing.host(code: code)

        #expect(radio.hosted?.code == code, "the same code is read out for either way in")
        #expect(radio.hosted?.share == sharing.revival.share, "and the same share")
    }

    @Test func joiningLooksOnBothLinks() throws {
        let (sharing, _, radio) = make()
        let code = try #require(SessionCode("730264"))
        sharing.join(code)
        #expect(radio.joined == code)
    }

    @Test func stoppingClosesBoth() {
        let (sharing, store, radio) = make()
        store.configure(setup)
        sharing.host()
        sharing.stop()
        #expect(radio.stops == 1)
    }

    /// The case the whole transport exists for: the host's phone locked, so the network link
    /// went, but the score is still going through. Saying "reconnecting" here would be a worry
    /// about nothing.
    @Test func aMatchStillCarriedOverBluetoothIsNotReconnecting() async {
        let (sharing, _, radio) = make()
        sharing.join(SessionCode("482915")!)
        sharing.apply(.joined(peers: 1))

        // The network link goes first, which is what a host locking their phone looks like
        // from here, and only then does the radio report who it still has.
        sharing.apply(.searching)
        radio.present(1)
        await eventually { sharing.reachablePeers == 1 }

        #expect(sharing.isReconnecting == false, "Bluetooth still has it")
        #expect(sharing.reachablePeers == 1, "and somebody is still on the match")
    }

    @Test func aMatchOnNeitherLinkIsReconnecting() async {
        let (sharing, _, radio) = make()
        sharing.join(SessionCode("482915")!)
        sharing.apply(.joined(peers: 1))
        sharing.apply(.searching)
        radio.present(1)
        await eventually { sharing.reachablePeers == 1 }

        radio.present(0)
        await eventually { sharing.reachablePeers == 0 }

        #expect(sharing.isReconnecting, "now it really has gone quiet")
    }

    @Test func nobodyIsToldTheMatchIsLostWhileBluetoothHasIt() async throws {
        let (sharing, _, radio) = make()
        sharing.join(SessionCode("482915")!)
        sharing.apply(.joined(peers: 1))
        radio.present(1)
        await eventually { radio.reachableCount == 1 }

        sharing.apply(.searching)
        // Nothing to wait for — the point is that the notice never comes — so the only honest
        // way to say it did not is to give it longer than the grace.
        try await Task.sleep(for: .milliseconds(200))

        #expect(sharing.hasLostTheMatch == false, "it was never out of reach")
    }

    /// The same phone is usually on both links and nothing on the wire says so, so counting
    /// them together would tell four people there are eight of them.
    @Test func thePeerCountIsPeopleRatherThanLinks() async {
        let (sharing, _, radio) = make()
        sharing.join(SessionCode("482915")!)
        radio.present(1)
        await eventually { sharing.reachablePeers == 1 }
        sharing.apply(.joined(peers: 1))

        #expect(sharing.reachablePeers == 1, "one phone, reachable two ways, counted once")
    }
}

private extension SharedSession.Revival {
    var share: UUID? {
        if case .hosting(_, let share) = self { return share }
        return nil
    }
}

/// Running both links means the same phone answers twice. The outbox may only forget what has
/// reached everybody, so it matters that two answers from one phone are not mistaken for one
/// phone that is behind.
@Suite("Answers from two links at once")
struct TwoLinkReplyTests {
    private let session = UUID(uuidString: "6F2A9C41-0000-0000-0000-0000000000AA")!

    @Test func aPeerAnsweringOnBothLinksStillAcknowledges() throws {
        let phone = DeviceID()
        var vector = VersionVector()
        vector[phone] = 4
        let reply = try Wire.hello(sessionID: session, vector: vector).encoded()

        let folded = ReplyFold.fold([reply, reply], expected: 2)

        let acknowledgement = try #require(folded.acknowledgement, "both links answered")
        guard case .hello(_, let bound, _) = try Wire.decode(acknowledgement) else {
            Issue.record("an acknowledgement is a hello")
            return
        }
        #expect(bound[phone] == 4, "one phone heard twice is not a phone left behind")
    }

    @Test func oneLinkAnsweringForTwoAcknowledgesNothing() throws {
        var vector = VersionVector()
        vector[DeviceID()] = 4
        let reply = try Wire.hello(sessionID: session, vector: vector).encoded()

        let folded = ReplyFold.fold([reply, nil], expected: 2)

        #expect(folded.acknowledgement == nil, "somebody did not answer, so nothing may be forgotten")
    }

    /// Two phones genuinely at different points still bound the outbox at the slower one.
    @Test func theSlowerOfTwoStillSetsTheBound() throws {
        let phone = DeviceID()
        var ahead = VersionVector()
        ahead[phone] = 9
        var behind = VersionVector()
        behind[phone] = 3

        let folded = ReplyFold.fold([
            try Wire.hello(sessionID: session, vector: ahead).encoded(),
            try Wire.hello(sessionID: session, vector: behind).encoded(),
        ], expected: 2)

        let acknowledgement = try #require(folded.acknowledgement)
        guard case .hello(_, let bound, _) = try Wire.decode(acknowledgement) else {
            Issue.record("an acknowledgement is a hello")
            return
        }
        #expect(bound[phone] == 3)
    }
}
