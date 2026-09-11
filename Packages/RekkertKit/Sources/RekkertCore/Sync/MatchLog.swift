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
            case .point, .setScore, .confirmRound, .nextRound, .finish: true
            case .configure, .undo, .chooseServeSide: false
            }
        }
    }

    /// The total order both devices agree on. Lamport first, device id to break ties.
    public var ordered: [MatchEvent] {
        events.values.sorted { ($0.lamport, $0.id) < ($1.lamport, $1.id) }
    }

    public var isEmpty: Bool { events.isEmpty }

    /// Highest sequence number seen per device — what the other side needs in order to
    /// work out which events we are missing.
    public var vector: VersionVector {
        var result = VersionVector()
        for event in events.values {
            result[event.id.device] = event.id.seq
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
    /// on one device and a new point on the other both survive the merge. Resolved in
    /// reverse order because an undo always carries a higher Lamport stamp than its target.
    public var effectiveEvents: [MatchEvent] {
        let sorted = ordered
        var cancelledBy: [EventID: Int] = [:]
        var cancelled: Set<EventID> = []

        for event in sorted.reversed() {
            let isEffective = (cancelledBy[event.id] ?? 0).isMultiple(of: 2)
            if !isEffective { cancelled.insert(event.id) }
            if isEffective, case .undo(let target) = event.kind {
                cancelledBy[target, default: 0] += 1
            }
        }
        return sorted.filter { !cancelled.contains($0.id) }
    }

    /// The most recent still-effective event that an undo should target.
    public func lastUndoableEvent() -> MatchEvent? {
        effectiveEvents.last { $0.isUndoable }
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
