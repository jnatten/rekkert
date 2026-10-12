public struct Standing: Sendable, Hashable, Identifiable {
    public var player: Player
    public var pointsFor: Int
    public var pointsAgainst: Int
    public var compensation: Int
    public var roundsPlayed: Int
    public var sitOuts: Int
    /// Ladder only.
    public var roundsWon = 0
    /// Ladder only: the court they finished the last round on, or are playing it on.
    public var court: Int?

    public var id: PlayerID { player.id }
    public var total: Int { pointsFor + compensation }
    public var differential: Int { pointsFor - pointsAgainst }
}

public enum Leaderboard {
    public static func standings(for tournament: Tournament, onlyConfirmed: Bool = false) -> [Standing] {
        if tournament.isLadder { return ladder(tournament) }
        var byPlayer: [PlayerID: Standing] = [:]
        for player in tournament.players {
            byPlayer[player.id] = Standing(
                player: player, pointsFor: 0, pointsAgainst: 0,
                compensation: 0, roundsPlayed: 0, sitOuts: 0
            )
        }

        let compensation = tournament.config.sitOutCompensation
            .points(target: tournament.config.pointRules.target)

        for round in tournament.rounds where !round.isCancelled {
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

    /// The order the last round finished in — each court's winners above its losers, court by
    /// court — or, while it is being played, where everybody is playing it. Its bench below.
    private static func ladder(_ tournament: Tournament) -> [Standing] {
        var byPlayer: [PlayerID: Standing] = [:]
        for player in tournament.players {
            byPlayer[player.id] = Standing(
                player: player, pointsFor: 0, pointsAgainst: 0,
                compensation: 0, roundsPlayed: 0, sitOuts: 0
            )
        }

        let played = tournament.rounds.filter { !$0.isCancelled }
        for round in played {
            for match in round.matches {
                let status = tournament.status(of: match, in: round)
                for side in TeamSide.allCases {
                    for id in match.teams[side] {
                        byPlayer[id]?.pointsFor += status.line[side]
                        byPlayer[id]?.pointsAgainst += status.line[side.other]
                        byPlayer[id]?.roundsPlayed += 1
                        if status.winner == side { byPlayer[id]?.roundsWon += 1 }
                    }
                }
            }
            for id in round.sitOuts { byPlayer[id]?.sitOuts += 1 }
        }

        var place: [PlayerID: Int] = [:]
        if let last = played.last {
            for match in last.matches {
                let winner = tournament.status(of: match, in: last).winner
                for side in TeamSide.allCases {
                    for id in match.teams[side] {
                        byPlayer[id]?.court = match.courtIndex
                        place[id] = match.courtIndex * 2 + (winner == side.other ? 1 : 0)
                    }
                }
            }
        }

        return tournament.players.compactMap { byPlayer[$0.id] }.sorted { lhs, rhs in
            let one = place[lhs.id] ?? .max
            let two = place[rhs.id] ?? .max
            if one != two { return one < two }
            if lhs.roundsWon != rhs.roundsWon { return lhs.roundsWon > rhs.roundsWon }
            if lhs.differential != rhs.differential { return lhs.differential > rhs.differential }
            if lhs.player.name != rhs.player.name { return lhs.player.name < rhs.player.name }
            return lhs.player.id < rhs.player.id
        }
    }

    static func isRankedAbove(_ lhs: Standing, _ rhs: Standing) -> Bool {
        if lhs.total != rhs.total { return lhs.total > rhs.total }
        if lhs.differential != rhs.differential { return lhs.differential > rhs.differential }
        if lhs.player.name != rhs.player.name { return lhs.player.name < rhs.player.name }
        return lhs.player.id < rhs.player.id
    }
}
