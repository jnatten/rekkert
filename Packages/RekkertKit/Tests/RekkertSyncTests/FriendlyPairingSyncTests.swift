import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private func firstTwoApart(_ players: [RekkertCore.Player]) -> [PairingRule] {
    [PairingRule(kind: .apart, players: [players[0].id, players[1].id])]
}

@Suite("Pairing rules across devices", .serialized)
@MainActor
struct FriendlyPairingSyncTests {
    private func sameRounds(_ court: CourtHarness, _ devices: [CourtHarness.Device]) -> Bool {
        let rounds = devices.map { court.friendly(on: $0)?.rounds }
        return rounds.allSatisfy { $0 != nil && $0 == rounds[0] }
    }

    @Test func phoneAndWatchDrawTheSameWithRules() async throws {
        let court = CourtHarness(guests: 0, withWatches: true)
        let phone = court.host.phone
        let watch = court.host.watch!
        await court.run(for: .seconds(2))
        court.startFriendly(players: ["Ada", "Bob", "Cy", "Dan", "Eve", "Finn"], rules: firstTwoApart)
        #expect(await court.until(within: .seconds(5)) { sameRounds(court, [phone, watch]) })

        for round in 0 ..< 12 {
            court.playFriendlyRound(on: round.isMultiple(of: 2) ? phone : watch)
            #expect(await court.until(within: .seconds(5)) {
                sameRounds(court, [phone, watch]) && court.friendly(on: phone)?.rounds.count == round + 2
            })
        }
        let session = try #require(court.friendly(on: phone))
        let ada = session.players[0].id
        let bob = session.players[1].id
        #expect(session.rounds.allSatisfy { round in
            !TeamSide.allCases.contains { round.teams[$0].contains(ada) && round.teams[$0].contains(bob) }
        })
    }

    @Test func everyDeviceRecordsTheSameBrokenRounds() async throws {
        let court = CourtHarness(guests: 1, withWatches: false)
        let phone = court.host.phone
        let guest = court.guests.first!.phone
        court.startFriendly(players: ["Ada", "Bob", "Cy", "Dan", "Eve"]) { players in
            [PairingRule(kind: .apart, players: [players[0].id, players[1].id, players[2].id])]
        }
        court.share()
        court.join(court.guests.first!)
        #expect(await court.until(within: .seconds(30)) { sameRounds(court, [phone, guest]) })

        for round in 0 ..< 9 {
            #expect(court.friendly(on: guest)?.nextDraw()?.unkept == court.friendly(on: phone)?.nextDraw()?.unkept)
            court.playFriendlyRound(on: phone)
            #expect(await court.until(within: .seconds(10)) {
                sameRounds(court, [phone, guest]) && court.friendly(on: guest)?.rounds.count == round + 2
            })
        }
        let rounds = try #require(court.friendly(on: guest)?.rounds)
        #expect(rounds.count == 10)
        #expect(rounds.count { !$0.unkept.isEmpty } == 4)
    }

    private func sharedFriendly(players: [String] = ["Ada", "Bob", "Cy", "Dan"], access: ShareAccess = .full) async -> CourtHarness {
        let court = CourtHarness(guests: 1, withWatches: true)
        if access != .full { court.host.phone.store.setDefaultAccess(access) }
        court.startFriendly(players: players)
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        return court
    }

    private func apartRule(_ court: CourtHarness, on device: CourtHarness.Device) -> [PairingRule] {
        let players = court.friendly(on: device)!.players
        return [PairingRule(kind: .apart, players: [players[0].id, players[1].id])]
    }

    @Test func aFullAccessGuestChangesTheRules() async throws {
        let court = await sharedFriendly()
        let host = court.host
        let guest = court.guests.first!.phone
        let devices = [host.phone, host.watch!, guest]
        #expect(sameRounds(court, devices))
        let inPlay = try #require(court.friendly(on: host.phone)?.rounds)

        let rules = apartRule(court, on: guest)
        guest.store.setPairingRules(rules)
        #expect(await court.until(within: .seconds(10)) {
            devices.allSatisfy { court.friendly(on: $0)?.pairingRules == rules }
        })
        #expect(court.friendly(on: host.phone)?.rounds == inPlay, "the round in play stays as it was")

        court.playFriendlyRound(on: host.phone)
        #expect(await court.until(within: .seconds(10)) {
            sameRounds(court, devices) && court.friendly(on: guest)?.rounds.count == inPlay.count + 1
        })
        let drawn = try #require(court.friendly(on: guest)?.rounds.last)
        let ids = rules[0].players
        #expect(!TeamSide.allCases.contains { Set(drawn.teams[$0]) == Set(ids) })
    }

    @Test func aRuleChangeIsNeverUndone() async throws {
        let court = await sharedFriendly()
        let host = court.host.phone
        let guest = court.guests.first!.phone
        let rules = apartRule(court, on: host)
        host.store.setPairingRules(rules)
        let round = try #require(court.friendly(on: host)?.currentIndex)
        host.store.tap(round: round, court: 0, team: .a)
        #expect(await court.until(within: .seconds(10)) { court.friendly(on: guest)?.pairingRules == rules })

        host.store.undoLast()
        guest.store.undoLast()
        await court.run(for: .seconds(5))
        for device in [host, guest, court.host.watch!] {
            #expect(court.friendly(on: device)?.pairingRules == rules)
        }
    }

    @Test func onlyScoreIsNotOffered() async {
        let court = await sharedFriendly(access: .score)
        #expect(court.host.phone.store.canEditPairingRules)
        #expect(!court.guests.first!.phone.store.canEditPairingRules)

        let readOnly = await sharedFriendly(access: .readOnly)
        #expect(!readOnly.guests.first!.phone.store.canEditPairingRules)

        let threes = await sharedFriendly(players: ["Ada", "Bob", "Cy"])
        #expect(!threes.host.phone.store.canEditPairingRules, "singles have no partners")
        #expect(!threes.guests.first!.phone.store.canEditPairingRules)
    }

    @Test func aGuestOfAnOlderHostIsNotOffered() async {
        let court = CourtHarness(guests: 1, withWatches: false)
        court.host.phone.store.speaksProtocol = 2
        court.startFriendly()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep(includingWatches: false) })
        #expect(!court.guests.first!.phone.store.canEditPairingRules)
    }
}
