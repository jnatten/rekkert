import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Coming back after the app was ended", .serialized)
@MainActor
struct RestoreTests {
    private func sharedCourt(guests: Int = 1) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: false)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        #expect(court.allInStep())
        return court
    }

    @Test func aRelaunchedHostSharesAgainOnTheSameCodeAndShare() async {
        let court = await sharedCourt()
        court.endApp(court.host.phone)
        court.relaunch(court.host.phone)
        #expect(court.host.phone.sharing.code == court.code)

        court.score(on: court.host.phone)
        // Back on without anybody typing: the share id is the same, or the guest's fingerprint
        // check would have turned the host away.
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }

    @Test func aHostBetweenMatchesComesBackToo() async {
        let court = await sharedCourt()
        court.host.phone.store.startNewSession()
        court.endApp(court.host.phone)
        court.relaunch(court.host.phone)
        #expect(court.host.phone.sharing.code == court.code)
    }

    @Test func aRelaunchedGuestGoesBackToLookingForItsMatch() async {
        let court = await sharedCourt()
        let guest = court.guests.first!.phone
        court.endApp(guest)
        court.relaunch(guest)
        #expect(guest.sharing.phase != .off)
        #expect(await court.until(within: .seconds(30)) { guest.core.reachableCount > 0 })
    }

    @Test func aCodeThatHasRunOutRestoresNothing() async {
        let court = await sharedCourt()
        court.endApp(court.host.phone)
        let stale = KeptCode(
            code: court.code, share: UUID(), role: .host,
            startedAt: CourtHarness.epoch.addingTimeInterval(-KeptCode.lifetime - 60)
        )
        court.host.phone.keeper.keep(stale)
        court.relaunch(court.host.phone)
        #expect(court.host.phone.sharing.phase == .off)
        #expect(court.host.phone.keeper.read(now: CourtHarness.epoch) == nil)
    }

    @Test func aGuestThatLeftIsNotPutBackOnByARelaunch() async {
        let court = await sharedCourt()
        let guest = court.guests.first!.phone
        guest.sharing.leave()
        #expect(guest.keeper.read(now: CourtHarness.epoch)?.code == court.code)
        court.endApp(guest)
        court.relaunch(guest)
        #expect(guest.sharing.phase == .off)
    }

    @Test func pastTwelveHoursSharingCarriesOnButTheCodeIsNoLongerKept() async {
        let court = await sharedCourt()
        let host = court.host.phone
        let expired = KeptCode(
            code: court.code, share: UUID(), role: .host,
            startedAt: CourtHarness.epoch.addingTimeInterval(-KeptCode.lifetime - 60)
        )
        host.keeper.keep(expired)
        #expect(host.sharing.code == court.code)
        #expect(host.keeper.read(now: CourtHarness.epoch) == nil)

        court.endApp(host)
        court.relaunch(host)
        #expect(host.sharing.phase == .off)
    }
}
