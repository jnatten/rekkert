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
