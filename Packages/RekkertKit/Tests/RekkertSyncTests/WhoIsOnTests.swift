import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Who is on, and why not", .serialized)
@MainActor
struct WhoIsOnTests {
    private func sharedCourt(guests: Int = 2, withWatches: Bool = false) async -> CourtHarness {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(500))
        let court = CourtHarness(guests: guests, withWatches: withWatches, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(120)) { court.allInStep() }
        #expect(court.allInStep())
        return court
    }

    private func state(of guest: CourtHarness.Device, on court: CourtHarness) -> ParticipantState? {
        court.host.phone.store.participantStates().first { $0.id == guest.id }?.state
    }

    private func entries(_ device: CourtHarness.Device) -> [LinkRecordEntry] {
        device.recorder.read().entries
    }

    /// FR-010: the host sees each guest go and come back within 15 s.
    @Test func theHostSeesAGuestGoAndComeBack() async {
        let court = await sharedCourt()
        let guest = court.guests.first!.phone
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(15)) { state(of: guest, on: court) == .inStep })

        court.outOfRange(guest)
        #expect(await court.until(within: .seconds(15)) {
            if case .outOfReach? = state(of: guest, on: court) { true } else { false }
        })
        court.backInRange(guest)
        #expect(await court.until(within: .seconds(15)) { state(of: guest, on: court) == .inStep })
    }

    /// FR-011: the phone's link to its watch and its link to the match are told apart.
    @Test func eachDeviceSaysItsTwoLinksApart() async {
        let court = await sharedCourt(guests: 1, withWatches: true)
        let guest = court.guests.first!

        guest.phone.radio.switchRadio(on: false)
        #expect(await court.until(within: .seconds(10)) { guest.phone.sharing.reachablePeers == 0 })
        #expect(guest.phone.store.isPairReachable, "the watch is still there")
        guest.phone.radio.switchRadio(on: true)
        #expect(await court.until(within: .seconds(30)) { guest.phone.sharing.reachablePeers > 0 })

        court.separate(guest)
        #expect(await court.until(within: .seconds(5)) { !guest.phone.store.isPairReachable })
        #expect(guest.phone.sharing.reachablePeers > 0, "the match is still there")
    }

    /// SC-006: each failure staged in the field test leaves records that name the link that broke.
    @Test func theHostsAppEndedIsTheLinkToTheHost() async {
        let court = await sharedCourt(guests: 1)
        let guest = court.guests.first!.phone
        court.endApp(court.host.phone)
        await court.run(for: .seconds(20))
        court.relaunch(court.host.phone)
        await court.until(within: .seconds(30)) { court.allInStep() }

        let host = court.host.phone.id
        #expect(entries(guest).contains { $0.link == .host(host) && $0.kind.isADrop })
        #expect(entries(court.host.phone).contains { $0.kind == .appHadBeenEnded })
        #expect(!entries(guest).contains { $0.link == .pair && $0.kind.isADrop })
    }

    @Test func aGuestOutOfRangeIsTheLinkBetweenItAndTheHost() async {
        let court = await sharedCourt(guests: 1)
        let guest = court.guests.first!.phone
        court.outOfRange(guest)
        await court.run(for: .seconds(20))

        #expect(entries(court.host.phone).contains { $0.link == .guest(guest.id) && $0.kind == .outOfReach })
        #expect(entries(guest).contains { $0.link == .host(court.host.phone.id) && $0.kind.isADrop })
    }

    @Test func aGuestsRadioOffIsSaidOnThatGuest() async {
        let court = await sharedCourt(guests: 1)
        let guest = court.guests.first!.phone
        guest.radio.switchRadio(on: false)
        await court.run(for: .seconds(5))

        #expect(entries(guest).contains { $0.kind == .radioOff })
        #expect(entries(guest).contains { $0.link == .host(court.host.phone.id) && $0.kind == .dropped(.radioOff) })
    }

    @Test func aWatchOutOfReachOfItsPhoneIsThePairAndReachesThePhonesRecord() async {
        let court = await sharedCourt(guests: 1, withWatches: true)
        let guest = court.guests.first!
        court.separate(guest)
        await court.run(for: .seconds(5))
        court.reunite(guest)
        await court.run(for: .seconds(5))

        let merged = entries(guest.phone)
        #expect(merged.contains { $0.device == .watch && $0.link == .pair && $0.kind.isADrop })
        #expect(merged.contains { $0.device == .phone && $0.link == .pair && $0.kind.isADrop })
        #expect(merged.contains { $0.kind == .recordReceived(from: .watch) })
        #expect(!merged.contains { $0.device == .watch && $0.kind.isADrop && $0.link != .pair })
    }

    @Test func theRecordHoldsNoCodeAndNoScore() async {
        let court = await sharedCourt(guests: 1, withWatches: true)
        for point in 0 ..< 5 { court.score(on: court.host.phone, team: point.isMultiple(of: 2) ? .a : .b) }
        await court.run(for: .seconds(10))
        let header = LinkRecord.Header(app: "1.0 (1) test", phoneSystem: "iOS", phone: court.host.phone.id)
        for device in court.devices {
            let text = device.recorder.read().export(header, now: court.wallClock, in: .current)
            #expect(!text.contains("482915") && !text.contains("482 915") && !text.contains("482-915"))
            #expect(!text.contains("Us") && !text.contains("Them"))
        }
    }
}

private extension LinkEvent {
    var isADrop: Bool {
        switch self {
        case .dropped, .wroteOff, .redialled, .outOfReach: true
        default: false
        }
    }
}
