import Foundation

public struct Tally: Sendable, Hashable {
    public var won: Int
    public var drawn: Int
    public var lost: Int

    public init(won: Int = 0, drawn: Int = 0, lost: Int = 0) {
        self.won = won
        self.drawn = drawn
        self.lost = lost
    }

    public var played: Int { won + drawn + lost }
    public var winRate: Double? { played == 0 ? nil : Double(won) / Double(played) }

    mutating func record(_ winner: TeamSide?, for side: TeamSide) {
        if winner == nil {
            drawn += 1
        } else if winner == side {
            won += 1
        } else {
            lost += 1
        }
    }
}

public struct Pairing: Sendable, Hashable, Identifiable {
    public var person: PersonID
    public var name: String
    public var tally: Tally

    public var id: PersonID { person }
}

public struct PointTally: Sendable, Hashable {
    public var rounds = 0
    public var pointsFor = 0
    public var pointsAgainst = 0

    public var average: Double? { rounds == 0 ? nil : Double(pointsFor) / Double(rounds) }

    public var share: Double? {
        let total = pointsFor + pointsAgainst
        return total == 0 ? nil : Double(pointsFor) / Double(total)
    }
}

public struct ModeTally: Sendable, Hashable, Identifiable {
    public var name: String
    public var symbol: String
    public var tally: Tally

    public var id: String { name }
}

public struct Appearance: Sendable, Hashable, Identifiable {
    public var seat: Seat
    public var name: String
    public var record: UUID
    public var title: String
    public var modeName: String
    public var modeSymbol: String
    public var date: Date
    public var partners: [String]
    public var opponents: [String]
    public var tally: Tally

    public var id: Seat { seat }
}

public struct MergedName: Sendable, Hashable, Identifiable {
    public var id: PersonID
    public var name: String
    public var note: String?
}

public struct PersonStats: Sendable, Hashable, Identifiable {
    public var id: PersonID
    public var name: String
    public var note: String?
    public var spellings: [String]
    public var merged: [MergedName]
    public var overall: Tally
    public var modes: [ModeTally]
    public var partners: [Pairing]
    public var opponents: [Pairing]
    public var points: [TournamentFormat: PointTally]
    public var appearances: [Appearance]
    /// Sessions where two seats came out as this one person — two Johns in one americano.
    public var clashes: [UUID]
    public var lastPlayed: Date

    public static let bestPartnerMinimum = 3

    public var bestPartner: Pairing? {
        partners
            .filter { $0.tally.played >= Self.bestPartnerMinimum }
            .sorted(by: PlayerStats.isBetterPartnership)
            .first
    }

    public var records: Set<UUID> { Set(appearances.map(\.record)) }

    public func matches(_ query: String) -> Bool {
        let needle = KnownPlayer.searchKey(query)
        guard !needle.isEmpty else { return true }
        return ([name, note ?? ""] + spellings).contains { KnownPlayer.searchKey($0).contains(needle) }
    }
}

public struct PlayerStats: Sendable, Hashable {
    public var people: [PersonStats]
    public var links: PlayerLinks

    public init(people: [PersonStats] = [], links: PlayerLinks = PlayerLinks()) {
        self.people = people
        self.links = links
    }

    public func person(_ id: PersonID) -> PersonStats? {
        let id = links.canonical(id)
        return people.first { $0.id == id }
    }

    /// Copies left behind by a resume are taken out before the period is applied, so a game
    /// is counted in the period of the one copy that holds it and in no other.
    public static func make(from records: [HistoryRecord], links: PlayerLinks, during period: DateInterval? = nil) -> PlayerStats {
        var builders: [PersonID: Builder] = [:]
        let counted = FiledSession.counted(records, links: links)

        for record in counted where period?.holds(record.finishedAt) ?? true {
            let filed = FiledSession(record)
            var names: [Seat: String] = [:]
            var people: [Seat: PersonID] = [:]
            for (seat, name) in filed.seats {
                names[seat] = name
                people[seat] = links.person(at: seat, named: name)
            }

            var seatTallies: [Seat: Tally] = [:]
            var partnerNames: [Seat: [String]] = [:]
            var opponentNames: [Seat: [String]] = [:]

            for contest in filed.contests {
                let sides = contest.sides.map { seats in unique(seats.compactMap { people[$0] }) }
                let clashing = Set(sides.a).intersection(sides.b)

                for side in TeamSide.allCases {
                    for seat in contest.sides[side] {
                        seatTallies[seat, default: Tally()].record(contest.winner, for: side)
                        partnerNames[seat, default: []] += contest.sides[side].filter { $0 != seat }.compactMap { names[$0] }
                        opponentNames[seat, default: []] += contest.sides[side.other].compactMap { names[$0] }
                    }

                    let team = sides[side].filter { !clashing.contains($0) }
                    let across = contest.countsHeadToHead ? sides[side.other].filter { !clashing.contains($0) } : []
                    for person in team {
                        builders[person, default: Builder()].count(
                            contest, on: side, in: record.state,
                            partners: team.filter { $0 != person }, opponents: across
                        )
                    }
                }
            }

            let seatsByPerson = Dictionary(grouping: filed.seats.map(\.seat)) { people[$0]! }
            for (person, seats) in seatsByPerson where seats.count > 1 {
                builders[person, default: Builder()].clashes.append(record.id)
            }

            for (seat, name) in filed.seats {
                let person = people[seat]!
                let raw = links.placement(of: seat) ?? .named(name)
                builders[person, default: Builder()].appear(
                    Appearance(
                        seat: seat, name: name, record: record.id, title: record.title,
                        modeName: record.state.modeName, modeSymbol: record.state.modeSymbol,
                        date: record.finishedAt,
                        partners: unique(partnerNames[seat] ?? []),
                        opponents: unique(opponentNames[seat] ?? []),
                        tally: seatTallies[seat] ?? Tally()
                    ),
                    through: links.child(of: person, reachedFrom: raw)
                )
            }
        }

        let displayNames = builders.mapValues { $0.appearances.first?.name ?? "" }
        let people = builders
            .map { id, builder in builder.stats(id, names: displayNames, links: links) }
            .sorted(by: isListedAbove)
        return PlayerStats(people: people, links: links)
    }

