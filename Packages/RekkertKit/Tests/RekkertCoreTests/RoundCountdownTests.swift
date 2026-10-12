import Foundation
import Testing
@testable import RekkertCore

private let noon = Date(timeIntervalSince1970: 1_700_000_000)
private func minutes(_ count: Double) -> Date { noon.addingTimeInterval(count * 60) }

@Suite("A round's countdown")
struct RoundCountdownTests {
    private let twelve = RoundClock(length: 12 * 60, runningSince: noon)

    @Test func aRunningCountdownCountsDownFromItsLength() {
        #expect(twelve.remaining(at: noon) == 12 * 60)
        #expect(twelve.remaining(at: minutes(5)) == 7 * 60)
        #expect(twelve.endsAt == minutes(12))
        #expect(!twelve.hasRunOut(at: minutes(11.9)))
        #expect(twelve.hasRunOut(at: minutes(12)))
        #expect(twelve.remaining(at: minutes(13)) == -60, "a minute over")
    }

    @Test func pausingBanksWhatHasRun() {
        let paused = twelve.pausing(at: minutes(5))
        #expect(paused.isPaused)
        #expect(paused.remaining(at: minutes(5)) == 7 * 60)
        #expect(paused.remaining(at: minutes(30)) == 7 * 60, "a paused round loses nothing")
        #expect(paused.pausing(at: minutes(8)) == paused, "pausing twice is pausing once")
    }

    @Test func resumingCarriesOnFromWhereItWasPaused() {
        let resumed = twelve.pausing(at: minutes(5)).resuming(at: minutes(10))
        #expect(!resumed.isPaused)
        #expect(resumed.remaining(at: minutes(10)) == 7 * 60)
        #expect(resumed.endsAt == minutes(17))
        #expect(resumed.resuming(at: minutes(11)) == resumed, "resuming a running round changes nothing")
    }

    @Test func snoozingAddsMinutesToTheEnd() {
        let snoozed = twelve.snoozing(by: 2 * 60, at: minutes(5))
        #expect(snoozed.endsAt == minutes(14))
        #expect(snoozed.remaining(at: minutes(5)) == 9 * 60)
    }

    @Test func snoozingAfterTheEndGivesThoseMinutesFromNow() {
        let snoozed = twelve.snoozing(by: 2 * 60, at: minutes(15))
        #expect(snoozed.endsAt == minutes(17), "two minutes from now, not from when it ran out")
        #expect(snoozed.remaining(at: minutes(15)) == 2 * 60)
    }

    @Test func snoozingAPausedRoundLengthensWhatIsLeft() {
        let snoozed = twelve.pausing(at: minutes(5)).snoozing(by: 60, at: minutes(9))
        #expect(snoozed.isPaused)
        #expect(snoozed.remaining(at: minutes(20)) == 8 * 60)
    }

    @Test func aPausedCountdownHasNoEnd() {
        #expect(twelve.pausing(at: minutes(1)).endsAt == nil)
    }

    @Test func aDeviceBehindTheStampSeesTheFullLength() {
        #expect(twelve.remaining(at: noon.addingTimeInterval(-3)) == 12 * 60)
    }

    @Test func aCountdownSurvivesAnEncode() throws {
        for clock in [twelve, twelve.pausing(at: minutes(4)), twelve.snoozing(by: 120, at: minutes(1))] {
            let data = try JSONEncoder().encode(clock)
            #expect(try JSONDecoder().decode(RoundClock.self, from: data) == clock)
        }
    }
}
