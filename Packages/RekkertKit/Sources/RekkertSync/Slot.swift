import Foundation

/// One thing in use at a time, and a way to let go of it that cannot let go of its replacement.
///
/// The system reports that a listener or a browser has gone some time after it has — after this
/// end has already cancelled it and put a new one in. Cleared by that late word, the slot let go
/// of the new one: it went on running where nothing could stop it, and the next rebuild put up
/// another beside it.
nonisolated final class Slot<Value: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    var current: Value? { lock.withLock { value } }

    /// Puts `new` in, and hands back whatever it replaced, for the caller to stop.
    @discardableResult
    func install(_ new: Value?) -> Value? {
        lock.withLock {
            defer { value = new }
            return value
        }
    }

    /// Empties the slot, but only if it still holds `old`.
    @discardableResult
    func clear(ifStill old: Value) -> Bool {
        lock.withLock {
            guard value === old else { return false }
            value = nil
            return true
        }
    }
}
