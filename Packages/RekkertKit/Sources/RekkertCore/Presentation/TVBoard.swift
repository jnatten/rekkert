import Foundation

/// What a TV, or an iPad put up as one, shows of a session.
public struct TVBoard: Sendable, Hashable {
    public enum Content: Sendable, Hashable {
        case idle
        case waiting
        case match(Court)
        case courts([Court])
        case result(SessionResult)
    }

    public struct Player: Sendable, Hashable {
        public var name: String
        public var isServing: Bool
    }

    public struct Side: Sendable, Hashable {
        /// `nil` when the team is only called by its players, so they are not named twice.
        public var name: String?
        public var players: [Player]
        public var points: String
        public var sets: [Int]
        public var games: Int?
        public var roundsWon: Int?
        public var isServing: Bool
        public var isWinner: Bool
    }

    public struct Court: Sendable, Hashable, Identifiable {
        public var id: Int
        public var label: String?
        public var sides: BySide<Side>
        public var status: String?
        public var servingCourt: ServeCourt?
        public var isSuddenDeath: Bool
        public var isDone: Bool
    }

    public struct UpNext: Sendable, Hashable {
        public var teams: BySide<String>
        public var sittingOut: [String]
    }

    public var title: String
    public var mode: String
    public var symbol: String
    public var detail: String
    public var clockStart: Date?
    public var content: Content
    public var standings: [SessionResult.Placing]
    public var sittingOut: [String]
    public var upNext: UpNext?
    public var leftSide: TeamSide

    public static let idle = TVBoard(
        title: "", mode: "", symbol: "sportscourt", detail: "", clockStart: nil,
        content: .idle, standings: [], sittingOut: [], upNext: nil, leftSide: .a
    )

    public static func make(from state: SessionState?, lastResult: SessionState?, display: DisplayPreferences) -> TVBoard {
        if let state { return live(state, display: display) }
        if let lastResult { return result(lastResult) }
        return .idle
    }

    private static func result(_ state: SessionState) -> TVBoard {
        var board = header(state)
        board.content = .result(SessionResult.make(from: state))
        return board
    }

    private static func live(_ state: SessionState, display: DisplayPreferences) -> TVBoard {
        var board = header(state)

        switch state {
        case .tournament(let tournament):
            board.standings = standings(tournament)
            guard let round = tournament.currentRound else {
                board.detail = "Waiting for the first round"
                board.content = .waiting
                return board
            }
            let engine = PointCountEngine(rules: tournament.config.pointRules)
            let boards = round.matches.sorted { $0.courtIndex < $1.courtIndex }.compactMap { match in
                ScoreboardSnapshot.make(from: state, court: match.courtIndex).map { (match, $0) }
            }
            board.detail = round.isCancelled ? "Round \(round.index + 1) · cancelled" : "Round \(round.index + 1)"
            board.clockStart = boards.lazy.compactMap(\.1.clockStart).first
            board.content = .courts(boards.map { match, snapshot in
                var court = court(snapshot)
                if !court.isDone { court.status = "\(engine.pointsRemaining(match.state)) to play" }
                return court
            })
            board.sittingOut = round.sitOuts.compactMap { tournament.player($0)?.name }
            board.leftSide = display.isMirrored ? .b : .a
            return board

        case .friendly(let session):
            board.standings = SessionResult.make(from: state).placings
            if let round = session.currentRound {
                board.sittingOut = session.sitOutNames(in: round)
                if round.isFinished, let next = session.nextDraw() {
                    board.upNext = UpNext(teams: session.teamNames(in: next), sittingOut: session.sitOutNames(in: next))
                }
            }

        case .traditional, .winnerCourt, .pointCount:
            break
        }

        guard let snapshot = ScoreboardSnapshot.make(from: state) else {
            board.detail = "Waiting for the first round"
            board.content = .waiting
            return board
        }
        var court = court(snapshot)
        if case .winnerCourt(let session) = state {
            for side in TeamSide.allCases {
                court.sides[side].roundsWon = session.roundsWon[side]
                court.sides[side].sets = []
            }
        }
        board.detail = snapshot.detail
        board.clockStart = snapshot.clockStart
        board.content = .match(court)
        board.leftSide = display.isMirrored != snapshot.endsSwapped ? .b : .a
        return board
    }

    private static func header(_ state: SessionState) -> TVBoard {
        var board = TVBoard.idle
        board.title = state.title
        board.mode = state.modeName
        board.symbol = state.modeSymbol
        return board
    }

    private static func court(_ snapshot: ScoreboardSnapshot) -> Court {
        Court(
            id: snapshot.courtIndex,
            label: snapshot.courtLabel,
            sides: BySide(a: side(.a, of: snapshot), b: side(.b, of: snapshot)),
            status: nil,
            servingCourt: snapshot.servingCourt,
            isSuddenDeath: snapshot.isSuddenDeath,
            isDone: snapshot.isFinished || snapshot.isLocked
        )
    }

    private static func side(_ side: TeamSide, of snapshot: ScoreboardSnapshot) -> Side {
        let players = snapshot.players[side]
        let isServing = snapshot.serving == side
        var team = Side(
            name: players.joined(separator: " & ") == snapshot.teamNames[side] ? nil : snapshot.teamNames[side],
            players: players.map { Player(name: $0, isServing: isServing && $0 == snapshot.servingPlayer) },
            points: snapshot.primary[side],
            sets: snapshot.completedSets.map { $0.games[side] },
            games: snapshot.games?[side],
            roundsWon: nil,
            isServing: isServing,
            isWinner: snapshot.winner == side
        )
        // Over, there is no point or game in play to show: the sets are the score.
        if snapshot.isFinished, let current = snapshot.games {
            let played = snapshot.completedSets.map(\.games) + (current.total > 0 ? [current] : [])
            if played.count > 1 {
                team.points = "\(played.filter { $0.lead(side) > 0 }.count)"
                team.sets = played.map { $0[side] }
            } else {
                team.points = "\(played.first?[side] ?? 0)"
                team.sets = []
            }
            team.games = nil
        }
        return team
    }

    private static func standings(_ tournament: Tournament) -> [SessionResult.Placing] {
        Leaderboard.standings(for: tournament).enumerated().map { index, standing in
            SessionResult.Placing(
                id: standing.player.id.raw.uuidString,
                rank: index + 1,
                name: standing.player.name,
                value: "\(standing.total)",
                detail: standing.differential > 0 ? "+\(standing.differential)" : "\(standing.differential)"
            )
        }
    }
}
