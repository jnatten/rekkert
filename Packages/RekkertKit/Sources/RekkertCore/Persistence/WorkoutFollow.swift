import Foundation

/// Starts are acted on where the match began; endings only by the watch, which holds the
/// workout. An automatic stop waits out `grace`, so a rematch or a taken-back final point
/// keeps it one workout.
public struct WorkoutFollow: Equatable, Sendable {
    public enum Pending: Equatable, Sendable {
        case askToStart(UUID)
        /// A phone starting a match over the watch's ends the old one there a moment before
        /// the new one arrives: a replacement, not an ending.
        case settling(UUID, heard: Date, cue: WorkoutCue)
        case askToStop(UUID)
        case stopping(UUID, at: Date)
    }

    public enum Effect: Equatable, Sendable {
        case start
        case stop
        case buzz
    }

    public static let settle: TimeInterval = 3
    public static let grace: TimeInterval = 60

    public private(set) var pending: Pending?
    /// The watch hears its own join from both its store and the stand-in.
    private var lastBegan: UUID?
    private let handlesEndings: Bool

    public init(handlesEndings: Bool) {
        self.handlesEndings = handlesEndings
    }

    public var isAskingToStart: Bool {
        if case .askToStart = pending { return true }
        return false
    }

    public var isAskingToStop: Bool {
        if case .askToStop = pending { return true }
        return false
    }

    public var stopsAt: Date? {
        if case .stopping(_, let at) = pending { return at }
        return nil
    }

    public var nextDeadline: Date? {
        switch pending {
        case .settling(_, let heard, _): heard + Self.settle
        case .stopping(_, let at): at
        case .askToStart, .askToStop, nil: nil
        }
    }

    public mutating func began(_ session: UUID, cue: WorkoutCue, isTracking: Bool) -> [Effect] {
        guard session != lastBegan else { return [] }
        lastBegan = session
        pending = nil
        guard !isTracking else { return [] }
        switch cue {
        case .off: return []
        case .ask:
            pending = .askToStart(session)
            return []
        case .automatic: return [.start]
        }
    }

    public mutating func inPlay(_ session: UUID) {
        switch pending {
        case .settling, .askToStop, .stopping: pending = nil
        case .askToStart(let asked) where asked != session: pending = nil
        case .askToStart, nil: break
        }
    }

    public mutating func ended(_ session: UUID, cue: WorkoutCue, isTracking: Bool, at now: Date) {
        if case .askToStart(session) = pending { pending = nil }
        guard handlesEndings, isTracking, cue != .off else { return }
        pending = .settling(session, heard: now, cue: cue)
    }

    public mutating func tick(at now: Date, isTracking: Bool) -> [Effect] {
        var effects: [Effect] = []
        if case .settling(let session, let heard, let cue) = pending, now >= heard + Self.settle {
            guard isTracking else {
                pending = nil
                return []
            }
            pending = cue == .ask ? .askToStop(session) : .stopping(session, at: heard + Self.grace)
            effects.append(.buzz)
        }
        if case .stopping(_, let at) = pending, now >= at {
            pending = nil
            if isTracking { effects.append(.stop) }
        }
        return effects
    }

    public mutating func tracking(_ isTracking: Bool) {
        switch pending {
        case .askToStart where isTracking: pending = nil
        case .settling, .askToStop, .stopping: if !isTracking { pending = nil }
        default: break
        }
    }

    public mutating func keepGoing() {
        switch pending {
        case .settling, .askToStop, .stopping: pending = nil
        case .askToStart, nil: break
        }
    }

    public mutating func answerStart(_ yes: Bool) -> [Effect] {
        guard isAskingToStart else { return [] }
        pending = nil
        return yes ? [.start] : []
    }

    public mutating func answerStop(_ yes: Bool) -> [Effect] {
        guard isAskingToStop else { return [] }
        pending = nil
        return yes ? [.stop] : []
    }
}
