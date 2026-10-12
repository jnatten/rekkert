import Foundation

public struct TournamentID: Hashable, Codable, Sendable {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
}

public struct CourtMatch: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { courtIndex }
    public var courtIndex: Int
    public var teams: BySide<[PlayerID]>
    public var state: PointCountState
    public var isConfirmed: Bool
    /// The score on a winner-court ladder, which plays games rather than points.
    public var games: TraditionalState?
    /// Who took the one point a court still level at the whistle plays to settle it.
    public var decider: TeamSide?

    public init(
        courtIndex: Int,
        teams: BySide<[PlayerID]>,
        state: PointCountState = PointCountState(),
        isConfirmed: Bool = false,
        games: TraditionalState? = nil,
        decider: TeamSide? = nil
    ) {
        self.courtIndex = courtIndex
        self.teams = teams
        self.state = state
        self.isConfirmed = isConfirmed
        self.games = games
        self.decider = decider
    }

    public func side(of player: PlayerID) -> TeamSide? {
        if teams.a.contains(player) { return .a }
        if teams.b.contains(player) { return .b }
        return nil
    }

    public func partner(of player: PlayerID) -> PlayerID? {
        guard let side = side(of: player) else { return nil }
        return teams[side].first { $0 != player }
    }

    public var allPlayers: [PlayerID] { teams.a + teams.b }
}

public struct Round: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var matches: [CourtMatch]
    public var sitOuts: [PlayerID]
    /// When the round was drawn, which is what the clock on the board counts from. Stamped
    /// by the reducer from the event that drew it, so every device reads the same one. Nil
    /// on a round drawn before the clock existed, and on a draw that is only being previewed.
    public var startedAt: Date?
    public var isCancelled: Bool
    /// The whistle has gone on a ladder round: no more games, only deciding points.
    public var isEnded: Bool
    public var clock: RoundClock?

    public init(
        index: Int,
        matches: [CourtMatch],
        sitOuts: [PlayerID],
        startedAt: Date? = nil,
        isCancelled: Bool = false,
        isEnded: Bool = false,
        clock: RoundClock? = nil
    ) {
        self.index = index
        self.matches = matches
        self.sitOuts = sitOuts
        self.startedAt = startedAt
        self.isCancelled = isCancelled
        self.isEnded = isEnded
        self.clock = clock
    }

    private enum CodingKeys: String, CodingKey { case index, matches, sitOuts, startedAt, isCancelled, isEnded, clock }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        matches = try container.decode([CourtMatch].self, forKey: .matches)
        sitOuts = try container.decode([PlayerID].self, forKey: .sitOuts)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        isCancelled = try container.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        isEnded = try container.decodeIfPresent(Bool.self, forKey: .isEnded) ?? false
        clock = try container.decodeIfPresent(RoundClock.self, forKey: .clock)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(matches, forKey: .matches)
        try container.encode(sitOuts, forKey: .sitOuts)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encode(isCancelled, forKey: .isCancelled)
        if isEnded { try container.encode(isEnded, forKey: .isEnded) }
        try container.encodeIfPresent(clock, forKey: .clock)
    }
}

public struct Tournament: Codable, Sendable, Hashable {
    public var id: TournamentID
    public var name: String
    public var format: TournamentFormat
    public var players: [Player]
    public var config: TournamentConfig
    public var rounds: [Round]
    public var isFinished: Bool
    /// Kept with the tournament rather than its settings because every round is drawn again
    /// each time the log is replayed: a tournament begun before the tie-break existed has to
    /// go on being drawn without it, or the rounds already played would be re-partnered.
    public var benchOrder: BenchOrder

    public init(
        id: TournamentID = TournamentID(),
        name: String = "",
        format: TournamentFormat,
        players: [Player] = [],
        config: TournamentConfig = TournamentConfig(),
        rounds: [Round] = [],
        isFinished: Bool = false,
        benchOrder: BenchOrder = .longestRested
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.players = players
        self.config = config
        self.rounds = rounds
        self.isFinished = isFinished
        self.benchOrder = benchOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, format, players, config, rounds, isFinished, benchOrder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TournamentID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        format = try container.decode(TournamentFormat.self, forKey: .format)
        players = try container.decode([Player].self, forKey: .players)
        config = try container.decode(TournamentConfig.self, forKey: .config)
        rounds = try container.decode([Round].self, forKey: .rounds)
        isFinished = try container.decode(Bool.self, forKey: .isFinished)
        benchOrder = try container.decodeIfPresent(BenchOrder.self, forKey: .benchOrder) ?? .fewestSitOuts
    }

    public var currentRound: Round? { rounds.last }

    public func round(at index: Int) -> Round? {
        rounds.indices.contains(index) ? rounds[index] : nil
    }

    /// Index of the round the app opens on.
    public var latestRoundIndex: Int { max(0, rounds.count - 1) }

    public func player(_ id: PlayerID) -> Player? {
        players.first { $0.id == id }
    }

    /// Which team that player is on for this court and round, or nil when they are elsewhere.
    public func side(of player: PlayerID, round: Int, court: Int) -> TeamSide? {
        self.round(at: round)?.matches.first { $0.courtIndex == court }?.side(of: player)
    }

    public func court(of player: PlayerID, round: Int) -> Int? {
        self.round(at: round)?.matches.first { $0.side(of: player) != nil }?.courtIndex
    }

    /// Courts that can be filled this round, limited both by physical courts and by
    /// having four players per court.
    public var playableCourts: Int {
        min(config.courtCount, players.count / 4)
    }

    /// How many sit out each round.
    public var benchSize: Int {
        max(0, players.count - playableCourts * 4)
    }

    /// Whether the round in play can still be drawn again around a different bench: nothing
    /// has been scored or settled in it, so nobody loses anything by it.
    public var canRedrawCurrentRound: Bool {
        guard !isFinished, let round = currentRound, !round.isCancelled else { return false }
        return round.matches.allSatisfy { !status(of: $0, in: round).wasPlayed && !$0.isConfirmed }
    }
}

public enum TournamentError: Error, Sendable, Hashable {
    case notEnoughPlayers(needed: Int, have: Int)
    case roundIncomplete
    /// Players picked to sit out who are not all this tournament's, not all different, or
    /// more than the bench holds.
    case invalidSitOuts
    /// A ladder of fixed pairs with somebody left over.
    case unpairedPlayer
}
