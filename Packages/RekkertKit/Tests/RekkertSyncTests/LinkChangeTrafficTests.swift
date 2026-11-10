import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, research R-3: every link going up or down set off a full round of sync on every
/// link, all of it through the host's one Bluetooth queue.
@Suite("A link going up or down costs one hello on that link", .serialized)
@MainActor
struct LinkChangeTrafficTests {
    private func court() async -> CourtHarness {
        let court = CourtHarness(guests: 3, withWatches: false, guestRadios: { _ in .both })
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) {
            court.allInStep() && court.host.phone.wifiCore?.reachableCount == 3
        })
        await court.run(for: .seconds(5))
        return court
    }

    @Test func aSecondLinkDroppingAndComingBackRunsNoRoundAnywhere() async {
        let court = await court()
        let rounds = court.devices.map(\.store.synchroniseRounds)

        let guest = court.guests.first!.phone
        guest.wifiRadio!.walkAway()
        await court.run(for: .seconds(5))
        guest.wifiRadio!.comeBack()
        #expect(await court.until(within: .seconds(30)) { court.host.phone.wifiCore?.reachableCount == 3 })
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(10)) { court.allInStep() })

        #expect(court.devices.map(\.store.synchroniseRounds) == rounds)
    }

    @Test func aPointScoredWhileTheSecondLinkWasDownReachesTheGuestWhenItComesBack() async {
        let court = await court()
        let guest = court.guests.first!.phone
        guest.radio.walkAway()
        guest.wifiRadio!.walkAway()
        court.score(on: court.host.phone)
        await court.run(for: .seconds(3))
        guest.wifiRadio!.comeBack()
        #expect(await court.until(within: .seconds(30)) { court.inStep(guest, with: court.host.phone) })
    }

    @Test func aNewGuestStillExchangesItsCardAndTheAccessTable() async {
        let court = CourtHarness(guests: 2, withWatches: false, guestRadios: { _ in .both })
        court.startMatch()
        court.share()
        court.join(court.guests.first!)
        #expect(await court.until(within: .seconds(60)) {
            court.inStep(court.guests.first!.phone, with: court.host.phone)
        })
        let late = court.guests.last!
        court.join(late)
        #expect(await court.until(within: .seconds(60)) {
            court.inStep(late.phone, with: court.host.phone)
                && late.phone.store.accessTable != nil
                && court.host.phone.store.participants.participant(for: late.phone.id) != nil
        })
    }
}
