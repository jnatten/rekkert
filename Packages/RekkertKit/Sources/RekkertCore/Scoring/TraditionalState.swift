public struct SetResult: Codable, Sendable, Hashable {
    public var games: BySide<Int>
    public var tiebreak: BySide<Int>?
    public var winner: TeamSide

    public init(games: BySide<Int>, tiebreak: BySide<Int>? = nil, winner: TeamSide) {
        self.games = games
        self.tiebreak = tiebreak
        self.winner = winner
    }
}

public enum GamePhase: Codable, Sendable, Hashable {
    case game
    case tiebreak(target: Int)
    case finished
}

public struct TraditionalState: Codable, Sendable, Hashable {
    public var completedSets: [SetResult]
    public var games: BySide<Int>
    public var points: BySide<Int>
    /// Number of times the current game has reached 40–40. Drives the golden/star point rules.
    public var deuceCount: Int
    public var winner: TeamSide?
    /// Set by the receiving team when a sudden-death point is about to be played.
    public var suddenDeathCourt: ServeCourt?
    public var firstServerIndex: Int

    public init(firstServerIndex: Int = 0) {
        self.completedSets = []
        self.games = BySide(both: 0)
        self.points = BySide(both: 0)
        self.deuceCount = 0
        self.winner = nil
        self.suddenDeathCourt = nil
        self.firstServerIndex = firstServerIndex
    }

    public var setsWon: BySide<Int> {
        var result = BySide(both: 0)
        for set in completedSets { result[set.winner] += 1 }
        return result
    }

    public var isFinished: Bool { winner != nil }
}
