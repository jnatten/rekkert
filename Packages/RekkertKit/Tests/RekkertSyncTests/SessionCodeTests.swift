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
    @Test func theAlphabetLeavesOutTheLettersPeopleGetWrong() {
        for character in "ILOU" {
            #expect(!SessionCode.alphabet.contains(character), "\(character) is not in it")
        }
        #expect(SessionCode.alphabet.count == 32)
    }

    @Test func itIsReadBackTheWayItWasHeard() throws {
        let spoken = try #require(SessionCode("H7K3MR"))

        for variant in ["h7k3mr", "H7K-3MR", "H7K 3MR", "  h7k-3mr  "] {
            #expect(SessionCode(variant) == spoken, "\(variant)")
        }
    }

    /// Crockford's point: these are not excluded, they are folded onto what was meant.
    @Test func lettersThatLookLikeDigitsBecomeThem() throws {
        #expect(SessionCode("O7K3MR")?.letters == "07K3MR")
        #expect(SessionCode("I7K3MR")?.letters == "17K3MR")
        #expect(SessionCode("l7k3mr")?.letters == "17K3MR")
    }

    @Test func anythingThatIsNotACodeIsRefusedWhole() {
        #expect(SessionCode("H7K3M") == nil, "too short")
        #expect(SessionCode("H7K3MRR") == nil, "too long")
        #expect(SessionCode("") == nil)
        // Dropping the stray character would shift the rest along and silently make a
        // different, perfectly valid code.
        #expect(SessionCode("H7K3M!R") == nil)
        #expect(SessionCode("H7K3MU") == nil, "U is not in the alphabet")
    }

    @Test func itIsShownInTwoGroupsForReadingAloud() throws {
        #expect(try #require(SessionCode("H7K3MR")).description == "H7K-3MR")
    }

    @Test func drawingOneIsRepeatableWhenThePickerIs() {
        var one = FixedGenerator(7)
        var two = FixedGenerator(7)
        #expect(SessionCode.random(using: &one) == SessionCode.random(using: &two))

        var spread = FixedGenerator(99)
        var seen: Set<Character> = []
        for _ in 0 ..< 5_000 { seen.formUnion(SessionCode.random(using: &spread).letters) }
        #expect(seen.count == 32, "every symbol comes up")
    }

    @Test func theKeyIsThirtyTwoBytesAndTheFingerprintIsTwo() throws {
        let code = try #require(SessionCode("H7K3MR"))
        #expect(SessionKey.presharedKey(for: code, share: share).bitCount == 256)
        #expect(SessionKey.fingerprint(for: code, share: share).count == 4, "four hex characters")
    }

    /// Salting by the session id is what stops two courts drawing the same six symbols from
    /// ending up on each other's connection, and what makes an overheard code worthless later.
    @Test func theSameCodeGivesDifferentKeysInDifferentSessions() throws {
        let code = try #require(SessionCode("H7K3MR"))
        #expect(SessionKey.presharedKey(for: code, share: share) != SessionKey.presharedKey(for: code, share: other))
        #expect(SessionKey.fingerprint(for: code, share: share) != SessionKey.fingerprint(for: code, share: other))
    }

    @Test func differentCodesInOneSessionDoNotCollide() throws {
        let one = try #require(SessionCode("H7K3MR"))
        let two = try #require(SessionCode("H7K3MS"))
        #expect(SessionKey.presharedKey(for: one, share: share) != SessionKey.presharedKey(for: two, share: share))
    }

    /// The fingerprint goes out in the clear, so it must not be a piece of the key.
    @Test func theFingerprintIsNotAPartOfTheKey() throws {
        let code = try #require(SessionCode("H7K3MR"))
        let key = SessionKey.presharedKey(for: code, share: share).withUnsafeBytes {
            $0.map { String(format: "%02x", $0) }.joined()
        }
        #expect(!key.hasPrefix(SessionKey.fingerprint(for: code, share: share)))
    }

    /// Fixes the schedule against an installed build: changing the salt or the info strings
    /// would stop an upgraded phone talking to one that has not been updated yet.
    @Test func theKeyScheduleIsPinned() throws {
        let code = try #require(SessionCode("H7K3MR"))
        #expect(SessionKey.fingerprint(for: code, share: share) == "ddad")
    }
}
