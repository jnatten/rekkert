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
    case pointCount(rules: PointCountRules, teams: BySide<TeamInfo>)
}

public struct TraditionalSession: Codable, Sendable, Hashable {
    public var rules: TraditionalRules
    public var teams: BySide<TeamInfo>
    public var score: TraditionalState
    /// Called off before anyone won it. A match can end either by being played out or by
    /// being stopped, and only the first shows up in the score.
    public var isStopped: Bool

    public init(
        rules: TraditionalRules,
        teams: BySide<TeamInfo>,
        score: TraditionalState = TraditionalState(),
        isStopped: Bool = false
    ) {
        self.rules = rules
        self.teams = teams
        self.score = score
        self.isStopped = isStopped
    }

    public var engine: TraditionalEngine { TraditionalEngine(rules: rules) }

    private enum CodingKeys: String, CodingKey { case rules, teams, score, isStopped }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decode(TraditionalRules.self, forKey: .rules)
        teams = try container.decode(BySide<TeamInfo>.self, forKey: .teams)
        score = try container.decode(TraditionalState.self, forKey: .score)
        isStopped = try container.decodeIfPresent(Bool.self, forKey: .isStopped) ?? false
    }
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

/// One round of plain counting between two fixed teams — an americano round without the
/// tournament around it. The scoring is the same engine the courts use, so a round played
/// here and a round played in a tournament end on exactly the same rules.
public struct PointCountSession: Codable, Sendable, Hashable {
    public var rules: PointCountRules
    public var teams: BySide<TeamInfo>
    public var score: PointCountState
    /// Called off before the target was reached.
    public var isStopped: Bool

    public init(
        rules: PointCountRules,
        teams: BySide<TeamInfo>,
        score: PointCountState = PointCountState(),
        isStopped: Bool = false
    ) {
        self.rules = rules
        self.teams = teams
        self.score = score
        self.isStopped = isStopped
    }

    public var engine: PointCountEngine { PointCountEngine(rules: rules) }

    public var isFinished: Bool { engine.isFinished(score) || isStopped }

    /// `nil` for a draw, which a total-points target allows whenever it is even.
    public var winner: TeamSide? { engine.winner(score) }
}

public enum SessionState: Codable, Sendable, Hashable {
    case traditional(TraditionalSession)
    case tournament(Tournament)
    case winnerCourt(WinnerCourtSession)
    case pointCount(PointCountSession)

    public var isTournament: Bool {
        if case .tournament = self { return true }
        return false
    }

    public var isFinished: Bool {
        switch self {
        case .traditional(let session): session.score.isFinished || session.isStopped
        case .tournament(let tournament): tournament.isFinished
        case .winnerCourt(let session): session.isFinished
        case .pointCount(let session): session.isFinished
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
        case .pointCount(let session):
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
        case .pointCount(let session):
            session.score.points.total > 0
        }
    }

    /// Where the service rotation currently starts for this court, which is what a
    /// correction shifts.
    public func firstServerIndex(round: Int? = nil, court: Int = 0) -> Int? {
        switch self {
        case .traditional(let session): session.score.firstServerIndex
        case .winnerCourt(let session): session.score.firstServerIndex
        case .pointCount(let session): session.score.firstServerIndex
        case .tournament(let tournament):
            (round.map { tournament.round(at: $0) } ?? tournament.currentRound)?
                .matches.first { $0.courtIndex == court }?
                .state.firstServerIndex
        }
    }

    /// Courts the user can score right now: always one for a traditional match, and one
    /// per filled court in the current tournament round.
    public var courtCount: Int {
        switch self {
        case .traditional, .winnerCourt, .pointCount: 1
        case .tournament(let tournament): tournament.currentRound?.matches.count ?? 0
        }
    }
}
