import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-002: the guest's own note that it got on says which radio it got on over.
@Suite("Which radio a join got through on", .serialized)
@MainActor
struct JoinedEntryTests {
    @Test func theJoinNamesItsRadio() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
        let joined = court.guests.first!.phone.recorder.read().entries.first { $0.kind == .joined }
        #expect(joined?.radios == [.bluetooth])
    }
}
