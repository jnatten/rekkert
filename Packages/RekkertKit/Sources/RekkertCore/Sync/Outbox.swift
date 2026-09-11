/// Events appended locally but not yet acknowledged by the peer. Persisted alongside the
/// log, because WatchConnectivity's own durable queues are unusable on the Simulator and
/// we would rather own the guarantee than depend on them.
public struct Outbox: Codable, Sendable, Hashable {
    public private(set) var pending: [MatchEvent]

    public init(pending: [MatchEvent] = []) {
        self.pending = pending
    }

    public var isEmpty: Bool { pending.isEmpty }

    public mutating func enqueue(_ event: MatchEvent) {
        guard !pending.contains(where: { $0.id == event.id }) else { return }
        pending.append(event)
    }

    public mutating func enqueue(contentsOf events: [MatchEvent]) {
        for event in events { enqueue(event) }
    }

    public mutating func acknowledge(upTo vector: VersionVector) {
        pending.removeAll { $0.id.seq <= vector[$0.id.device] }
    }
}
