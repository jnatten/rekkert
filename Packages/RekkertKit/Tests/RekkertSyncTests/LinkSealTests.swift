import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let code = SessionCode("482915")!
private let share = UUID(uuidString: "6F2A9C41-0000-0000-0000-000000000001")!
private let other = UUID(uuidString: "6F2A9C41-0000-0000-0000-000000000002")!

private struct Refused: Error {}

private extension LinkSeal {
    mutating func sealing(_ frame: Frame) throws -> Data {
        guard let sealed = seal(frame) else { throw Refused() }
        return sealed
    }

    mutating func sealing(_ score: String) throws -> Data {
        try sealing(Frame(kind: .oneway, payload: Data(score.utf8)))
    }
}

/// A guest and a host through the whole proof, and what the wire carried on the way.
private struct Connection {
    var guest = LinkSeal(role: .guest, code: code, share: share)
    var host = LinkSeal(role: .host, code: code, share: share)
    var challenge = Data()
    var answer = Data()
    var confirmation = Data()

    static func proven() throws -> Connection {
        var connection = Connection()
        guard let challenge = connection.guest.challenge(),
              case .answer(let answer)? = connection.host.open(challenge),
              case .proven(let confirmation?)? = connection.guest.open(answer),
              connection.host.open(confirmation) == .proven(confirmation: nil)
        else { throw Refused() }
        connection.challenge = challenge
        connection.answer = answer
        connection.confirmation = confirmation
        return connection
    }
}

@Suite("Sealing a Bluetooth connection")
struct LinkSealTests {
    @Test func bothEndsProveThemselvesAndAFrameComesBackAsItself() throws {
        var connection = try Connection.proven()
        #expect(connection.guest.isProven)
        #expect(connection.host.isProven)

        let frame = Frame(kind: .request, correlation: 42, payload: Data("score".utf8))
        let fromGuest = try connection.guest.sealing(frame)
        let atHost = connection.host.open(fromGuest)
        #expect(atHost == .frame(frame))
        let fromHost = try connection.host.sealing(frame)
        let atGuest = connection.guest.open(fromHost)
        #expect(atGuest == .frame(frame))
    }

    @Test func nothingIsSealedBeforeTheOtherEndHasProvedItself() {
        var guest = LinkSeal(role: .guest, code: code, share: share)
        var host = LinkSeal(role: .host, code: code, share: share)
        #expect((try? guest.sealing("1-0")) == nil)
        #expect((try? host.sealing("1-0")) == nil)
        #expect(host.challenge() == nil, "only a guest opens")
    }

    @Test func theWrongCodeProvesNothing() throws {
        let guest = LinkSeal(role: .guest, code: code, share: share)
        var wrongCode = LinkSeal(role: .host, code: SessionCode("730264")!, share: share)
        var wrongShare = LinkSeal(role: .host, code: code, share: other)
        let challenge = try #require(guest.challenge())

        let withWrongCode = wrongCode.open(challenge)
        #expect(withWrongCode == nil)
        // And a code overheard at one match is worth nothing at the next.
        let withWrongShare = wrongShare.open(challenge)
        #expect(withWrongShare == nil)
    }

    /// The proof used to be one fixed frame sealed with a key the whole match shares. Caught once,
    /// it proved anything that played it back to every guest that came after.
    @Test func aHostsAnswerCaughtOnceProvesNothingToTheNextGuest() throws {
        let earlier = try Connection.proven()
        var next = LinkSeal(role: .guest, code: code, share: share)
        _ = try #require(next.challenge())

        let opened = next.open(earlier.answer)
        #expect(opened == nil)
        #expect(!next.isProven)
    }

    /// And the guest's side of it: a challenge and a confirmation played back from an earlier
    /// connection got a stranger counted as a guest, holding everybody's acknowledgement back.
    @Test func aGuestsProofCaughtOnceProvesNothingToTheHost() throws {
        let earlier = try Connection.proven()
        var host = LinkSeal(role: .host, code: code, share: share)

        guard case .answer? = host.open(earlier.challenge) else { throw Refused() }
        let confirmed = host.open(earlier.confirmation)
        #expect(confirmed == nil)
        #expect(!host.isProven)
    }

    @Test func aFrameFromAnotherConnectionDoesNotOpen() throws {
        var earlier = try Connection.proven()
        var later = try Connection.proven()
        let frame = try earlier.guest.sealing("1-0")

        let elsewhere = later.host.open(frame)
        #expect(elsewhere == nil)
        let here = earlier.host.open(frame)
        #expect(here != nil)
    }

    @Test func aFrameOpensOnce() throws {
        var connection = try Connection.proven()
        let first = try connection.guest.sealing("1-0")
        let second = try connection.guest.sealing("2-0")

        let opened = [first, first, second, first].map { connection.host.open($0) != nil }
        #expect(opened == [true, false, true, false], "played back, in order or out of it, it opens nothing")
    }

    /// A frame lost on the way — a write that failed — leaves a gap, and what follows it still opens.
    @Test func aFrameLostOnTheWayDoesNotStopTheOnesAfterIt() throws {
        var connection = try Connection.proven()
        _ = try connection.guest.sealing("lost")
        let after = try connection.guest.sealing("1-0")
        let opened = connection.host.open(after)
        #expect(opened != nil)
    }

    /// One key for both ways let a guest's own frame open for that guest, so a peripheral that did
    /// nothing but echo passed the proof and stood in for the host. Each way has its own key.
    @Test func whatOneEndSealsDoesNotOpenForItself() throws {
        var guest = LinkSeal(role: .guest, code: code, share: share)
        let challenge = try #require(guest.challenge())
        let echoed = guest.open(challenge)
        #expect(echoed == nil, "echoed back, it opens nothing")

        var connection = try Connection.proven()
        let frame = try connection.guest.sealing("1-0")
        let echoedFrame = connection.guest.open(frame)
        #expect(echoedFrame == nil)
    }

    @Test func aTamperedFrameOpensNothing() throws {
        var connection = try Connection.proven()
        var sealed = try connection.guest.sealing("1-0")
        sealed[sealed.count - 1] ^= 0xFF
        let tampered = connection.host.open(sealed)
        #expect(tampered == nil)

        var relabelled = try connection.guest.sealing("2-0")
        relabelled[relabelled.startIndex] = 3
        let passedOff = connection.host.open(relabelled)
        #expect(passedOff == nil, "a frame cannot pass for part of the proof")
    }

    @Test func aFrameOverTheLimitIsNotSealed() throws {
        var connection = try Connection.proven()
        let oversized = Frame(kind: .oneway, payload: Data(count: FrameCodec.maximumPayload + 1))
        #expect((try? connection.guest.sealing(oversized)) == nil)
    }

    @Test func rubbishOpensNothing() throws {
        var connection = try Connection.proven()
        let opened = [Data(), Data(repeating: 7, count: 64), Data([4]) + Data(repeating: 7, count: 64)]
            .map { connection.host.open($0) }
        #expect(opened == [nil, nil, nil])
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
