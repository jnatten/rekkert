import Foundation

/// One canonical coder. `.sortedKeys` matters: JSONEncoder does not otherwise guarantee
/// key order, and the application-context channel silently skips a payload identical to
/// the last one — so the bytes must be stable for equal state and differ for unequal.
public enum JSONCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder { JSONDecoder() }
}

public enum Wire: Codable, Sendable, Hashable {
    /// "Here is what I have" — the reply carries whatever the sender is missing.
    case hello(sessionID: UUID, vector: VersionVector)
    case events(sessionID: UUID, events: [MatchEvent])
    /// Whole-log backstop, used on the coalescing application-context channel.
    case snapshot(MatchLog)
    /// "The session you are offering ended here." Retiring a session is otherwise
    /// knowledge one device holds alone: it refuses every packet for that session, and a
    /// counterpart that never heard the ending goes on scoring into a match that can no
    /// longer reach it.
    case retired(sessionID: UUID)
    /// Saved configurations, so a session can be started from either device.
    case presets(PresetLibrary)
    /// How the phone should draw its scoreboard, so the watch can flip it.
    case display(DisplayPreferences)
    /// Who is carrying the whistle. The log says nothing about it — a guest's log is the
    /// host's log — and a watch has no way to tell whose phone it is paired to.
    case role(SessionRole)

    public func encoded() throws -> Data {
        try JSONCoding.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Wire {
        try JSONCoding.decoder.decode(Wire.self, from: data)
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
    /// Hands the payload to a queue that survives the counterpart not running. Delivery is
    /// eventual and unacknowledged, so it supplements the outbox rather than replacing it.
    func queue(_ payload: Data)
}
