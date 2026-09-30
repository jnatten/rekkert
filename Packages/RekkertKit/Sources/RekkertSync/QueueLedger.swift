import Foundation
import RekkertCore

/// The events already handed to a durable queue in this session, so each goes on it once.
///
/// The queue keeps what it is given and delivers it in order. Handing it the whole backlog again
/// on every change only repeats what it already holds, and a backlog that grows by a point at a
/// time made that quadratic.
nonisolated struct QueueLedger {
    private var session: UUID?
    private var handedOver: Set<EventID> = []

    mutating func admitting(_ events: [MatchEvent], in session: UUID) -> [MatchEvent] {
        if session != self.session {
            self.session = session
            handedOver = []
        }
        return events.filter { handedOver.insert($0.id).inserted }
    }
}
