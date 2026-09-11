public struct PointCountState: Codable, Sendable, Hashable {
    public var points: BySide<Int>
    public var firstServerIndex: Int

    public init(points: BySide<Int> = BySide(both: 0), firstServerIndex: Int = 0) {
        self.points = points
        self.firstServerIndex = firstServerIndex
    }
}

public struct PointCountEngine: Sendable, Hashable {
    public let rules: PointCountRules

    public init(rules: PointCountRules) {
        self.rules = rules
    }

    public func initialState(firstServerIndex: Int = 0) -> PointCountState {
        PointCountState(firstServerIndex: firstServerIndex)
    }

    public func isFinished(_ state: PointCountState) -> Bool {
        switch rules.targetKind {
        case .totalPointsPlayed: state.points.total >= rules.target
        case .firstToTarget: max(state.points.a, state.points.b) >= rules.target
        }
    }

    /// `nil` while the round is unfinished, and also for a finished draw — which
    /// `.totalPointsPlayed` allows whenever the target is even.
    public func winner(_ state: PointCountState) -> TeamSide? {
        isFinished(state) ? state.points.leader : nil
    }

    public func pointsRemaining(_ state: PointCountState) -> Int {
        switch rules.targetKind {
        case .totalPointsPlayed:
            max(0, rules.target - state.points.total)
        case .firstToTarget:
            max(0, rules.target - max(state.points.a, state.points.b))
        }
    }

    public func serve(_ state: PointCountState) -> ServeState {
        let slot = ServeRotation.pointCountingSlot(
            totalPointsPlayed: state.points.total,
            servesPerTeam: rules.servesPerTeam,
            startIndex: state.firstServerIndex
        )
        return ServeState(slot: slot, court: state.points.total.isMultiple(of: 2) ? .deuce : .ad)
    }

    public func scoringPoint(_ side: TeamSide, in state: PointCountState) -> PointCountState {
        guard !isFinished(state) else { return state }
        var next = state
        next.points[side] += 1
        return next
    }

    /// Direct score entry from the organiser's court list. Clamped to what the rules allow,
    /// so a typo can never put a round into an unreachable state.
    public func settingScore(_ points: BySide<Int>, in state: PointCountState) -> PointCountState {
        var next = state
        var clamped = BySide(a: max(0, points.a), b: max(0, points.b))

        switch rules.targetKind {
        case .firstToTarget:
            clamped.a = min(clamped.a, rules.target)
            clamped.b = min(clamped.b, rules.target)
            if clamped.a == rules.target, clamped.b == rules.target {
                clamped.b = rules.target - 1
            }
        case .totalPointsPlayed:
            clamped.a = min(clamped.a, rules.target)
            clamped.b = min(clamped.b, rules.target - clamped.a)
        }
        next.points = clamped
        return next
    }
}
