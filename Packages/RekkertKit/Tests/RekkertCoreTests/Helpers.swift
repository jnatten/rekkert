import RekkertCore

extension TraditionalEngine {
    func play(_ sequence: [TeamSide], from state: TraditionalState? = nil) -> TraditionalState {
        sequence.reduce(state ?? initialState()) { scoringPoint($1, in: $0) }
    }

    /// Wins `count` whole games for `side` from `state`, four straight points each.
    func winGames(_ count: Int, for side: TeamSide, from state: TraditionalState) -> TraditionalState {
        (0 ..< count).reduce(state) { current, _ in
            play(Array(repeating: side, count: 4), from: current)
        }
    }
}

extension PointCountEngine {
    func play(_ sequence: [TeamSide], from state: PointCountState? = nil) -> PointCountState {
        sequence.reduce(state ?? initialState()) { scoringPoint($1, in: $0) }
    }
}

func repeated(_ pattern: [TeamSide], _ times: Int) -> [TeamSide] {
    (0 ..< times).flatMap { _ in pattern }
}

extension MatchLog {
    /// Mirrors `MatchStore.nextRound()`: the draw is addressed to the round on screen now.
    @discardableResult
    mutating func drawRound(from device: DeviceID) -> MatchEvent {
        guard case .tournament(let tournament)? = SessionReducer.state(of: self) else {
            return append(.nextRound(after: -1), from: device)
        }
        return append(.nextRound(after: tournament.rounds.count - 1), from: device)
    }

    /// Mirrors `MatchStore.nextRound()` for a friendly, which addresses the round on screen
    /// now so two devices tapping at once still produce one.
    @discardableResult
    mutating func drawFriendlyRound(from device: DeviceID) -> MatchEvent {
        guard case .friendly(let session)? = SessionReducer.state(of: self) else {
            return append(.nextRound(after: -1), from: device)
        }
        return append(.nextRound(after: session.rounds.count - 1), from: device)
    }

    /// Mirrors `MatchStore.endRound()`.
    @discardableResult
    mutating func blowWhistle(from device: DeviceID) -> MatchEvent {
        guard case .winnerCourt(let session)? = SessionReducer.state(of: self) else {
            return append(.endRound(round: 0), from: device)
        }
        return append(.endRound(round: session.completedRounds.count), from: device)
    }
}
