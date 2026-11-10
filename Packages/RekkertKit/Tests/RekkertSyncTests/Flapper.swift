import Foundation
@testable import RekkertSync

/// Drops and restores guests' second links the way the field records of 8 and 9 November show
/// (spec 005, research D-10): up a median 43 s, down a median 4.1 s, a third of drops shared
/// with another guest within the second.
nonisolated final class Flapper: @unchecked Sendable {
    struct Schedule {
        var upMedian = 43.0
        var upP90 = 127.0
        var downMedian = 4.1
        var downP90 = 10.9
        var sharedShare = 1.0 / 3.0
    }

    private let schedule: Schedule
    private let lock = NSLock()
    private var random: SplitMix
    private var radios: [SimulatedRadio] = []
    private var timers: [ObjectIdentifier: any RadioTimer] = [:]
    private var down: Set<ObjectIdentifier> = []
    private var dropCount: [ObjectIdentifier: Int] = [:]
    private weak var clock: TestClock?

    init(seed: UInt64 = 0xF1A9, schedule: Schedule = Schedule()) {
        self.schedule = schedule
        random = SplitMix(seed: seed)
    }

    func start(_ radios: [SimulatedRadio], on clock: TestClock) {
        lock.withLock {
            self.radios = radios
            self.clock = clock
        }
        for radio in radios { scheduleDrop(of: radio) }
    }

    func stop() {
        let pending = lock.withLock { () -> [any RadioTimer] in
            defer { timers = [:] }
            return Array(timers.values)
        }
        for timer in pending { timer.cancel() }
    }

    func drops(of radio: SimulatedRadio) -> Int {
        lock.withLock { dropCount[ObjectIdentifier(radio), default: 0] }
    }

    private func scheduleDrop(of radio: SimulatedRadio) {
        guard let clock = lock.withLock({ self.clock }) else { return }
        let after = lock.withLock { sample(median: schedule.upMedian, p90: schedule.upP90) }
        let timer = clock.run(after: after) { [weak self] in self?.drop(radio, sharing: true) }
        lock.withLock { timers[ObjectIdentifier(radio)] = timer }
    }

    private func drop(_ radio: SimulatedRadio, sharing: Bool) {
        let key = ObjectIdentifier(radio)
        let (alreadyDown, partner) = lock.withLock { () -> (Bool, SimulatedRadio?) in
            guard !down.contains(key) else { return (true, nil) }
            down.insert(key)
            dropCount[key, default: 0] += 1
            timers[key]?.cancel()
            guard sharing, random.next() < schedule.sharedShare else { return (false, nil) }
            let others = radios.filter { !down.contains(ObjectIdentifier($0)) }
            guard !others.isEmpty else { return (false, nil) }
            return (false, others[Int(random.next() * Double(others.count)) % others.count])
        }
        guard !alreadyDown, let clock = lock.withLock({ self.clock }) else { return }
        radio.walkAway()
        if let partner { drop(partner, sharing: false) }
        let after = lock.withLock { sample(median: schedule.downMedian, p90: schedule.downP90) }
        let timer = clock.run(after: after) { [weak self] in
            guard let self else { return }
            lock.withLock { _ = down.remove(key) }
            radio.comeBack()
            scheduleDrop(of: radio)
        }
        lock.withLock { timers[key] = timer }
    }

    /// Log-normal around the median, spread so the 90th percentile lands where the records put it.
    /// Called with the lock held.
    private func sample(median: Double, p90: Double) -> Duration {
        let sigma = log(p90 / median) / 1.2816
        let u1 = max(random.next(), .leastNonzeroMagnitude)
        let u2 = random.next()
        let z = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        return .milliseconds(Int64((median * exp(sigma * z) * 1_000).rounded()))
    }
}
