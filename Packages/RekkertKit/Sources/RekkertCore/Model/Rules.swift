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

/// When the two sides swap ends. Off unless a match asks for it: a board that turns itself
/// over is a surprise to anyone who did not set it up that way.
public enum ChangeEndsRule: String, Codable, Sendable, Hashable, CaseIterable {
    case off
    case oddGames
    case everySet

    public var displayName: String {
        switch self {
        case .off: "Never"
        case .oddGames: "Odd games"
        case .everySet: "Every set"
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
    public var changeEnds: ChangeEndsRule

    public init(
        sport: Sport = .padel,
        setsToWin: Int = 2,
        gamesPerSet: Int = 6,
        tiebreakAtGames: Int? = 6,
        tiebreakPoints: Int = 7,
        decidingSet: DecidingSet = .normal,
        deuceRule: DeuceRule = .advantage,
        changeEnds: ChangeEndsRule = .off
    ) {
        self.sport = sport
        self.setsToWin = setsToWin
        self.gamesPerSet = gamesPerSet
        self.tiebreakAtGames = tiebreakAtGames
        self.tiebreakPoints = tiebreakPoints
        self.decidingSet = decidingSet
        self.deuceRule = deuceRule
        self.changeEnds = changeEnds
    }

    private enum CodingKeys: String, CodingKey {
        case sport, setsToWin, gamesPerSet, tiebreakAtGames, tiebreakPoints, decidingSet, deuceRule, changeEnds
    }

    /// Hand-rolled so a match, preset or history record filed before ends could change still
    /// reads. A synthesised decoder asks for every key it knows about, and the three places
    /// these are loaded from all swallow the failure: `active.json` is quarantined, the
    /// history drops the records it cannot read, and the preset library is replaced whole by
    /// an empty one — so the match, the history and the presets would go without a word.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sport = try container.decode(Sport.self, forKey: .sport)
        setsToWin = try container.decode(Int.self, forKey: .setsToWin)
        gamesPerSet = try container.decode(Int.self, forKey: .gamesPerSet)
        tiebreakAtGames = try container.decodeIfPresent(Int.self, forKey: .tiebreakAtGames)
        tiebreakPoints = try container.decode(Int.self, forKey: .tiebreakPoints)
        decidingSet = try container.decode(DecidingSet.self, forKey: .decidingSet)
        deuceRule = try container.decode(DeuceRule.self, forKey: .deuceRule)
        changeEnds = try container.decodeIfPresent(ChangeEndsRule.self, forKey: .changeEnds) ?? .off
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

extension TraditionalRules {
    /// A set that never ends by itself, in a match that never ends by itself — the shape
    /// winner court needs, where a whistle decides when a round is over.
    public static func endless(deuceRule: DeuceRule, sport: Sport = .padel) -> TraditionalRules {
        TraditionalRules(
            sport: sport,
            setsToWin: .max,
            gamesPerSet: .max,
            tiebreakAtGames: nil,
            decidingSet: .normal,
            deuceRule: deuceRule
        )
    }
}

public struct WinnerCourtRules: Codable, Sendable, Hashable {
    public var sport: Sport
    public var deuceRule: DeuceRule

    public init(sport: Sport = .padel, deuceRule: DeuceRule = .goldenPoint) {
        self.sport = sport
        self.deuceRule = deuceRule
    }

    var scoring: TraditionalRules { .endless(deuceRule: deuceRule, sport: sport) }
}