    static func isListedAbove(_ lhs: PersonStats, _ rhs: PersonStats) -> Bool {
        if lhs.overall.played != rhs.overall.played { return lhs.overall.played > rhs.overall.played }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.lastPlayed != rhs.lastPlayed { return lhs.lastPlayed > rhs.lastPlayed }
        return String(describing: lhs.id) < String(describing: rhs.id)
    }

    static func isBetterPartnership(_ lhs: Pairing, _ rhs: Pairing) -> Bool {
        let left = lhs.tally.winRate ?? 0
        let right = rhs.tally.winRate ?? 0
        if left != right { return left > right }
        if lhs.tally.won != rhs.tally.won { return lhs.tally.won > rhs.tally.won }
        if lhs.tally.played != rhs.tally.played { return lhs.tally.played > rhs.tally.played }
        return lhs.name < rhs.name
    }

    static func isPlayedMore(_ lhs: Pairing, _ rhs: Pairing) -> Bool {
        if lhs.tally.played != rhs.tally.played { return lhs.tally.played > rhs.tally.played }
        if lhs.tally.won != rhs.tally.won { return lhs.tally.won > rhs.tally.won }
        return lhs.name < rhs.name
    }
}

private func unique<T: Hashable>(_ values: [T]) -> [T] {
    var seen: Set<T> = []
    return values.filter { seen.insert($0).inserted }
}

private struct Builder {
    var overall = Tally()
    var modes: [String: (symbol: String, tally: Tally)] = [:]
    var partners: [PersonID: Tally] = [:]
    var opponents: [PersonID: Tally] = [:]
    var points: [TournamentFormat: PointTally] = [:]
    var appearances: [Appearance] = []
    var merged: [PersonID: String] = [:]
    var mergedOrder: [PersonID] = []
    var clashes: [UUID] = []

    mutating func count(
        _ contest: Contest, on side: TeamSide, in state: SessionState,
        partners team: [PersonID], opponents across: [PersonID]
    ) {
        overall.record(contest.winner, for: side)
        modes[state.modeName, default: (state.modeSymbol, Tally())].tally.record(contest.winner, for: side)
        for partner in team {
            partners[partner, default: Tally()].record(contest.winner, for: side)
        }
        for opponent in across {
            opponents[opponent, default: Tally()].record(contest.winner, for: side)
        }
        if let format = contest.format, let score = contest.points {
            points[format, default: PointTally()].rounds += 1
            points[format]?.pointsFor += score[side]
            points[format]?.pointsAgainst += score[side.other]
        }
    }

    mutating func appear(_ appearance: Appearance, through child: PersonID?) {
        appearances.append(appearance)
        if let child, merged[child] == nil {
            merged[child] = appearance.name
            mergedOrder.append(child)
        }
    }

    func stats(_ id: PersonID, names: [PersonID: String], links: PlayerLinks) -> PersonStats {
        func pairings(_ tallies: [PersonID: Tally]) -> [Pairing] {
            tallies
                .map { Pairing(person: $0.key, name: names[$0.key] ?? "", tally: $0.value) }
                .sorted(by: PlayerStats.isPlayedMore)
        }

        return PersonStats(
            id: id,
            name: appearances.first?.name ?? "",
            note: links.note(for: id),
            spellings: unique(appearances.map(\.name)),
            merged: mergedOrder.map { MergedName(id: $0, name: merged[$0] ?? "", note: links.note(for: $0)) },
            overall: overall,
            modes: modes
                .map { ModeTally(name: $0.key, symbol: $0.value.symbol, tally: $0.value.tally) }
                .sorted { $0.tally.played != $1.tally.played ? $0.tally.played > $1.tally.played : $0.name < $1.name },
            partners: pairings(partners),
            opponents: pairings(opponents),
            points: points,
            appearances: appearances,
            clashes: unique(clashes),
            lastPlayed: appearances.first?.date ?? .distantPast
        )
    }
}
