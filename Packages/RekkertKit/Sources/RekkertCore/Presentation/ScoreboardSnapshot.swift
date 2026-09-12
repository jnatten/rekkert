/// Everything a scoreboard needs to draw itself, derived from session state. Keeping this
/// in the core means the phone and the watch render the same truth from the same code.
public struct ScoreboardSnapshot: Sendable, Hashable {
    public var courtIndex: Int
    public var courtLabel: String?
    public var teamNames: BySide<String>
    /// The two big numbers.
    public var primary: BySide<String>
    /// Games in the current set. Traditional matches only.
    public var games: BySide<Int>?
    public var completedSets: [SetResult]
    public var detail: String
    public var serving: TeamSide?
    /// Which half the serve is struck from, as the server sees it: deuce is their right.
    public var servingCourt: ServeCourt?
    public var servingPlayer: String?
    public var isSuddenDeath: Bool
    public var suddenDeathCourt: ServeCourt?
    public var isLocked: Bool
    public var isFinished: Bool
    public var winner: TeamSide?

    /// `round` selects which round to render; `nil` means whichever is current. Ignored
    /// by traditional matches.
    public static func make(from state: SessionState, round: Int? = nil, court: Int = 0) -> ScoreboardSnapshot? {
        switch state {
        case .traditional(let session): traditional(session)
        case .tournament(let tournament): tournamentCourt(tournament, round: round, court: court)
        case .winnerCourt(let session): winnerCourt(session)
        }
    }

    private static func traditional(_ session: TraditionalSession) -> ScoreboardSnapshot {
        let engine = session.engine
        let score = session.score
        let serve = engine.serve(score)
        let names = BySide(a: session.teams.a.name, b: session.teams.b.name)

        return ScoreboardSnapshot(
            courtIndex: 0,
            courtLabel: nil,
            teamNames: names,
            primary: engine.pointDisplay(score).map(\.text),
            games: score.games,
            completedSets: score.completedSets,
            detail: detail(for: session, engine: engine),
            serving: score.isFinished ? nil : serve.slot.team,
            servingCourt: score.isFinished ? nil : serve.court,
            servingPlayer: playerName(at: serve.slot, teams: session.teams),
            isSuddenDeath: engine.isSuddenDeathPoint(score),
            suddenDeathCourt: score.suddenDeathCourt,
            isLocked: score.isFinished,
            isFinished: score.isFinished,
            winner: score.winner
        )
    }

    private static func winnerCourt(_ session: WinnerCourtSession) -> ScoreboardSnapshot {
        let engine = session.engine
        let score = session.score
        let serve = engine.serve(score)

        return ScoreboardSnapshot(
            courtIndex: 0,
            courtLabel: nil,
            teamNames: BySide(a: session.teams.a.name, b: session.teams.b.name),
            primary: engine.pointDisplay(score).map(\.text),
            games: score.games,
            completedSets: score.completedSets,
            detail: engine.isSuddenDeathPoint(score)
                ? "Round \(session.roundNumber) · sudden death"
                : "Round \(session.roundNumber)",
            serving: session.isFinished ? nil : serve.slot.team,
            servingCourt: session.isFinished ? nil : serve.court,
            servingPlayer: session.teams[serve.slot.team].players[safe: serve.slot.playerIndex],
            isSuddenDeath: engine.isSuddenDeathPoint(score),
            suddenDeathCourt: score.suddenDeathCourt,
            isLocked: session.isFinished,
            isFinished: session.isFinished,
            winner: nil
        )
    }

    private static func tournamentCourt(_ tournament: Tournament, round index: Int?, court: Int) -> ScoreboardSnapshot? {
        guard let round = index.map({ tournament.round(at: $0) }) ?? tournament.currentRound,
              let match = round.matches.first(where: { $0.courtIndex == court })
        else { return nil }

        let engine = PointCountEngine(rules: tournament.config.pointRules)
        let serve = engine.serve(match.state)
        let names = match.teams.map { team in
            team.compactMap { tournament.player($0)?.name }.joined(separator: " & ")
        }
        let remaining = engine.pointsRemaining(match.state)
        let servingID = match.teams[serve.slot.team][safe: serve.slot.playerIndex]

        return ScoreboardSnapshot(
            courtIndex: court,
            courtLabel: "Court \(court + 1)",
            teamNames: names,
            primary: match.state.points.map(String.init),
            games: nil,
            completedSets: [],
            detail: "Round \(round.index + 1) · \(remaining) to play",
            serving: engine.isFinished(match.state) ? nil : serve.slot.team,
            servingCourt: engine.isFinished(match.state) ? nil : serve.court,
            servingPlayer: servingID.flatMap { tournament.player($0) }?.name,
            isSuddenDeath: false,
            suddenDeathCourt: nil,
            isLocked: match.isConfirmed,
            isFinished: engine.isFinished(match.state),
            winner: engine.winner(match.state)
        )
    }

    private static func detail(for session: TraditionalSession, engine: TraditionalEngine) -> String {
        let score = session.score
        if let winner = score.winner {
            return "\(session.teams[winner].name) won"
        }
        if case .tiebreak(let target) = engine.phase(score) {
            return engine.isDecidingSet(score) && target != session.rules.tiebreakPoints
                ? "Super tiebreak to \(target)"
                : "Tiebreak to \(target)"
        }
        let setNumber = score.completedSets.count + 1
        if engine.isSuddenDeathPoint(score) {
            return "Set \(setNumber) · sudden death"
        }
        return "Set \(setNumber)"
    }

    private static func playerName(at slot: ServeSlot, teams: BySide<TeamInfo>) -> String? {
        teams[slot.team].players[safe: slot.playerIndex]
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
