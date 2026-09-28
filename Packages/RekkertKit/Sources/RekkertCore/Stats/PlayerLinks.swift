import Foundation

public enum Seat: Codable, Sendable, Hashable {
    case player(PlayerID)
    case slot(record: UUID, side: TeamSide, index: Int)
}

public enum PersonID: Codable, Sendable, Hashable {
    case name(String)
    case separate(UUID)

    public static func named(_ name: String) -> PersonID { .name(KnownPlayer.key(name)) }
}

/// Who is who across the history, kept beside it rather than written into it: by default a
/// name is a person, and only what the user has merged or separated by hand is stored.
public struct PlayerLinks: Codable, Sendable, Hashable {
    public private(set) var seats: [Seat: PersonID]
    public private(set) var merges: [PersonID: PersonID]
    public private(set) var notes: [PersonID: String]
    public private(set) var resumed: [UUID: UUID]

    public init() {
        seats = [:]
        merges = [:]
        notes = [:]
        resumed = [:]
    }

    private enum CodingKeys: String, CodingKey { case seats, merges, notes, resumed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seats = try container.decodeIfPresent([Seat: PersonID].self, forKey: .seats) ?? [:]
        merges = try container.decodeIfPresent([PersonID: PersonID].self, forKey: .merges) ?? [:]
        notes = try container.decodeIfPresent([PersonID: String].self, forKey: .notes) ?? [:]
        resumed = try container.decodeIfPresent([UUID: UUID].self, forKey: .resumed) ?? [:]
    }

    public func person(at seat: Seat, named name: String) -> PersonID {
        canonical(placement(of: seat) ?? .named(name))
    }

    public func canonical(_ person: PersonID) -> PersonID {
        var person = person
        var seen: Set<PersonID> = [person]
        while let parent = merges[person], seen.insert(parent).inserted {
            person = parent
        }
        return person
    }

    public func note(for person: PersonID) -> String? {
        notes[person]
    }

    /// Where a seat was put by hand, if anywhere. A match picked up again from History is
    /// filed under a new id, and inherits whatever was decided for the seats of the old one.
    func placement(of seat: Seat) -> PersonID? {
        var seat = seat
        var visited: Set<UUID> = []
        while true {
            if let placed = seats[seat] { return placed }
            guard case .slot(let record, let side, let index) = seat,
                  let original = resumed[record],
                  visited.insert(original).inserted
            else { return nil }
            seat = .slot(record: original, side: side, index: index)
        }
    }

    /// Whoever was merged straight into `root` on the way up from `raw`, so a merge can be
    /// undone one person at a time.
    func child(of root: PersonID, reachedFrom raw: PersonID) -> PersonID? {
        var current = raw
        var seen: Set<PersonID> = [raw]
        while let parent = merges[current], seen.insert(parent).inserted {
            if parent == root { return current }
            current = parent
        }
        return nil
    }

    func inheritedPlacement(of seat: Seat, named name: String) -> PersonID {
        if case .slot(let record, let side, let index) = seat, let original = resumed[record] {
            return placement(of: .slot(record: original, side: side, index: index)) ?? .named(name)
        }
        return .named(name)
    }

    /// Merges two people and returns whoever is left. A name outlasts a separated person
    /// either way round, so the next time that name is typed it still lands on the merge.
    @discardableResult
    public mutating func merge(_ person: PersonID, into target: PersonID) -> PersonID {
        let person = canonical(person)
        let target = canonical(target)
        guard person != target else { return target }

        let (absorbed, kept) = switch (person, target) {
        case (.name, .separate): (target, person)
        default: (person, target)
        }
        merges[absorbed] = kept
        return kept
    }

    public mutating func unmerge(_ person: PersonID) {
        merges[person] = nil
    }

    @discardableResult
    public mutating func separate(_ appearances: [Appearance], note: String = "") -> PersonID {
        let person = PersonID.separate(UUID())
        for appearance in appearances {
            seats[appearance.seat] = person
        }
        setNote(note, for: person)
        return person
    }

    public mutating func move(_ appearances: [Appearance], to person: PersonID) {
        for appearance in appearances {
            let inherited = inheritedPlacement(of: appearance.seat, named: appearance.name)
            seats[appearance.seat] = person == inherited ? nil : person
        }
    }

    public mutating func setNote(_ note: String, for person: PersonID) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[person] = trimmed.isEmpty ? nil : trimmed
    }

    public mutating func resume(_ record: UUID, from original: UUID) {
        guard record != original else { return }
        resumed[record] = original
    }
}
