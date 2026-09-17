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
        sharing.join(SessionCode("H7K3MR")!)
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
        sharing.join(SessionCode("H7K3MR")!)

        sharing.apply(.failed(.rejected))

        #expect(sharing.phase == .failed(.rejected))
        #expect(sharing.isSharing == false)
    }

    @Test func aFirstJoinThatFindsNothingStillSaysSo() {
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(), snapshotInterval: 0)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport())
        sharing.join(SessionCode("H7K3MR")!)

        sharing.apply(.failed(.notFound))

        #expect(sharing.phase == .failed(.notFound))
        #expect(sharing.isSharing == false)
    }

    /// Having been on one match does not make the next code typed unquestionable.
    @Test func typingACodeAgainCanFailAgain() {
        let (sharing, _) = joined()
        sharing.stop()

        sharing.join(SessionCode("K9M4PT")!)
        sharing.apply(.failed(.rejected))

        #expect(sharing.phase == .failed(.rejected))
    }
}
