public struct TournamentAbsence: Codable, Sendable, Hashable {
    public var player: PlayerID
    /// The first round index they miss.
    public var from: Int
    /// The first round index they play again, after `from`; nil while still away.
    public var until: Int?

    public init(player: PlayerID, from: Int, until: Int? = nil) {
        self.player = player
        self.from = from
        self.until = until
    }

    public func covers(round index: Int) -> Bool {
        from <= index && until.map { index < $0 } != false
    }
}

public struct AwayStretch: Sendable, Hashable {
    public var firstMissed: Int
    public var backFor: Int?

    public init(firstMissed: Int, backFor: Int? = nil) {
        self.firstMissed = firstMissed
        self.backFor = backFor
    }
}

public struct AwayPreview: Sendable, Hashable {
    public struct StoppingCourt: Sendable, Hashable {
        public var court: Int
        public var score: BySide<Int>
    }

    public var player: PlayerID
    public var isAway: Bool
    public var fromRound: Int
    public var courtsBefore: Int
    public var courtsAfter: Int
    public var benchBefore: Int
    public var benchAfter: Int
    public var redrawsRoundInPlay: Bool
    public var stoppingCourt: StoppingCourt?
    public var isShortOfPlayers: Bool
}
