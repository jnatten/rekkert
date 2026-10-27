import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("A guest joins and leaves from the wrist", .serialized)
@MainActor
struct GuestWristTests {
    private func court() -> CourtHarness {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(500))
        let court = CourtHarness(guests: 1, withWatches: true, timing: timing)
        court.startMatch()
        court.share()
        return court
    }

    private func onTheMatch(_ court: CourtHarness, _ device: CourtHarness.Device) -> Bool {
        device.store.log.sessionID == court.host.phone.store.log.sessionID && device.store.state != nil
    }

    @Test func theWatchKeepsThePhonesCode() async {
        let court = court()
        let guest = court.guests.first!
        court.join(guest)
        #expect(await court.until(within: .seconds(30)) { guest.watch!.keeper.read(now: court.wallClock) != nil })
        let onThePhone = guest.phone.keeper.read(now: court.wallClock)
        let onTheWrist = guest.watch!.keeper.read(now: court.wallClock)
        #expect(onTheWrist?.code == court.code)
        #expect(onTheWrist?.role == .guest)
        #expect(onTheWrist?.startedAt == onThePhone?.startedAt)
    }

    /// SC-008: the phone in a bag, the code typed on the wrist, and both on within 10 s.
    @Test func joiningOnTheWristWithThePhoneInABag() async {
        let court = court()
        let guest = court.guests.first!
        guest.phone.radio.background(true)
        guest.watch!.standIn!.join(court.code)
        #expect(await court.until(within: .seconds(10)) {
            onTheMatch(court, guest.phone) && onTheMatch(court, guest.watch!)
        })
    }

    /// FR-022, FR-024: off from the wrist, the phone with it, and back on without typing.
    @Test func leavingAndJoiningAgainFromTheWrist() async {
        let court = court()
        let guest = court.guests.first!
        court.join(guest)
        await court.until(within: .seconds(30)) { onTheMatch(court, guest.watch!) }
        await court.until(within: .seconds(10)) { guest.watch!.standIn!.canJoinAgain == false }

        guest.watch!.sharing.leave()
        #expect(await court.until(within: .seconds(10)) { guest.phone.store.state == nil && guest.watch!.store.state == nil })
        #expect(guest.watch!.standIn!.canJoinAgain, "the code is still kept")

        guest.watch!.standIn!.joinAgain()
        #expect(await court.until(within: .seconds(30)) {
            onTheMatch(court, guest.phone) && onTheMatch(court, guest.watch!)
        })
    }

    /// FR-023: off on the phone is off on the wrist.
    @Test func leavingOnThePhoneTakesTheWatchOff() async {
        let court = court()
        let guest = court.guests.first!
        court.join(guest)
        await court.until(within: .seconds(30)) { onTheMatch(court, guest.watch!) }

        guest.phone.sharing.stop()
        #expect(await court.until(within: .seconds(10)) { guest.watch!.store.state == nil })
    }

    /// FR-024: the host stopped, so joining again says nothing is there, and lets the code go.
    @Test func joiningAgainAfterTheHostStoppedSaysSoAndForgets() async {
        let court = court()
        let guest = court.guests.first!
        court.join(guest)
        await court.until(within: .seconds(30)) { onTheMatch(court, guest.watch!) }
        await court.until(within: .seconds(10)) { guest.watch!.keeper.read(now: court.wallClock) != nil }

        court.host.phone.sharing.stop()
        await court.until(within: .seconds(10)) { guest.watch!.store.state == nil }
        #expect(guest.watch!.standIn!.canJoinAgain)

        guest.watch!.standIn!.joinAgain()
        #expect(await court.until(within: .seconds(60)) { guest.watch!.standIn!.joining == .failed(.notFound) })
        #expect(guest.watch!.keeper.read(now: court.wallClock) == nil)
        #expect(!guest.watch!.standIn!.canJoinAgain)
    }

    /// FR-021: a watch whose phone is hosting is asked before joining, since it stops the sharing.
    @Test func aHostsWatchIsAskedBeforeJoiningAnotherMatch() async {
        let court = court()
        let watch = court.host.watch!.standIn!
        #expect(await court.until(within: .seconds(5)) { watch.joiningStopsSharing })
        court.host.phone.sharing.stop()
        #expect(await court.until(within: .seconds(5)) { !watch.joiningStopsSharing })
    }

    /// FR-025: the wrist's app ended and run again, its phone out of reach, back on with nothing typed.
    @Test func aRelaunchedWatchGetsBackOnByItself() async {
        let court = court()
        let guest = court.guests.first!
        court.join(guest)
        await court.until(within: .seconds(30)) { onTheMatch(court, guest.watch!) }
        await court.until(within: .seconds(10)) { guest.watch!.keeper.read(now: court.wallClock) != nil }

        court.endApp(guest.watch!)
        court.relaunch(guest.watch!)
        court.separate(guest)
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(60)) { court.inStep(guest.watch!, with: court.host.phone) })
    }
}
