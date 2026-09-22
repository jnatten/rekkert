import Foundation

/// Everything a scoreboard needs to draw itself, derived from session state. Keeping this
/// in the core means the phone and the watch render the same truth from the same code.
public struct ScoreboardSnapshot: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case traditional
        case winnerCourt
        case tournament
        case pointCount
        case friendly
    }

    public var kind: Kind
    public var courtIndex: Int
    public var courtLabel: String?
    public var teamNames: BySide<String>
    /// The two big numbers.
    public var points: BySide<PointDisplay>
    /// Games in the current set. Traditional matches only.
    public var games: BySide<Int>?
    public var completedSets: [SetResult]
    public var detail: String
    public var serving: TeamSide?
    /// Which half the serve is struck from, as the server sees it: deuce is their right.
    public var servingCourt: ServeCourt?
    public var servingPlayer: String?
    /// Whether "swap serving player" has anyone to swap: the serving side has two named
    /// players and the board is still live.
    public var canSwapServingPlayer: Bool
    public var isSuddenDeath: Bool
    public var suddenDeathCourt: ServeCourt?
    public var isLocked: Bool
    public var isFinished: Bool
    public var winner: TeamSide?
    /// When the clock on the board started counting: this round, for the modes that play in
    /// rounds, and the session for the ones that do not. `nil` once there is nothing to
    /// time — a board that is over or being looked back at, or a session played before the
    /// clock existed. The date is state; the ticking is the view's business.
    public var clockStart: Date?
    /// How many times the two sides have changed ends. Zero for the modes that have no ends
    /// rule, and for the matches that were not set up to use one.
    ///
    /// The count rather than a flag: which way round the court is reads off its parity, and
    /// a changeover to call out is the one step it takes forward. One number cannot disagree
    /// with itself the way two derived flags can.
    public var changeovers = 0

    /// Which way round the court is standing now.
    public var endsSwapped: Bool { !changeovers.isMultiple(of: 2) }

    /// The two big numbers as drawn.
    public var primary: BySide<String> { points.map(\.text) }

    /// `round` selects which round to render; `nil` means whichever is current. Ignored
    /// by traditional matches.
    public static func make(from state: SessionState, round: Int? = nil, court: Int = 0) -> ScoreboardSnapshot? {
        switch state {
        case .traditional(let session): traditional(session)
        case .tournament(let tournament): tournamentCourt(tournament, round: round, court: court)
        case .winnerCourt(let session): winnerCourt(session)
        case .pointCount(let session): pointCount(session)
        case .friendly(let session): friendly(session, round: round)
        }
    }

    private static func traditional(_ session: TraditionalSession) -> ScoreboardSnapshot {
        let engine = session.engine
        let score = session.score
        let serve = engine.serve(score)
        let names = BySide(a: session.teams.a.name, b: session.teams.b.name)

        return ScoreboardSnapshot(
            kind: .traditional,
            courtIndex: 0,
            courtLabel: nil,
            teamNames: names,
            points: engine.pointDisplay(score),
            games: score.games,
            completedSets: score.completedSets,
            detail: detail(for: session, engine: engine),
            serving: score.isFinished ? nil : serve.slot.team,
            servingCourt: score.isFinished ? nil : serve.court,
            servingPlayer: name(session.teams[serve.slot.team].players, at: serve.slot.playerIndex),
            canSwapServingPlayer: !score.isFinished && hasTwoNamed(session.teams[serve.slot.team].players),
            isSuddenDeath: engine.isSuddenDeathPoint(score),
            suddenDeathCourt: score.suddenDeathCourt,
            isLocked: score.isFinished,
            isFinished: score.isFinished,
            winner: score.winner,
            clockStart: score.isFinished ? nil : session.startedAt,
            changeovers: engine.changeovers(score)
        )
    }

    /// A friendly round is an ordinary match between partnerships drawn for it, so this is
    /// the traditional scoreboard with the round written on it and the serve resolved against
    /// teams that may hold only one player.
    private static func friendly(_ session: FriendlySession, round index: Int?) -> ScoreboardSnapshot? {
        let roundIndex = index ?? session.currentIndex
        guard let round = session.round(at: roundIndex),
              let match = session.match(at: roundIndex) else { return nil }

        var snapshot = traditional(match)
        snapshot.kind = .friendly
        snapshot.detail = detail(for: session, round: round)
        snapshot.isLocked = round.isFinished
        snapshot.isFinished = round.isFinished
        // `match(at:)` packages the round as a match and has no stamp of its own to carry,
        // so the round's own is put back here.
        snapshot.clockStart = round.isFinished ? nil : round.startedAt

        if round.isFinished {
            snapshot.serving = nil
            snapshot.servingCourt = nil
            snapshot.servingPlayer = nil
            snapshot.canSwapServingPlayer = false
        } else {
            // The padel rotation asks for the second player on a side, which a singles team
            // has not got — so the one who is there serves every time.
            let serve = match.engine.serve(round.score)
            let players = match.teams[serve.slot.team].players
            snapshot.servingPlayer = name(players, at: serve.slot.playerIndex) ?? players.first
            snapshot.canSwapServingPlayer = session.teamSize == 2 && hasTwoNamed(players)
        }
        return snapshot
    }

    private static func detail(for session: FriendlySession, round: FriendlyRound) -> String {
        let engine = session.engine
        let number = "Round \(round.index + 1)"
        if let winner = round.score.winner {
            return "\(number) · \(session.names(winner, in: round)) won"
        }
        if round.isStopped {
            return "\(number) · stopped"
        }
        if case .tiebreak(let target) = engine.phase(round.score) {
            return engine.isDecidingSet(round.score) && target != session.rules.tiebreakPoints
                ? "\(number) · super tiebreak to \(target)"
                : "\(number) · tiebreak to \(target)"
        }
        if engine.isSuddenDeathPoint(round.score) {
            return "\(number) · sudden death"
        }
        if session.rules.setsToWin > 1 {
            return "\(number) · set \(round.score.completedSets.count + 1)"
        }
        return number
    }

    private static func winnerCourt(_ session: WinnerCourtSession) -> ScoreboardSnapshot {
        let engine = session.engine
        let score = session.score
        let serve = engine.serve(score)

        return ScoreboardSnapshot(
            kind: .winnerCourt,
            courtIndex: 0,
            courtLabel: nil,
            teamNames: BySide(a: session.teams.a.name, b: session.teams.b.name),
            points: engine.pointDisplay(score),
            games: score.games,
            completedSets: score.completedSets,
            detail: engine.isSuddenDeathPoint(score)
                ? "Round \(session.roundNumber) · sudden death"
                : "Round \(session.roundNumber)",
            serving: session.isFinished ? nil : serve.slot.team,
            servingCourt: session.isFinished ? nil : serve.court,
            servingPlayer: name(session.teams[serve.slot.team].players, at: serve.slot.playerIndex),
            canSwapServingPlayer: !session.isFinished && hasTwoNamed(session.teams[serve.slot.team].players),
            isSuddenDeath: engine.isSuddenDeathPoint(score),
            suddenDeathCourt: score.suddenDeathCourt,
            isLocked: session.isFinished,
            isFinished: session.isFinished,
            winner: nil,
            clockStart: session.isFinished ? nil : session.roundStartedAt
        )
    }

    private static func pointCount(_ session: PointCountSession) -> ScoreboardSnapshot {
        let engine = session.engine
        let serve = engine.serve(session.score)
        let names = BySide(a: session.teams.a.name, b: session.teams.b.name)

        return ScoreboardSnapshot(
            kind: .pointCount,
            courtIndex: 0,
            courtLabel: nil,
            teamNames: names,
            points: session.score.points.map { PointDisplay.count($0) },
            games: nil,
            completedSets: [],
            detail: detail(for: session, names: names),
            serving: session.isFinished ? nil : serve.slot.team,
            servingCourt: session.isFinished ? nil : serve.court,
            servingPlayer: name(session.teams[serve.slot.team].players, at: serve.slot.playerIndex),
            canSwapServingPlayer: !session.isFinished && hasTwoNamed(session.teams[serve.slot.team].players),
            isSuddenDeath: false,
            suddenDeathCourt: nil,
            isLocked: session.isFinished,
            isFinished: session.isFinished,
            winner: session.winner,
            clockStart: session.isFinished ? nil : session.startedAt
        )
    }

    private static func detail(for session: PointCountSession, names: BySide<String>) -> String {
        guard session.isFinished else {
            return "\(session.engine.pointsRemaining(session.score)) to play"
        }
        guard let winner = session.winner else { return "All square" }
        return "\(names[winner]) won"
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
        let servingSide = match.teams[serve.slot.team]
        let servingID = servingSide[safe: serve.slot.playerIndex]
        let isLive = !match.isConfirmed && !engine.isFinished(match.state)

        return ScoreboardSnapshot(
            kind: .tournament,
            courtIndex: court,
            courtLabel: "Court \(court + 1)",
            teamNames: names,
            points: match.state.points.map { PointDisplay.count($0) },
            games: nil,
            completedSets: [],
            detail: "Round \(round.index + 1) · \(remaining) to play",
            serving: engine.isFinished(match.state) ? nil : serve.slot.team,
            servingCourt: engine.isFinished(match.state) ? nil : serve.court,
            servingPlayer: servingID.flatMap { tournament.player($0) }?.name,
            canSwapServingPlayer: isLive && servingSide.count >= 2
                && servingSide.allSatisfy { tournament.player($0) != nil },
            isSuddenDeath: false,
            suddenDeathCourt: nil,
            isLocked: match.isConfirmed,
            isFinished: engine.isFinished(match.state),
            winner: engine.winner(match.state),
            // The clock belongs to the round, so every court in it reads the same one.
            clockStart: isLive ? round.startedAt : nil
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

    /// A blank slot is nobody rather than an empty name: the line-up is positional, so the
    /// second player can be typed without the first.
    private static func name(_ players: [String], at index: Int) -> String? {
        guard let name = players[safe: index], !name.isEmpty else { return nil }
        return name
    }

    private static func hasTwoNamed(_ players: [String]) -> Bool {
        players.count >= 2 && !players[0].isEmpty && !players[1].isEmpty
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
