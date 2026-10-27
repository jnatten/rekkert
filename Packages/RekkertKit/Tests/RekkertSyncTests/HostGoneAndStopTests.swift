import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("When the host goes, or stops sharing", .serialized)
@MainActor
struct HostGoneAndStopTests {
    private func sharedCourt(guests: Int = 2, withWatches: Bool = false) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: withWatches)
        court.startMatch()
        court.share()
        court.joinAll()
        for point in 0 ..< 3 { court.score(on: court.host.phone, team: point.isMultiple(of: 2) ? .a : .b) }
        await court.until(within: .seconds(60)) { court.allInStep() }
        #expect(court.allInStep())
        return court
    }

    private func history(of device: CourtHarness.Device, _ session: UUID) -> HistoryRecord? {
        SessionStore(directory: device.directory).historyRecord(session)
    }

    /// FR-026: the host's phone walks off for good. Guests say so, keep scoring, cannot end it,
    /// and everything comes together when it is back.
    @Test func guestsAreToldTheHostIsOutOfReachAndCarryOn() async {
        let court = await sharedCourt()
        let gone = court.clock.now
        court.outOfRange(court.host.phone)

        #expect(await court.until(within: .seconds(15)) {
            court.guests.allSatisfy { $0.phone.sharing.hostOutOfReachSince != nil }
        })
        let goneAt = CourtHarness.epoch.addingTimeInterval(gone.seconds)
        for guest in court.guests {
            let since = guest.phone.sharing.hostOutOfReachSince ?? .distantFuture
            #expect(abs(since.timeIntervalSince(goneAt)) < 2, "since when it went, not since it was noticed")
            #expect(!guest.phone.store.canEndSession && !guest.phone.store.canSettleScore)
        }

        let scorer = court.guests.first!.phone
        let point = court.score(on: scorer, team: .b)
        #expect(point.map { scorer.store.log.events[$0] != nil } == true, "scoring carries on")

        court.backInRange(court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(point.map { court.host.phone.store.log.events[$0] != nil } == true)
        #expect(court.guests.allSatisfy { $0.phone.sharing.hostOutOfReachSince == nil })
    }

    /// FR-028: every guest hears it before the links go, keeps its copy as it stood, and lets go
    /// of the code. Its watch goes with it.
    @Test func stoppingTellsEveryGuestWhoKeepsTheirCopyAndForgetsTheCode() async {
        let court = await sharedCourt(withWatches: true)
        let session = court.host.phone.store.log.sessionID
        let board = court.host.phone.store.state

        court.host.phone.sharing.stop()
        #expect(await court.until(within: .seconds(5)) {
            court.guests.allSatisfy { $0.phone.store.state == nil && $0.phone.sharing.hostStoppedSharing }
        })
        for guest in court.guests {
            #expect(history(of: guest.phone, session)?.state == board, "filed as it stood")
            #expect(guest.phone.keeper.read(now: court.wallClock) == nil, "the code is forgotten")
            #expect(!guest.phone.sharing.isSharing)
        }
        #expect(await court.until(within: .seconds(10)) { court.guests.allSatisfy { $0.watch!.store.state == nil } })
        #expect(court.host.phone.store.state == board, "the host's own match carries on")
    }

    /// The guests call the match by who the host said they are: "Ada's match", on the phone and
    /// on the wrist, right up to "Ada stopped sharing".
    @Test func theGuestsKnowTheHostByTheNameTheyGave() async {
        let court = await sharedCourt(guests: 1, withWatches: true)
        let guest = court.guests.first!
        #expect(guest.phone.store.hostName == nil)

        court.host.phone.store.identify(as: "Ada")
        #expect(await court.until(within: .seconds(10)) {
            guest.phone.store.hostName == "Ada" && guest.watch!.store.hostName == "Ada"
                && guest.watch!.standIn!.phonesHostName == "Ada"
        })
        #expect(court.host.phone.store.hostName == nil, "the host's own match is not somebody else's")

        court.host.phone.sharing.stop()
        #expect(await court.until(within: .seconds(10)) { guest.phone.sharing.hostWhoStopped == "Ada" })
    }

    /// A host from before this build cuts its links without a word. Its guests see it go as they
    /// would a host out of reach, and keep the match and the code to get back on.
    @Test func anOlderHostThatSaysNothingLeavesItsGuestsOutOfReach() async {
        let court = await sharedCourt(guests: 1)
        let guest = court.guests.first!.phone
        court.host.phone.core.stop()
        court.host.phone.radio.end()

        #expect(await court.until(within: .seconds(15)) { guest.sharing.hostOutOfReachSince != nil })
        #expect(guest.store.state != nil)
        #expect(!guest.sharing.hostStoppedSharing)
        #expect(guest.keeper.read(now: court.wallClock) != nil)
    }
}
