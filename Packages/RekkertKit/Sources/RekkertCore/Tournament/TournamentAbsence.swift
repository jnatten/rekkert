/// A stretch of rounds one player of an Americano or Mexicano misses: from the round they leave
/// before, until the round they are back for, or for the rest of the tournament (spec 008).
public struct TournamentAbsence: Codable, Sendable, Hashable {
    public var player: PlayerID
    /// The first round index they miss.
    public var from: Int
    /// The first round index they play again; nil while they are still away. Always after `from`.
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

/// An absence as the table shows it, numbered from 1.
public struct AwayStretch: Sendable, Hashable {
    public var firstMissed: Int
    public var backFor: Int?

    public init(firstMissed: Int, backFor: Int? = nil) {
        self.firstMissed = firstMissed
        self.backFor = backFor
    }
}

/// What marking a player as gone, or back, would do right now: what the confirmation says.
public struct AwayPreview: Sendable, Hashable {
    public struct StoppingCourt: Sendable, Hashable {
        /// Numbered from 1.
        public var court: Int
        public var score: BySide<Int>
    }

    public var player: PlayerID
    public var isAway: Bool
    /// The round, numbered from 1, the change takes effect from.
    public var fromRound: Int
    public var courtsBefore: Int
    public var courtsAfter: Int
    public var benchBefore: Int
    public var benchAfter: Int
    public var redrawsRoundInPlay: Bool
    public var stoppingCourt: StoppingCourt?
    public var isShortOfPlayers: Bool
}
