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

        let chosen = try #require(SessionCode("K9M4PT"))
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
        sharing.join(try #require(SessionCode("K9M4PT")))

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
        sharing.join(try #require(SessionCode("K9M4PT")))
        store.startSharing()

        #expect(store.role == .host, "startSharing is refused for a guest, allowed here")

        sharing.stop()
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
}
