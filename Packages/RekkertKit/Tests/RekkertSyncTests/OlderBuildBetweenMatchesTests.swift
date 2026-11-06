import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// D-13: what the between-matches flow does next to devices that do not say the new things.
@Suite("Between matches, beside older devices", .serialized)
@MainActor
struct OlderBuildBetweenMatchesTests {
    private func sharedCourt(guests: Int = 1) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: true)
        court.startMatch()
        court.share()
        court.joinAll()
        court.score(on: court.host.phone)
        await court.until(within: .seconds(60)) { court.allInStep() }
        return court
    }

    /// An older host never says Keep: the guest is asked stay or leave, and the next match still
    /// comes with its notice.
    @Test func aHostThatNeverSaysKeepLeavesTheQuestionPlain() async {
        let court = await sharedCourt()
        let guest = court.guests.first!.phone
        court.finish(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { guest.store.betweenMatches.ask != nil })
        await court.run(for: .seconds(10))
        #expect(guest.store.betweenMatches.ask?.side == .guest(hostName: guest.store.accessTable?.hostName, hostKeepsSharing: false))
        court.startMatch()
        let next = court.host.phone.store.log.sessionID
        #expect(await court.until(within: .seconds(30)) { guest.store.betweenMatches.newMatch?.session == next })
    }

    /// A watch that never hears its phone's answer is asked on its own, and nothing stalls; the
    /// answer reaches it once the two are back in touch.
    @Test func aWatchThatMissesTheAnswerIsAskedOnItsOwn() async {
        let court = await sharedCourt(guests: 2)
        let guest = court.guests.first!
        court.finish(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) {
            guest.phone.store.betweenMatches.ask != nil && guest.watch!.store.betweenMatches.ask != nil
        })
        await court.until(within: .seconds(20)) { court.host.phone.store.participantStates().count == 2 }
        court.separate(guest)
        court.holdQueues(of: guest)
        court.answer(.leave, on: guest.phone)
        #expect(guest.phone.store.role == .solo)
        #expect(await court.until(within: .seconds(15)) { court.host.phone.store.participantStates().count == 1 })
        #expect(guest.watch!.store.betweenMatches.ask != nil, "still asked, and nothing waits on it")
        court.holdQueues(of: guest, false)
        court.reunite(guest)
        #expect(await court.until(within: .seconds(10)) { guest.watch!.store.betweenMatches.ask == nil })
    }
}
