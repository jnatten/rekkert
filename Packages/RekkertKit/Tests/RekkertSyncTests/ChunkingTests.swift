import CryptoKit
import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let share = UUID(uuidString: "6F2A9C41-0000-0000-0000-000000000001")!
private let other = UUID(uuidString: "6F2A9C41-0000-0000-0000-000000000002")!

/// The byte handling on its own. This is where a packet protocol usually goes wrong — a
/// message that lands one byte over the limit, a read that stops halfway — and none of it
/// needs a radio.
@Suite("Chunking")
struct ChunkingTests {
    private func roundTrip(_ payload: Data, mtu: Int) throws -> Data? {
        let reassembler = Chunking.Reassembler()
        var last: Data?
        for chunk in Chunking.split(payload, mtu: mtu) {
            #expect(chunk.count <= mtu, "a chunk never exceeds what the link will carry")
            last = try reassembler.accept(chunk)
        }
        return last
    }

    @Test func aMessageThatFitsTravelsWhole() throws {
        let payload = Data("482915".utf8)
        #expect(Chunking.split(payload, mtu: 180).count == 1)
        #expect(try roundTrip(payload, mtu: 180) == payload)
    }

    @Test func aLongMessageComesBackTheSame() throws {
        let payload = Data((0 ..< 5_000).map { UInt8($0 % 251) })
        let chunks = Chunking.split(payload, mtu: 180)
        #expect(chunks.count > 1)
        #expect(try roundTrip(payload, mtu: 180) == payload)
    }

    /// The boundaries a full match log will find on its own eventually.
    @Test(arguments: [0, 1, 178, 179, 180, 181, 358, 359, 360, 4_096])
    func anySizeSurvivesTheRoundTrip(_ size: Int) throws {
        let payload = Data((0 ..< size).map { UInt8($0 % 251) })
        #expect(try roundTrip(payload, mtu: 180) == payload)
    }

    /// A pocketed phone gets a smaller allowance, and the smallest one still has to work.
    @Test(arguments: [2, 3, 20, 512])
    func aNarrowLinkStillCarriesIt(_ mtu: Int) throws {
        let payload = Data((0 ..< 300).map { UInt8($0 % 251) })
        #expect(try roundTrip(payload, mtu: mtu) == payload)
    }

    @Test func nothingIsSaidUntilTheLastChunkArrives() throws {
        let payload = Data((0 ..< 1_000).map { UInt8($0 % 251) })
        let chunks = Chunking.split(payload, mtu: 180)
        let reassembler = Chunking.Reassembler()

        for chunk in chunks.dropLast() {
            #expect(try reassembler.accept(chunk) == nil, "still mid-message")
        }
        #expect(try reassembler.accept(chunks.last!) == payload)
    }

    @Test func aLinkThatDroppedMidMessageDoesNotPoisonTheNextOne() throws {
        let payload = Data((0 ..< 1_000).map { UInt8($0 % 251) })
        let reassembler = Chunking.Reassembler()
        _ = try reassembler.accept(Chunking.split(payload, mtu: 180)[0])

        reassembler.reset()

        let fresh = Data("after the drop".utf8)
        #expect(try reassembler.accept(Chunking.split(fresh, mtu: 180)[0]) == fresh)
    }

