import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private func firstTwoApart(_ players: [RekkertCore.Player]) -> [PairingRule] {
    [PairingRule(kind: .apart, players: [players[0].id, players[1].id])]
}

/// Spec 006, FR-014: no device that cannot draw with pairing rules ever holds a friendly with them.
@Suite("Older builds stay off a friendly with rules", .serialized)
@MainActor
struct PairingRulesAdmissionTests {
    private func holdsRules(_ device: CourtHarness.Device, in court: CourtHarness) -> Bool {
        court.friendly(on: device).map { !$0.pairingRules.isEmpty } ?? false
    }

    @Test func aProtocolTwoGuestIsToldToUpdate() async {
        let court = CourtHarness(guests: 1, withWatches: true)
        let guest = court.guests.first!
        guest.phone.store.speaksProtocol = 2
        guest.watch!.store.speaksProtocol = 2
        court.startFriendly(rules: firstTwoApart)
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.needsUpdate) })
        #expect(guest.phone.recorder.read().entries.contains { $0.kind == .refused(.needsUpdate) })
        #expect(!holdsRules(guest.phone, in: court))
    }

    @Test func aOneOneGuestIsTurnedAway() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.actsAsOlderBuild = true
        court.startFriendly(rules: firstTwoApart)
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.noRoom) })
        #expect(court.host.phone.store.participants.all.isEmpty)
        #expect(!holdsRules(guest.phone, in: court))
    }

    @Test func aCurrentGuestJoins() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        court.startFriendly(rules: firstTwoApart)
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep(includingWatches: false) })
        #expect(holdsRules(guest.phone, in: court))
        #expect(court.friendly(on: guest.phone)?.rounds == court.friendly(on: court.host.phone)?.rounds)
    }

    @Test func rulesArrivingTakeOlderGuestsOff() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.speaksProtocol = 2
        court.startFriendly()
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep(includingWatches: false) })

        court.finish(on: court.host.phone)
        court.answer(.keepSharing, on: court.host.phone)
        court.startFriendly(rules: firstTwoApart)
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.needsUpdate) })
        #expect(!holdsRules(guest.phone, in: court))
    }

    @Test func withoutRulesOlderGuestsStay() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.speaksProtocol = 2
        court.startFriendly(players: ["Ada", "Bob", "Cy", "Dan", "Eve"])
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep(includingWatches: false) })
        for _ in 0 ..< 5 {
            court.playFriendlyRound(on: court.host.phone)
            await court.run(for: .seconds(3))
        }
        #expect(await court.until(within: .seconds(30)) { court.allInStep(includingWatches: false) })
        #expect(court.friendly(on: guest.phone)?.rounds.map(\.teams) == court.friendly(on: court.host.phone)?.rounds.map(\.teams))
        #expect(court.friendly(on: guest.phone)?.rounds.count == 6)
    }

    @Test func anOlderWatchIsHeldBackAndThePhoneSaysSo() async {
        let court = CourtHarness(guests: 0, withWatches: true)
        let phone = court.host.phone
        let watch = court.host.watch!
        watch.store.speaksProtocol = 2
        await court.run(for: .seconds(2))
        court.startFriendly(rules: firstTwoApart)
        #expect(await court.until(within: .seconds(5)) { phone.store.pairNeedsUpdateForRules })
        for _ in 0 ..< 3 {
            court.playFriendlyRound(on: phone)
            await court.run(for: .seconds(2))
        }
        #expect(!holdsRules(watch, in: court))

        court.endApp(phone)
        court.relaunch(phone)
        #expect(phone.store.pairNeedsUpdateForRules, "remembered from before, without waiting for the watch")
        court.playFriendlyRound(on: phone)
        await court.run(for: .seconds(5))
        #expect(!holdsRules(watch, in: court))
    }

    @Test func anOlderWatchFollowsAFriendlyWithoutRules() async {
        let court = CourtHarness(guests: 0, withWatches: true)
        let phone = court.host.phone
        let watch = court.host.watch!
        watch.store.speaksProtocol = 2
        await court.run(for: .seconds(2))
        court.startFriendly()
        for _ in 0 ..< 2 {
            court.playFriendlyRound(on: phone)
            #expect(await court.until(within: .seconds(5)) {
                court.friendly(on: watch)?.rounds.count == court.friendly(on: phone)?.rounds.count
            })
        }
        #expect(!phone.store.pairNeedsUpdateForRules)
    }

    @Test func theWatchCatchesUpOnceUpdated() async {
        let court = CourtHarness(guests: 0, withWatches: true)
        let phone = court.host.phone
        let watch = court.host.watch!
        watch.store.speaksProtocol = 2
        await court.run(for: .seconds(2))
        court.startFriendly(rules: firstTwoApart)
        court.playFriendlyRound(on: phone)
        #expect(await court.until(within: .seconds(5)) { phone.store.pairNeedsUpdateForRules })

        court.endApp(watch)
        court.relaunch(watch)
        #expect(await court.until(within: .seconds(10)) {
            holdsRules(watch, in: court) && court.friendly(on: watch)?.rounds == court.friendly(on: phone)?.rounds
        })
        #expect(!phone.store.pairNeedsUpdateForRules)
    }
}
