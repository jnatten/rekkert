import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// FR-009: a guest's phone app ended by the system, and its watch on the wrist.
@Suite("The wrist standing in, and handing back", .serialized)
@MainActor
struct StandInHandBackTests {
    private func sharedCourt() async -> CourtHarness {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(500))
        let court = CourtHarness(guests: 1, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(120)) { court.allInStep() }
        #expect(court.allInStep())
        return court
    }

    @Test func withAWorkoutTheWatchCarriesOnByItself() async {
        let court = await sharedCourt()
        let guest = court.guests.first!
        court.endApp(guest.phone)

        #expect(await court.until(within: .seconds(60)) { guest.watch!.sharing.reachablePeers > 0 })
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.inStep(guest.watch!, with: court.host.phone) })
        #expect(!guest.watch!.standIn!.phoneNeedsOpening)
        #expect(guest.watch!.standIn!.statuses.contains(.followingOnTheWatch))
    }

    @Test func withoutAWorkoutOrTheAppInFrontItSaysThePhoneNeedsOpening() async {
        let court = await sharedCourt()
        let guest = court.guests.first!
        guest.watch!.standIn!.mayUseTheRadio = { false }
        court.endApp(guest.phone)

        #expect(await court.until(within: .seconds(30)) { guest.watch!.standIn!.phoneNeedsOpening })
        #expect(!guest.watch!.sharing.isSharing)
        #expect(guest.watch!.standIn!.statuses.first == .phoneNeedsOpening)
    }

    @Test func thePhoneBackTakesOverAndNothingIsLost() async {
        let court = await sharedCourt()
        let guest = court.guests.first!
        court.endApp(guest.phone)
        #expect(await court.until(within: .seconds(60)) { guest.watch!.sharing.reachablePeers > 0 })
        let fromTheWrist = court.score(on: guest.watch!, team: .b)

        court.relaunch(guest.phone)
        #expect(await court.until(within: .seconds(60)) { !guest.watch!.sharing.isSharing })
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(fromTheWrist.map { court.host.phone.store.log.events[$0] != nil } == true)
        #expect(fromTheWrist.map { guest.phone.store.log.events[$0] != nil } == true)
    }
}
