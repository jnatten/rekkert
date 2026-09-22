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
}

extension BluetoothTransport: SharedLink {}
