import CryptoKit
import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Pinned so a code drawn in a test is the same one every run.
private struct FixedGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private let share = UUID(uuidString: "6F2A9C41-0000-0000-0000-000000000001")!
private let other = UUID(uuidString: "6F2A9C41-0000-0000-0000-000000000002")!

@Suite("Session codes")
struct SessionCodeTests {
    @Test func itIsDigitsOnlySoANumberPadIsEnough() {
        #expect(String(SessionCode.alphabet) == "0123456789")
    }

    @Test func itIsReadBackTheWayItWasHeard() throws {
        let spoken = try #require(SessionCode("482915"))

        for variant in ["482-915", "482 915", "  482-915  "] {
            #expect(SessionCode(variant) == spoken, "\(variant)")
        }
    }

    @Test func lettersThatLookLikeDigitsBecomeThem() throws {
        #expect(SessionCode("O82915")?.letters == "082915")
        #expect(SessionCode("I82915")?.letters == "182915")
        #expect(SessionCode("l82915")?.letters == "182915")
    }

    @Test func anythingThatIsNotACodeIsRefusedWhole() {
        #expect(SessionCode("48291") == nil, "too short")
        #expect(SessionCode("4829155") == nil, "too long")
        #expect(SessionCode("") == nil)
        // Dropping the stray character would shift the rest along and silently make a
        // different, perfectly valid code.
        #expect(SessionCode("48291!5") == nil)
        #expect(SessionCode("48291A") == nil, "letters are not in the alphabet")
    }

    @Test func itIsShownInTwoGroupsForReadingAloud() throws {
        #expect(try #require(SessionCode("482915")).description == "482-915")
    }

    @Test func drawingOneIsRepeatableWhenThePickerIs() {
        var one = FixedGenerator(7)
        var two = FixedGenerator(7)
        #expect(SessionCode.random(using: &one) == SessionCode.random(using: &two))

        var spread = FixedGenerator(99)
        var seen: Set<Character> = []
        for _ in 0 ..< 5_000 { seen.formUnion(SessionCode.random(using: &spread).letters) }
        #expect(seen.count == 10, "every digit comes up")
    }

    @Test func theKeyIsThirtyTwoBytesAndTheFingerprintIsOne() throws {
        let code = try #require(SessionCode("482915"))
        #expect(SessionKey.presharedKey(for: code, share: share).bitCount == 256)
        #expect(SessionKey.fingerprint(for: code, share: share).count == 2, "two hex characters")
    }

    /// Salting by the session id is what stops two courts drawing the same six digits from
    /// ending up on each other's connection, and what makes an overheard code worthless later.
    @Test func theSameCodeGivesDifferentKeysInDifferentSessions() throws {
        let code = try #require(SessionCode("482915"))
        #expect(SessionKey.presharedKey(for: code, share: share) != SessionKey.presharedKey(for: code, share: other))
        #expect(SessionKey.fingerprint(for: code, share: share) != SessionKey.fingerprint(for: code, share: other))
    }

    @Test func differentCodesInOneSessionDoNotCollide() throws {
        let one = try #require(SessionCode("482915"))
        let two = try #require(SessionCode("482916"))
        #expect(SessionKey.presharedKey(for: one, share: share) != SessionKey.presharedKey(for: two, share: share))
    }

    /// The fingerprint goes out in the clear, so it must not be a piece of the key.
    @Test func theFingerprintIsNotAPartOfTheKey() throws {
        let code = try #require(SessionCode("482915"))
        let key = SessionKey.presharedKey(for: code, share: share).withUnsafeBytes {
            $0.map { String(format: "%02x", $0) }.joined()
        }
        #expect(!key.hasPrefix(SessionKey.fingerprint(for: code, share: share)))
    }

    /// Fixes the schedule against an installed build: changing the salt or the info strings
    /// would stop an upgraded phone talking to one that has not been updated yet.
    @Test func theKeyScheduleIsPinned() throws {
        let code = try #require(SessionCode("482915"))
        #expect(SessionKey.fingerprint(for: code, share: share) == "cc")
    }
}
