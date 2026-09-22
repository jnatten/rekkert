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
        let payload = Data("H7K3MR".utf8)
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
}

@Suite("Sealed frames")
struct SealedFrameTests {
    private let code = SessionCode("H7K3MR")!

    @Test func aFrameComesBackAsItself() throws {
        let key = SessionKey.sealingKey(for: code, share: share)
        let frame = Frame(kind: .request, correlation: 42, payload: Data("score".utf8))

        let sealed = try #require(SealedFrame.seal(frame, with: key))
        #expect(SealedFrame.open(sealed, with: key) == frame)
    }

    @Test func theWrongCodeOpensNothing() throws {
        let frame = Frame(kind: .oneway, payload: Data("score".utf8))
        let sealed = try #require(
            SealedFrame.seal(frame, with: SessionKey.sealingKey(for: code, share: share))
        )

        let wrongCode = SessionKey.sealingKey(for: SessionCode("K9M4PT")!, share: share)
        #expect(SealedFrame.open(sealed, with: wrongCode) == nil)

        // And a code overheard at one match is worth nothing at the next.
        let wrongShare = SessionKey.sealingKey(for: code, share: other)
        #expect(SealedFrame.open(sealed, with: wrongShare) == nil)
    }

    @Test func aTamperedFrameOpensNothing() throws {
        let key = SessionKey.sealingKey(for: code, share: share)
        var sealed = try #require(SealedFrame.seal(Frame(kind: .oneway, payload: Data("1-0".utf8)), with: key))
        sealed[sealed.count - 1] ^= 0xFF

        #expect(SealedFrame.open(sealed, with: key) == nil)
    }

    @Test func rubbishOpensNothing() {
        let key = SessionKey.sealingKey(for: code, share: share)
        #expect(SealedFrame.open(Data(), with: key) == nil)
        #expect(SealedFrame.open(Data(repeating: 7, count: 64), with: key) == nil)
    }

    /// The whole point of sealing over Bluetooth: it is the same guarantee the pre-shared key
    /// gives on the local network, so neither link is the weak one.
    @Test func sealingIsNotTheSameKeyAsTheHandshake() {
        #expect(
            SessionKey.sealingKey(for: code, share: share)
                != SessionKey.presharedKey(for: code, share: share)
        )
    }
}
