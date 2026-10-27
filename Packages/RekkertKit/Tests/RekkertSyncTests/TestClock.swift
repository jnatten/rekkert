import Foundation
@testable import RekkertSync

/// Time that moves only when a test moves it, so a radio's timeouts can be run through in a
/// moment and in the same order every time.
nonisolated final class TestClock: RadioScheduler, @unchecked Sendable {
    private struct Pending {
        let id: Int
        let due: Duration
        let work: @Sendable () -> Void
    }

    private final class Timer: RadioTimer, @unchecked Sendable {
        weak var clock: TestClock?
        let id: Int

        init(clock: TestClock, id: Int) {
            self.clock = clock
            self.id = id
        }

        func cancel() { clock?.cancel(id) }
    }

    private let lock = NSLock()
    private var current: Duration = .zero
    private var pending: [Pending] = []
    private var counter = 0

    var now: Duration { lock.withLock { current } }

    func run(_ work: @escaping @Sendable () -> Void) {
        _ = schedule(after: .zero, work)
    }

    @discardableResult
    func run(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> any RadioTimer {
        schedule(after: delay, work)
    }

    /// Runs everything due by `now + delta`, earliest first, including whatever that work puts
    /// on the clock in the meantime.
    func advance(by delta: Duration = .zero) {
        let target = lock.withLock { current + delta }
        while let next = takeNext(dueBy: target) {
            lock.withLock { current = max(current, next.due) }
            next.work()
        }
        lock.withLock { current = max(current, target) }
    }

    var hasPending: Bool { lock.withLock { !pending.isEmpty } }

    private func schedule(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> Timer {
        let id = lock.withLock { () -> Int in
            counter += 1
            pending.append(Pending(id: counter, due: current + delay, work: work))
            return counter
        }
        return Timer(clock: self, id: id)
    }

    private func takeNext(dueBy target: Duration) -> Pending? {
        lock.withLock {
            guard let index = pending.indices
                .filter({ pending[$0].due <= target })
                .min(by: { (pending[$0].due, pending[$0].id) < (pending[$1].due, pending[$1].id) })
            else { return nil }
            return pending.remove(at: index)
        }
    }

    private func cancel(_ id: Int) {
        lock.withLock { pending.removeAll { $0.id == id } }
    }
}
