import Foundation

public enum Wire: Codable, Sendable, Hashable {
    /// "Here is what I have" — the reply carries whatever the sender is missing.
    case hello(sessionID: UUID, vector: VersionVector)
    case events(sessionID: UUID, events: [MatchEvent])
    /// Whole-log backstop, used on the coalescing application-context channel.
    case snapshot(MatchLog)

    public var sessionID: UUID {
        switch self {
        case .hello(let id, _): id
        case .events(let id, _): id
        case .snapshot(let log): log.sessionID
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> Wire {
        try JSONDecoder().decode(Wire.self, from: data)
    }
}

public struct InboundPacket: Sendable {
    public let payload: Data
    public let reply: (@Sendable (Data) -> Void)?

    public init(payload: Data, reply: (@Sendable (Data) -> Void)? = nil) {
        self.payload = payload
        self.reply = reply
    }
}

/// What `MatchStore` needs from the outside world. WatchConnectivity implements it for
/// real; the tests implement it in memory, which is how convergence gets covered on macOS.
public protocol PeerTransport: Sendable {
    var inbound: AsyncStream<InboundPacket> { get }
    /// Fires when the peer becomes reachable or unreachable, which is when anti-entropy
    /// is worth running.
    var reachability: AsyncStream<Bool> { get }
    var isReachable: Bool { get }

    func activate()
    /// Returns the peer's reply, or `nil` if the message was not delivered.
    func sendLive(_ payload: Data) async -> Data?
    func publishSnapshot(_ payload: Data)
}
