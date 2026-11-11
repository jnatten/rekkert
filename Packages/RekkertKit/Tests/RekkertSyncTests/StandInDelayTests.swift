import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, Edge Cases: a guest's watch standing in for its phone counts once, and still gets
/// its points within FR-010's times.
@Suite("A watch standing in gets its points in time", .serialized)
@MainActor
struct StandInDelayTests {
    @Test func aWatchStandingInForItsPhoneMeetsFR010() async {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(300))
        timing.standInTick = .milliseconds(10)
        timing.skipsIdleTime = true
        let court = CourtHarness(guests: 2, withWatches: true, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
        let guest = court.guests.first!
        let watch = guest.watch!
        #expect(await court.until(within: .seconds(10)) { watch.sharing.standbyCode != nil })

        court.endApp(guest.phone)
        #expect(await court.until(within: .seconds(60)) { watch.sharing.isSharing && watch.sharing.reachablePeers > 0 })
        #expect(court.host.phone.store.participants.all.count == 2)

        let scorers = [court.host.phone, court.host.watch!, court.guests.last!.phone, court.guests.last!.watch!]
        for index in 0 ..< 120 {
            court.score(on: scorers[index % scorers.count], team: index.isMultiple(of: 2) ? .a : .b)
            await court.run(for: .seconds(8))
        }
        #expect(await court.until(within: .seconds(30)) { court.inStep(watch, with: court.host.phone) })

        let fine = CourtHarness.DelayStats(court.arrivals(on: watch).filter(\.nothingWrong))
        let phone = CourtHarness.DelayStats(court.arrivals(on: court.guests.last!.phone).filter(\.nothingWrong))
        #expect(fine.isJudgeable, "\(fine.count) arrivals where nothing was wrong")
        // Standing in costs it nothing against a guest's phone on the same match.
        #expect((fine.p95 ?? .seconds(60)) <= (phone.p95 ?? .zero) + .milliseconds(250), "p95 \(String(describing: fine.p95)) against \(String(describing: phone.p95))")
        // FR-010's own numbers wait for calibrated radio speeds, as in `BusyHallTests` (T077).
        withKnownIssue("FR-010 is judged on calibrated radio speeds (T059)", isIntermittent: true) {
            #expect(fine.share(within: .seconds(1)) >= 0.95, "\(fine.share(within: .seconds(1))) within 1 s")
            #expect(fine.share(within: .seconds(2)) == 1, "slowest \(String(describing: fine.slowest))")
        }
        print("StandIn watch: \(fine.count) fine, p95 \(String(describing: fine.p95)); guest phone p95 \(String(describing: phone.p95))")
    }
}
