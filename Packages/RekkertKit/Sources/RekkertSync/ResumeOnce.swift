import Foundation

/// Guards a continuation against being resumed twice.
///
/// Every transport here needs one: WatchConnectivity can call both the reply and the error
/// handler, a socket can be answered and then time out, and resuming a continuation a second
/// time is a crash rather than a mistake to be noticed later.
nonisolated final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?

    init(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Data?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
