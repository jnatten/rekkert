import Foundation
import Testing
@testable import RekkertCore

private func makeTournament(
    _ format: TournamentFormat,
    players: Int,
    courts: Int = 1,
    compensation: SitOutCompensation = .half,
    target: Int = 16
) -> Tournament {
    Tournament(
        id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!),
        name: "Test",
        format: format,
        players: (0 ..< players).map { Player(name: "P\($0)") },
        config: TournamentConfig(
            pointRules: PointCountRules(target: target),
            courtCount: courts,
            sitOutCompensation: compensation
        )
    )
}

private func playRounds(_ tournament: Tournament, count: Int, score: (Int) -> BySide<Int> = { _ in BySide(a: 9, b: 7) }) throws -> Tournament {
    var current = tournament
    for round in 0 ..< count {
        current = try TournamentEngine.appendingRound(to: current)
        for index in current.rounds[round].matches.indices {
            current.rounds[round].matches[index].state.points = score(round)
            current.rounds[round].matches[index].isConfirmed = true
        }
    }
    return current
}

/// Every round's teams as names, which is what a draw actually is once the identifiers are
/// stripped off it.
private func drawn(_ tournament: Tournament) -> [[[[String]]]] {
    tournament.rounds.map { round in
        round.matches.map { match in
            TeamSide.allCases.map { side in
                match.teams[side].compactMap { tournament.player($0)?.name }
            }
        }
    }
}

private func benched(_ tournament: Tournament) -> [[String]] {
    tournament.rounds.map { $0.sitOuts.compactMap { tournament.player($0)?.name } }
}

@Suite("Tournament scheduling")
struct TournamentTests {
    @Test func fourPlayersOneCourtNobodySitsOut() throws {
        let t = try TournamentEngine.appendingRound(to: makeTournament(.americano, players: 4))
        #expect(t.rounds.count == 1)
        #expect(t.rounds[0].sitOuts.isEmpty)
        #expect(t.rounds[0].matches.count == 1)
        #expect(Set(t.rounds[0].matches[0].allPlayers).count == 4)
    }

    @Test func eightPlayersFillTwoCourts() throws {
        let t = try TournamentEngine.appendingRound(to: makeTournament(.americano, players: 8, courts: 2))
        #expect(t.rounds[0].matches.count == 2)
        #expect(t.rounds[0].sitOuts.isEmpty)
        let all = t.rounds[0].matches.flatMap(\.allPlayers)
        #expect(Set(all).count == 8, "no player is on two courts")
    }

    @Test func tooFewPlayersThrows() {
        #expect(throws: TournamentError.notEnoughPlayers(needed: 4, have: 3)) {
            try TournamentEngine.appendingRound(to: makeTournament(.americano, players: 3))
        }
    }

    @Test func spareCourtsAreLeftEmptyRatherThanHalfFilled() throws {
        let t = try TournamentEngine.appendingRound(to: makeTournament(.americano, players: 6, courts: 2))
        #expect(t.rounds[0].matches.count == 1, "6 players only fills one court")
        #expect(t.rounds[0].sitOuts.count == 2)
    }

    @Test func sitOutsRotateEvenly() throws {
        let t = try playRounds(makeTournament(.americano, players: 6), count: 6)
        let counts = t.players.map { player in
            t.rounds.count { $0.sitOuts.contains(player.id) }
        }
        #expect(counts.allSatisfy { $0 == 2 }, "6 players, 6 rounds, 2 bench slots each round: got \(counts)")
    }

    @Test func americanoAvoidsRepeatingPartners() throws {
        let t = try playRounds(makeTournament(.americano, players: 8, courts: 2), count: 7)
        var partnered: [PairKey: Int] = [:]
        for round in t.rounds {
            for match in round.matches {
                for side in TeamSide.allCases {
                    partnered[PairKey(match.teams[side][0], match.teams[side][1]), default: 0] += 1
                }
            }
        }
        #expect(partnered.count == 28, "8 players have 28 possible partnerships")
        #expect(partnered.values.allSatisfy { $0 == 1 }, "each pairing happens exactly once")
    }

    @Test func americanoSpreadsPartnersWithOddPlayerCounts() throws {
        let t = try playRounds(makeTournament(.americano, players: 7), count: 7)
        var partnered: [PairKey: Int] = [:]
        for round in t.rounds {
            for match in round.matches {
                for side in TeamSide.allCases {
                    partnered[PairKey(match.teams[side][0], match.teams[side][1]), default: 0] += 1
                }
            }
        }
        #expect(partnered.values.max() ?? 0 <= 2, "no pairing repeats more than twice")
    }

    @Test func schedulingIsDeterministic() throws {
        let base = makeTournament(.americano, players: 11, courts: 2)
        let one = try playRounds(base, count: 5)
        let two = try playRounds(base, count: 5)
        #expect(one.rounds == two.rounds, "same tournament id must yield the same schedule on both devices")
    }

    @Test func mexicanoPairsTopFourAsOneAndFour() throws {
        var t = try playRounds(makeTournament(.mexicano, players: 8, courts: 2), count: 1)
        let ranking = Leaderboard.standings(for: t, onlyConfirmed: true).map(\.player.id)

        t = try TournamentEngine.appendingRound(to: t)
        let court = t.rounds[1].matches[0]
        #expect(Set(court.allPlayers) == Set(ranking.prefix(4)), "court 1 gets the top four")
        #expect(Set(court.teams.a) == Set([ranking[0], ranking[3]]))
        #expect(Set(court.teams.b) == Set([ranking[1], ranking[2]]))
    }

    @Test func mexicanoHonoursTheAlternativePairing() throws {
        var base = makeTournament(.mexicano, players: 4)
        base.config.mexicanoPairing = .topWithThird
        var t = try playRounds(base, count: 1)
        let ranking = Leaderboard.standings(for: t, onlyConfirmed: true).map(\.player.id)

        t = try TournamentEngine.appendingRound(to: t)
        #expect(Set(t.rounds[1].matches[0].teams.a) == Set([ranking[0], ranking[2]]))
    }
}

