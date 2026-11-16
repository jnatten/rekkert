/// Who a draw put where: each court's two sides, court 1 first, and the bench.
public struct RoundPlacement: Codable, Sendable, Hashable {
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

    /// The round as placed, as long as it places this tournament's players, each of them
    /// once, two a side on as many courts as can be played.
    func round(for tournament: Tournament) -> Round? {
        let everyone = Set(tournament.players.map(\.id))
        let placed = courts.flatMap { $0.a + $0.b } + sitOuts
        guard courts.count == tournament.playableCourts,
              courts.allSatisfy({ $0.a.count == 2 && $0.b.count == 2 }),
              placed.count == everyone.count, Set(placed) == everyone else { return nil }
        let matches = courts.enumerated().map { court, teams in
            CourtMatch(courtIndex: court, teams: teams, games: tournament.isLadder ? TraditionalState() : nil)
        }
        return Round(index: tournament.rounds.count, matches: matches, sitOuts: sitOuts)
    }

    public init(_ round: FriendlyRound) {
        courts = [round.teams]
        sitOuts = round.sitOuts
    }

    /// The friendly round as placed, as long as it places the friendly's players, each of them
    /// once, `teamSize` a side, and benches as many as the seats leave over.
    func friendlyRound(for session: FriendlySession) -> FriendlyRound? {
        guard courts.count == 1, let teams = courts.first else { return nil }
        let everyone = Set(session.players.map(\.id))
        let placed = teams.a + teams.b + sitOuts
        guard teams.a.count == session.teamSize, teams.b.count == session.teamSize,
              sitOuts.count == session.sitOutCount,
              placed.count == everyone.count, Set(placed) == everyone else { return nil }
        return FriendlyScheduler.makeRound(index: session.rounds.count, teams: teams, sitOuts: sitOuts, in: session)
    }
}
