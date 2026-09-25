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
/// Only the watch can hold one, so the traffic is lopsided: the phone asks for something to
/// happen to it, and the watch says what it is doing. Starting is not in here — the phone
/// starts one by launching the watch app with a workout configuration, which is Health's
/// own way of asking, and needs no message of ours.
///
/// Which direction a case travels is the only thing keeping `pause` and `paused` apart, so
/// every one of them says so.
public enum WorkoutSignal: Codable, Sendable, Hashable {
    /// Phone to watch: end the workout and save it.
    case stop
    /// Phone to watch: hold it where it is, or pick it up again.
    case pause
    case resume
    /// Watch to phone: one is running, and has been since this moment.
    case running(since: Date)
    /// Watch to phone: one is running but held, and the clock stopped at this reading. The
    /// reading rather than the moment it stopped, because a held clock does not move: this
    /// goes on being true however long afterwards it is repeated.
    case paused(since: Date, elapsed: TimeInterval)
    /// Watch to phone: none is running.
    case idle
    /// Watch to phone: this one ended and Health kept it. The phone files it, because the
    /// watch keeps no history of its own.
    case finished(WorkoutRecord)
    /// Watch to phone: how a finished one's heart rate and energy went, read out of Health
    /// after it ended. Its own message rather than part of `finished`, which goes the moment
    /// the workout ends and must not wait on a query.
    case series(WorkoutSeries)
}

/// What a phone and its own watch say to each other about joining somebody else's match.
///
/// Lopsided for the same reason `WorkoutSignal` is: only one of the two can do the thing. A
/// watch has no transport that reaches a stranger — the local network and Bluetooth are both
/// built on iOS alone — so the wrist asks and the phone goes and does it.
///
/// The code goes to the phone in the same pocket and nowhere else. `FanOutTransport.Scope
/// .sharedSession` drops this case, which matters more here than for anything else on the
/// wire: handing the code to a peer would hand over the key to the match.
public enum SharingSignal: Codable, Sendable, Hashable {
    /// Watch to phone: join this one.
    case join(SessionCode)
    /// Watch to phone: stop looking.
    case cancel
    /// Phone to watch: here is how it is going.
    case state(SharingState)
}

/// How a join is going, as much of it as is worth saying on a wrist.
///
/// A cut-down `SharedSession.Phase`: no `hosting`, which a watch cannot do, and the failure
/// flattened to its three reasons rather than carrying `LocalNetworkTransport.Failure` — that
/// belongs to a transport the watch does not build.
public enum SharingState: Codable, Sendable, Hashable {
    case off
    case searching
    case joined
    case failed(SharingFailure)
}

public enum SharingFailure: String, Codable, Sendable, Hashable {
    case notFound, rejected, blocked
    /// The phone never heard the code. Not one of the transport's own answers — a join is
    /// live or it is nothing, so a watch whose message did not land has to be told, rather
    /// than left watching a search that was never started.
    case unreachable
}

public enum Wire: Codable, Sendable, Hashable {
    /// "Here is what I have" — the reply carries whatever the sender is missing.
    ///
    /// `from` is the sender's own device id, which is how a phone and its own watch learn to
    /// recognise each other's work. Every event already carries its author, but nothing else
    /// says which of those authors is the other half of this pair — and "somebody else scored
    /// that" has to mean somebody other than the two of you. Optional, and absent from older
    /// builds, which decode this without it and go on as they did.
    case hello(sessionID: UUID, vector: VersionVector, from: DeviceID? = nil)
    case events(sessionID: UUID, events: [MatchEvent])
    /// Whole-log backstop, used on the coalescing application-context channel.
    case snapshot(MatchLog)
    /// "The session you are offering ended here." Retiring a session is otherwise
    /// knowledge one device holds alone: it refuses every packet for that session, and a
    /// counterpart that never heard the ending goes on scoring into a match that can no
    /// longer reach it. `archive` says how it ended — kept, or thrown away — so a counterpart
    /// that missed the ending files it the same way rather than keeping a match the people
    /// on it called off.
    ///
    /// `farewell` is the log as it stood when it ended, when the sender still has it. The
    /// point that ended a match is in there and nowhere else once the outbox is cleared, so
    /// a counterpart that was out of reach for that one point files the same result as
    /// everybody else instead of a match stopped a point short. Optional, and absent from
    /// older builds, which decode this without it and go on as they did.
    case retired(sessionID: UUID, archive: Bool, farewell: MatchLog? = nil)
    /// Saved configurations, so a session can be started from either device.
    case presets(PresetLibrary)
    /// How the phone should draw its scoreboard, so the watch can flip it.
    case display(DisplayPreferences)
    /// Who is carrying the whistle. The log says nothing about it — a guest's log is the
    /// host's log — and a watch has no way to tell whose phone it is paired to.
    case role(SessionRole)
    /// "I have stepped off this session" — between a phone and its own watch only, never to
    /// anybody else's phone. The pair mirrors one match, so a leave on one side has to be a
    /// leave on the other, and nothing is retired: the match goes on for whoever is still on it.
    case left(sessionID: UUID)
    /// Whether this phone's own watch is on a workout, and the summary once it ends. The live
    /// reading never goes: what does is the ended workout's, and only ever to this phone.
    case workout(WorkoutSignal)
    /// When the watch buzzes, so it can be set from whichever device is in your hand. Only
    /// the watch acts on it — the phone has no wrist to tap.
    case haptics(HapticPreferences)
    /// Joining somebody's match from the wrist: the code one way, how it is going the other.
    /// Only the phone acts on it — it is the only one of the pair that can reach a stranger.
    case sharing(SharingSignal)

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
    /// Whether this came from this device's own watch or phone rather than from somebody
    /// else's. Nothing on the wire says so — the pair holds the same match, so its packets
    /// name the session already on screen — and a join has to be able to tell an offer from
    /// its own wrist repeating what it has.
    public let isFromPairedDevice: Bool

    public init(payload: Data, reply: (@Sendable (Data) -> Void)? = nil, isFromPairedDevice: Bool = false) {
        self.payload = payload
        self.reply = reply
        self.isFromPairedDevice = isFromPairedDevice
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
