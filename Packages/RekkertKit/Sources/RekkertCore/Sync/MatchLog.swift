import Foundation

public struct MatchLog: Codable, Sendable, Hashable {
    public let sessionID: UUID
    public private(set) var events: [EventID: MatchEvent]

    public init(sessionID: UUID = UUID(), events: [MatchEvent] = []) {
        self.sessionID = sessionID
        self.events = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
    }

    /// The total order both devices agree on. Lamport first, device id to break ties.
    public var ordered: [MatchEvent] {
        events.values.sorted { ($0.lamport, $0.id) < ($1.lamport, $1.id) }
    }

    public var isEmpty: Bool { events.isEmpty }

    /// Highest sequence number seen per device — what the other side needs in order to
    /// work out which events we are missing.
    public var vector: [DeviceID: UInt32] {
        var result: [DeviceID: UInt32] = [:]
        for event in events.values {
            result[event.id.device] = max(result[event.id.device] ?? 0, event.id.seq)
        }
        return result
    }

    private var nextLamport: UInt64 {
        (events.values.map(\.lamport).max() ?? 0) + 1
    }

    @discardableResult
    public mutating func append(_ kind: EventKind, from device: DeviceID) -> MatchEvent {
        let event = MatchEvent(
            id: EventID(device: device, seq: (vector[device] ?? 0) + 1),
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

    public func events(missingRelativeTo remote: [DeviceID: UInt32]) -> [MatchEvent] {
        ordered.filter { $0.id.seq > (remote[$0.id.device] ?? 0) }
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
}
