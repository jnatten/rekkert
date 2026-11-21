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
}
