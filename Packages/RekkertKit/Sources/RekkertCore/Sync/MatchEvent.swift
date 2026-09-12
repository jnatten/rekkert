import Foundation

public enum EventKind: Codable, Sendable, Hashable {
    case configure(SessionSetup)
    /// `round` is ignored by traditional matches, which have only one scoreline. In a
    /// tournament it addresses the round explicitly, so an edit to an earlier round
    /// cannot land on the current one just because it arrived late.
    case point(round: Int, court: Int, team: TeamSide)
    case setScore(round: Int, court: Int, points: BySide<Int>)
    /// On a golden/star sudden-death point the receiving team picks which side it is
    /// served to.
    case chooseServeSide(ServeCourt)
    case setRoundConfirmed(round: Int, isConfirmed: Bool)
    /// The whistle in winner court: closes round `round` wherever it stands. Naming the
    /// round makes it idempotent — if both devices whistle, the second is a no-op instead
    /// of closing a second round.
    case endRound(round: Int)
    /// Draws the round after `after`, and only if that is still the last one — so two
    /// devices advancing at once produce one new round, not two.
    case nextRound(after: Int)
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
        case .point, .setScore, .setRoundConfirmed, .nextRound, .finish, .endRound: true
        case .configure, .undo, .chooseServeSide: false
        }
    }
}
