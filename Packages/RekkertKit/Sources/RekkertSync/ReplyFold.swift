import Foundation
import RekkertCore

/// Folds several peers' answers into the single answer `MatchStore` was written to expect.
///
/// Sending to more than one counterpart at a time is the whole difficulty of sharing a match:
/// the store asks one question and needs one answer, but the outbox may only forget what has
/// reached *everybody*. So the bound is the peer furthest behind, and there is no bound at all
/// unless every one of them replied.
nonisolated enum ReplyFold {
    struct Folded {
        /// What to hand back to the store, if anything can be acknowledged.
        var acknowledgement: Data?
        /// Answers that were not acknowledgements — a snapshot, a retirement notice — which
        /// still have to reach the store even though nobody asked them a question.
        var unsolicited: [Data] = []
    }

    /// `expected` is how many were sent to. A reply missing from the list is a peer that did
    /// not answer, and acknowledging past it would drop events it never received.
    static func fold(_ replies: [Data?], expected: Int) -> Folded {
        var folded = Folded()
        var sessionID: UUID?
        var vectors: [VersionVector] = []
        var agree = true
        var only: (from: DeviceID?, clock: Date?, sharing: Int?)?

        for reply in replies.compactMap({ $0 }) {
            guard case .hello(let session, let vector, let from, let clock, let sharing)? = try? Wire.decode(reply) else {
                folded.unsolicited.append(reply)
                continue
            }
            sessionID = sessionID ?? session
            agree = agree && session == sessionID
            vectors.append(vector)
            only = (from, clock, sharing)
        }

        guard let sessionID, agree, vectors.count == expected else { return folded }
        // One answer is that device's own, clock and all (spec 005, D-2). Several have no one
        // clock between them.
        let single = vectors.count == 1 ? only : nil
        folded.acknowledgement = try? Wire.hello(
            sessionID: sessionID,
            vector: VersionVector.lowerBound(of: vectors),
            from: single?.from, clock: single?.clock, protocol: single?.sharing
        ).encoded()
        return folded
    }
}
