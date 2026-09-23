import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

/// Coming back, as the coordinator sees it. The transport is an inert stub on macOS, so the
/// statuses a socket would publish are handed to `apply` directly — which is where the bug
/// lived anyway.
@Suite("Coming back")
@MainActor
struct ReconnectTests {
    private func joined() -> (SharedSession, MatchStore) {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        store.configure(setup)
        sharing.join(SessionCode("482915")!)
        sharing.apply(.joined(peers: 1))
        return (sharing, store)
    }

    /// The one that took people out of a match they were already scoring: the host's phone
    /// locked, the guest redialled what it could still see, and that dial failed.
    @Test func aDropAfterJoiningGoesBackToLookingRatherThanFailing() {
        let (sharing, _) = joined()

        sharing.apply(.failed(.rejected))

        #expect(sharing.phase == .searching)
        #expect(sharing.isSharing, "the match is still on, it is just out of earshot")
    }

    @Test func aTimeoutAfterJoiningDoesNotEndTheSharing() {
        let (sharing, _) = joined()
        sharing.apply(.failed(.notFound))
        #expect(sharing.phase == .searching)
        #expect(sharing.isSharing)
    }

    @Test func aBlockedNetworkAfterJoiningDoesNotEndTheSharing() {
        let (sharing, _) = joined()
        sharing.apply(.failed(.blocked))
        #expect(sharing.phase == .searching)
        #expect(sharing.isSharing)
    }

    @Test func aFirstJoinThatIsRefusedStillSaysSo() {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        sharing.join(SessionCode("482915")!)

        sharing.apply(.failed(.rejected))

        #expect(sharing.phase == .failed(.rejected))
        #expect(sharing.isSharing == false)
    }

    @Test func aFirstJoinThatFindsNothingStillSaysSo() {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        sharing.join(SessionCode("482915")!)

        sharing.apply(.failed(.notFound))

        #expect(sharing.phase == .failed(.notFound))
        #expect(sharing.isSharing == false)
    }

    /// Having been on one match does not make the next code typed unquestionable.
    @Test func typingACodeAgainCanFailAgain() {
        let (sharing, _) = joined()
        sharing.stop()

        sharing.join(SessionCode("730264")!)
        sharing.apply(.failed(.rejected))

        #expect(sharing.phase == .failed(.rejected))
    }

    @Test func aGuestComingBackToTheFrontLooksForTheSameMatchAgain() throws {
        let code = try #require(SessionCode("482915"))
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        sharing.join(code)
        sharing.apply(.joined(peers: 1))

        #expect(sharing.revival == .joining(code))

        // And still, once the host has gone quiet — which is the whole point of it.
        sharing.apply(.searching)
        #expect(sharing.revival == .joining(code))
    }

    @Test func aHostComingBackToTheFrontAdvertisesTheSameShareAgain() throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        store.configure(setup)
        let code = try #require(SessionCode("730264"))
        sharing.host(code: code)

        guard case .hosting(let revived, let share) = sharing.revival else {
            Issue.record("a host has something to put back")
            return
        }
        #expect(revived == code)

        // The share id is minted once and kept: a guest dialling back has to find the same
        // advertisement it was told about, not a new one under the same code.
        #expect(sharing.revival == .hosting(code, share))
    }

    @Test func aSessionThatWasNeverSharedHasNothingToPutBack() {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        #expect(sharing.revival == .nothing)
    }

    @Test func aFailureThatWasNotDismissedIsNotPutBack() {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        sharing.join(SessionCode("482915")!)
        sharing.apply(.failed(.notFound))

        #expect(sharing.revival == .nothing, "it was told the code found nothing")
    }
}

/// What the badge is entitled to say.
@Suite("Saying it is reconnecting")
@MainActor
struct ReconnectingBadgeTests {
    private func make() -> SharedSession {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        return SharedSession(store: store, link: LocalNetworkTransport())
    }

    @Test func lookingForTheFirstTimeIsNotReconnecting() {
        let sharing = make()
        sharing.join(SessionCode("482915")!)
        #expect(sharing.isReconnecting == false, "it has never been on this match")
    }

    @Test func lookingAgainAfterBeingOnItIs() {
        let sharing = make()
        sharing.join(SessionCode("482915")!)
        sharing.apply(.joined(peers: 1))
        sharing.apply(.searching)
        #expect(sharing.isReconnecting)
    }

    @Test func beingBackOnItIsNot() {
        let sharing = make()
        sharing.join(SessionCode("482915")!)
        sharing.apply(.joined(peers: 1))
        sharing.apply(.searching)
        sharing.apply(.joined(peers: 1))
        #expect(sharing.isReconnecting == false)
    }

    @Test func aHostIsNeverReconnecting() throws {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        sharing.host()
        sharing.apply(.searching)
        #expect(sharing.isReconnecting == false, "a host does not go looking")
    }
}
