/// How a session turned out, in the shape a result screen wants to draw it. Derived rather
/// than stored, so the same summary serves the phone and the watch.
public struct SessionResult: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case won
        case drawn
        /// Ended before it had run its course, so the score is where it got to rather than
        /// a result.
        case stopped
    }

    public struct Placing: Sendable, Hashable, Identifiable {
        public var id: String
        public var rank: Int
        public var name: String
        public var value: String

        public init(id: String, rank: Int, name: String, value: String) {
            self.id = id
            self.rank = rank
            self.name = name
            self.value = value
        }
    }

    /// "Blue win", "All square", "Jonas wins".
    public var headline: String
    /// The result in one line: "6–4  6–3", "16–12", "3–1".
    public var score: String
    /// What the score means, where it needs saying.
    public var detail: String?
    public var outcome: Outcome
    /// Which colour to celebrate in. `nil` for a draw, and for a tournament, which is won
    /// by a player rather than by one of the two sides.
    public var winningSide: TeamSide?
    /// Tournament finishes only; empty for the two-team modes.
    public var placings: [Placing]

    public static func make(from state: SessionState) -> SessionResult {
        switch state {
        case .traditional(let session): traditional(session)
        case .pointCount(let session): pointCount(session)
        case .winnerCourt(let session): winnerCourt(session)
        case .tournament(let tournament): self.tournament(tournament)
        }
    }

    // MARK: - Two-team modes

    private static func traditional(_ session: TraditionalSession) -> SessionResult {
        let score = session.score
        var sets = score.completedSets.map { "\($0.games.a)–\($0.games.b)" }
        // A match stopped part-way still has a set on the go, and leaving it out would
        // under-report what was played.
        if score.games.total > 0 || score.points.total > 0 {
            sets.append("\(score.games.a)–\(score.games.b)")
        }

        guard let winner = score.winner else {
            return SessionResult(
                headline: "Match stopped",
                score: sets.joined(separator: "  "),
                detail: sets.isEmpty ? "Nothing was played" : nil,
                outcome: .stopped,
                winningSide: nil,
                placings: []
            )
        }
        let won = score.setsWon
        return SessionResult(
            headline: "\(session.teams[winner].name) win",
            score: sets.joined(separator: "  "),
            detail: "\(won[winner]) \(plural(won[winner], "set")) to \(won[winner.other])",
            outcome: .won,
            winningSide: winner,
            placings: []
        )
    }

    private static func pointCount(_ session: PointCountSession) -> SessionResult {
        let points = session.score.points
        let score = "\(points.a)–\(points.b)"

        // Called off short of the target: what is on the board is where it got to, not a
        // result, however far ahead one side happened to be.
        guard session.engine.isFinished(session.score) else {
            return SessionResult(
                headline: "Round stopped",
                score: score,
                detail: points.total == 0 ? "Nothing was played" : "Short of \(session.rules.target)",
                outcome: .stopped,
                winningSide: nil,
                placings: []
            )
        }
        guard let winner = points.leader else {
            return SessionResult(
                headline: "All square",
                score: score,
                detail: "Played to \(session.rules.target)",
                outcome: .drawn,
                winningSide: nil,
                placings: []
            )
        }
        return SessionResult(
            headline: "\(session.teams[winner].name) win",
            score: score,
            detail: "by \(points.lead(winner))",
            outcome: .won,
            winningSide: winner,
            placings: []
        )
    }

    private static func winnerCourt(_ session: WinnerCourtSession) -> SessionResult {
        let rounds = session.roundsWon
        let games = session.totalGames
        let played = session.completedRounds.count

        guard played > 0 else {
            return SessionResult(
                headline: "Session stopped",
                score: "",
                detail: "No round was finished",
                outcome: .stopped,
                winningSide: nil,
                placings: []
            )
        }
        let detail = "\(played) \(plural(played, "round")) · games \(games.a)–\(games.b)"
        guard let winner = rounds.leader else {
            return SessionResult(
                headline: "All square",
                score: "\(rounds.a)–\(rounds.b)",
                detail: detail,
                outcome: .drawn,
                winningSide: nil,
                placings: []
            )
        }
        return SessionResult(
            headline: "\(session.teams[winner].name) win",
            score: "\(rounds.a)–\(rounds.b)",
            detail: detail,
            outcome: .won,
            winningSide: winner,
            placings: []
        )
    }

    // MARK: - Tournament

    private static func tournament(_ tournament: Tournament) -> SessionResult {
        let standings = Leaderboard.standings(for: tournament)
        let rounds = tournament.rounds.count
        let placings = standings.enumerated().map { index, standing in
            Placing(
                id: standing.player.id.raw.uuidString,
                rank: index + 1,
                name: standing.player.name,
                value: "\(standing.total)"
            )
        }

        guard let top = standings.first, top.total > 0 else {
            return SessionResult(
                headline: "Tournament stopped",
                score: "",
                detail: "Nothing was played",
                outcome: .stopped,
                winningSide: nil,
                placings: placings
            )
        }
        // A shared top score is a tie however the table breaks it, and naming one of them
        // as the winner would be wrong.
        let tied = standings.filter { $0.total == top.total }
        let detail = "\(rounds) \(plural(rounds, "round")) · \(tournament.players.count) players"

        return SessionResult(
            headline: tied.count > 1
                ? "\(tied.map(\.player.name).joined(separator: " & ")) tie"
                : "\(top.player.name) wins",
            score: "\(top.total)",
            detail: detail,
            outcome: tied.count > 1 ? .drawn : .won,
            winningSide: nil,
            placings: placings
        )
    }

    private static func plural(_ count: Int, _ singular: String) -> String {
        count == 1 ? singular : singular + "s"
    }
}
