import Foundation

/// Keeping a link honest when nobody has anything to say on it.
///
/// A guest that is only following sends nothing, so a host that had given up on it never heard
/// from it again, and it never heard the next point. Now a quiet guest asks after ten seconds,
/// and a host goes on asking a guest it has given up on, every fifteen.
nonisolated struct LinkLiveness {
    static var idleHello: Duration { .seconds(10) }
    static var probeEvery: Duration { .seconds(15) }

    private(set) var lastSent: Duration
    private var lastNudge: Duration?
    private var lastProbe: Duration?

    init(now: Duration) {
        lastSent = now
    }

    mutating func sent(at now: Duration) {
        lastSent = max(lastSent, now)
    }

    /// A guest with nothing said for a while: time to ask what it is missing, once per quiet spell.
    mutating func shouldNudge(now: Duration) -> Bool {
        guard now - lastSent >= Self.idleHello else { return false }
        if let lastNudge, now - lastNudge < Self.idleHello { return false }
        lastNudge = now
        return true
    }

    /// A guest given up on: asked at once, and every fifteen seconds after.
    mutating func shouldProbe(now: Duration) -> Bool {
        if let lastProbe, now - lastProbe < Self.probeEvery { return false }
        lastProbe = now
        return true
    }

    mutating func answered() {
        lastProbe = nil
    }
}
