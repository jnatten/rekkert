import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let eightPlayers = SessionSetup.tournament(Tournament(
    name: "Thursday", format: .americano,
    players: ["Ada", "Bob", "Cy", "Di", "Eli", "Fay", "Gus", "Hal"].map { Player(name: $0) },
    config: TournamentConfig(pointRules: PointCountRules(target: 128), courtCount: 2)
))

@Suite("A club night", .serialized)
@MainActor
struct ClubNightTests {
    /// US1 AS6, SC-009: an americano over two courts, a host and seven guests each with a watch,
    /// for half an hour with points tapped on every phone and watch. Every device shows the host's
    /// score at every check, and the points arrive within FR-002's times. The radio's speed is the
    /// estimate until the field test measures it.
    @Test func twoCourtsSevenGuestsHalfAnHour() async {
        var timing = CourtHarness.Timing()
        timing.step = .milliseconds(200)
        let court = CourtHarness(guests: 7, withWatches: true, timing: timing)
        court.startMatch(eightPlayers)
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(180)) { court.allInStep() }, "everybody on")

        let scorers = court.devices
        for point in 0 ..< 150 {
            court.score(on: scorers[point % scorers.count], court: point % 2, team: point % 4 < 2 ? .a : .b)
            await court.run(for: .seconds(12))
            if point % 15 == 14 {
                #expect(await court.until(within: .seconds(30)) { court.allInStep() }, "check after point \(point + 1)")
            }
        }

        let times = court.arrivalTimes().sorted()
        let onTime = times.filter { $0 <= .seconds(5) }.count
        #expect(Double(onTime) >= Double(times.count) * 0.95, "95% within 5 s: \(onTime) of \(times.count)")
        #expect((times.last ?? .zero) <= .seconds(30), "every point within 30 s")
    }

    /// FR-002, FR-021: a watch on the match without its phone, with no workout and Rekkert in the
    /// background, says the phone needs opening; brought to the front, it is back in step within 10 s.
    @Test func aWatchWithoutItsPhoneCatchesUpWhenItComesToTheFront() async {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(300))
        timing.standInTick = .milliseconds(10)
        let court = CourtHarness(guests: 1, withWatches: true, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        let guest = court.guests.first!
        let watch = guest.watch!.standIn!
        await court.until(within: .seconds(10)) { guest.watch!.sharing.standbyCode != nil }

        watch.mayUseTheRadio = { false }
        court.endApp(guest.phone)
        #expect(await court.until(within: .seconds(120)) { watch.phoneNeedsOpening })
        court.score(on: court.host.phone)
        await court.run(for: .seconds(5))
        #expect(!court.inStep(guest.watch!, with: court.host.phone), "nothing reaches a watch in the background")

        watch.mayUseTheRadio = { true }
        #expect(await court.until(within: .seconds(10)) { court.inStep(guest.watch!, with: court.host.phone) })
    }
}
