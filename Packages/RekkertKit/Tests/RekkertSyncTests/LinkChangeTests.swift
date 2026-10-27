import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@MainActor
private final class ChangeLog {
    private(set) var changes: [LinkChange] = []
    private var listening: Task<Void, Never>?

    init(_ stream: AsyncStream<LinkChange>) {
        listening = Task { [weak self] in
            for await change in stream { self?.changes.append(change) }
        }
    }

    var ups: Int { changes.count { if case .up = $0 { true } else { false } } }
    var reasons: [LinkDropReason] {
        changes.compactMap { if case .down(_, let reason) = $0 { reason } else { nil } }
    }

    func stop() { listening?.cancel() }
}

@Suite("Link changes", .serialized)
@MainActor
struct LinkChangeTests {
    private func sharedCourt() async -> CourtHarness {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        return court
    }

    @Test func aGuestWalkingOffIsAPeerClosingAndComingBackIsTheLinkUpAgain() async {
        let court = await sharedCourt()
        let host = ChangeLog(court.host.phone.core.linkChanges)
        defer { host.stop() }

        court.outOfRange(court.guests.first!.phone)
        #expect(await court.until(within: .seconds(10)) { host.reasons == [.closedByPeer] })
        court.backInRange(court.guests.first!.phone)
        #expect(await court.until(within: .seconds(60)) { host.ups == 1 })
    }

    @Test func aGuestSwitchingItsRadioOffSaysSo() async {
        let court = await sharedCourt()
        let guest = ChangeLog(court.guests.first!.phone.core.linkChanges)
        defer { guest.stop() }

        court.guests.first!.phone.radio.switchRadio(on: false)
        #expect(await court.until(within: .seconds(10)) { guest.reasons == [.radioOff] })
    }

    @Test func theHostStoppingHangsUpOnEveryGuest() async {
        let court = await sharedCourt()
        let host = ChangeLog(court.host.phone.core.linkChanges)
        defer { host.stop() }

        court.host.phone.sharing.stop()
        #expect(await court.until(within: .seconds(10)) { host.reasons == [.hungUp] })
    }

    @Test func theFanOutPassesItsChildrensChangesOn() async {
        let court = await sharedCourt()
        let fanned = ChangeLog(court.host.phone.links.linkChanges)
        defer { fanned.stop() }

        court.outOfRange(court.guests.first!.phone)
        #expect(await court.until(within: .seconds(10)) { fanned.reasons == [.closedByPeer] })
    }
}
