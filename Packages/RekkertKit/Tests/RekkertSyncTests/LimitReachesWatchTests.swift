import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-013 and FR-014: the host's limit reaches everywhere "N of M" is shown, and a
/// guest turned away hears how many fit.
@Suite("The limit reaches every screen", .serialized)
@MainActor
struct LimitReachesWatchTests {
    @Test func theHostsWatchHoldsTheLimitAndTheCount() async {
        let court = CourtHarness(guests: 2, withWatches: true, guestLimit: 3)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
        let standIn = court.host.watch!.standIn!
        #expect(await court.until(within: .seconds(15)) { standIn.hosting?.limit == 3 && standIn.hosting?.participants.count == 2 })
    }

    @Test func aGuestTurnedAwayHearsHowManyFitOnPhoneAndWatch() async {
        let court = CourtHarness(guests: 4, withWatches: true, guestLimit: 3)
        court.startMatch()
        court.share()
        for guest in court.guests.dropLast() { court.join(guest) }
        #expect(await court.until(within: .seconds(90)) {
            court.guests.dropLast().allSatisfy { court.inStep($0.phone, with: court.host.phone) }
        })
        let fourth = court.guests.last!
        await court.until(within: .seconds(5)) { fourth.watch!.store.isPairReachable }
        fourth.watch!.standIn!.join(court.code)
        #expect(await court.until(within: .seconds(15)) {
            fourth.watch!.standIn!.joining == .failed(.noRoom) && fourth.watch!.standIn!.fullLimit == 3
        })
        #expect(fourth.phone.sharing.phase == .failed(.noRoom))
        #expect(fourth.phone.store.noRoomLimit == 3)
    }

    /// FR-013: told on phone and watch, whichever the code was typed on.
    @Test func aGuestTurnedAwayOnThePhoneIsToldOnTheWristToo() async {
        let court = CourtHarness(guests: 4, withWatches: true, guestLimit: 3)
        court.startMatch()
        court.share()
        for guest in court.guests.dropLast() { court.join(guest) }
        #expect(await court.until(within: .seconds(90)) {
            court.guests.dropLast().allSatisfy { court.inStep($0.phone, with: court.host.phone) }
        })
        let fourth = court.guests.last!
        await court.until(within: .seconds(5)) { fourth.watch!.store.isPairReachable }
        court.join(fourth)
        #expect(await court.until(within: .seconds(15)) {
            fourth.phone.sharing.phase == .failed(.noRoom) && fourth.watch!.standIn!.phoneTurnedAway?.limit == 3
        })

        fourth.watch!.standIn!.dismissPhoneTurnedAway()
        #expect(fourth.watch!.standIn!.phoneTurnedAway == nil)
    }
}