    @Test func aPeerClaimingMoreThanWeWillHoldIsRefused() {
        let reassembler = Chunking.Reassembler()
        let chunk = Data([1]) + Data(repeating: 0, count: 1_024)
        #expect(throws: Chunking.Fault.oversized) {
            // Never terminated, so it would grow for as long as the peer kept talking.
            for _ in 0 ... (Chunking.maximumMessage / 1_024) {
                _ = try reassembler.accept(chunk)
            }
        }
    }

    /// A 512-byte chunk over a link that carries 182 at a time, as the host is handed it.
    private func pieces(of chunk: Data, packet: Int = 182) -> [(offset: Int, value: Data)] {
        stride(from: 0, to: chunk.count, by: packet).map { start in
            (start, chunk.subdata(in: start ..< min(start + packet, chunk.count)))
        }
    }

    @Test func aChunkWrittenInPiecesIsPutBackTogether() throws {
        let payload = Data((0 ..< 3_000).map { UInt8($0 % 251) })
        let reassembler = Chunking.Reassembler()
        var last: Data?
        for chunk in Chunking.split(payload, mtu: 512) {
            for rebuilt in Chunking.chunks(fromWrites: pieces(of: chunk)) {
                last = try reassembler.accept(rebuilt)
            }
        }
        #expect(last == payload)
    }

    @Test func twoWritesHandedOverTogetherStayTwo() {
        let first = Data(repeating: 1, count: 300)
        let second = Data(repeating: 2, count: 40)
        #expect(Chunking.chunks(fromWrites: pieces(of: first) + pieces(of: second)) == [first, second])
    }

    /// A link can report more room than an attribute has. Written at that length, every chunk
    /// over 512 bytes was refused, and nothing longer than one packet ever arrived.
    @Test func noChunkIsLongerThanAnAttributeCanHold() {
        #expect(Chunking.packetLength(reportedMaximum: 514) == 512)
        #expect(Chunking.packetLength(reportedMaximum: 182) == 182)
        let chunks = Chunking.split(Data(repeating: 1, count: 5_000), mtu: Chunking.packetLength(reportedMaximum: 514))
        #expect(chunks.allSatisfy { $0.count <= 512 })
    }

    @Test func aPieceThatContinuesNothingIsDropped() {
        let chunk = Data(repeating: 3, count: 300)
        #expect(Chunking.chunks(fromWrites: Array(pieces(of: chunk).dropFirst())).isEmpty)
    }
}

@Suite("Sealed frames")
struct SealedFrameTests {
    private let code = SessionCode("482915")!

    @Test func aFrameComesBackAsItself() throws {
        let key = SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest)
        let frame = Frame(kind: .request, correlation: 42, payload: Data("score".utf8))

        let sealed = try #require(SealedFrame.seal(frame, with: key))
        #expect(SealedFrame.open(sealed, with: key) == frame)
    }

    @Test func theWrongCodeOpensNothing() throws {
        let frame = Frame(kind: .oneway, payload: Data("score".utf8))
        let sealed = try #require(
            SealedFrame.seal(frame, with: SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest))
        )

        let wrongCode = SessionKey.sealingKey(for: SessionCode("730264")!, share: share, direction: .hostToGuest)
        #expect(SealedFrame.open(sealed, with: wrongCode) == nil)

        // And a code overheard at one match is worth nothing at the next.
        let wrongShare = SessionKey.sealingKey(for: code, share: other, direction: .hostToGuest)
        #expect(SealedFrame.open(sealed, with: wrongShare) == nil)
    }

    @Test func aTamperedFrameOpensNothing() throws {
        let key = SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest)
        var sealed = try #require(SealedFrame.seal(Frame(kind: .oneway, payload: Data("1-0".utf8)), with: key))
        sealed[sealed.count - 1] ^= 0xFF

        #expect(SealedFrame.open(sealed, with: key) == nil)
    }

    @Test func aFrameOverTheLimitIsNotSealed() {
        let key = SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest)
        #expect(SealedFrame.seal(Frame(kind: .oneway, payload: Data(count: FrameCodec.maximumPayload + 1)), with: key) == nil)
    }

    @Test func rubbishOpensNothing() {
        let key = SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest)
        #expect(SealedFrame.open(Data(), with: key) == nil)
        #expect(SealedFrame.open(Data(repeating: 7, count: 64), with: key) == nil)
    }

    /// One key for both ways let a guest's own frame open for that guest, so a peripheral that did
    /// nothing but echo passed the proof and stood in for the host. Each way has its own key.
    @Test func aFrameSealedOneWayDoesNotOpenTheOther() throws {
        let frame = Frame(kind: .oneway, payload: Data())
        let fromGuest = try #require(SealedFrame.seal(
            frame, with: SessionKey.sealingKey(for: code, share: share, direction: .guestToHost)
        ))
        #expect(SealedFrame.open(fromGuest, with: SessionKey.sealingKey(for: code, share: share, direction: .guestToHost)) == frame)
        #expect(SealedFrame.open(fromGuest, with: SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest)) == nil,
                "echoed back, it opens nothing")
    }

    /// The whole point of sealing over Bluetooth: it is the same guarantee the pre-shared key
    /// gives on the local network, so neither link is the weak one.
    @Test func sealingIsNotTheSameKeyAsTheHandshake() {
        #expect(
            SessionKey.sealingKey(for: code, share: share, direction: .hostToGuest)
                != SessionKey.presharedKey(for: code, share: share)
        )
    }
}
