import Foundation

public struct MatchLog: Codable, Sendable, Hashable {
    public let sessionID: UUID
    /// When this session was started. Decides which session wins if a phone and a watch
    /// each have one: the most recently started match is the one both devices show.
    public let createdAt: Date
    public private(set) var events: [EventID: MatchEvent]

    public init(sessionID: UUID = UUID(), createdAt: Date = Date(), events: [MatchEvent] = []) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.events = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
    }

    /// Whether anything has actually been scored, as opposed to only being configured.
    public var hasProgress: Bool {
        effectiveEvents.contains { event in
            switch event.kind {
            // A restored session arrives with a score already on it, so it is worth
            // keeping if something else displaces it.
            case .point, .setScore, .setRoundConfirmed, .nextRound, .finish, .endRound, .restore: true
            case .setFirstServer, .setServeOrder: false
            case .configure, .undo, .chooseServeSide: false
            }
        }
    }

    /// The total order both devices agree on. Lamport first, device id to break ties.
    public var ordered: [MatchEvent] {
        events.values.sorted { ($0.lamport, $0.id) < ($1.lamport, $1.id) }
    }

    public var isEmpty: Bool { events.isEmpty }

    /// Highest sequence number seen per device — what a new event has to be numbered after.
    public var vector: VersionVector {
        var result = VersionVector()
        for event in events.values {
            result[event.id.device] = event.id.seq
        }
        return result
    }

    /// Highest *contiguous* sequence number held per device — what a peer must be told when
    /// it asks what it is missing.
    ///
    /// `vector` answers a different question and is a lie for this one: a device holding X.3
    /// but not X.1 truthfully reports "X: 3", is sent nothing back, and then quietly replays a
    /// different match for the rest of the session. The frontier can only be claimed where
    /// there is nothing missing below it.
    public var coverage: VersionVector {
        var seen: [DeviceID: Set<UInt32>] = [:]
        for id in events.keys { seen[id.device, default: []].insert(id.seq) }

        var result = VersionVector()
        for (device, sequences) in seen {
            var frontier: UInt32 = 0
            while sequences.contains(frontier + 1) { frontier += 1 }
            guard frontier > 0 else { continue }
            result[device] = frontier
        }
        return result
    }

    private var nextLamport: UInt64 {
        (events.values.map(\.lamport).max() ?? 0) + 1
    }

    @discardableResult
    public mutating func append(_ kind: EventKind, from device: DeviceID) -> MatchEvent {
        let event = MatchEvent(
            id: EventID(device: device, seq: vector[device] + 1),
            lamport: nextLamport,
            kind: kind
        )
        events[event.id] = event
        return event
    }

    /// Union by event id: commutative, associative and idempotent, so duplicated or
    /// out-of-order delivery is harmless and a retrying outbox is safe.
    @discardableResult
    public mutating func merge(_ incoming: [MatchEvent]) -> Bool {
        var changed = false
        for event in incoming where events[event.id] == nil {
            events[event.id] = event
            changed = true
        }
        return changed
    }

    public func events(missingRelativeTo remote: VersionVector) -> [MatchEvent] {
        ordered.filter { $0.id.seq > remote[$0.id.device] }
    }

    /// Events that still count. An undo is a tombstone rather than a deletion, so an undo
    /// on one device and a new point on the other both survive the merge.
    ///
    /// Resolved in reverse order, which is safe because an undo always carries a higher Lamport
    /// stamp than the event it targets. Cancelling is a set rather than a count: the last event
    /// worth taking back is a function of the log rather than of who is looking at it, so two
    /// people reaching for undo at the same moment name the same point — and counting would let
    /// that pair of tombstones cancel each other out and hand the point back. Taking an undo
    /// back is still said as an undo *of the undo*, and a chain resolves the same way it always
    /// did.
    public var effectiveEvents: [MatchEvent] {
        let sorted = ordered
        var cancelled: Set<EventID> = []

        for event in sorted.reversed() where !cancelled.contains(event.id) {
            if case .undo(let target) = event.kind { cancelled.insert(target) }
        }
        return sorted.filter { !cancelled.contains($0.id) }
    }

    /// The most recent still-effective event that an undo should target.
    ///
    /// Nothing before a `.restore` qualifies: the restore replays the whole state over
    /// whatever came before it, so taking back an earlier point would change nothing on the
    /// board while still spending the undo.
    public func lastUndoableEvent() -> MatchEvent? {
        let effective = effectiveEvents
        let floor = effective.lastIndex { if case .restore = $0.kind { true } else { false } }
        let candidates = floor.map { effective[($0 + 1)...] } ?? effective[...]
        return candidates.last { $0.isUndoable }
    }

    /// Encoded as an ordered array rather than a dictionary: half the bytes over the wire
    /// (a struct-keyed dictionary encodes as alternating key/value), and stable output,
    /// which matters because the application-context channel skips unchanged payloads.
    private enum CodingKeys: String, CodingKey {
        case sessionID, createdAt, events
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let list = try container.decode([MatchEvent].self, forKey: .events)
        events = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(ordered, forKey: .events)
    }
}
