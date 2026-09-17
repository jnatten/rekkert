/// How one player's evening has gone. A friendly is won by a person rather than by a side,
/// since the sides are redrawn every round.
public struct FriendlyStanding: Sendable, Hashable, Identifiable {
    public var player: Player
    public var roundsWon: Int
    public var roundsPlayed: Int
    public var gamesFor: Int
    public var gamesAgainst: Int
    public var sitOuts: Int

    public var id: PlayerID { player.id }
    public var gameDifferential: Int { gamesFor - gamesAgainst }
}

extension Leaderboard {
    /// Ranked on rounds won, ties broken on games won — the question a friendly evening
    /// actually asks. Only rounds that were played count, so a round just drawn does not
    /// hand everybody on court a sit-out or a played round they have not had yet.
    public static func standings(for session: FriendlySession) -> [FriendlyStanding] {
        var byPlayer: [PlayerID: FriendlyStanding] = [:]
        for player in session.players {
            byPlayer[player.id] = FriendlyStanding(
                player: player, roundsWon: 0, roundsPlayed: 0,
                gamesFor: 0, gamesAgainst: 0, sitOuts: 0
            )
        }

        for round in session.rounds where round.wasPlayed {
            let games = round.games
            for side in TeamSide.allCases {
                for id in round.teams[side] {
                    byPlayer[id]?.roundsPlayed += 1
                    byPlayer[id]?.gamesFor += games[side]
                    byPlayer[id]?.gamesAgainst += games[side.other]
                    if round.score.winner == side { byPlayer[id]?.roundsWon += 1 }
                }
            }
            for id in round.sitOuts {
                byPlayer[id]?.sitOuts += 1
            }
        }

        return session.players
            .compactMap { byPlayer[$0.id] }
            .sorted(by: isRankedAbove)
    }

    static func isRankedAbove(_ lhs: FriendlyStanding, _ rhs: FriendlyStanding) -> Bool {
        if lhs.roundsWon != rhs.roundsWon { return lhs.roundsWon > rhs.roundsWon }
        if lhs.gamesFor != rhs.gamesFor { return lhs.gamesFor > rhs.gamesFor }
        if lhs.player.name != rhs.player.name { return lhs.player.name < rhs.player.name }
        return lhs.player.id < rhs.player.id
    }
}
