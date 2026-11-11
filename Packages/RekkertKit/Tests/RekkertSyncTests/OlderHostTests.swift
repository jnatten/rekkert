import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-015: a guest from this release on a host still on 1.1 follows as today. It never
/// asks that host the time, which 1.1 could not read, and the delays that come through it read
/// unknown, put down to the older host rather than to clocks that could not be bounded.
@Suite("A host on 1.1", .serialized)
@MainActor
struct OlderHostTests {
    @Test func aGuestOnAnOlderHostFollowsAndItsRelayedDelaysReadUnknown() async {
        let court = CourtHarness(guests: 2, withWatches: false)
        court.host.phone.store.actsAsOlderBuild = true
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })

        let (first, second) = (court.guests.first!.phone, court.guests.last!.phone)
        for index in 0 ..< 10 {
            court.score(on: [court.host.phone, first, second][index % 3], team: index.isMultiple(of: 2) ? .a : .b)
            await court.run(for: .seconds(35))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(court.host.phone.store.clockQuestionsHeard == 0)

        let arrived = first.recorder.read().entries.filter {
            if case .pointArrived = $0.kind { true } else { false }
        }
        #expect(arrived.count >= 6)
        #expect(arrived.allSatisfy { $0.kind == .pointArrived(latency: nil) && $0.detail == "older" })
    }
}
