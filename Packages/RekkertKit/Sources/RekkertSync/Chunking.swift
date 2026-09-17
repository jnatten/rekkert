import Foundation

/// Splitting a frame across Bluetooth packets, and putting it back together.
///
/// Bluetooth hands over something like 180 bytes at a time, and fewer once the phone is in a
/// pocket and the connection interval has been relaxed. `FrameCodec`'s length prefix is no use
/// at that size — the length has to arrive before the thing it measures, and here it may not
/// fit in the same packet.
///
/// What makes a single byte enough is that a GATT connection delivers in order and without
/// gaps: every write is acknowledged and every notification queued, so the only question a
/// chunk has to answer is whether more of the message is coming. A connection that drops
/// mid-message takes its half-built buffer with it, which is what `reset()` is for.
nonisolated enum Chunking {
    static let headerSize = 1
    private static let more: UInt8 = 1
    private static let last: UInt8 = 0

    /// A peer claiming a message longer than this is broken or hostile, and either way the
    /// answer is to hang up rather than to go on allocating for it.
    static let maximumMessage = FrameCodec.maximumPayload

    enum Fault: Error, Equatable {
        case oversized
    }

    /// `mtu` is the whole packet, header included. An empty payload still produces one chunk:
    /// a message nobody sent and a message that says nothing are different things.
    static func split(_ payload: Data, mtu: Int) -> [Data] {
        let room = Swift.max(1, mtu - headerSize)
        guard payload.count > room else {
            return [Data([last]) + payload]
        }

        var chunks: [Data] = []
        var offset = payload.startIndex
        while offset < payload.endIndex {
            let end = Swift.min(offset + room, payload.endIndex)
            let isLast = end == payload.endIndex
            chunks.append(Data([isLast ? last : more]) + payload[offset ..< end])
            offset = end
        }
        return chunks
    }

    /// Holds the pieces until a message is whole. Not `Sendable` on purpose: it belongs to one
    /// link, and the transport keeps it under the same lock as everything else about that link.
    final class Reassembler {
        private var buffer = Data()

        /// The finished message, or `nil` while there is more to come.
        func accept(_ chunk: Data) throws -> Data? {
            guard let flag = chunk.first else { return nil }
            let body = chunk.dropFirst()
            guard buffer.count + body.count <= maximumMessage else {
                buffer = Data()
                throw Fault.oversized
            }
            buffer.append(body)
            guard flag == last else { return nil }
            defer { buffer = Data() }
            return buffer
        }

        func reset() {
            buffer = Data()
        }
    }
}
