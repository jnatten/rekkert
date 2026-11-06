import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Stop sharing between matches", .serialized)
@MainActor
struct StopBetweenMatchesTests {
    private func waitingCourt(guests: Int = 2, withWatches: Bool = false) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: withWatches)
        court.startMatch()
        court.share()
        court.joinAll()
        court.score(on: court.host.phone)
        await court.until(within: .seconds(60)) { court.allInStep() }
        court.finish(on: court.host.phone)
        await court.until(within: .seconds(30)) { court.guests.allSatisfy { $0.phone.store.betweenMatches.ask != nil } }
        for guest in court.guests { court.answer(.stay, on: guest.phone) }
        #expect(court.guests.allSatisfy { court.isWaiting($0.phone) })
        return court
    }

    /// R-3: the host's empty log and each guest's have ids of their own.
    @Test func stopWithNoMatchOnReachesEveryGuest() async {
        let court = await waitingCourt()
        court.host.phone.sharing.stop()
        #expect(await court.until(within: .seconds(10)) { court.guests.allSatisfy { $0.phone.sharing.hostStoppedSharing } })
        for guest in court.guests {
            #expect(guest.phone.store.role == .solo)
            #expect(guest.phone.keeper.read(now: court.wallClock) == nil, "the code is forgotten")
            #expect(!guest.phone.sharing.isSharing)
        }
        court.startMatch()
        await court.run(for: .seconds(10))
        #expect(court.guests.allSatisfy { $0.phone.store.log.isEmpty }, "the host's next match reaches nobody")
    }

    @Test func theStopSaysWhy() async {
        let court = await waitingCourt(guests: 1, withWatches: true)
        let guest = court.guests.first!
        court.host.phone.sharing.stop()
        #expect(await court.until(within: .seconds(10)) { guest.phone.sharing.hostStoppedSharing })
        #expect(guest.phone.sharing.hostStopReason == .host)
        #expect(await court.until(within: .seconds(10)) { guest.watch!.standIn!.hostStoppedSharing })
        #expect(guest.watch!.standIn!.hostStopReason == .host)
    }

    /// What an older host's Stop between matches looks like: a notice naming its own empty log.
    @Test func aStopNamingAnotherEmptyLogStillReachesTheGuest() async {
        let court = await waitingCourt(guests: 1)
        let guest = court.guests.first!.phone
        #expect(court.host.phone.store.log.sessionID != guest.store.log.sessionID)
        await court.host.phone.store.sayStoppedSharing().value
        #expect(await court.until(within: .seconds(10)) { guest.sharing.hostStoppedSharing })
        #expect(guest.store.role == .solo)
    }
}
