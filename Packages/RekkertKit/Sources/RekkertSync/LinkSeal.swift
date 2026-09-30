import CryptoKit
import Foundation
import RekkertCore

/// The code wrapped around one Bluetooth connection.
///
/// Bluetooth has no TLS, so the property the local network gets from a pre-shared-key handshake
/// is built here instead: a phone without the code can neither read what goes past nor put
/// anything of its own on the link.
///
/// Each end proves itself afresh on every connection. The guest opens with a nonce, the host
/// answers with it and one of its own, and the guest confirms with the host's. A sealed frame
/// caught once proves nothing later: it carries the wrong nonce. And every frame after that is
/// bound to both nonces and numbered, so it opens on this connection, once, and nowhere else.
nonisolated struct LinkSeal {
    enum Role: Sendable {
        case host
        case guest
    }

    enum Opened: Equatable {
        /// The other end's frame, once it has proved itself on this connection.
        case frame(Frame)
        /// The host's half of the proof, to go back to the guest.
        case answer(Data)
        /// The other end has proved itself. The guest has its confirmation still to send.
        case proven(confirmation: Data?)
    }

    private enum Kind: UInt8 {
        case challenge = 1
        case answer = 2
        case confirmation = 3
        case frame = 4
    }

    private static let nonceSize = 16

    private let role: Role
    private let sealing: SymmetricKey
    private let opening: SymmetricKey
    private var own = Self.nonce()
    private var theirs: Data?
    private(set) var isProven = false
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    init(role: Role, code: SessionCode, share: UUID) {
        self.role = role
        let outbound: SessionKey.Direction = role == .guest ? .guestToHost : .hostToGuest
        let inbound: SessionKey.Direction = role == .guest ? .hostToGuest : .guestToHost
        sealing = SessionKey.sealingKey(for: code, share: share, direction: outbound)
        opening = SessionKey.sealingKey(for: code, share: share, direction: inbound)
    }

    /// What a guest opens the connection with.
    func challenge() -> Data? {
        guard role == .guest else { return nil }
        return seal(.challenge, own)
    }

    /// `nil` until the other end has proved itself here, and for a frame the far end would refuse
    /// as too big.
    mutating func seal(_ frame: Frame) -> Data? {
        guard isProven, FrameCodec.fits(frame) else { return nil }
        sent += 1
        var body = Data()
        body.append(bigEndian: sent)
        body.append(FrameCodec.encode(frame))
        return seal(.frame, body)
    }

    /// `nil` for anything that will not open or does not belong: a wrong code, a corrupted packet,
    /// a peer making things up, and a frame from another connection or already opened here.
    mutating func open(_ sealed: Data) -> Opened? {
        guard let raw = sealed.first, let kind = Kind(rawValue: raw),
              let box = try? ChaChaPoly.SealedBox(combined: sealed.dropFirst()),
              let body = try? ChaChaPoly.open(box, using: opening, authenticating: binding(for: kind))
        else { return nil }

        switch (role, kind) {
        case (.host, .challenge):
            guard body.count == Self.nonceSize else { return nil }
            theirs = body
            own = Self.nonce()
            isProven = false
            sent = 0
            received = 0
            return seal(.answer, body + own).map(Opened.answer)

        case (.guest, .answer):
            guard !isProven, body.count == 2 * Self.nonceSize, body.prefix(Self.nonceSize) == own else { return nil }
            let hosts = Data(body.suffix(Self.nonceSize))
            theirs = hosts
            isProven = true
            return .proven(confirmation: seal(.confirmation, hosts))

        case (.host, .confirmation):
            guard !isProven, theirs != nil, body == own else { return nil }
            isProven = true
            return .proven(confirmation: nil)

        case (_, .frame):
            guard isProven, body.count > 8 else { return nil }
            let number = body.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard number > received else { return nil }
            var buffer = Data(body.dropFirst(8))
            guard let frames = try? FrameCodec.decode(from: &buffer),
                  let frame = frames.first, frames.count == 1, buffer.isEmpty
            else { return nil }
            received = number
            return .frame(frame)

        default:
            return nil
        }
    }

    private func seal(_ kind: Kind, _ body: Data) -> Data? {
        guard let box = try? ChaChaPoly.seal(body, using: sealing, authenticating: binding(for: kind)) else { return nil }
        return Data([kind.rawValue]) + box.combined
    }

    /// The kind always, so one cannot be passed off as another; and for a frame, both nonces.
    private func binding(for kind: Kind) -> Data {
        guard kind == .frame, let theirs else { return Data([kind.rawValue]) }
        let (guests, hosts) = role == .guest ? (own, theirs) : (theirs, own)
        return Data([kind.rawValue]) + guests + hosts
    }

    private static func nonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0 ..< nonceSize).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

nonisolated private extension Data {
    mutating func append(bigEndian value: UInt64) {
        append(contentsOf: (0 ..< 8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}
