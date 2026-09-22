import Foundation

/// The six characters a host reads out across a court.
///
/// Crockford's alphabet, which is chosen for how it *decodes* rather than for what it leaves
/// out: somebody who hears "oh" and types `O` gets `0`, and `I` or `l` get `1`. An alphabet
/// that merely excluded the ambiguous letters would make those keystrokes dead ends, and the
/// person typing has no way to know which of the pair was meant. `U` is left out as well, so
/// a code read aloud in a clubhouse cannot come out as a word somebody minds.
///
/// Here rather than beside `SessionKey`, which derives the actual keys from it: the code is six
/// characters and nothing else, and a watch that cannot host or join anything still has to be
/// able to name one when it asks its phone to. The key schedule needs CryptoKit and stays where
/// the transports are.
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

    /// The same folding as `init?`, but forgiving: anything that is not a code character is
    /// dropped rather than refusing the lot, and the result is cut to length.
    ///
    /// For a field being typed into, where half a code is not yet wrong. `O` becomes `0` in
    /// front of the person typing rather than being refused once they have finished — which
    /// also happens to be exactly what dictated letters need, and is what makes the code
    /// enterable on a watch at all.
    public static func folding(_ raw: String) -> String {
        var out = ""
        for character in raw.uppercased() {
            switch character {
            case "O": out.append("0")
            case "I", "L": out.append("1")
            case "-", " ", "\u{2013}": continue
            default:
                if alphabet.contains(character) { out.append(character) }
            }
        }
        return String(out.prefix(length))
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

/// Plain six characters on the wire rather than a wrapped field, and put back through `init?`
/// on the way in — so something that is not a code cannot arrive as one.
extension SessionCode: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let code = SessionCode(raw) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "\(raw.count) characters, and a code is \(Self.length)"
                )
            )
        }
        self = code
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(letters)
    }
}
