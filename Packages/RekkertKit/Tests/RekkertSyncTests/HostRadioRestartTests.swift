import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-009: at 19:54 on 9 November the host's Bluetooth went off for two seconds by
/// itself, and every guest was back within seven. Pinned so later changes cannot lose it.
@Suite("Back in step after the host's Bluetooth restarts", .serialized)
@MainActor
struct HostRadioRestartTests {
    @Test func everyGuestIsBackWithinTenSeconds() async {
        let court = CourtHarness(guests: 4, withWatches: false)
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) { court.allInStep() })

        court.host.phone.radio.switchRadio(on: false)
        await court.run(for: .seconds(2))
        court.host.phone.radio.switchRadio(on: true)
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(10)) {
            court.allInStep() && court.host.phone.core.reachableCount == 4
        })
    }
}
