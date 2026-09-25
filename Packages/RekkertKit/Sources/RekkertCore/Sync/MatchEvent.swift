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
    /// Calls a tournament round off so it counts for nobody. Only the last round can be,
    /// so a cancel that arrives after the next draw cannot void what that draw was built on.
    case setRoundCancelled(round: Int, isCancelled: Bool)
    /// The whistle in winner court: closes round `round` wherever it stands. Naming the
    /// round makes it idempotent — if both devices whistle, the second is a no-op instead
    /// of closing a second round. `at` is where the next round's clock starts.
    case endRound(round: Int, at: Date? = nil)
    /// Draws the round after `after`, and only if that is still the last one — so two
    /// devices advancing at once produce one new round, not two. `at` is where the drawn
    /// round's clock starts.
    ///
    /// `sitOuts` are players picked to sit the round out, the rest of the bench drawn as
    /// usual. With them it also draws the round after `after` again when that has already
    /// been drawn but nothing has been played in it, which is how the bench is picked by
    /// hand: the round is drawn as always, then drawn again around who is actually there.
    /// Absent from older builds, which drop it and keep the round they drew.
    case nextRound(after: Int, at: Date? = nil, sitOuts: [PlayerID]? = nil)
    /// Ends the session. `archive` is false when it is being thrown away rather than kept,
    /// and travels with the event so the other device does not file it either.
    case finish(archive: Bool)
    /// Picks an archived session back up. It carries the whole state rather than the events
    /// that built it, because the log a session was played from is not kept once it is
    /// filed away — only what it came to.
    ///
    /// `takingBack` names the session a result was taken back from, when that is what this
    /// is: the same match going on, so whatever filed that session's record should drop it.
    case restore(SessionState, takingBack: UUID? = nil)
    case undo(EventID)
}

public struct MatchEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: EventID
    public let lamport: UInt64
    public let kind: EventKind
    /// When the device that recorded it did, by its own clock. For the timeline only: the
    /// log is ordered by Lamport stamp, and nothing that decides the score reads this.
    /// Absent from events written before it existed, and dropped by an older build that
    /// passes one on, which is harmless because an event is known by its id.
    public let at: Date?

    public init(id: EventID, lamport: UInt64, kind: EventKind, at: Date? = nil) {
        self.id = id
        self.lamport = lamport
        self.kind = kind
        self.at = at
    }

    /// A moment to a tenth of a second: finer than any timeline is drawn at, and a dozen
    /// bytes shorter on every event than the full-precision number.
    public static func stamp(_ date: Date = Date()) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate * 10).rounded() / 10)
    }

    /// Events an undo can target. Configuration and undo itself are excluded so that
    /// "undo" always means "take back the last thing that changed the score".
    public var isUndoable: Bool {
        switch kind {
        case .point, .setScore, .setRoundConfirmed, .setRoundCancelled, .nextRound, .finish, .endRound: true
        // A serve correction is its own undo — swapping again puts it back — and undo
        // should keep meaning "take back the last thing that changed the score".
        case .configure, .restore, .undo, .chooseServeSide, .setFirstServer, .setServeOrder: false
        }
    }
}

extension EventKind {
    /// The moment the few kinds that carry one were stamped with, for logs whose events
    /// predate `MatchEvent.at`.
    public var payloadDate: Date? {
        switch self {
        case .configure(_, let at), .endRound(_, let at), .nextRound(_, let at, _): at
        case .point, .setScore, .setFirstServer, .setServeOrder, .chooseServeSide,
             .setRoundConfirmed, .setRoundCancelled, .finish, .restore, .undo: nil
        }
    }
}
