public struct Standing: Sendable, Hashable, Identifiable {
    public var player: Player
    public var pointsFor: Int
    public var pointsAgainst: Int
    public var compensation: Int
    public var roundsPlayed: Int
    public var sitOuts: Int

    public var id: PlayerID { player.id }
    public var total: Int { pointsFor + compensation }
    public var differential: Int { pointsFor - pointsAgainst }
}

public enum Leaderboard {
    public static func standings(for tournament: Tournament, onlyConfirmed: Bool = false) -> [Standing] {
        var byPlayer: [PlayerID: Standing] = [:]
        for player in tournament.players {
            byPlayer[player.id] = Standing(
                player: player, pointsFor: 0, pointsAgainst: 0,
                compensation: 0, roundsPlayed: 0, sitOuts: 0
            )
        }

        let compensation = tournament.config.sitOutCompensation
            .points(target: tournament.config.pointRules.target)

        for round in tournament.rounds {
            for match in round.matches where !onlyConfirmed || match.isConfirmed {
                for side in TeamSide.allCases {
                    for id in match.teams[side] {
                        byPlayer[id]?.pointsFor += match.state.points[side]
                        byPlayer[id]?.pointsAgainst += match.state.points[side.other]
                        byPlayer[id]?.roundsPlayed += 1
                    }
                }
            }
            for id in round.sitOuts {
                byPlayer[id]?.sitOuts += 1
                byPlayer[id]?.compensation += compensation
            }
        }

        return tournament.players
            .compactMap { byPlayer[$0.id] }
            .sorted(by: isRankedAbove)
    }

    static func isRankedAbove(_ lhs: Standing, _ rhs: Standing) -> Bool {
        if lhs.total != rhs.total { return lhs.total > rhs.total }
        if lhs.differential != rhs.differential { return lhs.differential > rhs.differential }
        if lhs.player.name != rhs.player.name { return lhs.player.name < rhs.player.name }
        return lhs.player.id < rhs.player.id
    }
}
