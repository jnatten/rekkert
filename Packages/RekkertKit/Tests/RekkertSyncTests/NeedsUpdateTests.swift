import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-015 and D-14: a later release that cannot take this one's guests says so, and
/// this release puts it plainly on the phone and the watch, rather than "not found".
@Suite("Told plainly to update", .serialized)
@MainActor
struct NeedsUpdateTests {
    private func court() -> CourtHarness {
        let court = CourtHarness(guests: 1, withWatches: true)
        court.startMatch()
        court.share()
        court.host.phone.store.refusesAsNeedingUpdate = true
        return court
    }

    @Test func aGuestJoiningFromThePhoneIsToldToUpdate() async {
        let court = court()
        let guest = court.guests.first!
        court.join(guest)
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.needsUpdate) })
        #expect(guest.phone.recorder.read().entries.contains { $0.kind == .refused(.needsUpdate) })
    }

    @Test func aGuestJoiningFromTheWristIsToldToUpdateThere() async {
        let court = court()
        let guest = court.guests.first!
        await court.until(within: .seconds(5)) { guest.watch!.store.isPairReachable }
        guest.watch!.standIn!.join(court.code)
        #expect(await court.until(within: .seconds(15)) { guest.watch!.standIn!.joining == .failed(.needsUpdate) })
    }
}
