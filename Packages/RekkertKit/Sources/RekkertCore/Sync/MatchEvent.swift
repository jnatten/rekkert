import Foundation

public enum EventKind: Codable, Sendable, Hashable {
    /// `at` is when the session started, which is what the clock on the board counts from.
    /// Payload and never an ordering key: the log is ordered by Lamport stamp and device id
    /// precisely because two devices' clocks do not agree. Absent from logs written before
    /// the clock existed, which replay without one.
    case configure(SessionSetup, at: Date? = nil)
    /// `round` is ignored by traditional matches, which have only one scoreline. In a
    /// tournament it addresses the round explicitly, so an edit to an earlier round
    /// cannot land on the current one just because it arrived late.
    case point(round: Int, court: Int, team: TeamSide)
    case setScore(round: Int, court: Int, points: BySide<Int>)
    /// Corrects who is serving. Absolute rather than "swap", so two devices fixing it at
    /// once land on the same answer instead of swapping twice.
    case setFirstServer(round: Int, court: Int, index: Int)
    /// Corrects who serves in full: where the rotation starts and, per side, which partner
    /// goes first. Absolute for the same reason as `setFirstServer`, which it supersedes —
    /// that one stays so logs written before it still replay.
    case setServeOrder(round: Int, court: Int, order: ServeOrder)
    /// On a golden/star sudden-death point the receiving team picks which side it is
    /// served to.
    case chooseServeSide(ServeCourt)
    case setRoundConfirmed(round: Int, isConfirmed: Bool)
    /// The whistle in winner court: closes round `round` wherever it stands. Naming the
    /// round makes it idempotent — if both devices whistle, the second is a no-op instead
    /// of closing a second round. `at` is where the next round's clock starts.
    case endRound(round: Int, at: Date? = nil)
    /// Draws the round after `after`, and only if that is still the last one — so two
    /// devices advancing at once produce one new round, not two. `at` is where the drawn
    /// round's clock starts.
    case nextRound(after: Int, at: Date? = nil)
    /// Ends the session. `archive` is false when it is being thrown away rather than kept,
    /// and travels with the event so the other device does not file it either.
    case finish(archive: Bool)
    /// Picks an archived session back up. It carries the whole state rather than the events
    /// that built it, because the log a session was played from is not kept once it is
    /// filed away — only what it came to.
    case restore(SessionState)
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
        // A serve correction is its own undo — swapping again puts it back — and undo
        // should keep meaning "take back the last thing that changed the score".
        case .configure, .restore, .undo, .chooseServeSide, .setFirstServer, .setServeOrder: false
        }
    }
}
