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

    public init(courtIndex: Int, teams: BySide<[PlayerID]>, state: PointCountState = PointCountState(), isConfirmed: Bool = false) {
        self.courtIndex = courtIndex
        self.teams = teams
        self.state = state
        self.isConfirmed = isConfirmed
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

    public init(index: Int, matches: [CourtMatch], sitOuts: [PlayerID]) {
        self.index = index
        self.matches = matches
        self.sitOuts = sitOuts
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

    public init(
        id: TournamentID = TournamentID(),
        name: String = "",
        format: TournamentFormat,
        players: [Player] = [],
        config: TournamentConfig = TournamentConfig(),
        rounds: [Round] = [],
        isFinished: Bool = false
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.players = players
        self.config = config
        self.rounds = rounds
        self.isFinished = isFinished
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

    /// Courts that can be filled this round, limited both by physical courts and by
    /// having four players per court.
    public var playableCourts: Int {
        min(config.courtCount, players.count / 4)
    }
}

public enum TournamentError: Error, Sendable, Hashable {
    case notEnoughPlayers(needed: Int, have: Int)
    case roundIncomplete
}
