import Foundation

/// One message on a stream connection.
///
/// A TCP connection is bytes, not messages, and `PeerTransport.sendLive` is a question that
/// expects its own answer back. So each payload carries its length, what it is, and a number
/// that ties an answer to the question that asked it.
nonisolated public struct Frame: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        /// Expects a `reply` carrying the same correlation.
        case request = 0
        case reply = 1
        /// Sent without being asked, and nobody answers it.
        case oneway = 2
    }

    public var kind: Kind
    public var correlation: UInt32
    public var payload: Data

    public init(kind: Kind, correlation: UInt32 = 0, payload: Data) {
        self.kind = kind
        self.correlation = correlation
        self.payload = payload
    }
}

/// Length-prefixed frames, kept apart from the networking so the byte handling can be tested
/// on its own. This is where a stream protocol usually goes wrong — a receive that lands in
/// the middle of a message, two messages arriving in one read — and none of that needs a
/// socket to exercise.
nonisolated public enum FrameCodec {
    /// `[UInt32 length][UInt8 kind][UInt32 correlation]`, big-endian.
    public static let headerSize = 9

    /// A peer claiming a bigger message than this is either broken or hostile. Either way the
    /// answer is to hang up rather than to allocate what it asked for.
    public static let maximumPayload = 4 << 20

    public enum Fault: Error, Equatable {
        case oversized
        case unknownKind(UInt8)
    }

    public static func encode(_ frame: Frame) -> Data {
        var out = Data(capacity: headerSize + frame.payload.count)
        out.append(bigEndian: UInt32(frame.payload.count))
        out.append(frame.kind.rawValue)
        out.append(bigEndian: frame.correlation)
        out.append(frame.payload)
        return out
    }

    /// Takes every whole frame the buffer holds and leaves the rest in place, so a receive
    /// that stops mid-frame simply contributes nothing this time round.
    public static func decode(from buffer: inout Data) throws -> [Frame] {
        var frames: [Frame] = []
        var offset = buffer.startIndex

        while buffer.endIndex - offset >= headerSize {
            let length = Int(buffer.readingBigEndian(at: offset))
            guard length <= maximumPayload else { throw Fault.oversized }
            guard buffer.endIndex - offset >= headerSize + length else { break }

            let raw = buffer[offset + 4]
            guard let kind = Frame.Kind(rawValue: raw) else { throw Fault.unknownKind(raw) }
            let correlation = buffer.readingBigEndian(at: offset + 5)
            let start = offset + headerSize

            frames.append(Frame(
                kind: kind,
                correlation: correlation,
                payload: Data(buffer[start ..< start + length])
            ))
            offset += headerSize + length
        }

        buffer = Data(buffer[offset...])
        return frames
    }
}

// Nonisolated because the package builds this target MainActor-by-default, and framing runs
// on the connection's own queue.
nonisolated private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ])
    }

    func readingBigEndian(at index: Index) -> UInt32 {
        (0 ..< 4).reduce(UInt32(0)) { ($0 << 8) | UInt32(self[index + $1]) }
    }
}
