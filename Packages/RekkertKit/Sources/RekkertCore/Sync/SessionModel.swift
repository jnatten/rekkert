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
    /// The whole session travels, so the id that seeds the draw is the same on both devices.
    case friendly(FriendlySession)
}

public struct TraditionalSession: Codable, Sendable, Hashable {
    public var rules: TraditionalRules
    public var teams: BySide<TeamInfo>
    public var score: TraditionalState
    /// Called off before anyone won it. A match can end either by being played out or by
    /// being stopped, and only the first shows up in the score.
    public var isStopped: Bool
    /// When the match started, which is what the clock on the board counts from. A match has
    /// no rounds, so this one clock runs the whole way through.
    public var startedAt: Date?

    public init(
        rules: TraditionalRules,
        teams: BySide<TeamInfo>,
        score: TraditionalState = TraditionalState(),
        isStopped: Bool = false,
        startedAt: Date? = nil
    ) {
        self.rules = rules
        self.teams = teams
        self.score = score
        self.isStopped = isStopped
        self.startedAt = startedAt
    }

    public var engine: TraditionalEngine { TraditionalEngine(rules: rules) }

    private enum CodingKeys: String, CodingKey { case rules, teams, score, isStopped, startedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decode(TraditionalRules.self, forKey: .rules)
        teams = try container.decode(BySide<TeamInfo>.self, forKey: .teams)
        score = try container.decode(TraditionalState.self, forKey: .score)
        isStopped = try container.decodeIfPresent(Bool.self, forKey: .isStopped) ?? false
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
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
    /// When the round now on the board began — the session, for the first one, and the last
    /// whistle for every one after it. Only the current round's, because a round here is a
    /// completed set rather than a struct with somewhere to keep one.
    public var roundStartedAt: Date?

    public init(
        rules: WinnerCourtRules,
        teams: BySide<TeamInfo>,
        score: TraditionalState = TraditionalState(),
        isFinished: Bool = false,
        roundStartedAt: Date? = nil
    ) {
        self.rules = rules
        self.teams = teams
        self.score = score
        self.isFinished = isFinished
        self.roundStartedAt = roundStartedAt
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
    /// When the counting started, which is what the clock on the board counts from.
    public var startedAt: Date?

    public init(
        rules: PointCountRules,
        teams: BySide<TeamInfo>,
        score: PointCountState = PointCountState(),
        isStopped: Bool = false,
        startedAt: Date? = nil
    ) {
        self.rules = rules
        self.teams = teams
        self.score = score
        self.isStopped = isStopped
        self.startedAt = startedAt
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
    case friendly(FriendlySession)

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
        // Rounds never run out, so a friendly ends only when somebody says it has.
        case .friendly(let session): session.isFinished
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
        case .friendly(let session):
            session.name.isEmpty ? "Friendly" : session.name
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
        case .friendly(let session):
            session.wasPlayed
        }
    }

    /// The service order on this court as it stands, which is what a correction rewrites.
    public func serveOrder(round: Int? = nil, court: Int = 0) -> ServeOrder? {
        switch self {
        case .traditional(let session): session.score.serveOrder
        case .winnerCourt(let session): session.score.serveOrder
        case .pointCount(let session): session.score.serveOrder
        case .friendly(let session):
            session.round(at: round ?? session.currentIndex)?.score.serveOrder
        case .tournament(let tournament):
            (round.map { tournament.round(at: $0) } ?? tournament.currentRound)?
                .matches.first { $0.courtIndex == court }?
                .state.serveOrder
        }
    }

    /// Who serves the next point on this court. Read here rather than off the scoreboard,
    /// which is presentation: it drops the serve once a board is over and stands a singles
    /// player in for a partner.
    public func serve(round: Int? = nil, court: Int = 0) -> ServeState? {
        switch self {
        case .traditional(let session): session.engine.serve(session.score)
        case .winnerCourt(let session): session.engine.serve(session.score)
        case .pointCount(let session): session.engine.serve(session.score)
        case .friendly(let session):
            session.round(at: round ?? session.currentIndex).map { session.engine.serve($0.score) }
        case .tournament(let tournament):
            (round.map { tournament.round(at: $0) } ?? tournament.currentRound)?
                .matches.first { $0.courtIndex == court }
                .map { PointCountEngine(rules: tournament.config.pointRules).serve($0.state) }
        }
    }

    /// What it was played as. A tournament is named by its format, since Americano and
    /// Mexicano are what you would call them rather than "tournament".
    public var modeName: String {
        switch self {
        case .traditional: "Match"
        case .pointCount: "Points"
        case .winnerCourt: "Winner court"
        case .friendly: "Friendly"
        case .tournament(let tournament): tournament.format.displayName
        }
    }

    public var modeSymbol: String {
        switch self {
        case .traditional: "figure.tennis"
        case .pointCount: "number"
        case .winnerCourt: "arrow.up.arrow.down"
        case .friendly: "shuffle"
        case .tournament(let tournament):
            tournament.format == .americano ? "arrow.triangle.2.circlepath" : "list.number"
        }
    }

    /// Whether this session could be picked up where it left off. One that was played to
    /// its end cannot: it has a winner, and there is no un-winning a match.
    public var canResume: Bool { resumed() != nil }

    /// The same session with whatever ended it lifted, or `nil` if it ran its course.
    public func resumed() -> SessionState? {
        switch self {
        case .traditional(var session):
            guard session.score.winner == nil else { return nil }
            session.isStopped = false
            return .traditional(session)

        case .pointCount(var session):
            guard !session.engine.isFinished(session.score) else { return nil }
            session.isStopped = false
            return .pointCount(session)

        case .winnerCourt(var session):
            // A round-after-round session never ends by itself, so there is always more
            // of it to play.
            session.isFinished = false
            return .winnerCourt(session)

        case .friendly(var session):
            // Same as winner court: there is always another round in it.
            session.isFinished = false
            return .friendly(session)

        case .tournament(var tournament):
            tournament.isFinished = false
            return .tournament(tournament)
        }
    }

    /// The same session with the clock on the board started again.
    ///
    /// Kept apart from `resumed()`, which `canResume` reads on every redraw and which taking
    /// a result back goes through: a session picked up out of history stopped being played
    /// and the round it left off in did not go on running, but a result taken back a second
    /// after it was reached never stopped at all.
    ///
    /// Stamped before the event is recorded rather than when it is applied, so the new start
    /// travels inside the payload and every device reads the one this device chose.
    public func restarted(at date: Date) -> SessionState {
        switch self {
        case .traditional(var session):
            session.startedAt = date
            return .traditional(session)

        case .pointCount(var session):
            session.startedAt = date
            return .pointCount(session)

        case .winnerCourt(var session):
            session.roundStartedAt = date
            return .winnerCourt(session)

        case .friendly(var session):
            guard let index = session.rounds.indices.last else { return .friendly(session) }
            session.rounds[index].startedAt = date
            return .friendly(session)

        case .tournament(var tournament):
            guard let index = tournament.rounds.indices.last else { return .tournament(tournament) }
            tournament.rounds[index].startedAt = date
            return .tournament(tournament)
        }
    }

    /// Courts the user can score right now: always one for a traditional match, and one
    /// per filled court in the current tournament round.
    public var courtCount: Int {
        switch self {
        case .traditional, .winnerCourt, .pointCount, .friendly: 1
        case .tournament(let tournament): tournament.currentRound?.matches.count ?? 0
        }
    }
}
