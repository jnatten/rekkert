import Foundation

/// The far end of a Bluetooth link: a central subscribed to this host, or a host this guest dials.
///
/// `key` is the object behind it, for as long as the radio holds that object. `address` is what
/// the radio reports for it, which is what a host turned away is remembered by.
nonisolated public struct RadioPeer: Hashable, Sendable {
    public let key: ObjectIdentifier
    public let address: UUID

    public init(key: ObjectIdentifier, address: UUID) {
        self.key = key
        self.address = address
    }
}

nonisolated public protocol RadioTimer: Sendable {
    func cancel()
}

/// Where `RadioCore` runs its work and keeps its time. Every radio event arrives on the same
/// serial line that `run` puts work on.
nonisolated public protocol RadioScheduler: Sendable {
    /// Time since the scheduler began.
    var now: Duration { get }
    func run(_ work: @escaping @Sendable () -> Void)
    @discardableResult
    func run(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> any RadioTimer
}

/// What `RadioCore` asks of the radio. Each `open` is given a session number, and every event
/// from that radio carries it, so one from a manager since let go of can be told apart.
nonisolated public protocol Radio: AnyObject, Sendable {
    var scheduler: any RadioScheduler { get }
    var canHost: Bool { get }
    func attach(_ listener: any RadioListener)

    func openPeripheral(session: Int)
    func publish()
    func closePeripheral()
    func update(_ chunk: Data, to central: RadioPeer) -> Bool
    func maximumUpdate(for central: RadioPeer) -> Int

    func openCentral(session: Int)
    func closeCentral()
    func scan()
    func stopScan()
    func connect(_ peripheral: RadioPeer)
    func cancelConnection(_ peripheral: RadioPeer)
    func isConnected(_ peripheral: RadioPeer) -> Bool
    /// Finds the service, its characteristics, and reads the greeting.
    func discover(_ peripheral: RadioPeer)
    func subscribe(_ peripheral: RadioPeer)
    /// With a response, which `RadioListener.wrote(to:failed:)` reports.
    func write(_ chunk: Data, to peripheral: RadioPeer)
    func maximumWrite(for peripheral: RadioPeer) -> Int
}

nonisolated public protocol RadioListener: AnyObject, Sendable {
    func peripheralState(poweredOn: Bool, session: Int)
    func greeting(session: Int) -> Data?
    func subscribed(_ central: RadioPeer, session: Int)
    func unsubscribed(_ central: RadioPeer)
    /// Whether the session was current, which is what the radio answers the writes with.
    func received(writes: [(central: RadioPeer, offset: Int, value: Data)], session: Int) -> Bool
    func readyToUpdate()

    func centralState(poweredOn: Bool, session: Int)
    func discovered(_ peripheral: RadioPeer, session: Int)
    func connected(_ peripheral: RadioPeer, session: Int)
    func disconnected(_ peripheral: RadioPeer, failed: Bool, session: Int)
    func foundInbox(on peripheral: RadioPeer)
    func greeted(_ value: Data?, failed: Bool, by peripheral: RadioPeer)
    func notifying(_ isNotifying: Bool, on peripheral: RadioPeer)
    func received(_ chunk: Data, from peripheral: RadioPeer)
    func wrote(to peripheral: RadioPeer, failed: Bool)
    func servicesChanged(on peripheral: RadioPeer, invalidatedOurs: Bool)
}
