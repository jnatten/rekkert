import Foundation

/// Who a ladder draw put where: each court's two sides, court 1 first, and the bench.
public struct LadderPlacement: Codable, Sendable, Hashable {
    public var courts: [BySide<[PlayerID]>]
    public var sitOuts: [PlayerID]

    public init(courts: [BySide<[PlayerID]>], sitOuts: [PlayerID]) {
        self.courts = courts
        self.sitOuts = sitOuts
    }

    public init(_ round: Round) {
        courts = round.matches.sorted { $0.courtIndex < $1.courtIndex }.map(\.teams)
        sitOuts = round.sitOuts
    }
}

/// Winner court: winners move up a court and losers down, the top court's winners and the
/// bottom court's losers staying where they are. Whoever comes back from the bench starts at
/// the bottom.
public enum LadderScheduler {
    public static func nextRound(for tournament: Tournament, sitOuts: [PlayerID]? = nil) throws -> Round {
        let ladder = tournament.ladder ?? LadderRules()
        let fixed = ladder.partners == .fixed
        if fixed, !tournament.players.count.isMultiple(of: 2) { throw TournamentError.unpairedPlayer }
        let courts = tournament.playableCourts
        guard courts >= 1 else {
            throw TournamentError.notEnoughPlayers(needed: 4, have: tournament.players.count)
        }

        let units = units(of: tournament, fixed: fixed)
        let perCourt = fixed ? 2 : 4
        let chosen = try chosenUnits(sitOuts, units: units, benchSize: units.count - courts * perCourt)

        let index = tournament.rounds.count
        let history = PairingHistory(tournament)
        var generator = SeededGenerator(tournament.id.raw, salt: UInt64(index))
        let leads = units.compactMap { tournament.player($0[0]) }
        let (_, sitting) = RoundScheduler.split(
            players: leads, seats: courts * perCourt, history: history,
            order: tournament.benchOrder, chosen: chosen.map { $0[0] }, generator: &generator
        )
        let benched = Set(sitting)

        let previous = tournament.rounds.last { !$0.isCancelled }
        let placed = order(units, after: previous, in: tournament, start: ladder.start)
            .filter { !benched.contains($0[0]) }

        let matches = (0 ..< courts).map { court in
            let arriving = Array(placed[(court * perCourt) ..< ((court + 1) * perCourt)])
            let teams = fixed
                ? BySide(a: arriving[0], b: arriving[1])
                : split(arriving.map { $0[0] }, previous: previous, history: history)
            return CourtMatch(courtIndex: court, teams: teams, games: TraditionalState())
        }
        let sitOutPlayers = units.filter { benched.contains($0[0]) }.flatMap(\.self)
        return Round(index: index, matches: matches, sitOuts: sitOutPlayers)
    }

    /// The round a draw carried, as long as it places this tournament's players, each of them
    /// once, two a side on as many courts as can be played.
    static func round(placed placement: LadderPlacement, for tournament: Tournament) -> Round? {
        let everyone = Set(tournament.players.map(\.id))
        let placed = placement.courts.flatMap { $0.a + $0.b } + placement.sitOuts
        guard placement.courts.count == tournament.playableCourts,
              placement.courts.allSatisfy({ $0.a.count == 2 && $0.b.count == 2 }),
              placed.count == everyone.count, Set(placed) == everyone else { return nil }
        let matches = placement.courts.enumerated().map { court, teams in
            CourtMatch(courtIndex: court, teams: teams, games: TraditionalState())
        }
        return Round(index: tournament.rounds.count, matches: matches, sitOuts: placement.sitOuts)
    }

    /// Pairs taken from the list two at a time, or everybody on their own.
    static func units(of tournament: Tournament, fixed: Bool) -> [[PlayerID]] {
        let ids = tournament.players.map(\.id)
        guard fixed else { return ids.map { [$0] } }
        return stride(from: 0, to: ids.count - 1, by: 2).map { [ids[$0], ids[$0 + 1]] }
    }

    /// Picking one of a fixed pair to sit out sits the pair out.
    private static func chosenUnits(_ sitOuts: [PlayerID]?, units: [[PlayerID]], benchSize: Int) throws -> [[PlayerID]] {
        guard let sitOuts else { return [] }
        guard Set(sitOuts).count == sitOuts.count else { throw TournamentError.invalidSitOuts }
        let picked = Set(sitOuts)
        let chosen = units.filter { $0.contains(where: picked.contains) }
        guard sitOuts.allSatisfy({ id in units.contains { $0.contains(id) } }),
              chosen.count <= benchSize else { throw TournamentError.invalidSitOuts }
        return chosen
    }

    /// Everyone from the top of the ladder down, as the round after `previous` should place them.
    private static func order(_ units: [[PlayerID]], after previous: Round?, in tournament: Tournament, start: LadderStart) -> [[PlayerID]] {
        guard let previous else {
            guard start == .random else { return units }
            var generator = SeededGenerator(tournament.id.raw, salt: .max)
            return units.shuffled(using: &generator)
        }

        let courts = previous.matches.sorted { $0.courtIndex < $1.courtIndex }
        let results = courts.map { match -> (won: [PlayerID], lost: [PlayerID]) in
            let status = tournament.status(of: match, in: previous)
            let winner = status.winner ?? status.line.leader ?? .a
            return (match.teams[winner], match.teams[winner.other])
        }
        var players: [PlayerID] = []
        for (court, result) in results.enumerated() {
            players += result.won
            if court > 0 { players += results[court - 1].lost }
        }
        players += results.last?.lost ?? []
        players += tournament.players.map(\.id).filter { previous.sitOuts.contains($0) }

        var seen: Set<[PlayerID]> = []
        var ordered: [[PlayerID]] = []
        for player in players + units.flatMap(\.self) {
            guard let unit = units.first(where: { $0.contains(player) }), seen.insert(unit).inserted else { continue }
            ordered.append(unit)
        }
        return ordered
    }

    /// Of the three ways to pair four, the one that splits last round's partners and, after
    /// that, repeats the fewest partners and opponents. The highest placed is on side A.
    private static func split(_ four: [PlayerID], previous: Round?, history: PairingHistory) -> BySide<[PlayerID]> {
        let partners = Set((previous?.matches ?? []).flatMap { [$0.teams.a, $0.teams.b] }.map(Set.init))
        let options = [
            BySide(a: [four[0], four[1]], b: [four[2], four[3]]),
            BySide(a: [four[0], four[2]], b: [four[1], four[3]]),
            BySide(a: [four[0], four[3]], b: [four[1], four[2]]),
        ]
        func cost(_ teams: BySide<[PlayerID]>) -> Int {
            let together = TeamSide.allCases.filter { partners.contains(Set(teams[$0])) }.count
            return together * 10_000 + PairingSearch.cost([teams], history: history)
        }
        return options.min { cost($0) < cost($1) } ?? options[0]
    }
}
