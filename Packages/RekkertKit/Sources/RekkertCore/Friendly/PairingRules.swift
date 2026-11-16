import Foundation

public struct PairingRule: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case apart
        case together
    }

    public let id: UUID
    public var kind: Kind
    /// Sorted, so two devices holding the same rule encode the same bytes.
    public var players: [PlayerID] {
        get { members }
        set { members = newValue.sorted() }
    }

    private var members: [PlayerID]

    public init(id: UUID = UUID(), kind: Kind, players: [PlayerID]) {
        self.id = id
        self.kind = kind
        members = players.sorted()
    }

    public var isWellFormed: Bool {
        guard Set(members).count == members.count else { return false }
        switch kind {
        case .apart: return members.count >= 2
        case .together: return members.count == 2
        }
    }

    private enum CodingKeys: String, CodingKey { case id, kind, members = "players" }
}

public struct UnkeptRule: Codable, Sendable, Hashable {
    public var kind: PairingRule.Kind
    public var players: [PlayerID]

    public init(kind: PairingRule.Kind, players: [PlayerID]) {
        self.kind = kind
        self.players = players.sorted()
    }
}

public struct PairingConflict: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        case sameTwoBothWays
        case twoPartnersForOne
        case togetherInsideApart
    }

    public var rules: [UUID]
    public var reason: Reason

    public init(rules: [UUID], reason: Reason) {
        self.rules = rules
        self.reason = reason
    }
}

public struct PairingForecast: Sendable, Hashable {
    public var rounds: Int
    public var breaking: Int
    public var unkept: [UnkeptRule]

    public init(rounds: Int, breaking: Int, unkept: [UnkeptRule]) {
        self.rounds = rounds
        self.breaking = breaking
        self.unkept = unkept
    }
}

extension Array where Element == PairingRule {
    public var conflicts: [PairingConflict] {
        let rules = filter(\.isWellFormed)
        var found: [PairingConflict] = []
        for (i, one) in rules.enumerated() {
            for two in rules.dropFirst(i + 1) {
                let shared = Set(one.players).intersection(two.players)
                switch (one.kind, two.kind) {
                case (.together, .together):
                    if shared.count == 1 { found.append(PairingConflict(rules: [one.id, two.id], reason: .twoPartnersForOne)) }
                case (.together, .apart), (.apart, .together):
                    let together = one.kind == .together ? one : two
                    let apart = one.kind == .apart ? one : two
                    guard Set(together.players).isSubset(of: apart.players) else { continue }
                    let reason: PairingConflict.Reason = apart.players.count == 2 ? .sameTwoBothWays : .togetherInsideApart
                    found.append(PairingConflict(rules: [one.id, two.id], reason: reason))
                case (.apart, .apart):
                    continue
                }
            }
        }
        return found
    }

    public func pruned(to players: [PlayerID]) -> [PairingRule] {
        let listed = Set(players)
        return compactMap { rule in
            var kept = rule
            kept.players = rule.players.filter(listed.contains)
            return kept.players.count >= 2 ? kept : nil
        }
    }

    public func breaks(_ teams: BySide<[PlayerID]>) -> [UnkeptRule] {
        var found = Set<UnkeptRule>()
        for rule in self where rule.isWellFormed {
            switch rule.kind {
            case .apart:
                let members = Set(rule.players)
                for side in TeamSide.allCases {
                    let together = teams[side].filter(members.contains).sorted()
                    for (i, one) in together.enumerated() {
                        for two in together.dropFirst(i + 1) {
                            found.insert(UnkeptRule(kind: .apart, players: [one, two]))
                        }
                    }
                }
            case .together:
                let pair = rule.players
                let sideOf = { (id: PlayerID) in TeamSide.allCases.first { teams[$0].contains(id) } }
                if let first = sideOf(pair[0]), let second = sideOf(pair[1]), first != second {
                    found.insert(UnkeptRule(kind: .together, players: pair))
                }
            }
        }
        return found.sorted { one, two in
            if one.kind != two.kind { return one.kind == .apart }
            return one.players.lexicographicallyPrecedes(two.players)
        }
    }

    func breakCount(_ courts: [BySide<[PlayerID]>]) -> Int {
        courts.reduce(0) { $0 + breaks($1).count }
    }
}

func fourWayPartitions(_ four: [PlayerID]) -> [BySide<[PlayerID]>] {
    [(1, 2, 3), (2, 1, 3), (3, 1, 2)].map { partner, third, fourth in
        BySide(a: [four[0], four[partner]], b: [four[third], four[fourth]])
    }
}

extension Array where Element == PairingRule {
    func fewestBreaks(among four: [PlayerID]) -> Int {
        fourWayPartitions(four).map { breaks($0).count }.min() ?? 0
    }
}
