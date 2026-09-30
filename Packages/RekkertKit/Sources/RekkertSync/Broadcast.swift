import Foundation

/// A stream that every listener hears in full.
///
/// `AsyncStream` hands each element to one iterator only, so two loops over the same stream each
/// hear about half of what was said.
nonisolated final class Broadcast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var listeners: [UUID: AsyncStream<Element>.Continuation] = [:]

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { listeners[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.listeners.removeValue(forKey: id) }
            }
        }
    }

    func yield(_ value: Element) {
        for listener in lock.withLock({ Array(listeners.values) }) { listener.yield(value) }
    }
}
