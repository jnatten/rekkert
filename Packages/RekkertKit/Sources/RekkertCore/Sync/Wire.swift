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

/// What a phone and its own watch tell each other about a workout.
///
/// Only the watch can hold one, so the traffic is lopsided: the phone asks for it to stop,
/// and the watch says what it is doing. Starting is not in here — the phone starts one by
/// launching the watch app with a workout configuration, which is Health's own way of
/// asking, and needs no message of ours.
public enum WorkoutSignal: Codable, Sendable, Hashable {
    /// Phone to watch: end the workout and save it.
    case stop
    /// Watch to phone: one is running, and has been since this moment.
    case running(since: Date)
    /// Watch to phone: none is running.
    case idle
    /// Watch to phone: this one ended and Health kept it. The phone files it, because the
    /// watch keeps no history of its own.
    case finished(WorkoutRecord)
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
    /// Whether this phone's own watch is on a workout, and the summary once it ends. The
    /// heart rate itself is never in here: it stays on the wrist it was read from.
    case workout(WorkoutSignal)

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

    /// Throws away any snapshot being kept for peers that arrive later. Called when a session
    /// ends: what is cached at that moment is the farewell, and handing it to somebody who
    /// turns up afterwards would file a result for a match they never played.
    ///
    /// Declared here rather than only in the extension below. A member that exists solely in
    /// a protocol extension dispatches statically, so through an `any PeerTransport` the
    /// default would be the only one that ever ran.
    func forgetSnapshot()

    /// How many counterparts are reachable. `isReachable` stays "is anyone there", because
    /// that is what decides whether a live send is worth attempting; this is what a UI counts.
    var reachableCount: Int { get }
}

extension PeerTransport {
    public func forgetSnapshot() {}
    public var reachableCount: Int { isReachable ? 1 : 0 }
}
