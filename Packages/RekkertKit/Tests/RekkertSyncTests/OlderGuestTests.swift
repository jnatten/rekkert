import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-015: a guest on 1.1, which sends no clock, protocol or offsets, is on the match,
/// counted once and gets every point, and its points' delays read unknown, not wrong.
@Suite("A guest on 1.1", .serialized)
@MainActor
struct OlderGuestTests {
    @Test func anOlderGuestFollowsAndItsDelaysReadUnknown() async {
        let court = CourtHarness(guests: 2, withWatches: false)
        let older = court.guests.first!.phone
        older.store.actsAsOlderBuild = true
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
        #expect(court.host.phone.store.participants.all.count == 2)

        for index in 0 ..< 10 {
            court.score(on: index.isMultiple(of: 2) ? court.host.phone : older, team: index.isMultiple(of: 3) ? .a : .b)
            await court.run(for: .seconds(5))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })

        let fromOlder = court.host.phone.recorder.read().entries.filter {
            guard case .pointArrived = $0.kind, case .guest(let guest) = $0.link else { return false }
            return guest == older.id
        }
        #expect(!fromOlder.isEmpty)
        #expect(fromOlder.allSatisfy { $0.kind == .pointArrived(latency: nil) && $0.detail == "older" })
    }
}
