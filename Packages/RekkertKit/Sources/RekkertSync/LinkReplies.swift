import Foundation
import RekkertCore

/// Decisions both links make the same way about what goes over them, kept apart from the links
/// themselves because neither exists where the tests run.
nonisolated enum LinkReplies {
    /// What a host sends a Bluetooth peer the moment that peer has proved it holds the code.
    ///
    /// The probe first: it is the host's own proof, and the guest gives the host only so long to
    /// produce one. Behind a whole match's snapshot, it arrived after the guest had given up and
    /// written the right host off as somebody else's court.
    static func opening(snapshot: Data?, probe: Frame) -> [Frame] {
        [probe] + (snapshot.map { [Frame(kind: .oneway, payload: $0)] } ?? [])
    }
}
