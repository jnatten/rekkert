import Foundation
import Testing
@testable import RekkertSync

private func payload(_ size: Int, seed: UInt8 = 0) -> Data {
    Data((0 ..< size).map { UInt8(truncatingIfNeeded: $0 &+ Int(seed)) })
}

@Suite("Framing")
struct FramingTests {
    @Test func aFrameSurvivesTheRoundTrip() throws {
        for size in [0, 1, 9, 1024, 3 << 20] {
            let original = Frame(kind: .request, correlation: 7, payload: payload(size))
            var buffer = FrameCodec.encode(original)
            let decoded = try FrameCodec.decode(from: &buffer)

            #expect(decoded == [original], "size \(size)")
            #expect(buffer.isEmpty, "nothing left over")
        }
    }

    @Test func everyKindAndCorrelationComesBackIntact() throws {
        let frames = [
            Frame(kind: .request, correlation: 1, payload: payload(3)),
            Frame(kind: .reply, correlation: .max, payload: Data()),
            Frame(kind: .oneway, correlation: 0, payload: payload(64, seed: 9)),
        ]
        var buffer = frames.map(FrameCodec.encode).reduce(Data(), +)
        #expect(try FrameCodec.decode(from: &buffer) == frames)
        #expect(buffer.isEmpty)
    }

    /// The failure a stream protocol actually has: a read that stops in the middle of a
    /// message. Feeding the same bytes one at a time must produce the same frames.
    @Test func aByteAtATimeIsTheSameAsAllAtOnce() throws {
        let frames = [
            Frame(kind: .request, correlation: 11, payload: payload(200)),
            Frame(kind: .reply, correlation: 11, payload: payload(1, seed: 5)),
            Frame(kind: .oneway, payload: payload(3000, seed: 2)),
        ]
        let stream = frames.map(FrameCodec.encode).reduce(Data(), +)

        var buffer = Data()
        var collected: [Frame] = []
        for byte in stream {
            buffer.append(byte)
            collected.append(contentsOf: try FrameCodec.decode(from: &buffer))
        }

        #expect(collected == frames)
        #expect(buffer.isEmpty)
    }

    @Test func aPartialFrameIsLeftWhereItIs() throws {
        let frame = Frame(kind: .request, correlation: 4, payload: payload(100))
        let encoded = FrameCodec.encode(frame)

        var buffer = encoded.prefix(encoded.count - 1)
        #expect(try FrameCodec.decode(from: &buffer).isEmpty, "not yet")
        #expect(buffer.count == encoded.count - 1, "and kept for the next read")

        buffer.append(encoded.last!)
        #expect(try FrameCodec.decode(from: &buffer) == [frame])
    }

    @Test func aHeaderOnItsOwnIsNotAFrame() throws {
        var buffer = FrameCodec.encode(Frame(kind: .oneway, payload: payload(10))).prefix(FrameCodec.headerSize)
        #expect(try FrameCodec.decode(from: &buffer).isEmpty)
        #expect(buffer.count == FrameCodec.headerSize)
    }

    /// Refused on the claim rather than on delivery, so nothing allocates what a hostile or
    /// broken peer asked for.
    @Test func anImpossibleLengthIsRefusedBeforeAnythingIsAllocated() {
        var buffer = Data()
        let absurd = UInt32(FrameCodec.maximumPayload + 1)
        buffer.append(contentsOf: [
            UInt8(truncatingIfNeeded: absurd >> 24), UInt8(truncatingIfNeeded: absurd >> 16),
            UInt8(truncatingIfNeeded: absurd >> 8), UInt8(truncatingIfNeeded: absurd),
        ])
        buffer.append(contentsOf: [0, 0, 0, 0, 0])

        #expect(throws: FrameCodec.Fault.oversized) { try FrameCodec.decode(from: &buffer) }
    }

    @Test func anUnknownKindIsRefused() {
        var buffer = Data([0, 0, 0, 0, 99, 0, 0, 0, 0])
        #expect(throws: FrameCodec.Fault.unknownKind(99)) { try FrameCodec.decode(from: &buffer) }
    }

    /// Arbitrary bytes must never crash, hang, or invent a frame that does not re-encode to
    /// what it came from.
    @Test func randomBytesAreSurvivable() throws {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 2_000 {
            var buffer = Data((0 ..< Int.random(in: 0 ... 80, using: &generator)).map { _ in
                UInt8.random(in: 0 ... 255, using: &generator)
            })
            let before = buffer
            guard let frames = try? FrameCodec.decode(from: &buffer) else { continue }

            let consumed = before.count - buffer.count
            let reencoded = frames.map(FrameCodec.encode).reduce(Data(), +)
            #expect(reencoded == before.prefix(consumed), "what came out is what went in")
        }
    }
}
