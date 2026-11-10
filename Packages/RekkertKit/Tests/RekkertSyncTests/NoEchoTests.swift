import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, research R-4: a guest on both radios sent the host's points back to it over the
/// other link, doubling the Bluetooth traffic for every point.
@Suite("A point goes back to no device that sent it", .serialized)
@MainActor
struct NoEchoTests {
    @Test func guestsOnBothRadiosSendNothingBackToTheHost() async {
        let court = CourtHarness(guests: 2, withWatches: false, guestRadios: { _ in .both })
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) {
            court.allInStep() && court.host.phone.wifiCore?.reachableCount == 2
        })

        for _ in 0 ..< 50 {
            court.score(on: court.host.phone)
            await court.run(for: .seconds(2))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(court.host.phone.store.echoesHeard == 0)
    }

    @Test func theHostSendsNothingBackToTheGuestThatScored() async {
        let court = CourtHarness(guests: 2, withWatches: false, guestRadios: { _ in .both })
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) {
            court.allInStep() && court.host.phone.wifiCore?.reachableCount == 2
        })

        let scorer = court.guests.first!.phone
        for _ in 0 ..< 30 {
            court.score(on: scorer)
            await court.run(for: .seconds(2))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(scorer.store.echoesHeard == 0)
    }
}
