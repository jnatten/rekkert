import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Why a join did not work", .serialized)
@MainActor
struct JoinRefusalTests {
    private func hostingCourt(_ prepare: (CourtHarness) -> Void = { _ in }) -> (CourtHarness, CourtHarness.Device) {
        let court = CourtHarness(guests: 1, withWatches: false)
        prepare(court)
        court.startMatch()
        court.share()
        return (court, court.guests.first!.phone)
    }

    @Test func aWrongCodeFindsNothingWithinFifteenSeconds() async {
        let (court, guest) = hostingCourt()
        guest.sharing.join(SessionCode("111111")!)
        #expect(await court.until(within: .seconds(15)) { guest.sharing.phase == .failed(.notFound) })
        #expect(!guest.radio.isScanning, "nothing left looking once the screen has said so")
    }

    @Test func aHostOutOfRangeFindsNothingWithinFifteenSeconds() async {
        let (court, guest) = hostingCourt { court in court.outOfRange(court.host.phone) }
        court.join(court.guests.first!)
        #expect(await court.until(within: .seconds(15)) { guest.sharing.phase == .failed(.notFound) })
    }

    @Test func bluetoothSwitchedOffIsSaidSo() async {
        let (court, guest) = hostingCourt()
        guest.radio.switchRadio(on: false)
        court.join(court.guests.first!)
        #expect(await court.until(within: .seconds(15)) { guest.sharing.phase == .failed(.bluetoothOff) })
    }

    @Test func bluetoothRefusedToTheAppIsSaidSo() async {
        let (court, guest) = hostingCourt()
        guest.radio.deny()
        court.join(court.guests.first!)
        #expect(await court.until(within: .seconds(15)) { guest.sharing.phase == .failed(.bluetoothDenied) })
    }

    /// FR-008: already on the match, Bluetooth switched off is said on the phone and its watch,
    /// not left as "out of reach", and switched back on the guest is back on by itself.
    @Test func bluetoothSwitchedOffOnTheMatchIsSaidOnThePhoneAndTheWatch() async {
        let court = CourtHarness(guests: 1, withWatches: true)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        let guest = court.guests.first!

        guest.phone.radio.switchRadio(on: false)
        #expect(await court.until(within: .seconds(15)) {
            guest.phone.sharing.radioTrouble == .bluetoothOff
                && guest.watch!.standIn!.statuses.first == .phoneBluetoothOff
        })

        guest.phone.radio.switchRadio(on: true)
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(guest.phone.sharing.radioTrouble == nil)
        #expect(!guest.watch!.standIn!.statuses.contains(.phoneBluetoothOff))
    }

    @Test func bluetoothRefusedOnTheMatchIsSaidOnThePhoneAndTheWatch() async {
        let court = CourtHarness(guests: 1, withWatches: true)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        let guest = court.guests.first!

        guest.phone.radio.deny()
        #expect(await court.until(within: .seconds(15)) {
            guest.phone.sharing.radioTrouble == .bluetoothDenied
                && guest.watch!.standIn!.statuses.first == .phoneBluetoothDenied
        })
    }

    @Test func twoCourtsSideBySideEachGuestLandsOnItsOwnHost() async {
        let first = CourtHarness(guests: 1, withWatches: false)
        let second = CourtHarness(guests: 1, withWatches: false, air: first.air, code: SessionCode("731604")!)
        for court in [first, second] {
            court.startMatch()
            court.share()
            court.joinAll()
        }
        #expect(await first.until(within: .seconds(30)) { first.allInStep() && second.allInStep() })
        #expect(first.host.phone.store.log.sessionID != second.host.phone.store.log.sessionID)
    }

    @Test func aHostSlowToProveItselfIsAskedAgainRatherThanTurnedAway() async {
        let (court, guest) = hostingCourt()
        guest.radio.losesWrites = true
        court.join(court.guests.first!)
        await court.run(for: .seconds(5))
        guest.radio.losesWrites = false
        #expect(await court.until(within: .seconds(10)) { court.allInStep() })
        await court.run(for: .seconds(5))
        #expect(!guest.store.isJoining)
        #expect(guest.sharing.phase == .searching && guest.sharing.reachablePeers == 1)
    }

    /// The greeting's one byte agrees by chance for one code in 256, so the code is found that does.
    @Test func onlyAHostThatRefusesTheKeyIsPassedOver() {
        let air = Airwaves()
        let share = UUID()
        let right = SessionCode("482915")!
        let fingerprint = SessionKey.fingerprint(for: right, share: share)
        let lookalike = (0 ..< 1_000_000).lazy
            .compactMap { SessionCode(String(format: "%06d", $0)) }
            .first { $0 != right && SessionKey.fingerprint(for: $0, share: share) == fingerprint }!
        let wrongHost = RadioCore(radio: air.radio())
        let rightHost = RadioCore(radio: air.radio())
        let guest = RadioCore(radio: air.radio())
        defer { for core in [wrongHost, rightHost, guest] { core.stop() } }

        wrongHost.startHosting(code: lookalike, share: share)
        air.clock.advance(by: .milliseconds(100))
        guest.startJoining(code: right)
        for _ in 0 ..< 60 { air.clock.advance(by: .milliseconds(50)) }
        #expect(!guest.isReachable)

        rightHost.startHosting(code: right, share: UUID())
        var waited = Duration.zero
        while !guest.isReachable, waited < .seconds(3) {
            air.clock.advance(by: .milliseconds(50))
            waited += .milliseconds(50)
        }
        #expect(guest.isReachable, "on the right host well before a proof could time out")
        #expect(rightHost.reachableCount == 1)
        #expect(wrongHost.reachableCount == 0)
    }

    @Test func aHostWhoseAddressMovedOnIsFoundAgainWithinThirtySeconds() async {
        let (court, _) = hostingCourt()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        #expect(court.allInStep())

        court.outOfRange(court.host.phone)
        await court.run(for: .seconds(20))
        court.host.phone.radio.rotateAddress()
        court.score(on: court.host.phone)
        court.backInRange(court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }
}
