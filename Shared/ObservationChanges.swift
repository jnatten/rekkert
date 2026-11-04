import Observation

/// `Observations` for systems that predate it: the value now, then again after every change
/// to what `read` touched. Tracking fires before the change lands, so the new value is read
/// on the next turn of the main actor rather than in the callback.
@MainActor
func observationChanges<Value: Sendable>(
    of read: @escaping @MainActor () -> Value
) -> AsyncStream<Value> {
    let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingNewest(1))
    let tracker = ObservationTracker(read: read, continuation: continuation)
    continuation.onTermination = { _ in Task { @MainActor in tracker.stop() } }
    continuation.yield(read())
    tracker.track()
    return stream
}

@MainActor
private final class ObservationTracker<Value: Sendable> {
    private let read: @MainActor () -> Value
    private let continuation: AsyncStream<Value>.Continuation
    private var stopped = false

    init(read: @escaping @MainActor () -> Value, continuation: AsyncStream<Value>.Continuation) {
        self.read = read
        self.continuation = continuation
    }

    func track() {
        guard !stopped else { return }
        withObservationTracking {
            _ = read()
        } onChange: { [weak self] in
            Task { @MainActor in self?.changed() }
        }
    }

    func stop() {
        stopped = true
    }

    private func changed() {
        guard !stopped else { return }
        continuation.yield(read())
        track()
    }
}