@Suite("Leaderboard")
struct LeaderboardTests {
    @Test func pointsAccumulateForBothTeams() throws {
        let t = try playRounds(makeTournament(.americano, players: 4), count: 1)
        let standings = Leaderboard.standings(for: t)
        #expect(standings.map(\.total) == [9, 9, 7, 7])
        #expect(standings.allSatisfy { $0.roundsPlayed == 1 })
    }

    @Test func sitOutsAreCompensatedWithHalfTheTarget() throws {
        let t = try playRounds(makeTournament(.americano, players: 5, compensation: .half, target: 16), count: 1)
        let benched = t.rounds[0].sitOuts[0]
        let standing = Leaderboard.standings(for: t).first { $0.id == benched }
        #expect(standing?.compensation == 8)
        #expect(standing?.total == 8)
        #expect(standing?.roundsPlayed == 0)
    }

    @Test(arguments: [
        (SitOutCompensation.none, 0),
        (SitOutCompensation.half, 8),
        (SitOutCompensation.full, 16),
        (SitOutCompensation.fixed(5), 5),
    ])
    func compensationModes(mode: SitOutCompensation, expected: Int) throws {
        let t = try playRounds(makeTournament(.americano, players: 5, compensation: mode, target: 16), count: 1)
        let benched = t.rounds[0].sitOuts[0]
        #expect(Leaderboard.standings(for: t).first { $0.id == benched }?.total == expected)
    }

    @Test func differentialBreaksTiesOnPoints() throws {
        var t = try playRounds(makeTournament(.americano, players: 4), count: 0)
        t = try TournamentEngine.appendingRound(to: t)
        t.rounds[0].matches[0].state.points = BySide(a: 12, b: 4)
        t.rounds[0].matches[0].isConfirmed = true

        let standings = Leaderboard.standings(for: t)
        #expect(standings.prefix(2).allSatisfy { $0.total == 12 && $0.differential == 8 })
        #expect(standings.suffix(2).allSatisfy { $0.total == 4 && $0.differential == -8 })
    }

    @Test func unconfirmedRoundsAreExcludedWhenAsked() throws {
        var t = try playRounds(makeTournament(.americano, players: 4), count: 0)
        t = try TournamentEngine.appendingRound(to: t)
        t.rounds[0].matches[0].state.points = BySide(a: 10, b: 6)

        #expect(Leaderboard.standings(for: t, onlyConfirmed: false).first?.total == 10)
        #expect(Leaderboard.standings(for: t, onlyConfirmed: true).allSatisfy { $0.total == 0 })
    }

    // MARK: - Cancelled rounds

    @Test func aCancelledRoundCountsForNobody() throws {
        let played = try playRounds(makeTournament(.americano, players: 5), count: 2)
        let before = Leaderboard.standings(for: played)

        var t = try TournamentEngine.appendingRound(to: played)
        t.rounds[2].matches[0].state.points = BySide(a: 5, b: 3)
        #expect(!t.rounds[2].sitOuts.isEmpty)
        #expect(Leaderboard.standings(for: t) != before)

        t.rounds[2].isCancelled = true
        #expect(Leaderboard.standings(for: t) == before, "neither the court points nor the bench count")
    }

    @Test func aCancelledRoundLeavesItsBenchStillOwed() throws {
        var t = try playRounds(makeTournament(.americano, players: 5), count: 1)
        t = try TournamentEngine.appendingRound(to: t)
        let benched = t.rounds[1].sitOuts[0]
        #expect(PairingHistory(t).sitOutCount(benched) == 1)

        t.rounds[1].isCancelled = true
        #expect(PairingHistory(t).sitOutCount(benched) == 0)
    }

