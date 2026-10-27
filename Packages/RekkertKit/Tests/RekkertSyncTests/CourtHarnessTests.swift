import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Court harness", .serialized)
@MainActor
struct CourtHarnessTests {
    @Test func aGuestPhoneJoinsOverTheRadioAndFollowsThePoint() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })

        #expect(court.host.phone.core.reachableCount == 1)

        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }

    @Test func theHostKnowsEachGuestByItsPhone() async {
        let court = CourtHarness(guests: 2)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) { court.allInStep() })
        court.score(on: court.guests.first!.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })

        let known = Set(court.host.phone.store.participants.all.map(\.id))
        #expect(known == Set(court.guests.map(\.phone.id)))
        #expect(court.host.phone.store.participants.all.allSatisfy { !$0.isOlderBuild })
    }

    @Test func aGuestOutOfRangeNeverGetsOn() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.startMatch()
        court.outOfRange(court.guests.first!.phone)
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() } == false)
        #expect(court.host.phone.core.reachableCount == 0)
    }

    @Test func twoGuestsWithWatchesFollowAPointScoredOnAWatch() async {
        let court = CourtHarness(guests: 2)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) { court.allInStep() })

        let guestWatch = court.guests.first!.watch!
        court.score(on: guestWatch)
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
    }
}
