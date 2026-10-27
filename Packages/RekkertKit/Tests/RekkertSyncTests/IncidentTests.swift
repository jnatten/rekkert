import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// The ways guests fell off a match shared over Bluetooth on 2026-10-26, each replayed over the
/// simulated radio. Every one of these failed on the code as it was that evening.
@Suite("The incident", .serialized)
@MainActor
struct IncidentTests {
    private func sharedCourt(
        guests: Int,
        withWatches: Bool = true,
        settings: Airwaves.Settings = Airwaves.Settings(),
        timing: CourtHarness.Timing = CourtHarness.Timing()
    ) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: withWatches, settings: settings, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(120)) { court.allInStep() }
        #expect(court.allInStep(), "everybody on before the incident starts")
        return court
    }

    /// RC-1: iOS ends the host's app in the bag. Its watch keeps scoring and wakes it, and every
    /// guest has to be back on, on the same code, with nothing typed.
    @Test func hostAppEndedComesBackOnTheSameCode() async {
        let court = await sharedCourt(guests: 2)
        court.endApp(court.host.phone)
        await court.run(for: .seconds(5))

        court.score(on: court.host.watch!)
        court.relaunch(court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(court.host.phone.sharing.code == court.code)
    }

    /// RC-2: what the host sends one guest stops getting through for a while, so that guest hears
    /// nothing and says nothing — and has nothing waiting to say, so nothing of its own revives
    /// the link. Within 30 s of the link carrying again it has to be back in step (FR-003).
    @Test func silentFollowerIsNeverWrittenOff() async {
        var timing = CourtHarness.Timing()
        timing.retryInterval = .seconds(600)
        let court = await sharedCourt(guests: 2, withWatches: false, timing: timing)
        let quiet = court.guests.last!.phone
        quiet.radio.missesIncoming = true
        for _ in 0 ..< 4 {
            court.score(on: court.host.phone)
            await court.run(for: .seconds(6))
        }
        quiet.radio.missesIncoming = false
        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }

    /// RC-3: seven guests behind a host whose transmit queue frees one slot at a time. Every one
    /// of them gets every point, not just the ones that come first.
    @Test func everyGuestGetsTurns() async {
        var settings = Airwaves.Settings()
        settings.queueSlots = 2
        settings.slotsPerReady = 1
        settings.bytesPerSecond = 1_500
        let court = await sharedCourt(guests: 7, withWatches: false, settings: settings)
        for _ in 0 ..< 8 {
            court.score(on: court.host.phone)
            await court.run(for: .milliseconds(500))
        }
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
    }

    /// RC-4: half an hour of play with seven guests. What each guest is sent stays in proportion
    /// to what is scored, and the points arrive in time.
    @Test func deliveryDoesNotSnowball() async {
        var settings = Airwaves.Settings()
        settings.bytesPerSecond = 1_200
        var timing = CourtHarness.Timing()
        timing.step = .milliseconds(200)
        let court = await sharedCourt(guests: 7, withWatches: false, settings: settings, timing: timing)
        let scorers = court.players.map(\.phone)
        let before = court.guests.map { court.air.bytesDelivered(to: $0.phone.radio) }

        // Side to side, so the game goes to deuce and the match is still on at the end.
        for point in 0 ..< 150 {
            court.score(on: scorers[point % scorers.count], team: point.isMultiple(of: 2) ? .a : .b)
            await court.run(for: .seconds(8))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })

        let times = court.arrivalTimes().sorted()
        let onTime = times.filter { $0 <= .seconds(5) }.count
        #expect(Double(onTime) >= Double(times.count) * 0.95, "95% of points within 5 s")
        #expect((times.last ?? .zero) <= .seconds(30), "every point within 30 s")
        for (index, guest) in court.guests.enumerated() {
            let sent = court.air.bytesDelivered(to: guest.phone.radio) - before[index]
            #expect(sent < 250_000, "bytes to \(guest.phone.name): \(sent)")
        }
    }

    /// RC-5: iOS ends a guest's app. Run again, it gets back on without the code typed.
    @Test func guestAppEndedRejoinsWithoutTyping() async {
        let court = await sharedCourt(guests: 1, withWatches: false)
        let guest = court.guests.first!.phone
        court.endApp(guest)
        court.score(on: court.host.phone)
        await court.run(for: .seconds(5))

        court.relaunch(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }

    /// RC-7: an eighth guest is turned away and told so, and the seven already on carry on.
    @Test func eighthGuestIsToldNoRoom() async {
        let court = CourtHarness(guests: 8, withWatches: false)
        court.startMatch()
        court.share()
        for guest in court.guests.dropLast() { court.join(guest) }
        await court.until(within: .seconds(120)) {
            court.guests.dropLast().allSatisfy { court.inStep($0.phone, with: court.host.phone) }
        }
        let eighth = court.guests.last!.phone
        court.join(court.guests.last!)
        #expect(await court.until(within: .seconds(60)) { eighth.sharing.phase == .failed(.noRoom) })

        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) {
            court.guests.dropLast().allSatisfy { court.inStep($0.phone, with: court.host.phone) }
        })
        #expect(court.host.phone.store.participants.all.count == 7)
        #expect(!court.inStep(eighth, with: court.host.phone))
    }

    /// RW-2: the guest's watch was warming up a match of its own when the phone joined. It ends up
    /// on the host's match with nothing scored and nothing done on the wrist, even with what the
    /// two queue for each other taking its time, as WatchConnectivity's queue does.
    @Test func guestWatchTakesItsPhonesMatch() async {
        let court = CourtHarness(guests: 1)
        court.startMatch()
        court.share()
        let guest = court.guests.first!
        guest.watch!.store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)), warmup: true)
        await court.run(for: .seconds(2))

        court.holdQueues(of: guest)
        court.join(guest)
        #expect(await court.until(within: .seconds(10)) {
            guest.watch!.store.log.sessionID == court.host.phone.store.log.sessionID
        })
    }

    /// RW-4: a guest's watch standing in for its phone is the same guest, not another one.
    @Test func standingInWatchCountsOnce() async {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(500))
        let court = await sharedCourt(guests: 1, timing: timing)
        let guest = court.guests.first!
        guest.phone.radio.switchRadio(on: false)
        #expect(await court.until(within: .seconds(120)) { guest.watch!.sharing.reachablePeers > 0 })

        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(60)) { court.inStep(guest.watch!, with: court.host.phone) })
        #expect(court.host.phone.store.participants.all.count == 1)
    }
}
