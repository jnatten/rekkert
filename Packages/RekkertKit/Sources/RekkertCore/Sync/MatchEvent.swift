import Foundation

public enum EventKind: Codable, Sendable, Hashable {
    case configure(SessionSetup)
    case point(court: Int, team: TeamSide)
    case setScore(court: Int, points: BySide<Int>)
    case confirmRound
    case nextRound
    case finish
    case undo(EventID)
}

public struct MatchEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: EventID
    public let lamport: UInt64
    public let kind: EventKind

    public init(id: EventID, lamport: UInt64, kind: EventKind) {
        self.id = id
        self.lamport = lamport
        self.kind = kind
    }

    /// Events an undo can target. Configuration and undo itself are excluded so that
    /// "undo" always means "take back the last thing that changed the score".
    public var isUndoable: Bool {
        switch kind {
        case .point, .setScore, .confirmRound, .nextRound, .finish: true
        case .configure, .undo: false
        }
    }
}
