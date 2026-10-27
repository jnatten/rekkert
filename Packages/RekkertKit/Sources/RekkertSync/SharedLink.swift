import Foundation
import RekkertCore

/// The part of a shared-match link that `SharedSession` drives.
///
/// Two transports carry a shared match — the local network while the app is in front of
/// somebody, Bluetooth for the rest of the time — and the coordinator starts, stops and revives
/// them in step. Named as a protocol because neither of them exists where the tests run: the
/// local network is an inert stub off iOS and Bluetooth needs a radio, so the only way to
/// exercise the coordinator's own bookkeeping is for a third implementation to stand in.
public protocol SharedLink: Sendable {
    var reachability: AsyncStream<Bool> { get }
    var reachableCount: Int { get }

    func startHosting(code: SessionCode, share: UUID)
    func resumeHosting(code: SessionCode, share: UUID)
    func startJoining(code: SessionCode)
    func resumeJoining(code: SessionCode)
    func stop()
    /// Lets nobody new in, while the ones already on are told the sharing has stopped.
    func stopAdmitting()

    /// Whether the radio under this link can be used at all.
    var availability: RadioAvailability { get }
    /// Each change of it.
    var availabilityChanges: AsyncStream<RadioAvailability> { get }
}

extension SharedLink {
    public func stopAdmitting() {}
    public var availability: RadioAvailability { .unknown }
    public var availabilityChanges: AsyncStream<RadioAvailability> { AsyncStream { $0.finish() } }
}

extension BluetoothTransport: SharedLink {}
extension RadioCore: SharedLink {}
