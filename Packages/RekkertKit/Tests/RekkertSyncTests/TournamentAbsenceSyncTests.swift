import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 008, SC-004: every device on a tournament agrees on who has left and what that draws.
@Suite("Leaving early across devices", .serialized)
@MainActor
struct TournamentAbsenceSyncTests {
    private func sharedTournament(_ format: TournamentFormat = .americano) async -> CourtHarness {
        let court = CourtHarness(guests: 1, withWatches: true)
        court.startTournament(format)
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        return court
    }

    /// Plays out every court of the round in play without drawing the next.
    private func finishRound(on device: CourtHarness.Device, in court: CourtHarness) {
        guard let tournament = court.tournament(on: device), let round = tournament.currentRound else { return }
        for match in round.matches {
            device.store.setScore(round: round.index, court: match.courtIndex, points: BySide(a: tournament.config.pointRules.target, b: 0))
        }
    }

    private func agree(_ court: CourtHarness) -> Bool {
        guard let host = court.tournament(on: court.host.phone) else { return false }
        return court.devices.allSatisfy { device in
            guard let tournament = court.tournament(on: device) else { return false }
            return tournament.rounds == host.rounds && tournament.absences == host.absences
                && Leaderboard.standings(for: tournament) == Leaderboard.standings(for: host)
        }
    }

    @Test(arguments: [TournamentFormat.americano, .mexicano])
    func betweenRoundsEveryDeviceAgrees(format: TournamentFormat) async throws {
        let court = await sharedTournament(format)
        let guest = court.guests.first!.phone
        let drawers = [court.host.phone, court.host.watch!, guest]
        court.playTournamentRound(on: court.host.phone)
        #expect(await court.until(within: .seconds(5)) { agree(court) })

        finishRound(on: court.host.phone, in: court)
        #expect(await court.until(within: .seconds(5)) { court.tournament(on: guest)?.currentRound.map { court.tournament(on: guest)!.isDone($0) } == true })
        let leaving = try #require(court.tournamentPlayer(4))
        #expect(guest.store.canMarkAway)
        guest.store.setAway(leaving, isAway: true)
        #expect(await court.until(within: .seconds(5)) { agree(court) && court.tournament(on: court.host.phone)?.isAway(leaving) == true })
        court.host.phone.store.nextRound()

        for turn in 0 ..< 4 {
            #expect(await court.until(within: .seconds(5)) { agree(court) })
            court.playTournamentRound(on: drawers[turn % drawers.count])
        }
        #expect(await court.until(within: .seconds(5)) { agree(court) })
        let tournament = try #require(court.tournament(on: court.host.phone))
        #expect(tournament.rounds.count == 7)
        for round in tournament.rounds.dropFirst(2) {
            #expect(!round.matches.flatMap(\.allPlayers).contains(leaving))
            #expect(!round.sitOuts.contains(leaving))
            #expect(round.matches.count == 2 && round.sitOuts.isEmpty, "eight fill two courts")
        }
    }

    @Test func midRoundEveryDeviceAgrees() async throws {
        let court = await sharedTournament()
        let guest = court.guests.first!.phone
        let host = court.host.phone
        let tournament = try #require(court.tournament(on: host))
        let round = try #require(tournament.currentRound)
        host.store.setScore(round: round.index, court: 0, points: BySide(a: 6, b: 5))
        #expect(await court.until(within: .seconds(5)) { agree(court) })

        let leaving = round.matches[0].teams.a[0]
        guest.store.setAway(leaving, isAway: true)
        #expect(await court.until(within: .seconds(5)) { agree(court) && court.tournament(on: host)?.rounds[round.index].matches[0].isConfirmed == true })
        court.host.watch!.store.setScore(round: round.index, court: 1, points: BySide(a: 16, b: 0))
        #expect(await court.until(within: .seconds(5)) { agree(court) && court.tournament(on: host)?.canDrawNextRound == true })

        for device in court.devices {
            let seen = try #require(court.tournament(on: device)?.rounds[round.index])
            #expect(seen.matches.map(\.teams) == round.matches.map(\.teams))
            #expect(seen.matches[0].state.points == BySide(a: 6, b: 5))
            #expect(seen.matches[0].isConfirmed)
        }
    }

    /// SC-006 and D-5: the guest marks somebody gone while out of reach; meanwhile the host draws
    /// a round with them in it and scores on it. The departure sorts first, and the round stands.
    @Test func aDepartureThatRacedADrawRepartnersNothing() async throws {
        let court = await sharedTournament()
        let guest = court.guests.first!.phone
        let host = court.host.phone
        finishRound(on: host, in: court)
        #expect(await court.until(within: .seconds(5)) { agree(court) && court.tournament(on: guest)?.canDrawNextRound == true })

        court.outOfRange(guest)
        host.store.setRoundConfirmed(0)
        host.store.nextRound()
        let drawn = try #require(court.tournament(on: host)?.rounds.last)
        #expect(drawn.index == 1)
        host.store.tap(round: 1, court: 0, team: .a)
        let leaving = drawn.matches[0].teams.a[0]
        guest.store.setAway(leaving, isAway: true)

        court.backInRange(guest)
        #expect(await court.until(within: .seconds(20)) { agree(court) && court.tournament(on: guest)?.rounds.count == 2 })
        for device in court.devices {
            let tournament = try #require(court.tournament(on: device))
            #expect(tournament.rounds[1].matches.map(\.teams) == drawn.matches.map(\.teams), "the round people walked onto")
            #expect(tournament.rounds[1].matches[0].state.points == BySide(a: 1, b: 0))
            #expect(tournament.awayPlayersOnCourt(inRound: 1) == [leaving])
        }

        host.store.setAway(leaving, isAway: true)
        #expect(await court.until(within: .seconds(5)) { agree(court) && court.tournament(on: guest)?.rounds[1].matches[0].isConfirmed == true })
        #expect(court.tournament(on: host)?.rounds[1].matches.map(\.teams) == drawn.matches.map(\.teams))
    }
}
