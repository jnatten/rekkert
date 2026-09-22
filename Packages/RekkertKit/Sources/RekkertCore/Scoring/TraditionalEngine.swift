public struct TraditionalEngine: Sendable, Hashable {
    public let rules: TraditionalRules

    public init(rules: TraditionalRules) {
        self.rules = rules
    }

    public func initialState(firstServerIndex: Int = 0) -> TraditionalState {
        TraditionalState(firstServerIndex: firstServerIndex)
    }

    // MARK: - Derived

    public func isDecidingSet(_ state: TraditionalState) -> Bool {
        let won = state.setsWon
        return won.a == rules.setsToWin - 1 && won.b == rules.setsToWin - 1
    }

    public func phase(_ state: TraditionalState) -> GamePhase {
        if state.isFinished { return .finished }
        if isDecidingSet(state), case .superTiebreak(let target) = rules.decidingSet {
            return .tiebreak(target: target)
        }
        if let at = rules.tiebreakAtGames, state.games.a == at, state.games.b == at {
            return .tiebreak(target: rules.tiebreakPoints)
        }
        return .game
    }

    /// True when the very next point decides the game outright.
    public func isSuddenDeathPoint(_ state: TraditionalState) -> Bool {
        guard case .game = phase(state) else { return false }
        guard let limit = rules.deuceRule.deucesBeforeSuddenDeath else { return false }
        return state.points.isLevel && state.points.a >= 3 && state.deuceCount > limit
    }

    public func pointDisplay(_ state: TraditionalState) -> BySide<PointDisplay> {
        if case .tiebreak = phase(state) {
            return BySide(a: .count(state.points.a), b: .count(state.points.b))
        }
        guard state.points.a >= 3, state.points.b >= 3 else {
            return BySide(a: .ladder(state.points.a), b: .ladder(state.points.b))
        }
        guard let leader = state.points.leader else {
            return BySide(a: .forty, b: .forty)
        }
        var display = BySide<PointDisplay>(both: .forty)
        display[leader] = .advantage
        return display
    }

    public func totalGamesPlayed(_ state: TraditionalState) -> Int {
        state.completedSets.reduce(0) { $0 + $1.games.total } + state.games.total
    }

    public func serve(_ state: TraditionalState) -> ServeState {
        var index = state.firstServerIndex + totalGamesPlayed(state)
        var court: ServeCourt = state.points.total.isMultiple(of: 2) ? .deuce : .ad

        if case .tiebreak = phase(state) {
            index += (state.points.total + 1) / 2
        } else if isSuddenDeathPoint(state), let chosen = state.suddenDeathCourt {
            court = chosen
        }
        return ServeState(slot: ServeRotation.slot(at: index, swapping: state.serversSwapped), court: court)
    }

    /// How many times the two sides have walked over. Counted off the score rather than
    /// remembered, so undo, a late joiner and a replayed log all arrive at the same court
    /// without an event of their own to carry it.
    ///
    /// Games are counted across the match rather than within each set. A set that ran to an
    /// odd number of games leaves everyone on the wrong end for the next one, and one running
    /// total carries that over by itself.
    public func changeovers(_ state: TraditionalState) -> Int {
        switch rules.changeEnds {
        case .off:
            0
        case .everySet:
            // Nobody walks over to shake hands, so the set that won the match is not one.
            max(0, state.completedSets.count - (state.isFinished ? 1 : 0))
        case .oddGames:
            gameChangeovers(state) + tiebreakChangeovers(state)
        }
    }

    /// Which way round the court is standing now.
    public func endsSwapped(_ state: TraditionalState) -> Bool {
        !changeovers(state).isMultiple(of: 2)
    }

    /// One after the first game, one after the third, and so on. Halved rather than taken as
    /// a parity: the walks come a pair of games apart, so which end you are at repeats every
    /// four games rather than every two.
    private func gameChangeovers(_ state: TraditionalState) -> Int {
        let played = totalGamesPlayed(state) - (state.isFinished ? 1 : 0)
        return (max(0, played) + 1) / 2
    }

    /// Six points at a time inside a tiebreak. A finished one drops the walk that would have
    /// landed on its very last point: that walk is the one between the sets, and the game the
    /// tiebreak just added has counted it already.
    private func tiebreakChangeovers(_ state: TraditionalState) -> Int {
        var live = 0
        if case .tiebreak = phase(state) { live = state.points.total / 6 }
        return state.completedSets.reduce(live) { running, set in
            guard let tiebreak = set.tiebreak else { return running }
            return running + (tiebreak.total - 1) / 6
        }
    }

    // MARK: - Mutation

    public func scoringPoint(_ side: TeamSide, in state: TraditionalState) -> TraditionalState {
        guard !state.isFinished else { return state }
        var next = state

        switch phase(state) {
        case .finished:
            return state

        case .tiebreak(let target):
            next.points[side] += 1
            if next.points[side] >= target, next.points.lead(side) >= 2 {
                let tiebreak = next.points
                next.games[side] += 1
                completeSet(&next, winner: side, tiebreak: tiebreak)
            }

        case .game:
            let suddenDeath = isSuddenDeathPoint(state)
            next.points[side] += 1
            next.suddenDeathCourt = nil

            if suddenDeath || (next.points[side] >= 4 && next.points.lead(side) >= 2) {
                winGame(&next, side: side)
            } else if next.points.isLevel, next.points.a >= 3 {
                next.deuceCount += 1
            }
        }
        return next
    }

    /// Closes the current set where it stands — the whistle in winner court. The game in
    /// progress goes to whoever is ahead in it; if the two are level it is discarded.
    public func endingRound(_ state: TraditionalState) -> TraditionalState {
        guard !state.isFinished else { return state }
        guard state.games.total > 0 || state.points.total > 0 else { return state }

        var next = state
        if let leading = next.points.leader {
            next.games[leading] += 1
        }
        completeSet(&next, winner: next.games.leader, tiebreak: nil)
        return next
    }

    private func winGame(_ state: inout TraditionalState, side: TeamSide) {
        state.games[side] += 1
        state.points = BySide(both: 0)
        state.deuceCount = 0
        state.suddenDeathCourt = nil

        if state.games[side] >= rules.gamesPerSet, state.games.lead(side) >= 2 {
            completeSet(&state, winner: side, tiebreak: nil)
        }
    }

    private func completeSet(_ state: inout TraditionalState, winner: TeamSide?, tiebreak: BySide<Int>?) {
        state.completedSets.append(SetResult(games: state.games, tiebreak: tiebreak, winner: winner))
        state.games = BySide(both: 0)
        state.points = BySide(both: 0)
        state.deuceCount = 0
        state.suddenDeathCourt = nil

        if let winner, state.setsWon[winner] >= rules.setsToWin {
            state.winner = winner
        }
    }
}
