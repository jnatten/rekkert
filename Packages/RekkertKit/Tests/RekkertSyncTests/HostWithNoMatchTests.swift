import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Sharing with no match on", .serialized)
@MainActor
struct HostWithNoMatchTests {
    @Test func shareFromThePhoneWithNoMatchOn() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.share()
        #expect(court.host.phone.store.state == nil)
        #expect(court.host.phone.sharing.code == court.code)
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.guests.first!.phone.sharing.reachablePeers > 0 })
    }

    @Test func shareFromTheWristWithNoMatchOn() async {
        let court = CourtHarness(guests: 0, withWatches: true)
        let watch = court.host.watch!.standIn!
        await court.run(for: .seconds(1))
        watch.startHosting()
        #expect(await court.until(within: .seconds(10)) { watch.hosting?.isSharing == true })
        #expect(court.host.phone.sharing.code != nil)
        #expect(watch.hosting?.code == court.host.phone.sharing.code)
        #expect(watch.hosting?.canShare == true)
        #expect(watch.hostingTrouble == nil)
    }

    @Test func theFirstMatchReachesEveryGuest() async {
        let court = CourtHarness(guests: 2, withWatches: true)
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.guests.allSatisfy { $0.phone.sharing.reachablePeers > 0 } }
        court.startMatch()
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
    }

    @Test func aGuestsPhoneStillCannotHost() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        let guest = court.guests.first!.phone
        #expect(guest.store.role == .guest)
        guest.sharing.host()
        #expect(guest.sharing.code == nil)
        #expect(guest.sharing.hostingStatus.canShare == false)
    }
}
