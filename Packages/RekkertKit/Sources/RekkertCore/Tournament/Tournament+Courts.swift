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
    public var pointEngine: PointCountEngine { PointCountEngine(rules: config.pointRules) }

    public func status(of match: CourtMatch, in round: Round) -> CourtStatus {
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
        pointEngine.serve(match.state)
    }

    /// Every court played out or settled by hand.
    public func isDone(_ round: Round) -> Bool {
        round.matches.allSatisfy { $0.isConfirmed || status(of: $0, in: round).isFinished }
    }
}

extension CourtMatch {
    public var serveOrder: ServeOrder {
        get { state.serveOrder }
        set { state.serveOrder = newValue }
    }
}
