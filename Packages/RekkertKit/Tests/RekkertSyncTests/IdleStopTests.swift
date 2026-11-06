import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("A forgotten share stops by itself", .serialized)
@MainActor
struct IdleStopTests {
    private func waitingCourt(withWatches: Bool = true, timing: CourtHarness.Timing = CourtHarness.Timing()) async -> CourtHarness {
        let court = CourtHarness(guests: 1, withWatches: withWatches, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        court.score(on: court.host.phone)
        await court.until(within: .seconds(60)) { court.allInStep() }
        court.finish(on: court.host.phone)
        await court.until(within: .seconds(30)) { court.guests.first!.phone.store.betweenMatches.ask != nil }
        return court
    }

    private func recorded(_ kind: LinkEvent, on device: CourtHarness.Device) -> Bool {
        device.recorder.read().entries.contains { $0.kind == kind }
    }

    @Test func thirtyMinutesWithNoMatchStopsSharing() async {
        let court = await waitingCourt()
        let guest = court.guests.first!
        court.answer(.stay, on: guest.phone)
        await court.fastForward(by: .seconds(29 * 60))
        #expect(court.host.phone.sharing.isSharing)
        await court.fastForward(by: .seconds(2 * 60))
        #expect(!court.host.phone.sharing.isSharing)
        #expect(court.host.phone.sharing.stoppedForIdle)
        #expect(await court.until(within: .seconds(10)) { guest.phone.sharing.hostStoppedSharing })
        #expect(guest.phone.sharing.hostStopReason == .idle)
        #expect(guest.phone.store.role == .solo)
        #expect(recorded(.idleStop, on: court.host.phone))
        #expect(recorded(.idleStop, on: guest.phone) || guest.phone.sharing.hostStopReason == .idle)
        #expect(await court.until(within: .seconds(10)) { court.host.watch!.standIn!.hosting?.endedBy == .idle })
    }

    @Test func matchesPauseTheClock() async {
        let court = CourtHarness(guests: 0, withWatches: false)
        court.share()
        court.startMatch()
        await court.fastForward(by: .seconds(45 * 60))
        #expect(court.host.phone.sharing.isSharing)
        court.finish(on: court.host.phone)
        await court.fastForward(by: .seconds(25 * 60))
        #expect(court.host.phone.sharing.isSharing)
    }

    @Test func stayAndKeepDoNotResetTheClock() async {
        let court = await waitingCourt(withWatches: false)
        await court.fastForward(by: .seconds(20 * 60))
        court.answer(.stay, on: court.guests.first!.phone)
        court.answer(.keepSharing, on: court.host.phone)
        await court.fastForward(by: .seconds(11 * 60))
        #expect(!court.host.phone.sharing.isSharing)
    }

    @Test func aRelaunchAfterThirtyMinutesDoesNotShare() async {
        let court = await waitingCourt(withWatches: false)
        court.answer(.keepSharing, on: court.host.phone)
        court.endApp(court.host.phone)
        await court.fastForward(by: .seconds(31 * 60))
        court.relaunch(court.host.phone)
        #expect(court.host.phone.sharing.phase == .off)
        #expect(court.host.phone.sharing.stoppedForIdle)
        #expect(court.host.phone.store.role == .solo)
    }

    /// An app suspended in a pocket has no running time to notice the half hour in.
    @Test func aResumeAfterThirtyMinutesDoesNotShare() async {
        var timing = CourtHarness.Timing()
        timing.idleCheck = .seconds(3 * 60 * 60)
        let court = await waitingCourt(withWatches: false, timing: timing)
        await court.fastForward(by: .seconds(31 * 60))
        #expect(court.host.phone.sharing.isSharing, "nothing has looked yet")
        court.host.phone.sharing.resume()
        #expect(!court.host.phone.sharing.isSharing)
        #expect(court.host.phone.sharing.stoppedForIdle)
    }

    @Test func aGuestLeavesByItself() async {
        let court = await waitingCourt(withWatches: false)
        let guest = court.guests.first!.phone
        court.answer(.stay, on: guest)
        court.outOfRange(court.host.phone)
        await court.fastForward(by: .seconds(31 * 60))
        #expect(guest.store.role == .solo)
        #expect(guest.sharing.hostStoppedSharing)
        #expect(guest.sharing.hostStopReason == .idle)
        #expect(guest.keeper.read(now: court.wallClock) == nil, "the code is forgotten")
    }

    @Test func aGuestRelaunchedAfterThirtyMinutesDoesNotRejoin() async {
        let court = await waitingCourt(withWatches: false)
        let guest = court.guests.first!.phone
        court.answer(.stay, on: guest)
        court.outOfRange(court.host.phone)
        court.endApp(guest)
        await court.fastForward(by: .seconds(31 * 60))
        court.relaunch(guest)
        #expect(guest.sharing.phase == .off)
        #expect(guest.store.role == .solo)
    }
}
