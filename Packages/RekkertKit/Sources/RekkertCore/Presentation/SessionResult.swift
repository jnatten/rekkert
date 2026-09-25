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
        /// The tie-breaker, where the table has one worth showing beside the number it ranks on.
        public var detail: String?

        public init(id: String, rank: Int, name: String, value: String, detail: String? = nil) {
            self.id = id
            self.rank = rank
            self.name = name
            self.value = value
            self.detail = detail
        }
    }

    /// One round of a session that played several, for the modes where the teams change
    /// between them and the summary is a list rather than a single score.
    public struct RoundLine: Sendable, Hashable, Identifiable {
        public var id: Int
        /// "Round 3".
        public var title: String
        public var teams: BySide<String>
        /// "6–4", or "6–4  3–6  10–7".
        public var score: String
        public var winner: TeamSide?
        /// Called off part-way rather than played out.
        public var isStopped: Bool
        /// "Siri, Tor", or `nil` when everybody played.
        public var sitOuts: String?

        public init(
            id: Int, title: String, teams: BySide<String>, score: String,
            winner: TeamSide?, isStopped: Bool, sitOuts: String?
        ) {
            self.id = id
            self.title = title
            self.teams = teams
            self.score = score
            self.winner = winner
            self.isStopped = isStopped
            self.sitOuts = sitOuts
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
    /// Tournament and friendly finishes; empty for the two-team modes.
    public var placings: [Placing]
    /// Round by round, for the modes that play several with different teams each time.
    /// Empty for everything else.
    public var rounds: [RoundLine] = []

    public static func make(from state: SessionState) -> SessionResult {
        switch state {
        case .traditional(let session): traditional(session)
        case .pointCount(let session): pointCount(session)
        case .winnerCourt(let session): winnerCourt(session)
        case .tournament(let tournament): self.tournament(tournament)
        case .friendly(let session): friendly(session)
        }
    }

    /// The set scores as they read, counting the set in progress — leaving it out would have
    /// a match stopped part-way show nothing of what was played.
    private static func setScores(_ score: TraditionalState) -> [String] {
        var sets = score.completedSets.map { "\($0.games.a)–\($0.games.b)" }
        if score.games.total > 0 || score.points.total > 0 {
            sets.append("\(score.games.a)–\(score.games.b)")
        }
        return sets
    }

    // MARK: - Two-team modes

    private static func traditional(_ session: TraditionalSession) -> SessionResult {
        let score = session.score
        let sets = setScores(score)

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

    // MARK: - Friendly

    private static func friendly(_ session: FriendlySession) -> SessionResult {
        let standings = Leaderboard.standings(for: session)
        let lines = roundLines(session)
        let placings = standings.enumerated().map { index, standing in
            Placing(
                id: standing.player.id.raw.uuidString,
                rank: index + 1,
                name: standing.player.name,
                value: "\(standing.roundsWon) won",
                detail: "\(standing.gamesFor) \(plural(standing.gamesFor, "game"))"
            )
        }
        let played = lines.count

        guard played > 0 else {
            return SessionResult(
                headline: "Friendly stopped",
                score: "",
                detail: "Nothing was played",
                outcome: .stopped,
                winningSide: nil,
                placings: placings,
                rounds: lines
            )
        }
        let rounds = "\(played) \(plural(played, "round")) · \(session.players.count) players"

        // Every round called off short of a winner: there is a list to show but nothing to
        // crown, and naming whoever happens to head the table would be wrong.
        guard let top = standings.first, top.roundsWon > 0 else {
            return SessionResult(
                headline: "Friendly stopped",
                score: "",
                detail: "\(rounds) · no round was won",
                outcome: .stopped,
                winningSide: nil,
                placings: placings,
                rounds: lines
            )
        }
        // A shared top score is a tie however the table breaks it.
        let tied = standings.filter { $0.roundsWon == top.roundsWon && $0.gamesFor == top.gamesFor }

        return SessionResult(
            headline: tied.count > 1
                ? "\(tied.map(\.player.name).joined(separator: " & ")) tie"
                : "\(top.player.name) wins",
            // "2 of 3" rather than a bare 2: rounds won on their own say nothing about how
            // many somebody was on court for, and with a bench they are not the same number.
            score: "\(top.roundsWon) of \(top.roundsPlayed)",
            detail: rounds,
            outcome: tied.count > 1 ? .drawn : .won,
            winningSide: nil,
            placings: placings,
            rounds: lines
        )
    }

    /// Only the rounds that were actually played: one just drawn has nothing to report.
    private static func roundLines(_ session: FriendlySession) -> [RoundLine] {
        session.rounds.filter(\.wasPlayed).map { round in
            let sitting = session.sitOutNames(in: round)
            return RoundLine(
                id: round.index,
                title: "Round \(round.index + 1)",
                teams: session.teamNames(in: round),
                score: setScores(round.score).joined(separator: "  "),
                winner: round.score.winner,
                isStopped: round.isStopped,
                sitOuts: sitting.isEmpty ? nil : sitting.joined(separator: ", ")
            )
        }
    }

    // MARK: - Tournament

    private static func tournament(_ tournament: Tournament) -> SessionResult {
        let standings = Leaderboard.standings(for: tournament)
        let rounds = tournament.rounds.filter { !$0.isCancelled }.count
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
