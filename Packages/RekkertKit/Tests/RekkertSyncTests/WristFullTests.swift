import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, R-6 and FR-013: a code typed on the wrist for a match that is full is answered
/// "no room" within 15 s, whichever half of the pair hears it, and never "not found".
@Suite("A wrist join on a full match", .serialized)
@MainActor
struct WristFullTests {
    private func fullCourt() async -> CourtHarness {
        let court = CourtHarness(guests: 2, withWatches: true, guestLimit: 1)
        court.startMatch()
        court.share()
        court.join(court.guests.first!)
        #expect(await court.until(within: .seconds(60)) { court.inStep(court.guests.first!.phone, with: court.host.phone) })
        return court
    }

    private func answer(on watch: CourtHarness.Device, in court: CourtHarness) async -> (full: Bool, notFound: Bool) {
        var notFound = false
        let full = await court.until(within: .seconds(15)) {
            if watch.standIn!.joining == .failed(.notFound) { notFound = true }
            return watch.standIn!.joining == .failed(.noRoom)
        }
        return (full, notFound)
    }

    @Test func thePhoneHearsIt() async {
        let court = await fullCourt()
        let guest = court.guests.last!
        await court.until(within: .seconds(5)) { guest.watch!.store.isPairReachable }
        guest.watch!.standIn!.join(court.code)
        let (full, notFound) = await answer(on: guest.watch!, in: court)
        #expect(full)
        #expect(!notFound)
    }

    @Test func theWristHearsItWithThePhoneOutOfTheHostsReach() async {
        let court = await fullCourt()
        let guest = court.guests.last!
        court.outOfRange(guest.phone)
        await court.until(within: .seconds(5)) { guest.watch!.store.isPairReachable }
        guest.watch!.standIn!.join(court.code)
        let (full, notFound) = await answer(on: guest.watch!, in: court)
        #expect(full)
        #expect(!notFound)
    }
}
