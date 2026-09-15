import CryptoKit
import Foundation

/// The six characters a host reads out across a court.
///
/// Crockford's alphabet, which is chosen for how it *decodes* rather than for what it leaves
/// out: somebody who hears "oh" and types `O` gets `0`, and `I` or `l` get `1`. An alphabet
/// that merely excluded the ambiguous letters would make those keystrokes dead ends, and the
/// person typing has no way to know which of the pair was meant. `U` is left out as well, so
/// a code read aloud in a clubhouse cannot come out as a word somebody minds.
nonisolated public struct SessionCode: Hashable, Sendable, CustomStringConvertible {
    public static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    public static let length = 6

    /// Six symbols, already normalised.
    public let letters: String

    /// `nil` unless the whole thing reads as a code. A stray character is refused rather than
    /// dropped: dropping one shifts the rest along and quietly makes a *different* valid code.
    public init?(_ raw: String) {
        var normalised = ""
        for character in raw.uppercased() {
            switch character {
            case "-", " ", "\u{2013}": continue
            case "O": normalised.append("0")
            case "I", "L": normalised.append("1")
            default:
                guard Self.alphabet.contains(character) else { return nil }
                normalised.append(character)
            }
        }
        guard normalised.count == Self.length else { return nil }
        letters = normalised
    }

    /// `SystemRandomNumberGenerator` is cryptographically secure on Apple platforms, so there
    /// is no reason to reach past it. The generator is a parameter only so a test can pin it.
    public static func random(using generator: inout some RandomNumberGenerator) -> SessionCode {
        var letters = ""
        for _ in 0 ..< length {
            letters.append(alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)])
        }
        return SessionCode(letters)!
    }

    public static func random() -> SessionCode {
        var system = SystemRandomNumberGenerator()
        return random(using: &system)
    }

    /// Grouped for reading aloud: `H7K-3MR`.
    public var description: String {
        let middle = letters.index(letters.startIndex, offsetBy: 3)
        return "\(letters[..<middle])-\(letters[middle...])"
    }
}

/// Turns the code into the key that guards the connection, and into the few bytes a joiner
/// needs in order to pick the right session out of the air without saying the code out loud.
nonisolated public enum SessionKey {
    /// Bump the version when the framing or the key schedule changes, so an old build and a
    /// new one cannot half-connect.
    private static let salt = Data("dev.natten.rekkert.share.v1".utf8)

    private static func bytes(of share: UUID) -> Data {
        withUnsafeBytes(of: share.uuid) { Data($0) }
    }

    /// The TLS pre-shared key. Never leaves the device.
    ///
    /// Salted by the session's own id so two courts that happen to draw the same six symbols
    /// do not end up with the same key, and a code overheard once is worth nothing against a
    /// later match.
    public static func presharedKey(for code: SessionCode, share: UUID) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(code.letters.utf8)),
            salt: salt,
            info: Data("psk|".utf8) + bytes(of: share),
            outputByteCount: 32
        )
    }

    /// Two bytes, published in the clear so a joiner can tell which advertised session is the
    /// one it was given the code for.
    ///
    /// Two and not four. The code carries thirty bits, so publishing thirty-two bits of a hash
    /// of it would let anyone within earshot of the network narrow it to exactly one candidate
    /// offline — which is the same as publishing the code. Sixteen bits leaves some sixteen
    /// thousand, each of which has to be tried against a live host one failed handshake at a
    /// time. The cost is a wasted handshake once in every 65,536 sessions picked, which is why
    /// the joiner tries every advertisement that matches rather than only the first.
    public static func fingerprint(for code: SessionCode, share: UUID) -> String {
        let digest = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(code.letters.utf8)),
            salt: salt,
            info: Data("fingerprint|".utf8) + bytes(of: share),
            outputByteCount: 2
        )
        return digest.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
    }

    public static let pskIdentity = Data("rekkert".utf8)
}
