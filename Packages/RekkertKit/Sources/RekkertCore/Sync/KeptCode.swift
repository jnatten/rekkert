import Foundation

/// What a device that has been on a shared match keeps of it, so the match survives the app
/// being ended: a host shares again on the same code, and a guest gets back on without it typed.
public struct KeptCode: Codable, Sendable, Hashable {
    public var code: SessionCode
    /// The host's share id, so every key derived from the code comes out the same. A guest is
    /// told it again by the host and keeps none.
    public var share: UUID?
    public var role: SessionRole
    public var startedAt: Date

    public static let lifetime: TimeInterval = 12 * 60 * 60

    public init(code: SessionCode, share: UUID?, role: SessionRole, startedAt: Date) {
        self.code = code
        self.share = share
        self.role = role
        self.startedAt = startedAt
    }

    public var expiresAt: Date { startedAt.addingTimeInterval(Self.lifetime) }

    public func current(now: Date) -> KeptCode? {
        now < expiresAt ? self : nil
    }

    public enum Moment: Sendable, Equatable {
        case hosted(KeptCode)
        /// A join that got through, on this code.
        case proven(KeptCode)
        /// A code typed in that has not got through yet.
        case typed
        case stoppedHosting
        case sharingStopped
        case left
    }

    /// What is kept once `moment` has happened.
    public static func after(_ moment: Moment, kept: KeptCode?) -> KeptCode? {
        switch moment {
        case .hosted(let new), .proven(let new): new
        case .typed, .left: kept
        case .stoppedHosting: kept?.role == .host ? nil : kept
        case .sharingStopped: kept?.role == .guest ? nil : kept
        }
    }
}
