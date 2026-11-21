import Foundation
@testable import RekkertCore

/// Tournaments built and drawn the way the store draws them, for the suites from spec 008 on.
enum TournamentFixture {
    static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", number))!
    }

    static func playerID(_ index: Int) -> PlayerID {
        PlayerID(uuid(0x1000 + index))
    }

    static func make(
        _ format: TournamentFormat,
        players: Int,
        courts: Int,
        seed: Int = 1,
        target: Int = 16,
        compensation: SitOutCompensation = .half,
        length: TournamentLength? = nil
    ) -> Tournament {
        Tournament(
            id: TournamentID(uuid(seed)),
            name: "Thursday",
            format: format,
            players: (0 ..< players).map { Player(id: playerID($0), name: "P\($0)") },
            config: TournamentConfig(
                pointRules: PointCountRules(target: target),
                courtCount: courts,
                sitOutCompensation: compensation,
                length: length
            )
        )
    }

    static func defaultScore(round: Int, court: Int, target: Int) -> BySide<Int> {
        BySide(a: target, b: (round * 3 + court) % target)
    }

    /// The next round as `MatchStore.nextRound` records it and the reducer folds it.
    static func draw(_ tournament: Tournament) throws -> Tournament {
        let sitOuts = TournamentEngine.sitOuts(for: tournament)
        let placed = TournamentEngine.placement(of: tournament, sitOuts: sitOuts)
        return try TournamentEngine.appendingRound(to: tournament, sitOuts: sitOuts, placed: placed)
    }

    /// The round in play drawn again around `picked`, as `MatchStore.redrawRound` records it.
    static func redraw(_ tournament: Tournament, picking picked: [PlayerID]) throws -> Tournament {
        let bench = TournamentEngine.sitOuts(for: tournament, picked: picked, redrawing: true) ?? picked
        let placed = TournamentEngine.placement(of: tournament, sitOuts: bench, redrawing: true)
        return try TournamentEngine.redrawingLastRound(of: tournament, sitOuts: bench, placed: placed)
    }

    /// Scores and confirms every court of round `index`.
    static func score(
        _ tournament: Tournament,
        round index: Int,
        with score: ((Int, Int) -> BySide<Int>)? = nil
    ) -> Tournament {
        var scored = tournament
        let target = tournament.config.pointRules.target
        for court in scored.rounds[index].matches.indices {
            let courtIndex = scored.rounds[index].matches[court].courtIndex
            scored.rounds[index].matches[court].state.points =
                score?(index, courtIndex) ?? defaultScore(round: index, court: courtIndex, target: target)
            scored.rounds[index].matches[court].isConfirmed = true
        }
        return scored
    }

    /// Draws and scores `rounds` more rounds.
    static func drawing(
        _ start: Tournament,
        rounds: Int,
        score scoring: ((Int, Int) -> BySide<Int>)? = nil
    ) throws -> Tournament {
        try (0 ..< rounds).reduce(start) { current, _ in
            let drawn = try draw(current)
            return score(drawn, round: drawn.rounds.count - 1, with: scoring)
        }
    }

    /// "P0+P1 v P2+P3 | P4+P5 v P6+P7 (P8 out)": courts in order, names sorted within a side.
    static func rendered(_ round: Round, in tournament: Tournament) -> String {
        func names(_ ids: [PlayerID]) -> [String] {
            ids.compactMap { tournament.player($0)?.name }.sorted()
        }
        let courts = round.matches.sorted { $0.courtIndex < $1.courtIndex }.map { match in
            "\(names(match.teams.a).joined(separator: "+")) v \(names(match.teams.b).joined(separator: "+"))"
        }
        let bench = names(round.sitOuts)
        return courts.joined(separator: " | ") + (bench.isEmpty ? "" : " (\(bench.joined(separator: ", ")) out)")
    }

    /// FNV-1a over the lines joined by newlines: one number that changes if any round does.
    static func fingerprint(_ lines: [String]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in lines.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
