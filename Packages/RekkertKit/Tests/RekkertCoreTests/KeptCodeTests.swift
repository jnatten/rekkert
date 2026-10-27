import Foundation
import Testing
@testable import RekkertCore

@Suite("Kept code")
struct KeptCodeTests {
    private let start = Date(timeIntervalSince1970: 50_000)
    private let code = SessionCode("482915")!

    private func kept(_ role: SessionRole, at time: Date? = nil) -> KeptCode {
        KeptCode(code: code, share: role == .host ? UUID() : nil, role: role, startedAt: time ?? start)
    }

    @Test func itLastsTwelveHoursFromWhenSharingStarted() {
        let host = kept(.host)
        #expect(host.expiresAt == start.addingTimeInterval(12 * 60 * 60))
        #expect(host.current(now: start.addingTimeInterval(12 * 60 * 60 - 1)) == host)
        #expect(host.current(now: start.addingTimeInterval(12 * 60 * 60)) == nil)
    }

    @Test func hostingOrProvingAJoinKeepsIt() {
        #expect(KeptCode.after(.hosted(kept(.host)), kept: nil)?.role == .host)
        #expect(KeptCode.after(.proven(kept(.guest)), kept: nil)?.role == .guest)
    }

    @Test func theHostStoppingForgetsItsOwnButNotAGuests() {
        #expect(KeptCode.after(.stoppedHosting, kept: kept(.host)) == nil)
        let guest = kept(.guest)
        #expect(KeptCode.after(.stoppedHosting, kept: guest) == guest)
    }

    @Test func aGuestToldSharingHasStoppedForgetsIt() {
        #expect(KeptCode.after(.sharingStopped, kept: kept(.guest)) == nil)
        let host = kept(.host)
        #expect(KeptCode.after(.sharingStopped, kept: host) == host)
    }

    @Test func aGuestThatLeavesKeepsItToJoinAgain() {
        let guest = kept(.guest)
        #expect(KeptCode.after(.left, kept: guest) == guest)
    }

    @Test func joiningAnotherCodeReplacesTheOneKept() {
        let other = KeptCode(code: SessionCode("111222")!, share: nil, role: .guest, startedAt: start)
        #expect(KeptCode.after(.proven(other), kept: kept(.guest)) == other)
    }

    @Test func aCodeTypedThatNeverWorkedIsNeverKept() {
        #expect(KeptCode.after(.typed, kept: nil) == nil)
        let guest = kept(.guest)
        #expect(KeptCode.after(.typed, kept: guest) == guest)
    }
}
