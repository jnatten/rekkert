import Foundation
import RekkertCore

/// Decisions both links make the same way about what goes over them, kept apart from the links
/// themselves because neither exists where the tests run.
nonisolated enum LinkReplies {
    /// A reply that turns up after its question was given up on. An acknowledgement is worth
    /// nothing by then, but anything else is still true: most of all the answer to a hello, which
    /// is everything the asker was missing and over Bluetooth takes longer than the wait to arrive.
    static func isWorthHandingOn(late payload: Data) -> Bool {
        guard let wire = try? Wire.decode(payload) else { return false }
        if case .hello = wire { return false }
        return true
    }

    /// What a host sends a Bluetooth peer the moment that peer has proved it holds the code.
    ///
    /// The probe first: it is the host's own proof, and the guest gives the host only so long to
    /// produce one. Behind a whole match's snapshot, it arrived after the guest had given up and
    /// written the right host off as somebody else's court.
    static func opening(snapshot: Data?, probe: Frame) -> [Frame] {
        [probe] + (snapshot.map { [Frame(kind: .oneway, payload: $0)] } ?? [])
    }
}
