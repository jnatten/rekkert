import Foundation
@testable import RekkertSync

/// A phone in a bag, as iOS runs an app with Bluetooth in the background: woken by each event
/// on its radio and let run for a while after it, its timers waiting for the next one meanwhile.
nonisolated final class Wakefulness: @unchecked Sendable {
    /// How long iOS lets an app run after a Bluetooth event wakes it.
    static let window: Duration = .seconds(10)

    private let clock: TestClock
    private let lock = NSLock()
    private var _isInABag = false
    private var awakeUntil: Duration = .zero
    private var held: [@Sendable () -> Void] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    var isInABag: Bool {
        get { lock.withLock { _isInABag } }
        set {
            let now = clock.now
            lock.withLock {
                _isInABag = newValue
                awakeUntil = now + Self.window
            }
            if !newValue { wake() }
        }
    }

    func wake() {
        let now = clock.now
        let pending = lock.withLock { () -> [@Sendable () -> Void] in
            awakeUntil = max(awakeUntil, now + Self.window)
            defer { held = [] }
            return held
        }
        for work in pending { clock.run(work) }
    }

    func whenAwake(_ work: @escaping @Sendable () -> Void) {
        let now = clock.now
        let runsNow = lock.withLock { () -> Bool in
            guard _isInABag, now >= awakeUntil else { return true }
            held.append(work)
            return false
        }
        if runsNow { work() }
    }

    var scheduler: any RadioScheduler { PausingScheduler(clock: clock, wakefulness: self) }
}

private nonisolated struct PausingScheduler: RadioScheduler {
    let clock: TestClock
    let wakefulness: Wakefulness

    var now: Duration { clock.now }

    func run(_ work: @escaping @Sendable () -> Void) {
        clock.run(work)
    }

    @discardableResult
    func run(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> any RadioTimer {
        let timer = HeldTimer()
        timer.underlying = clock.run(after: delay) { [wakefulness] in
            wakefulness.whenAwake { if !timer.isCancelled { work() } }
        }
        return timer
    }
}

private nonisolated final class HeldTimer: RadioTimer, @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var _underlying: (any RadioTimer)?

    var isCancelled: Bool { lock.withLock { _isCancelled } }

    var underlying: (any RadioTimer)? {
        get { lock.withLock { _underlying } }
        set { lock.withLock { _underlying = newValue } }
    }

    func cancel() {
        lock.withLock { _isCancelled = true }
        underlying?.cancel()
    }
}
