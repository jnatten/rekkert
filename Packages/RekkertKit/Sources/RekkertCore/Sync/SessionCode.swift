import Foundation

/// The six digits a host reads out across a court.
///
/// Digits so that both ends can use a number pad: the phone's keyboard and the watch's own.
/// `O`, `I` and `L` are still folded onto `0` and `1`, so somebody who hears "oh" and types it
/// gets what was meant rather than a dead end.
///
/// Here rather than beside `SessionKey`, which derives the actual keys from it: the code is six
/// digits and nothing else, and a watch that cannot host or join anything still has to be
/// able to name one when it asks its phone to. The key schedule needs CryptoKit and stays where
/// the transports are.
nonisolated public struct SessionCode: Hashable, Sendable, CustomStringConvertible {
    public static let alphabet = Array("0123456789")
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
    /// front of the person typing rather than being refused once they have finished.
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

    /// The same folding, with the hyphen the code is read out with put in as you type: `482-915`.
    ///
    /// For a field rather than for a value — what somebody typing sees, matching what the host's
    /// screen shows them. The hyphen is punctuation and never part of the code: `init?` skips it
    /// on the way back in, so a grouped field still parses.
    ///
    /// Nothing is added until there is a character to put after it. A trailing `482-` would
    /// reappear the moment it was deleted, and there would be no way back past it.
    public static func grouped(_ raw: String) -> String {
        let letters = folding(raw)
        guard letters.count > groupSize else { return letters }
        let middle = letters.index(letters.startIndex, offsetBy: groupSize)
        return "\(letters[..<middle])-\(letters[middle...])"
    }

    /// Where the hyphen goes, for reading aloud and for typing alike.
    private static let groupSize = 3

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

    /// Grouped for reading aloud: `482-915`. The same grouping a field being typed into puts
    /// in, so what a host reads off their screen is what a joiner watches appear on theirs.
    public var description: String { Self.grouped(letters) }
}

/// Plain six digits on the wire rather than a wrapped field, and put back through `init?`
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
