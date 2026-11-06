import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("The host's next match is announced", .serialized)
@MainActor
struct NextMatchNoticeTests {
    private func sharedCourt(guests: Int = 2, withWatches: Bool = true) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: withWatches)
        court.startMatch()
        court.share()
        court.joinAll()
        court.score(on: court.host.phone)
        await court.until(within: .seconds(60)) { court.allInStep() }
        #expect(court.allInStep())
        return court
    }

    /// Finishes the match, keeps sharing, and starts the next one: the host's next match.
    private func nextMatch(_ court: CourtHarness) -> UUID {
        court.finish(on: court.host.phone)
        court.answer(.keepSharing, on: court.host.phone)
        court.startMatch()
        return court.host.phone.store.log.sessionID
    }

    private func everyGuestDevice(_ court: CourtHarness) -> [CourtHarness.Device] {
        court.guests.flatMap { [$0.phone] + ($0.watch.map { [$0] } ?? []) }
    }

    private func recorded(_ kind: LinkEvent, on device: CourtHarness.Device) -> Bool {
        device.recorder.read().entries.contains { $0.kind == kind }
    }

    @Test func theNextMatchArrivesWithANotice() async {
        let court = await sharedCourt()
        let next = nextMatch(court)
        #expect(await court.until(within: .seconds(30)) {
            everyGuestDevice(court).allSatisfy { court.betweenMatches(of: $0).newMatch?.session == next }
        })
        #expect(recorded(.newMatchShown, on: court.guests.first!.phone))
    }

    @Test func aBluetoothGuestGetsTheNextMatchWithinThirtySeconds() async {
        let court = await sharedCourt(guests: 1, withWatches: false)
        let guest = court.guests.first!
        let next = nextMatch(court)
        #expect(await court.until(within: .seconds(30)) {
            guest.phone.store.log.sessionID == next && court.betweenMatches(of: guest.phone).newMatch?.session == next
        })
    }

    @Test func scoringWaitsForOK() async {
        let court = await sharedCourt(guests: 1)
        let guest = court.guests.first!
        let next = nextMatch(court)
        #expect(await court.until(within: .seconds(30)) { court.betweenMatches(of: guest.phone).newMatch?.session == next })
        #expect(!court.canScore(on: guest.phone))
        #expect(court.score(on: guest.phone) == nil, "a tap does nothing until OK")
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.inStep(guest.phone, with: court.host.phone) })
        court.answer(.ok, on: guest.phone)
        #expect(court.canScore(on: guest.phone))
        #expect(recorded(.newMatchAnswered(.ok), on: guest.phone))
        #expect(await court.until(within: .seconds(10)) { court.canScore(on: guest.watch!) })
        court.score(on: guest.phone, team: .b)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }

    @Test func okOnTheWatchClosesThePhone() async {
        let court = await sharedCourt(guests: 1)
        let guest = court.guests.first!
        let next = nextMatch(court)
        #expect(await court.until(within: .seconds(30)) { court.betweenMatches(of: guest.watch!).newMatch?.session == next })
        court.answer(.ok, on: guest.watch!)
        #expect(await court.until(within: .seconds(10)) { court.betweenMatches(of: guest.phone).newMatch == nil })
    }

    @Test func leaveFromTheNotice() async {
        let court = await sharedCourt()
        let leaver = court.guests.first!
        let next = nextMatch(court)
        #expect(await court.until(within: .seconds(30)) { court.betweenMatches(of: leaver.phone).newMatch?.session == next })
        await court.until(within: .seconds(20)) { court.host.phone.store.participantStates().count == 2 }
        court.answer(.leave, on: leaver.phone)
        #expect(leaver.phone.store.role == .solo)
        #expect(await court.until(within: .seconds(15)) { court.host.phone.store.participantStates().count == 1 })
        court.score(on: court.host.phone)
        await court.run(for: .seconds(5))
        #expect(leaver.phone.store.log.isEmpty || leaver.phone.store.log.sessionID != next || !court.inStep(leaver.phone, with: court.host.phone))
    }

    @Test func aStandingInWatchGetsTheNotice() async {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(500))
        let court = CourtHarness(guests: 1, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(120)) { court.allInStep() })
        let guest = court.guests.first!
        court.endApp(guest.phone)
        #expect(await court.until(within: .seconds(60)) { guest.watch!.sharing.reachablePeers > 0 })
        let next = nextMatch(court)
        #expect(await court.until(within: .seconds(60)) { court.betweenMatches(of: guest.watch!).newMatch?.session == next })
    }

    @Test func theHostIsNeverShownANotice() async {
        let court = await sharedCourt(guests: 1)
        let next = nextMatch(court)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(court.host.phone.store.log.sessionID == next)
        #expect(court.betweenMatches(of: court.host.phone).newMatch == nil)
        #expect(court.betweenMatches(of: court.host.watch!).newMatch == nil)
    }

    @Test func joiningMidMatchShowsNoNotice() async {
        let court = await sharedCourt()
        #expect(everyGuestDevice(court).allSatisfy { court.betweenMatches(of: $0).newMatch == nil })
        #expect(everyGuestDevice(court).allSatisfy { court.canScore(on: $0) })
    }
}
