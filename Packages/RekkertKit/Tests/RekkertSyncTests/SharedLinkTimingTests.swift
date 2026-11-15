import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-010 and FR-010a: a point tapped on a watch following its phone is timed on every
/// other phone from when that phone had it, and a watch following its phone times the hop from
/// it, each within a tenth of a second or unknown (FR-006).
@Suite("Points timed from where FR-010 and FR-010a start", .serialized)
@MainActor
struct SharedLinkTimingTests {
    private static var quickRadio: Airwaves.Settings {
        var settings = Airwaves.Settings()
        settings.bytesPerSecond = 40_000
        settings.latency = .milliseconds(15)
        return settings
    }

    private func court(olderHost: Bool = false) async -> CourtHarness {
        var timing = CourtHarness.Timing()
        timing.step = .milliseconds(10)
        timing.skipsIdleTime = true
        let court = CourtHarness(
            guests: 2, settings: Self.quickRadio, timing: timing,
            clockSkew: { index, isWatch in ([0, 2.7, -1.9][index % 3] + (isWatch ? 0.35 : 0), 0) }
        )
        if olderHost {
            court.host.phone.store.actsAsOlderBuild = true
            court.host.watch!.store.actsAsOlderBuild = true
        }
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) { court.allInStep() })
        // Long enough for every device to have asked the others the time twice.
        await court.run(for: .seconds(65))
        return court
    }

    private func play(_ court: CourtHarness, on device: CourtHarness.Device, points: Int) async {
        for index in 0 ..< points {
            court.score(on: device, team: index.isMultiple(of: 2) ? .a : .b)
            await court.run(for: .seconds(12))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }

    @Test func aPointTappedOnAWatchIsTimedFromItsPhone() async {
        let court = await court()
        let scorer = court.guests.first!
        await play(court, on: scorer.watch!, points: 12)

        for phone in [court.host.phone, court.guests.last!.phone] {
            let legs = court.recordedLegs(on: phone)
            #expect(legs.count >= 10, "\(phone.name): \(legs.count) recorded")
            var unknown = 0
            for (leg, truth) in legs {
                guard case .link(let recorded) = leg else {
                    Issue.record("\(phone.name): \(leg) on a phone")
                    continue
                }
                guard let recorded else {
                    unknown += 1
                    continue
                }
                #expect(abs(recorded - truth) <= 0.1, "\(phone.name): recorded \(recorded), truly \(truth)")
            }
            #expect(unknown * 10 <= legs.count, "\(phone.name): \(unknown) of \(legs.count) unknown")
        }
        #expect(court.recordedLegs(on: scorer.phone).isEmpty, "the scorer's own phone is where the link starts")
    }

    @Test func aWatchFollowingItsPhoneTimesTheHopFromIt() async {
        let court = await court()
        await play(court, on: court.host.phone, points: 12)

        let watch = court.guests.last!.watch!
        let legs = court.recordedLegs(on: watch)
        #expect(legs.count >= 10, "\(legs.count) recorded")
        var unknown = 0
        for (leg, truth) in legs {
            guard case .hop(let recorded) = leg else {
                Issue.record("\(leg) on a watch following its phone")
                continue
            }
            guard let recorded else {
                unknown += 1
                continue
            }
            #expect(abs(recorded - truth) <= 0.1, "recorded \(recorded), truly \(truth)")
        }
        #expect(unknown * 10 <= legs.count, "\(unknown) of \(legs.count) unknown")
    }

    /// FR-006: a 1.1 host passes on nothing to time it by.
    @Test func aPointRelayedThroughAnOlderHostReadsUnknown() async {
        let court = await court(olderHost: true)
        await play(court, on: court.guests.first!.watch!, points: 5)

        let other = court.guests.last!.phone
        let points = other.recorder.read().entries.filter { if case .pointArrived = $0.kind { true } else { false } }
        #expect(points.count >= 5)
        #expect(points.allSatisfy { $0.kind == .pointArrived(latency: nil) && $0.detail == "older" })
        #expect(points.allSatisfy { if case .link(_?)? = $0.leg { false } else { true } })
    }
}
