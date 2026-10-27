import Foundation

/// Whose turn it is on a host's radio, which has one transmit queue for every guest.
///
/// The turn carries on from one ready callback to the next, so a guest late in the list is not
/// starved by those ahead of it however few slots each callback frees. A guest's own frames go
/// in priority order, but only those not yet started: the far end reassembles one frame at a time.
nonisolated struct HubScheduler<Key: Hashable> {
    enum Priority: Int, Comparable {
        case handshake, live, catchUp

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Frames longer than this many chunks wait behind the short ones.
    static var liveChunks: Int { 4 }

    private(set) var order: [Key] = []
    private var cursor = 0

    /// Last in the current round, behind everybody already waiting.
    mutating func join(_ key: Key) {
        guard !order.contains(key) else { return }
        guard !order.isEmpty else { return order.append(key) }
        let start = cursor % order.count
        order.insert(key, at: start)
        cursor = start + 1
    }

    mutating func leave(_ key: Key) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        if index < cursor { cursor -= 1 }
        if cursor >= order.count { cursor = 0 }
    }

    /// Everybody, starting with whoever's turn it is.
    func turns() -> [Key] {
        guard !order.isEmpty else { return [] }
        let start = cursor % order.count
        return Array(order[start...] + order[..<start])
    }

    /// `key` had its turn; the next one is the guest after it.
    mutating func served(_ key: Key) {
        guard let index = order.firstIndex(of: key) else { return }
        cursor = (index + 1) % order.count
    }

    static func priority(chunks: Int) -> Priority {
        chunks > liveChunks ? .catchUp : .live
    }

    /// Where a frame of `priority` goes in a backlog: behind anything already started, and
    /// behind everything of the same or higher priority.
    static func position(for priority: Priority, in backlog: [(priority: Priority, started: Bool)]) -> Int {
        var index = 0
        while index < backlog.count, backlog[index].started || backlog[index].priority <= priority {
            index += 1
        }
        return index
    }
}
