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

    /// The round as placed, as long as it places everybody here for it, each of them once and
    /// nobody from outside the tournament, two a side on as many courts as those it places can
    /// fill. It may place somebody who has left: a draw made before their leaving reached the
    /// device that drew it stands as people walked onto it (spec 008, D-5). Somebody who has
    /// left is no longer on its bench, so they earn nothing for it.
    func round(for tournament: Tournament) -> Round? {
        let index = tournament.rounds.count
        let roster = Set(tournament.players.map(\.id))
        let here = Set(tournament.present(inRound: index).map(\.id))
        let placed = courts.flatMap { $0.a + $0.b } + sitOuts
        let placedOnce = Set(placed)
        guard placed.count == placedOnce.count, placedOnce.isSubset(of: roster), here.isSubset(of: placedOnce),
              courts.allSatisfy({ $0.a.count == 2 && $0.b.count == 2 }),
              courts.count == min(tournament.config.courtCount, placed.count / 4) else { return nil }
        let matches = courts.enumerated().map { court, teams in
            CourtMatch(courtIndex: court, teams: teams, games: tournament.isLadder ? TraditionalState() : nil)
        }
        return Round(index: index, matches: matches, sitOuts: sitOuts.filter(here.contains))
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
