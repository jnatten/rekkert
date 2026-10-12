/// Where a court stands, whatever it is scored in.
public struct CourtStatus: Sendable, Hashable {
    /// Points, or games for a court scored in games.
    public var line: BySide<Int>
    public var wasPlayed: Bool
    public var isFinished: Bool
    public var winner: TeamSide?
    public var awaitsDecider: Bool

    public init(line: BySide<Int>, wasPlayed: Bool, isFinished: Bool, winner: TeamSide?, awaitsDecider: Bool = false) {
        self.line = line
        self.wasPlayed = wasPlayed
        self.isFinished = isFinished
        self.winner = winner
        self.awaitsDecider = awaitsDecider
    }
}

extension Tournament {
    public var isLadder: Bool { format == .winnerCourt }

    public var ladder: LadderRules? {
        isLadder ? config.ladder ?? LadderRules() : nil
    }

    public var pointEngine: PointCountEngine { PointCountEngine(rules: config.pointRules) }

    /// What a ladder court is scored by, or nil for a tournament played in points.
    public var gameEngine: TraditionalEngine? {
        ladder.map { TraditionalEngine(rules: $0.scoring) }
    }

    public func status(of match: CourtMatch, in round: Round) -> CourtStatus {
        if let engine = gameEngine {
            return Self.status(of: match, in: round, engine: engine)
        }
        let engine = pointEngine
        return CourtStatus(
            line: match.state.points,
            wasPlayed: match.state.points.total > 0,
            isFinished: engine.isFinished(match.state),
            winner: engine.winner(match.state)
        )
    }

    public func status(round index: Int, court: Int) -> CourtStatus? {
        guard let round = round(at: index), let match = round.matches.first(where: { $0.courtIndex == court }) else { return nil }
        return status(of: match, in: round)
    }

    public func serve(of match: CourtMatch) -> ServeState {
        if let engine = gameEngine {
            return engine.serve(match.games ?? TraditionalState())
        }
        return pointEngine.serve(match.state)
    }

    /// Every court played out or settled by hand.
    public func isDone(_ round: Round) -> Bool {
        round.matches.allSatisfy { $0.isConfirmed || status(of: $0, in: round).isFinished }
    }

    /// The draw itself goes ahead whatever the courts say, so that a point arriving late
    /// cannot take a round away; this is what asks for every court to be settled first.
    public var canDrawNextRound: Bool {
        guard !isFinished else { return false }
        guard let round = currentRound else { return playableCourts >= 1 }
        return round.isCancelled || isDone(round)
    }

    /// Once the whistle has gone, the game in progress goes to whoever leads it, then the
    /// sets, then the games, and on a court level on all of those the deciding point.
    private static func status(of match: CourtMatch, in round: Round, engine: TraditionalEngine) -> CourtStatus {
        let games = match.games ?? TraditionalState()
        let closed = round.isEnded ? engine.endingRound(games) : games
        let line = closed.completedSets.reduce(closed.games) { running, set in
            BySide(a: running.a + set.games.a, b: running.b + set.games.b)
        }
        let winner = closed.winner
            ?? (round.isEnded ? closed.setsWon.leader ?? line.leader ?? match.decider : nil)
        return CourtStatus(
            line: line,
            wasPlayed: !games.completedSets.isEmpty || games.games.total > 0 || games.points.total > 0
                || match.decider != nil,
            isFinished: winner != nil,
            winner: winner,
            awaitsDecider: round.isEnded && winner == nil
        )
    }
}

extension CourtMatch {
    public var serveOrder: ServeOrder {
        get { games?.serveOrder ?? state.serveOrder }
        set {
            if games != nil { games?.serveOrder = newValue } else { state.serveOrder = newValue }
        }
    }
}
