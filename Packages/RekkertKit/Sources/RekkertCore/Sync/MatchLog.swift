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
            case .point, .setScore, .setRoundConfirmed, .setRoundCancelled, .nextRound, .finish, .endRound, .restore: true
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
    public mutating func append(_ kind: EventKind, from device: DeviceID, at: Date? = nil) -> MatchEvent {
        let event = MatchEvent(
            id: EventID(device: device, seq: vector[device] + 1),
            lamport: nextLamport,
            kind: kind,
            at: at
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

    /// From the first thing that still counts to the last, by the clocks that recorded them.
    /// `nil` for a log with no times in it at all.
    public var playedSpan: ClosedRange<Date>? {
        let times = effectiveEvents.compactMap { $0.at ?? $0.kind.payloadDate }
        guard let first = times.min(), let last = times.max() else { return nil }
        return first ... last
    }

    /// The most recent still-effective event that an undo should target: the last one that moved
    /// the board. One the reducer turned away — the second of two draws made at once, a whistle
    /// both devices blew, a point for a round already over — changed nothing, and taking it back
    /// would spend the undo on nothing.
    ///
    /// Nothing before a `.restore` qualifies: the restore replays the whole state over
    /// whatever came before it, so taking back an earlier point would change nothing on the
    /// board while still spending the undo.
    public func lastUndoableEvent(where touches: (EventKind) -> Bool = { _ in true }) -> MatchEvent? {
        var state: SessionState?
        var last: MatchEvent?
        for event in effectiveEvents {
            let before = state
            SessionReducer.apply(event.kind, to: &state)
            if case .restore = event.kind {
                last = nil
            } else if event.isUndoable, touches(event.kind), state != before {
                last = event
            }
        }
        return last
    }

    /// The same, for one court: what was scored there, or its round confirmed or called off. On a
    /// court shared between phones, somebody else's court is not this one's to take back.
    public func lastUndoableEvent(round: Int, court: Int) -> MatchEvent? {
        lastUndoableEvent(where: Self.touching(round: round, court: court))
    }

    /// Everything an undo has to take back for the board to move back.
    ///
    /// Usually the one event. But two devices drawing the same round, or blowing the same whistle,
    /// leave two of it in the log, and only the first counts — so taking that one back just lets
    /// the other count instead. Each one that would stand in is taken back with it.
    public func undoTargets(where touches: (EventKind) -> Bool = { _ in true }) -> [MatchEvent] {
        guard let first = lastUndoableEvent(where: touches) else { return [] }
        let board = SessionReducer.state(of: self)
        let scratch = DeviceID()
        var targets = [first]
        var without = self
        while targets.count < 8 {
            without.append(.undo(targets[targets.count - 1].id), from: scratch)
            guard SessionReducer.state(of: without) == board,
                  let next = without.lastUndoableEvent(where: touches) else { break }
            targets.append(next)
        }
        return targets
    }

    public func undoTargets(round: Int, court: Int) -> [MatchEvent] {
        undoTargets(where: Self.touching(round: round, court: court))
    }

    private static func touching(round: Int, court: Int) -> (EventKind) -> Bool {
        { kind in
            switch kind {
            case .point(let r, let c, _), .setScore(let r, let c, _): r == round && c == court
            case .setRoundConfirmed(let r, _), .setRoundCancelled(let r, _): r == round
            default: false
            }
        }
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
