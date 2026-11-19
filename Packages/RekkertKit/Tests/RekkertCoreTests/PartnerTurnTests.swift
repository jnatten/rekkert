import Foundation
import Testing
@testable import RekkertCore

private func uuid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", number))!
}

private func tournament(players: Int, courts: Int, seed: Int) -> Tournament {
    Tournament(
        id: TournamentID(uuid(seed)),
        name: "Thursday",
        format: .americano,
        players: (0 ..< players).map { Player(id: PlayerID(uuid(0x1000 + $0)), name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
    )
}

/// As the store draws it: the bench the event carries, folded as every build folds it.
private func draw(_ tournament: Tournament) throws -> Tournament {
    try TournamentEngine.appendingRound(to: tournament, sitOuts: TournamentEngine.sitOuts(for: tournament))
}

private func drawing(_ start: Tournament, rounds: Int) throws -> Tournament {
    try (0 ..< rounds).reduce(start) { current, _ in try draw(current) }
}

private func partners(_ round: Round) -> [PairKey] {
    round.matches.flatMap { match in TeamSide.allCases.map { PairKey(match.teams[$0][0], match.teams[$0][1]) } }
}

private func turn(players: Int, courts: Int) -> Int {
    players * (players - 1) / 2 / (courts * 2)
}

/// Pairs that partnered more often than `limit` in the rounds given.
private func overLimit(_ rounds: some Collection<Round>, limit: Int) -> Int {
    var counts: [PairKey: Int] = [:]
    for round in rounds { for pair in partners(round) { counts[pair, default: 0] += 1 } }
    return counts.values.count { $0 > limit }
}

private func backToBack(_ rounds: [Round]) -> Int {
    zip(rounds.dropFirst(), rounds).reduce(0) { total, pair in
        total + Set(partners(pair.0)).intersection(partners(pair.1)).count
    }
}

private func evenAndNeverTwiceRunning(_ tournament: Tournament) -> Bool {
    for count in 1 ... tournament.rounds.count {
        let tallies = tournament.players.map { player in
            tournament.rounds.prefix(count).count { $0.sitOuts.contains(player.id) }
        }
        if tallies.max()! - tallies.min()! > 1 { return false }
    }
    return zip(tournament.rounds.dropFirst(), tournament.rounds).allSatisfy { Set($0.sitOuts).isDisjoint(with: $1.sitOuts) }
}

@Suite("Nobody partners twice in a turn")
struct PartnerTurnTests {
    /// The Americano of 18 November, nine on two courts: rounds 1–5 as they were played. Round 6
    /// paired Mattis and Endre again, though six ways of pairing the eight on court repeated
    /// nobody.
    @Test(arguments: 1 ... 12)
    func roundSixOfEighteenNovemberRepeatsNobody(seed: Int) throws {
        let names = ["celine", "johannes", "jonas", "amandus", "magnus", "torgrim", "endre", "marlen", "mattis"]
        let players = names.enumerated().map { Player(id: PlayerID(uuid(0x2000 + $0.offset)), name: $0.element) }
        func id(_ name: String) -> PlayerID { players.first { $0.name == name }!.id }
        let played: [([[String]], String)] = [
            ([["celine", "johannes", "jonas", "amandus"], ["magnus", "torgrim", "endre", "marlen"]], "mattis"),
            ([["magnus", "marlen", "mattis", "jonas"], ["endre", "torgrim", "amandus", "johannes"]], "celine"),
            ([["torgrim", "johannes", "magnus", "celine"], ["mattis", "marlen", "jonas", "endre"]], "amandus"),
            ([["mattis", "celine", "johannes", "magnus"], ["amandus", "endre", "jonas", "marlen"]], "torgrim"),
            ([["magnus", "amandus", "mattis", "endre"], ["johannes", "marlen", "torgrim", "celine"]], "jonas"),
        ]
        var session = Tournament(
            id: TournamentID(uuid(0x7000 + seed)), name: "Onsdag", format: .americano, players: players,
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2),
            rounds: played.enumerated().map { index, round in
                Round(
                    index: index,
                    matches: round.0.enumerated().map { court, four in
                        CourtMatch(courtIndex: court, teams: BySide(a: [id(four[0]), id(four[1])], b: [id(four[2]), id(four[3])]))
                    },
                    sitOuts: [id(round.1)]
                )
            }
        )
        session = try draw(session)
        #expect(overLimit(session.rounds, limit: 1) == 0, "\(partners(session.rounds[5]).map { [$0.low, $0.high].compactMap { session.player($0)?.name } })")
        let finished = try drawing(session, rounds: 3)
        #expect(overLimit(finished.rounds, limit: 1) == 0, "the turn finishes with nobody twice")
        #expect(evenAndNeverTwiceRunning(finished))
    }

    @Test(arguments: [(5, 1), (6, 1), (9, 2), (10, 2), (11, 2), (13, 3), (14, 3)])
    func aFullTurnRepeatsNobody(players: Int, courts: Int) throws {
        for seed in 1 ... 6 {
            let played = try drawing(tournament(players: players, courts: courts, seed: seed), rounds: turn(players: players, courts: courts))
            #expect(overLimit(played.rounds, limit: 1) == 0, "seed \(seed)")
            #expect(evenAndNeverTwiceRunning(played), "seed \(seed)")
        }
    }

    /// A full rotation, everyone partnering everyone, ends in as few rounds as the partnerships
    /// allow: the turn uses every round's partnerships on new pairs, and the round after it
    /// takes what is left.
    @Test(arguments: [(5, 1), (6, 1), (9, 2), (10, 2), (11, 2), (13, 3), (14, 3)])
    func aFullRotationEndsAsSoonAsThePartnershipsAllow(players: Int, courts: Int) throws {
        let pairs = players * (players - 1) / 2
        let fewest = (pairs + courts * 2 - 1) / (courts * 2)
        for seed in 1 ... 6 {
            var played = tournament(players: players, courts: courts, seed: seed)
            var partnered: Set<PairKey> = []
            while partnered.count < pairs, played.rounds.count < fewest + 3 {
                played = try draw(played)
                partnered.formUnion(partners(played.rounds.last!))
            }
            #expect(played.rounds.count == fewest, "seed \(seed): \(played.rounds.count) rounds against \(fewest)")
        }
    }

    @Test func drawingRoundByRoundFollowsThePlanMadeAtTheStart() throws {
        let start = tournament(players: 10, courts: 2, seed: 3)
        let plan = RoundScheduler.plannedTurn(
            players: start.players, courts: 2, seed: start.id.raw, round: 0, history: PairingHistory(start)
        )
        let played = try drawing(start, rounds: plan.count)
        #expect(plan.count == 11)
        #expect(played.rounds.map { Set($0.sitOuts) } == plan.map { Set($0) })
    }

    /// Past the first turn repeats can't be helped, but nobody partners a third time before
    /// everyone has twice. Back-to-back partners are avoided wherever any bench avoids them: six
    /// on one court have two pairs a round to choose from, and once in a second turn there is no
    /// bench left without.
    @Test(arguments: [(9, 2, 0), (10, 2, 0), (6, 1, 1)])
    func pastTheTurnNobodyPartnersAThirdTimeEarly(players: Int, courts: Int, backToBackAllowed: Int) throws {
        for seed in 1 ... 4 {
            let played = try drawing(tournament(players: players, courts: courts, seed: seed), rounds: 2 * turn(players: players, courts: courts))
            #expect(overLimit(played.rounds, limit: 2) == 0, "seed \(seed)")
            #expect(backToBack(played.rounds) <= backToBackAllowed, "seed \(seed)")
            #expect(evenAndNeverTwiceRunning(played), "seed \(seed)")
        }
    }

    @Test func aHandPickedSitOutIsKeptAndTheTurnCarriesOn() throws {
        for seed in 1 ... 6 {
            var played = try drawing(tournament(players: 9, courts: 2, seed: seed), rounds: 4)
            let late = played.players.map(\.id).first { !played.rounds[3].sitOuts.contains($0) }!
            let bench = TournamentEngine.sitOuts(for: played, picked: [late], redrawing: true) ?? [late]
            played = try TournamentEngine.redrawingLastRound(of: played, sitOuts: bench)
            #expect(played.rounds[3].sitOuts == [late])
            played = try drawing(played, rounds: 5)
            #expect(backToBack(played.rounds) == 0, "seed \(seed)")
            #expect(overLimit(played.rounds, limit: 1) <= 1, "seed \(seed)")
        }
    }

    @Test func aRoundAnOlderBuildDrewIsFollowedAndPlanningCarriesOn() throws {
        for seed in 1 ... 6 {
            var played = try drawing(tournament(players: 9, courts: 2, seed: seed), rounds: 4)
            played = try TournamentEngine.appendingRound(to: played)
            played = try drawing(played, rounds: 4)
            #expect(backToBack(played.rounds) == 0, "seed \(seed)")
            #expect(overLimit(played.rounds, limit: 1) <= 1, "seed \(seed)")
        }
    }

    @Test func withNobodySittingOutTheDrawIsAsItWas() throws {
        var played = tournament(players: 8, courts: 2, seed: 4)
        for _ in 0 ..< 7 {
            #expect(TournamentEngine.sitOuts(for: played) == nil)
            #expect(TournamentEngine.bench(for: played) == [])
            played = try TournamentEngine.appendingRound(to: played)
        }
    }
}
