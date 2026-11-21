import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 008, FR-014: no device that would draw a tournament without its absences ever holds one.
@Suite("Older builds and a tournament someone left", .serialized)
@MainActor
struct AbsenceAdmissionTests {
    private func holdsAbsences(_ device: CourtHarness.Device, in court: CourtHarness) -> Bool {
        court.tournament(on: device)?.hasAbsences ?? false
    }

    @Test func aGuestOnProtocol3IsTurnedAwayWhenTheFirstAbsenceArrives() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.speaksProtocol = 3
        court.startTournament()
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep(includingWatches: false) })
        #expect(court.host.phone.store.olderPeersTurnedAway(ifNeeding: 4) == 1)

        court.finish(on: court.host.phone)
        court.answer(.keepSharing, on: court.host.phone)
        court.startTournament(away: [(player: 4, from: 0)])
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.needsUpdate) })
        #expect(court.host.phone.recorder.read().entries.contains { $0.kind == .refused(.needsUpdate) })
        #expect(!holdsAbsences(guest.phone, in: court))
        #expect(court.host.phone.store.olderPeersTurnedAway(ifNeeding: 4) == 0)
    }

    @Test func aGuestOnProtocol3IsTurnedAwayAtHello() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.speaksProtocol = 3
        court.startTournament(away: [(player: 4, from: 0)])
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.needsUpdate) })
        #expect(!holdsAbsences(guest.phone, in: court))
    }

    @Test func aOneOneGuestIsTurnedAwayAsFull() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.actsAsOlderBuild = true
        court.startTournament(away: [(player: 4, from: 0)])
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.noRoom) })
        #expect(!holdsAbsences(guest.phone, in: court))
    }

    @Test func aCurrentGuestFollows() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        court.startTournament(away: [(player: 4, from: 0)])
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep(includingWatches: false) })
        #expect(holdsAbsences(guest.phone, in: court))
    }

    @Test func aWatchOnProtocol3IsHeldBack() async {
        let court = CourtHarness(guests: 0, withWatches: true)
        let phone = court.host.phone
        let watch = court.host.watch!
        watch.store.speaksProtocol = 3
        await court.run(for: .seconds(2))
        court.startTournament(away: [(player: 4, from: 0)])
        #expect(await court.until(within: .seconds(5)) { phone.store.pairNeedsUpdate })
        court.playTournamentRound(on: phone)
        await court.run(for: .seconds(3))
        #expect(!holdsAbsences(watch, in: court))
    }

    @Test func aFriendlyWithRulesStillAdmitsProtocol3() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.speaksProtocol = 3
        court.startFriendly { [PairingRule(kind: .apart, players: [$0[0].id, $0[1].id])] }
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep(includingWatches: false) })
        #expect(court.friendly(on: guest.phone)?.pairingRules.isEmpty == false)
    }

    @Test func aGuestOffersTheActionOnlyToAHostAt4() async {
        let older = CourtHarness(guests: 1, withWatches: false)
        older.host.phone.store.speaksProtocol = 3
        older.startTournament()
        older.share()
        older.joinAll()
        #expect(await older.until(within: .seconds(60)) { older.allInStep(includingWatches: false) })
        #expect(!older.guests.first!.phone.store.canMarkAway)

        let current = CourtHarness(guests: 1, withWatches: false)
        current.startTournament()
        current.share()
        current.joinAll()
        #expect(await current.until(within: .seconds(60)) { current.allInStep(includingWatches: false) })
        #expect(current.host.phone.store.canMarkAway)
        #expect(current.guests.first!.phone.store.canMarkAway)
    }

    @Test func theNeedOutlivesTheReturn() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        let guest = court.guests.first!
        guest.phone.store.speaksProtocol = 3
        let players = (0 ..< 9).map { RekkertCore.Player(name: "P\($0)") }
        court.host.phone.store.configure(.tournament(Tournament(
            name: "Thursday", format: .americano, players: players,
            config: TournamentConfig(courtCount: 2),
            absences: [TournamentAbsence(player: players[4].id, from: 0, until: 1)]
        )))
        court.host.phone.store.nextRound()
        court.share()
        court.join(guest)
        #expect(await court.until(within: .seconds(15)) { guest.phone.sharing.phase == .failed(.needsUpdate) })
    }
}
