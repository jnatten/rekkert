import Foundation

public struct FriendlyID: Hashable, Codable, Sendable {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
}

/// One round of a friendly, which is a match in its own right: the partnerships drawn for it
/// and the score they played to. Whoever was over the four seats sat it out.
public struct FriendlyRound: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var teams: BySide<[PlayerID]>
    public var sitOuts: [PlayerID]
    public var score: TraditionalState
    /// Called off where it stood rather than played out. The games still count; nobody won it.
    public var isStopped: Bool
    /// When the round was drawn, which is what the clock on the board counts from. Stamped by
    /// the reducer from the event that drew it, so both devices read the same one.
    public var startedAt: Date?

    public init(
        index: Int,
        teams: BySide<[PlayerID]>,
        sitOuts: [PlayerID] = [],
        score: TraditionalState = TraditionalState(),
        isStopped: Bool = false,
        startedAt: Date? = nil
    ) {
        self.index = index
        self.teams = teams
        self.sitOuts = sitOuts
        self.score = score
        self.isStopped = isStopped
        self.startedAt = startedAt
    }

    /// Over, either way: won outright or stopped short. Nothing more is scored on it.
    public var isFinished: Bool { score.isFinished || isStopped }

    /// Whether anything actually happened in it, as opposed to it merely having been drawn.
    public var wasPlayed: Bool {
        !score.completedSets.isEmpty || score.games.total > 0 || score.points.total > 0
    }

    /// Games won across the round, counting the set in progress — a round stopped part-way
    /// still played the games it played.
    public var games: BySide<Int> {
        score.completedSets.reduce(score.games) { running, set in
            BySide(a: running.a + set.games.a, b: running.b + set.games.b)
        }
    }

    private enum CodingKeys: String, CodingKey { case index, teams, sitOuts, score, isStopped, startedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        teams = try container.decode(BySide<[PlayerID]>.self, forKey: .teams)
        sitOuts = try container.decodeIfPresent([PlayerID].self, forKey: .sitOuts) ?? []
        score = try container.decode(TraditionalState.self, forKey: .score)
        isStopped = try container.decodeIfPresent(Bool.self, forKey: .isStopped) ?? false
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
    }
}

/// A friendly: a group of people playing real matches, re-partnered after every one of them,
/// for as long as they feel like it. The rules are a match's rules, so a round here and a
/// round in Match mode are scored by exactly the same engine.
///
/// Four or more play doubles; two or three play singles. Anyone over the seats sits out, and
/// the bench goes to whoever has sat out least.
public struct FriendlySession: Codable, Sendable, Hashable {
    public var id: FriendlyID
    public var name: String
    public var rules: TraditionalRules
    public var players: [Player]
    /// The last one is the one in play.
    public var rounds: [FriendlyRound]
    public var isFinished: Bool

    public init(
        id: FriendlyID = FriendlyID(),
        name: String = "",
        rules: TraditionalRules = TraditionalRules(setsToWin: 1),
        players: [Player] = [],
        rounds: [FriendlyRound] = [],
        isFinished: Bool = false
    ) {
        self.id = id
        self.name = name
        self.rules = rules
        self.players = players
        self.rounds = rounds
        self.isFinished = isFinished
    }

    public var engine: TraditionalEngine { TraditionalEngine(rules: rules) }

    /// Doubles once there are four of you; singles before that.
    public var teamSize: Int { players.count >= 4 ? 2 : 1 }
    public var seats: Int { teamSize * 2 }
    public var sitOutCount: Int { max(0, players.count - seats) }
    public var canPlay: Bool { players.count >= 2 }

    public var currentIndex: Int { max(0, rounds.count - 1) }
    public var currentRound: FriendlyRound? { rounds.last }
    public var roundNumber: Int { rounds.count }

    public func round(at index: Int) -> FriendlyRound? {
        rounds.indices.contains(index) ? rounds[index] : nil
    }

    public func player(_ id: PlayerID) -> Player? {
        players.first { $0.id == id }
    }

    /// A name for somebody who is no longer on the list. Shown rather than dropped, so a
    /// round played weeks ago never quietly loses one of the four people who played it.
    public func name(_ id: PlayerID) -> String { player(id)?.name ?? "—" }

    /// "Jonas & Ola", or just "Jonas" in singles.
    public func names(_ side: TeamSide, in round: FriendlyRound) -> String {
        round.teams[side].map(name).joined(separator: " & ")
    }

    public func teamNames(in round: FriendlyRound) -> BySide<String> {
        BySide(a: names(.a, in: round), b: names(.b, in: round))
    }

    public func sitOutNames(in round: FriendlyRound) -> [String] {
        round.sitOuts.map(name)
    }

    /// The round packaged as an ordinary match, so every piece of traditional scoring,
    /// scoreboard and umpire code serves a friendly unchanged.
    func match(at index: Int) -> TraditionalSession? {
        guard let round = round(at: index) else { return nil }
        return TraditionalSession(
            rules: rules,
            teams: BySide(
                a: TeamInfo(name: names(.a, in: round), players: round.teams.a.map(name)),
                b: TeamInfo(name: names(.b, in: round), players: round.teams.b.map(name))
            ),
            score: round.score,
            isStopped: round.isStopped
        )
    }

    /// The round that drawing the next one would produce. The draw is a pure function of
    /// the session, so this is the same answer the event will reach — which is what lets the
    /// button offering the next round name the partnership before anybody commits to it.
    ///
    /// Unstamped: nothing has started, so it has no `startedAt` to carry.
    public func nextDraw() -> FriendlyRound? {
        try? FriendlyScheduler.nextRound(for: self)
    }

    /// Whether anything was actually played, as opposed to merely drawn.
    public var wasPlayed: Bool { rounds.contains { $0.wasPlayed } }
}
