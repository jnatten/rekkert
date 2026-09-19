public struct SetResult: Codable, Sendable, Hashable {
    public var games: BySide<Int>
    public var tiebreak: BySide<Int>?
    /// `nil` when the two sides finished level, which a winner-court round allows because
    /// it is ended by a whistle rather than by someone reaching a target.
    public var winner: TeamSide?

    public init(games: BySide<Int>, tiebreak: BySide<Int>? = nil, winner: TeamSide?) {
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
    /// Per side, whether the partners take their turns the other way round from how the
    /// rotation names them.
    public var serversSwapped: BySide<Bool>

    public init(firstServerIndex: Int = 0, serversSwapped: BySide<Bool> = BySide(both: false)) {
        self.completedSets = []
        self.games = BySide(both: 0)
        self.points = BySide(both: 0)
        self.deuceCount = 0
        self.winner = nil
        self.suddenDeathCourt = nil
        self.firstServerIndex = firstServerIndex
        self.serversSwapped = serversSwapped
    }

    public var serveOrder: ServeOrder {
        get { ServeOrder(firstServerIndex: firstServerIndex, serversSwapped: serversSwapped) }
        set {
            firstServerIndex = newValue.firstServerIndex
            serversSwapped = newValue.serversSwapped
        }
    }

    private enum CodingKeys: String, CodingKey {
        case completedSets, games, points, deuceCount, winner, suddenDeathCourt, firstServerIndex, serversSwapped
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedSets = try container.decode([SetResult].self, forKey: .completedSets)
        games = try container.decode(BySide<Int>.self, forKey: .games)
        points = try container.decode(BySide<Int>.self, forKey: .points)
        deuceCount = try container.decode(Int.self, forKey: .deuceCount)
        winner = try container.decodeIfPresent(TeamSide.self, forKey: .winner)
        suddenDeathCourt = try container.decodeIfPresent(ServeCourt.self, forKey: .suddenDeathCourt)
        firstServerIndex = try container.decode(Int.self, forKey: .firstServerIndex)
        serversSwapped = try container.decodeIfPresent(BySide<Bool>.self, forKey: .serversSwapped) ?? BySide(both: false)
    }

    public var setsWon: BySide<Int> {
        var result = BySide(both: 0)
        for set in completedSets {
            if let winner = set.winner { result[winner] += 1 }
        }
        return result
    }

    public var isFinished: Bool { winner != nil }
}
