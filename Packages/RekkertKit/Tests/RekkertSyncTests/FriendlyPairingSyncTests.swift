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
}
