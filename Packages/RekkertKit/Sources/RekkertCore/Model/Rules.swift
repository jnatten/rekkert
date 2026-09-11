public enum DeuceRule: String, Codable, Sendable, Hashable, CaseIterable {
    case advantage
    case goldenPoint
    case starPoint

    /// How many 40–40s are played out with advantage before the *next* one becomes a
    /// single sudden-death point. `nil` means never — deuces repeat forever.
    /// Golden point: the very first 40–40 is sudden death. Star point (current WPT rule):
    /// two deuces are played out, the third 40–40 is sudden death.
    public var deucesBeforeSuddenDeath: Int? {
        switch self {
        case .advantage: nil
        case .goldenPoint: 0
        case .starPoint: 2
        }
    }

    public var displayName: String {
        switch self {
        case .advantage: "Deuce"
        case .goldenPoint: "Golden point"
        case .starPoint: "Star point"
        }
    }
}

public enum DecidingSet: Codable, Sendable, Hashable {
    case normal
    case superTiebreak(points: Int)

    public static let standardSuperTiebreak = DecidingSet.superTiebreak(points: 10)
}

public struct TraditionalRules: Codable, Sendable, Hashable {
    public var sport: Sport
    public var setsToWin: Int
    public var gamesPerSet: Int
    /// Game count at which a tiebreak is played instead of another game. `nil` = advantage set.
    public var tiebreakAtGames: Int?
    public var tiebreakPoints: Int
    public var decidingSet: DecidingSet
    public var deuceRule: DeuceRule

    public init(
        sport: Sport = .padel,
        setsToWin: Int = 2,
        gamesPerSet: Int = 6,
        tiebreakAtGames: Int? = 6,
        tiebreakPoints: Int = 7,
        decidingSet: DecidingSet = .normal,
        deuceRule: DeuceRule = .advantage
    ) {
        self.sport = sport
        self.setsToWin = setsToWin
        self.gamesPerSet = gamesPerSet
        self.tiebreakAtGames = tiebreakAtGames
        self.tiebreakPoints = tiebreakPoints
        self.decidingSet = decidingSet
        self.deuceRule = deuceRule
    }
}

public enum TargetKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// The round ends when both scores together reach the target, so they always sum to it.
    case totalPointsPlayed
    /// The round ends when either side reaches the target on its own.
    case firstToTarget

    public var displayName: String {
        switch self {
        case .totalPointsPlayed: "Total points played"
        case .firstToTarget: "First to target"
        }
    }
}

public struct PointCountRules: Codable, Sendable, Hashable {
    public var target: Int
    public var targetKind: TargetKind
    public var servesPerTeam: Int

    public static let commonTargets = [16, 21, 24, 32]

    public init(target: Int = 16, targetKind: TargetKind = .totalPointsPlayed, servesPerTeam: Int = 2) {
        self.target = target
        self.targetKind = targetKind
        self.servesPerTeam = servesPerTeam
    }
}