    @Test func mexicanoRanksPastACancelledRound() throws {
        let played = try playRounds(makeTournament(.mexicano, players: 4), count: 1)
        var t = try TournamentEngine.appendingRound(to: played)
        t.rounds[1].matches[0].state.points = BySide(a: 16, b: 0)
        t.rounds[1].matches[0].isConfirmed = true
        t.rounds[1].isCancelled = true

        t = try TournamentEngine.appendingRound(to: t)
        #expect(t.rounds[2].matches[0].teams == t.rounds[1].matches[0].teams,
                "the standings are where round 1 left them, so the draw is the same")
    }

    @Test func aRoundSavedBeforeCancellingExistedStillDecodes() throws {
        let round = try playRounds(makeTournament(.americano, players: 5), count: 1).rounds[0]
        let data = try JSONCoding.encoder.encode(round)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.removeValue(forKey: "isCancelled") != nil, "the key is there to remove")

        let trimmed = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONCoding.decoder.decode(Round.self, from: trimmed)
        #expect(back == round)
    }

    // MARK: - Time between sit-outs

    @Test func theBenchComesRoundInTheOrderItFirstWent() throws {
        let played = try playRounds(makeTournament(.americano, players: 5), count: 15)
        let bench = benched(played)
        #expect(Set(bench.prefix(5)).count == 5, "everyone sits out once before anyone twice")
        for (index, sitting) in bench.enumerated() {
            #expect(sitting == bench[index % 5], "round \(index + 1) should repeat round \(index % 5 + 1)")
        }
    }

    @Test func nobodySitsOutAgainSoonerThanTheNumbersForce() throws {
        let played = try playRounds(makeTournament(.americano, players: 7), count: 14)
        for player in played.players {
            let rounds = played.rounds.indices.filter { played.rounds[$0].sitOuts.contains(player.id) }
            let gaps = zip(rounds.dropFirst(), rounds).map { $0 - $1 }
            #expect(gaps.allSatisfy { $0 >= 2 }, "\(player.name) sat out in rounds \(rounds)")
        }
        for count in 1 ... played.rounds.count {
            let tallies = played.players.map { player in
                played.rounds.prefix(count).count { $0.sitOuts.contains(player.id) }
            }
            #expect(tallies.max()! - tallies.min()! <= 1, "after \(count) rounds: \(tallies)")
        }
    }

    /// Drawn the way it always was: the tie-break would otherwise re-bench rounds already
    /// played in a tournament that was under way when the app was updated.
    @Test func aTournamentBegunBeforeTheTieBreakKeepsItsDraws() throws {
        let data = try JSONCoding.encoder.encode(makeTournament(.americano, players: 5))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.removeValue(forKey: "benchOrder") != nil, "the key is there to remove")

        let trimmed = try JSONSerialization.data(withJSONObject: object)
        let legacy = try JSONCoding.decoder.decode(Tournament.self, from: trimmed)
        #expect(legacy.benchOrder == .fewestSitOuts)

        let played = try playRounds(legacy, count: 12)
        #expect(benched(played) == [
            ["P3"], ["P0"], ["P1"], ["P2"], ["P4"], ["P4"],
            ["P0"], ["P1"], ["P3"], ["P2"], ["P0"], ["P1"],
        ])
    }

    @Test func aTournamentKeepsItsBenchOrderThroughAnEncode() throws {
        let tournament = makeTournament(.americano, players: 5)
        let back = try JSONCoding.decoder.decode(Tournament.self, from: JSONCoding.encoder.encode(tournament))
        #expect(back == tournament)
        #expect(back.benchOrder == .longestRested)
    }

    // MARK: - Golden draws

    /// A fingerprint of the rounds the schedulers draw today. The pairing machinery is shared
    /// with other modes, so a refactor of it has to reproduce these exactly rather than merely
    /// stay plausible — a draw that is still fair but different would silently re-partner
    /// everybody's Thursday.
    @Test func americanoDrawsTheRoundsItAlwaysHas() throws {
        let played = try playRounds(makeTournament(.americano, players: 8, courts: 2), count: 3)
        #expect(drawn(played) == [
            [[["P5", "P1"], ["P3", "P2"]], [["P4", "P0"], ["P6", "P7"]]],
            [[["P1", "P0"], ["P5", "P4"]], [["P7", "P2"], ["P3", "P6"]]],
            [[["P6", "P4"], ["P3", "P5"]], [["P1", "P2"], ["P0", "P7"]]],
        ])
    }

    @Test func mexicanoDrawsTheRoundsItAlwaysHas() throws {
        let played = try playRounds(
            makeTournament(.mexicano, players: 9, courts: 2),
            count: 3,
            score: { BySide(a: 10 - $0, b: 6 + $0) }
        )
        #expect(drawn(played) == [
            [[["P1", "P4"], ["P3", "P2"]], [["P5", "P8"], ["P7", "P0"]]],
            [[["P4", "P6"], ["P5", "P8"]], [["P0", "P7"], ["P2", "P3"]]],
            [[["P4", "P6"], ["P1", "P5"]], [["P8", "P2"], ["P0", "P7"]]],
        ])
        #expect(benched(played) == [["P6"], ["P1"], ["P3"]])
    }
}
