import CryptoKit
import Foundation
import RekkertCore

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

    /// The key that seals what goes over Bluetooth, where there is no TLS to do it.
    ///
    /// Derived apart from the pre-shared key rather than reusing it: the two guard different
    /// links in different ways, and a key with one job is easier to reason about than a key
    /// with two. Salted by the share id for the same reason the pre-shared key is — a code
    /// overheard once is worth nothing against a later match.
    public static func sealingKey(for code: SessionCode, share: UUID) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(code.letters.utf8)),
            salt: salt,
            info: Data("seal|".utf8) + bytes(of: share),
            outputByteCount: 32
        )
    }

    public static let pskIdentity = Data("rekkert".utf8)
}
