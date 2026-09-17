import CryptoKit
import Foundation

/// A frame with the session code wrapped around it.
///
/// Bluetooth has no TLS, so the property the local network gets from a pre-shared-key handshake
/// has to be built here instead: a phone without the code can neither read what goes past nor
/// put anything of its own on the link. Every frame is sealed, so there is no moment after
/// which the connection is trusted — a peer that stops being able to produce openable frames
/// stops being listened to, whatever it said a moment ago.
nonisolated enum SealedFrame {
    static func seal(_ frame: Frame, with key: SymmetricKey) -> Data? {
        try? ChaChaPoly.seal(FrameCodec.encode(frame), using: key).combined
    }

    /// `nil` for anything that will not open, which is the same answer for a wrong code, a
    /// corrupted packet and a peer making things up. None of the three is worth telling apart.
    static func open(_ sealed: Data, with key: SymmetricKey) -> Frame? {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed),
              let plain = try? ChaChaPoly.open(box, using: key)
        else { return nil }

        var buffer = plain
        guard let frames = try? FrameCodec.decode(from: &buffer),
              let frame = frames.first, frames.count == 1, buffer.isEmpty
        else { return nil }
        return frame
    }
}
