import Foundation

/// What the Lock Screen shows of a session. Codable, unlike the scoreboard it is read off,
/// because it travels to the widget extension as the Live Activity's content.
public struct LiveScore: Codable, Sendable, Hashable {
    public struct Board: Codable, Sendable, Hashable {
        public var label: String?
        public var names: BySide<String>
        public var points: BySide<String>
        public var games: BySide<Int>?
        public var sets: [SetResult]
        public var serving: TeamSide?
        public var isSuddenDeath: Bool
        public var isDone: Bool
        public var winner: TeamSide?

        public init(
            label: String? = nil,
            names: BySide<String>,
            points: BySide<String>,
            games: BySide<Int>? = nil,
            sets: [SetResult] = [],
            serving: TeamSide? = nil,
            isSuddenDeath: Bool = false,
            isDone: Bool = false,
            winner: TeamSide? = nil
        ) {
            self.label = label
            self.names = names
            self.points = points
            self.games = games
            self.sets = sets
            self.serving = serving
            self.isSuddenDeath = isSuddenDeath
            self.isDone = isDone
            self.winner = winner
        }

        init(_ snapshot: ScoreboardSnapshot) {
            self.init(
                label: snapshot.courtLabel,
                names: snapshot.teamNames,
                points: snapshot.primary,
                games: snapshot.games,
                sets: snapshot.completedSets,
                serving: snapshot.serving,
                isSuddenDeath: snapshot.isSuddenDeath,
                isDone: snapshot.isFinished || snapshot.isLocked,
                winner: snapshot.winner
            )
        }
    }

    public struct Leader: Codable, Sendable, Hashable {
        public var name: String
        public var total: Int

        public init(name: String, total: Int) {
            self.name = name
            self.total = total
        }
    }

    public var kind: ScoreboardSnapshot.Kind
    public var title: String
    public var symbol: String
    public var detail: String
    /// The tournament round, counted from one.
    public var round: Int?
    public var clockStart: Date?
    /// One for the two-team modes; every court of the round for a tournament.
    public var boards: [Board]
    public var leaders: [Leader]
    /// The side the phone's own board draws on the left.
    public var leftSide: TeamSide
    public var colorsSwapped: Bool
    /// How it ended, set only once it has.
    public var result: String?

    public init(
        kind: ScoreboardSnapshot.Kind,
        title: String,
        symbol: String,
        detail: String,
        round: Int? = nil,
        clockStart: Date? = nil,
        boards: [Board],
        leaders: [Leader] = [],
        leftSide: TeamSide = .a,
        colorsSwapped: Bool = false,
        result: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.round = round
        self.clockStart = clockStart
        self.boards = boards
        self.leaders = leaders
        self.leftSide = leftSide
        self.colorsSwapped = colorsSwapped
        self.result = result
    }

    public var isOver: Bool { result != nil }

    public static func make(from state: SessionState, display: DisplayPreferences) -> LiveScore {
        let snapshots: [ScoreboardSnapshot]
        var detail: String
        var round: Int?
        var leaders: [Leader] = []

        if case .tournament(let tournament) = state {
            let current = tournament.currentRound
            snapshots = (current?.matches ?? [])
                .map(\.courtIndex)
                .sorted()
                .compactMap { ScoreboardSnapshot.make(from: state, court: $0) }
            round = current.map { $0.index + 1 }
            detail = round.map { "Round \($0)" } ?? "Waiting for the first round"
            leaders = Leaderboard.standings(for: tournament)
                .prefix(3)
                .map { Leader(name: $0.player.name, total: $0.total) }
        } else {
            snapshots = ScoreboardSnapshot.make(from: state).map { [$0] } ?? []
            detail = snapshots.first?.detail ?? ""
        }

        let endsSwapped = snapshots.first?.endsSwapped ?? false
        return LiveScore(
            kind: snapshots.first?.kind ?? (state.isTournament ? .tournament : .traditional),
            title: state.title,
            symbol: state.modeSymbol,
            detail: detail,
            round: round,
            clockStart: snapshots.lazy.compactMap(\.clockStart).first,
            boards: snapshots.map(Board.init),
            leaders: leaders,
            leftSide: display.isMirrored != endsSwapped ? .b : .a,
            colorsSwapped: display.areColorsSwapped
        )
    }

    public static func final(from state: SessionState, display: DisplayPreferences) -> LiveScore {
        var score = make(from: state, display: display)
        let result = SessionResult.make(from: state)
        score.result = result.score.isEmpty ? result.headline : "\(result.headline) · \(result.score)"
        score.clockStart = nil
        return score
    }
}
