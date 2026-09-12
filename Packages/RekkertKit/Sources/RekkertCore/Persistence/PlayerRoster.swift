import Foundation

public struct KnownPlayer: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var lastUsed: Date
    public var useCount: Int

    /// Case- and accent-insensitive, so "jonas" and "Jonas" are the same person.
    public var id: String { KnownPlayer.key(name) }

    public init(name: String, lastUsed: Date = Date(), useCount: Int = 1) {
        self.name = name
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    /// Identity. Case- and accent-insensitive, but ø, æ and å stay distinct letters —
    /// they are not decorations on o and a, and merging them would fold real names
    /// together.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Matching. Deliberately more forgiving than identity, so someone typing "bjorn" on a
    /// hurried keyboard still finds Bjørn.
    static func searchKey(_ name: String) -> String {
        var folded = key(name)
        for (letter, ascii) in [("ø", "o"), ("æ", "ae"), ("å", "aa"), ("ß", "ss"), ("ð", "d"), ("þ", "th")] {
            folded = folded.replacingOccurrences(of: letter, with: ascii)
        }
        return folded
    }
}

/// Everyone who has played before, so the same eight people do not have to be typed in
/// every Thursday.
public struct PlayerRoster: Codable, Sendable, Hashable {
    public private(set) var players: [KnownPlayer]

    /// Keeps the file from growing without bound; the least useful entries go first.
    public static let capacity = 200

    public init(players: [KnownPlayer] = []) {
        self.players = players
    }

    public var isEmpty: Bool { players.isEmpty }

    public mutating func remember(_ names: [String], at date: Date = Date()) {
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if let index = players.firstIndex(where: { $0.id == KnownPlayer.key(name) }) {
                // Keep the spelling already stored: a hurried lowercase entry should not
                // overwrite a name that was capitalised properly.
                players[index].useCount += 1
                players[index].lastUsed = date
            } else {
                players.append(KnownPlayer(name: name, lastUsed: date))
            }
        }
        prune()
    }

    public mutating func forget(_ name: String) {
        players.removeAll { $0.id == KnownPlayer.key(name) }
    }

    /// Best matches for what has been typed so far. An empty query returns the most
    /// familiar names, which is what makes setting up a regular group quick.
    public func suggestions(
        matching query: String = "",
        excluding taken: [String] = [],
        limit: Int = 8
    ) -> [KnownPlayer] {
        let needle = KnownPlayer.searchKey(query)
        let used = Set(taken.map(KnownPlayer.key))

        return players
            .filter { !used.contains($0.id) }
            .filter { needle.isEmpty || KnownPlayer.searchKey($0.name).contains(needle) }
            .sorted { one, two in
                if needle.isEmpty == false {
                    let a = KnownPlayer.searchKey(one.name).hasPrefix(needle)
                    let b = KnownPlayer.searchKey(two.name).hasPrefix(needle)
                    if a != b { return a }
                }
                if one.useCount != two.useCount { return one.useCount > two.useCount }
                if one.lastUsed != two.lastUsed { return one.lastUsed > two.lastUsed }
                return one.name < two.name
            }
            .prefix(limit)
            .map { $0 }
    }

    private mutating func prune() {
        guard players.count > Self.capacity else { return }
        players = players
            .sorted { one, two in
                if one.useCount != two.useCount { return one.useCount > two.useCount }
                return one.lastUsed > two.lastUsed
            }
            .prefix(Self.capacity)
            .map { $0 }
    }
}
