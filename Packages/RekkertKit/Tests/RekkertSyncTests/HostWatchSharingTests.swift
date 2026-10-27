import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("The host runs sharing from the wrist", .serialized)
@MainActor
struct HostWatchSharingTests {
    private func court(guests: Int = 1) -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: true)
        court.startMatch()
        return court
    }

    private func hostWatch(_ court: CourtHarness) -> WatchStandIn { court.host.watch!.standIn! }

    /// FR-019, FR-010: the wrist hears of sharing starting, of who is on and how they are doing,
    /// of a new code, and of sharing stopping.
    @Test func theWatchIsToldWhatThePhoneIsSharing() async {
        let court = court()
        let watch = hostWatch(court)
        court.share()
        #expect(await court.until(within: .seconds(5)) { watch.hosting?.code == court.code })
        #expect(watch.hosting?.isSharing == true)
        #expect(watch.hosting?.joinLink == court.code.joinLink)

        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { watch.hosting?.participants.count == 1 })
        court.outOfRange(court.guests.first!.phone)
        #expect(await court.until(within: .seconds(20)) {
            if case .outOfReach? = watch.hosting?.participants.first?.state { true } else { false }
        })

        court.host.phone.sharing.stop()
        #expect(await court.until(within: .seconds(5)) { watch.hosting?.isSharing == false })
        let next = SessionCode("731604")!
        court.host.phone.sharing.host(code: next)
        #expect(await court.until(within: .seconds(5)) { watch.hosting?.code == next })
    }

    @Test func sharingStartsFromTheWristOnlyWithAMatchOn() async {
        let court = CourtHarness(guests: 1, withWatches: true)
        let watch = hostWatch(court)
        watch.startHosting()
        #expect(await court.until(within: .seconds(5)) { watch.hostingTrouble == .nothingToShare })
        #expect(court.host.phone.sharing.code == nil)

        court.startMatch()
        await court.run(for: .seconds(1))
        watch.startHosting()
        #expect(await court.until(within: .seconds(5)) { watch.hosting?.isSharing == true })
        #expect(court.host.phone.sharing.code != nil)
        #expect(watch.hostingTrouble == nil)
    }

    @Test func stoppingFromTheWristTellsTheGuests() async {
        let court = court()
        let watch = hostWatch(court)
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }

        watch.stopHosting()
        #expect(await court.until(within: .seconds(10)) {
            court.guests.allSatisfy { $0.phone.sharing.hostStoppedSharing }
        })
        #expect(court.host.phone.sharing.code == nil)
    }

    /// FR-020: the phone out of reach, the wrist says so and nothing changes.
    @Test func withThePhoneOutOfReachTheWristSaysSoAndNothingChanges() async {
        let court = court()
        let watch = hostWatch(court)
        court.separate(court.host)
        await court.run(for: .seconds(1))

        watch.startHosting()
        #expect(await court.until(within: .seconds(10)) { watch.hostingTrouble == .cannotReachPhone })
        #expect(court.host.phone.sharing.code == nil)
    }

    /// A watch app ended and run again has lost what it was told, and nothing on the phone has
    /// changed for it to be told again.
    @Test func aWatchRunAgainIsToldAgain() async {
        let court = court()
        court.share()
        #expect(await court.until(within: .seconds(5)) { hostWatch(court).hosting?.isSharing == true })

        court.endApp(court.host.watch!)
        court.relaunch(court.host.watch!)
        #expect(await court.until(within: .seconds(10)) { hostWatch(court).hosting?.code == court.code })
        #expect(hostWatch(court).hosting?.isSharing == true)
    }

    /// Between the matches of an evening the code stays the same.
    @Test func betweenMatchesTheCodeStaysShared() async {
        let court = court()
        let watch = hostWatch(court)
        court.share()
        #expect(await court.until(within: .seconds(5)) { watch.hosting?.isSharing == true })

        court.host.phone.store.finish()
        court.startMatch()
        await court.run(for: .seconds(3))
        #expect(watch.hosting?.isSharing == true)
        #expect(watch.hosting?.code == court.code)
    }
}
