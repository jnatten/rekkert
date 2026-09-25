import Foundation

/// A saved configuration, stored without any of the identity a running session carries —
/// starting from a preset mints a fresh tournament each time rather than replaying an old
/// one.
public enum PresetConfiguration: Codable, Sendable, Hashable {
    case traditional(rules: TraditionalRules, teams: BySide<TeamInfo>)
    case winnerCourt(rules: WinnerCourtRules, teams: BySide<TeamInfo>)
    case tournament(format: TournamentFormat, name: String, players: [Player], config: TournamentConfig)
    case pointCount(rules: PointCountRules, teams: BySide<TeamInfo>)
    case friendly(name: String, players: [Player], rules: TraditionalRules)

    public func makeSetup() -> SessionSetup {
        switch self {
        case .traditional(let rules, let teams):
            .traditional(rules: rules, teams: teams)
        case .winnerCourt(let rules, let teams):
            .winnerCourt(rules: rules, teams: teams)
        case .pointCount(let rules, let teams):
            .pointCount(rules: rules, teams: teams)
        case .tournament(let format, let name, let players, let config):
            .tournament(Tournament(
                id: TournamentID(),
                name: name,
                format: format,
                players: players.map { Player(name: $0.name) },
                config: config
            ))
        case .friendly(let name, let players, let rules):
            .friendly(FriendlySession(
                id: FriendlyID(),
                name: name,
                rules: rules,
                players: players.map { Player(name: $0.name) }
            ))
        }
    }

    /// True when starting this needs a round drawn before there is anything to score.
    public var drawsRounds: Bool {
        switch self {
        case .tournament, .friendly: true
        case .traditional, .winnerCourt, .pointCount: false
        }
    }

    public var symbol: String {
        switch self {
        case .traditional: "figure.tennis"
        case .winnerCourt: "arrow.up.arrow.down"
        case .pointCount: "number"
        case .friendly: "shuffle"
        case .tournament(let format, _, _, _):
            format == .americano ? "arrow.triangle.2.circlepath" : "list.number"
        }
    }

    public var summary: String {
        switch self {
        case .traditional(let rules, _):
            "Best of \(rules.setsToWin * 2 - 1) · \(rules.deuceRule.displayName)"
        case .winnerCourt(let rules, _):
            "Winner court · \(rules.deuceRule.displayName)"
        case .pointCount(let rules, _):
            "Points · to \(rules.target)"
        case .tournament(let format, _, let players, let config):
            "\(format.displayName) · \(players.count) players · \(config.courtCount) court\(config.courtCount == 1 ? "" : "s") · to \(config.pointRules.target)"
        case .friendly(_, let players, let rules):
            "Friendly · \(players.count) players · " + (rules.setsToWin == 1
                ? "first to \(rules.gamesPerSet)"
                : "best of \(rules.setsToWin * 2 - 1)")
        }
    }
}

public struct Preset: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var configuration: PresetConfiguration
    public var lastUsed: Date?
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        configuration: PresetConfiguration,
        lastUsed: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.lastUsed = lastUsed
        self.useCount = useCount
    }
}

/// Presets are edited on the phone and read on both, so the whole library travels together
/// and the newer one wins. That keeps deletions from being resurrected by a stale copy,
/// which per-preset merging would have to carry tombstones to avoid — and it carries the
/// order they were dragged into along with them, so the wrist lists them the same way.
public struct PresetLibrary: Codable, Sendable, Hashable {
    public private(set) var presets: [Preset]
    public private(set) var updatedAt: Date

    public init(presets: [Preset] = [], updatedAt: Date = .distantPast) {
        self.presets = presets
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { presets.isEmpty }

    public mutating func save(_ preset: Preset, at date: Date = Date()) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.insert(preset, at: 0)
        }
        updatedAt = date
    }

    /// Changes the copy held here rather than taking a whole preset back, so an edit made
    /// in a sheet opened a while ago does not undo a start the watch has recorded since.
    public mutating func update(_ id: UUID, at date: Date = Date(), _ change: (inout Preset) -> Void) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        change(&presets[index])
        updatedAt = date
    }

    public mutating func remove(_ id: UUID, at date: Date = Date()) {
        presets.removeAll { $0.id == id }
        updatedAt = date
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, at date: Date = Date()) {
        let moving = source.map { presets[$0] }
        var remaining = presets.indices.filter { !source.contains($0) }.map { presets[$0] }
        remaining.insert(contentsOf: moving, at: destination - source.count(in: 0 ..< destination))
        presets = remaining
        updatedAt = date
    }

    public mutating func markUsed(_ id: UUID, at date: Date = Date()) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].useCount += 1
        presets[index].lastUsed = date
        updatedAt = date
    }

    public func adopting(_ other: PresetLibrary) -> PresetLibrary {
        other.updatedAt > updatedAt ? other : self
    }

    private enum CodingKeys: String, CodingKey {
        case presets, updatedAt, arranged
    }

    /// A library written before presets could be dragged into order has none of its own: the
    /// list sorted it, most recently used first, then the most used, then alphabetical. It is
    /// put in that order as it is read, so upgrading leaves the list looking as it did.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presets = try container.decode([Preset].self, forKey: .presets)
        self.presets = container.contains(.arranged) ? presets : presets.sorted(by: Self.mostRecentlyUsedFirst)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presets, forKey: .presets)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(true, forKey: .arranged)
    }

    private static func mostRecentlyUsedFirst(_ one: Preset, _ two: Preset) -> Bool {
        switch (one.lastUsed, two.lastUsed) {
        case (let a?, let b?) where a != b: return a > b
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        if one.useCount != two.useCount { return one.useCount > two.useCount }
        return one.name.localizedCaseInsensitiveCompare(two.name) == .orderedAscending
    }
}
