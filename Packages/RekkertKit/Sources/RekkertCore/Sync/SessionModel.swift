import Foundation

public struct TeamInfo: Codable, Sendable, Hashable {
    public var name: String
    public var players: [String]

    public init(name: String, players: [String] = []) {
        self.name = name
        self.players = players
    }

    public static let home = TeamInfo(name: "Us")
    public static let away = TeamInfo(name: "Them")
}

public enum SessionSetup: Codable, Sendable, Hashable {
    case traditional(rules: TraditionalRules, teams: BySide<TeamInfo>)
    case tournament(Tournament)
}

public struct TraditionalSession: Codable, Sendable, Hashable {
    public var rules: TraditionalRules
    public var teams: BySide<TeamInfo>
    public var score: TraditionalState

    public var engine: TraditionalEngine { TraditionalEngine(rules: rules) }
}

public enum SessionState: Codable, Sendable, Hashable {
    case traditional(TraditionalSession)
    case tournament(Tournament)

    public var isTournament: Bool {
        if case .tournament = self { return true }
        return false
    }

    public var isFinished: Bool {
        switch self {
        case .traditional(let session): session.score.isFinished
        case .tournament(let tournament): tournament.isFinished
        }
    }

    public var title: String {
        switch self {
        case .traditional(let session):
            "\(session.teams.a.name) vs \(session.teams.b.name)"
        case .tournament(let tournament):
            tournament.name.isEmpty ? tournament.format.displayName : tournament.name
        }
    }

    /// Courts the user can score right now: always one for a traditional match, and one
    /// per filled court in the current tournament round.
    public var courtCount: Int {
        switch self {
        case .traditional: 1
        case .tournament(let tournament): tournament.currentRound?.matches.count ?? 0
        }
    }
}
