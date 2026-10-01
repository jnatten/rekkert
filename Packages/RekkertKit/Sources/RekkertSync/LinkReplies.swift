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

    /// How long a frame waits for its turn on the link before it is dropped unsent, in seconds.
    /// A question nobody waits for any more is not worth asking. An answer is still true after
    /// the asker gave up waiting — it is handed on late above — and over Bluetooth the one to a
    /// hello, everything the asker was missing, sits behind whatever big frame was already going
    /// out. Nothing for a oneway, which nobody waits for.
    static func patience(for kind: Frame.Kind, replyTimeout seconds: Int) -> Int? {
        switch kind {
        case .oneway: nil
        case .request: seconds
        case .reply: seconds * 8
        }
    }
}

/// Whether a peer that is still connected is still answering.
///
/// A link can stay up and carry nothing: the host stopped sharing or its app went away, and
/// Bluetooth kept the connection. The peer went on counting as there, so the loss was never
/// noticed, every send waited on it, and nothing it was sent was ever acknowledged.
nonisolated struct LinkHealth {
    /// In a row, and only questions that went out whole: a peer still being sent a long frame
    /// is slow, not gone.
    static let patience = 3
    private(set) var misses = 0

    mutating func answered() { misses = 0 }

    /// Whether that was one too many.
    mutating func missed() -> Bool {
        misses += 1
        return misses >= Self.patience
    }
}
