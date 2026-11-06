import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Joining, waiting and leaving with no match on", .serialized)
@MainActor
struct JoinBetweenMatchesTests {
    /// The host sharing with nothing on, and the guests joined to it.
    private func waitingCourt(guests: Int = 1, withWatches: Bool = true) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: withWatches)
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.guests.allSatisfy { court.isWaiting($0.phone) } }
        return court
    }

    /// R-5: today a guest stays joining until the host's first match arrives.
    @Test func aJoinWithNoMatchOnWaitsAsAGuest() async {
        let court = await waitingCourt()
        let guest = court.guests.first!.phone
        #expect(guest.store.role == .guest)
        #expect(!guest.store.isJoining)
        #expect(guest.store.accessTable != nil, "the host's word, and its name, came with the answer")
        #expect(guest.store.betweenMatches.idleSince != nil)
        #expect(guest.store.log.isEmpty)
    }

    @Test func itsWatchWaitsToo() async {
        let court = await waitingCourt()
        let watch = court.guests.first!.watch!
        #expect(await court.until(within: .seconds(10)) { watch.store.side == .guest })
    }

    @Test func theFirstMatchArrives() async {
        let court = await waitingCourt(guests: 2)
        court.startMatch()
        let first = court.host.phone.store.log.sessionID
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
        #expect(court.guests.allSatisfy { $0.phone.store.betweenMatches.newMatch?.session == first })
    }

    /// R-14: a link that is up before the host's match has arrived is still a join.
    @Test func aJoinMidMatchIsStillAJoin() async {
        let court = CourtHarness(guests: 1, withWatches: true)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
        let guest = court.guests.first!
        #expect(guest.phone.store.betweenMatches.newMatch == nil)
        #expect(guest.watch!.store.betweenMatches.newMatch == nil)
        #expect(court.canScore(on: guest.phone))
    }

    @Test func leavingFromThePhoneWhileWaitingTakesTheWatch() async {
        let court = await waitingCourt(guests: 2)
        let leaver = court.guests.first!
        #expect(await court.until(within: .seconds(20)) { court.host.phone.store.participantStates().count == 2 })
        leaver.phone.sharing.stop()
        #expect(leaver.phone.store.role == .solo)
        #expect(await court.until(within: .seconds(10)) { leaver.watch!.store.side == nil })
        #expect(await court.until(within: .seconds(15)) { court.host.phone.store.participantStates().count == 1 })
        #expect(court.isWaiting(court.guests.last!.phone))
    }

    @Test func leavingFromTheWatchWhileWaitingTakesThePhone() async {
        let court = await waitingCourt(guests: 2)
        let leaver = court.guests.first!
        #expect(await court.until(within: .seconds(10)) { leaver.watch!.store.side == .guest })
        #expect(await court.until(within: .seconds(20)) { court.host.phone.store.participantStates().count == 2 })
        leaver.watch!.sharing.leave()
        #expect(await court.until(within: .seconds(10)) { leaver.phone.store.role == .solo })
        #expect(await court.until(within: .seconds(15)) { court.host.phone.store.participantStates().count == 1 })
        #expect(court.isWaiting(court.guests.last!.phone))
    }

    @Test func aJoinAskedForByTheWatchWaitsToo() async {
        let court = CourtHarness(guests: 1, withWatches: true)
        court.share()
        let guest = court.guests.first!
        await court.run(for: .seconds(1))
        guest.watch!.standIn!.join(court.code)
        #expect(await court.until(within: .seconds(60)) { court.isWaiting(guest.phone) })
        court.startMatch()
        let first = court.host.phone.store.log.sessionID
        #expect(await court.until(within: .seconds(60)) {
            guest.phone.store.betweenMatches.newMatch?.session == first
                && guest.watch!.store.betweenMatches.newMatch?.session == first
        })
    }

    @Test func joinAgainWhileWaiting() async {
        let court = await waitingCourt()
        let guest = court.guests.first!
        guest.phone.sharing.stop()
        let kept = guest.phone.sharing.keptGuestCode
        #expect(kept == court.code)
        #expect(await court.until(within: .seconds(10)) { guest.watch!.standIn!.canJoinAgain })
        guest.phone.sharing.join(kept!)
        #expect(await court.until(within: .seconds(60)) { court.isWaiting(guest.phone) })
    }

    @Test func aJoinWithItsOwnMatchOnStillWaitsInTheSheet() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.share()
        let guest = court.guests.first!.phone
        guest.store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        let own = guest.store.log.sessionID
        court.score(on: guest)
        court.join(court.guests.first!)
        await court.run(for: .seconds(10))
        #expect(guest.store.isJoining)
        #expect(guest.store.log.sessionID == own, "its own match stays on until the host's arrives")
        court.startMatch()
        #expect(await court.until(within: .seconds(60)) { court.allInStep(includingWatches: false) })
        #expect(SessionStore(directory: court.guests.first!.phone.directory).historyRecord(own) != nil)
    }

    @Test func startingOwnMatchWhileWaitingLeavesSharing() async {
        let court = await waitingCourt()
        let guest = court.guests.first!
        #expect(guest.phone.store.startingOwnMatchLeavesSharing)
        #expect(await court.until(within: .seconds(10)) { guest.watch!.store.startingOwnMatchLeavesSharing })
        guest.phone.store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        #expect(guest.phone.store.role == .solo)
        #expect(!guest.phone.sharing.isSharing)
    }
}
