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
    case winnerCourt(rules: WinnerCourtRules, teams: BySide<TeamInfo>)
}

public struct TraditionalSession: Codable, Sendable, Hashable {
    public var rules: TraditionalRules
    public var teams: BySide<TeamInfo>
    public var score: TraditionalState

    public var engine: TraditionalEngine { TraditionalEngine(rules: rules) }
}

/// Winner court: you play games on a court until the organiser's whistle ends the round,
/// then move up or down. The app tracks only this team's side of it — the round number and
/// the games each side won — so there are no courts, partners or standings to keep.
public struct WinnerCourtSession: Codable, Sendable, Hashable {
    public var rules: WinnerCourtRules
    public var teams: BySide<TeamInfo>
    /// A round is a set that never completes on its own; the whistle closes it.
    public var score: TraditionalState
    public var isFinished: Bool

    public init(
        rules: WinnerCourtRules,
        teams: BySide<TeamInfo>,
        score: TraditionalState = TraditionalState(),
        isFinished: Bool = false
    ) {
        self.rules = rules
        self.teams = teams
        self.score = score
        self.isFinished = isFinished
    }

    public var engine: TraditionalEngine { TraditionalEngine(rules: rules.scoring) }

    public var roundNumber: Int { score.completedSets.count + 1 }

    public var completedRounds: [SetResult] { score.completedSets }

    /// Games won across every round, including the one in progress.
    public var totalGames: BySide<Int> {
        score.completedSets.reduce(score.games) { running, round in
            BySide(a: running.a + round.games.a, b: running.b + round.games.b)
        }
    }

    public var roundsWon: BySide<Int> { score.setsWon }
}

public enum SessionState: Codable, Sendable, Hashable {
    case traditional(TraditionalSession)
    case tournament(Tournament)
    case winnerCourt(WinnerCourtSession)

    public var isTournament: Bool {
        if case .tournament = self { return true }
        return false
    }

    public var isFinished: Bool {
        switch self {
        case .traditional(let session): session.score.isFinished
        case .tournament(let tournament): tournament.isFinished
        case .winnerCourt(let session): session.isFinished
        }
    }

    public var title: String {
        switch self {
        case .traditional(let session):
            "\(session.teams.a.name) vs \(session.teams.b.name)"
        case .tournament(let tournament):
            tournament.name.isEmpty ? tournament.format.displayName : tournament.name
        case .winnerCourt(let session):
            "\(session.teams.a.name) vs \(session.teams.b.name)"
        }
    }

    /// Whether anything was actually played, as opposed to merely set up. Decides whether
    /// a finished session is worth keeping in history.
    public var hasResults: Bool {
        switch self {
        case .traditional(let session):
            !session.score.completedSets.isEmpty || session.score.games.total > 0 || session.score.points.total > 0
        case .winnerCourt(let session):
            !session.completedRounds.isEmpty || session.score.games.total > 0 || session.score.points.total > 0
        case .tournament(let tournament):
            tournament.rounds.contains { round in
                round.matches.contains { $0.state.points.total > 0 } || !round.sitOuts.isEmpty
            }
        }
    }

    /// Courts the user can score right now: always one for a traditional match, and one
    /// per filled court in the current tournament round.
    public var courtCount: Int {
        switch self {
        case .traditional, .winnerCourt: 1
        case .tournament(let tournament): tournament.currentRound?.matches.count ?? 0
        }
    }
}
