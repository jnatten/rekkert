import Foundation
import RekkertCore
@testable import RekkertSync

/// Two radio cores driven as one, so `SharedSession` hosts and joins on both: Bluetooth, and a
/// second core standing in for the local network, as a phone with Wi-Fi switched on has.
nonisolated struct TwinLink: SharedLink {
    let bluetooth: RadioCore
    let wifi: RadioCore

    var reachability: AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let (bluetooth, wifi) = (bluetooth, wifi)
        let watchers = [bluetooth, wifi].map { core in
            Task {
                for await _ in core.reachability {
                    continuation.yield(bluetooth.isReachable || wifi.isReachable)
                }
            }
        }
        continuation.onTermination = { _ in for watcher in watchers { watcher.cancel() } }
        return stream
    }

    var reachableCount: Int { max(bluetooth.reachableCount, wifi.reachableCount) }

    func startHosting(code: SessionCode, share: UUID) {
        bluetooth.startHosting(code: code, share: share)
        wifi.startHosting(code: code, share: share)
    }

    func resumeHosting(code: SessionCode, share: UUID) {
        bluetooth.resumeHosting(code: code, share: share)
        wifi.resumeHosting(code: code, share: share)
    }

    func startJoining(code: SessionCode) {
        bluetooth.startJoining(code: code)
        wifi.startJoining(code: code)
    }

    func resumeJoining(code: SessionCode) {
        bluetooth.resumeJoining(code: code)
        wifi.resumeJoining(code: code)
    }

    func stop() {
        bluetooth.stop()
        wifi.stop()
    }

    func stopAdmitting() {
        bluetooth.stopAdmitting()
        wifi.stopAdmitting()
    }

    var availability: RadioAvailability { bluetooth.availability }
    var availabilityChanges: AsyncStream<RadioAvailability> { bluetooth.availabilityChanges }
}
