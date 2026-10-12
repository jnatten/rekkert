import RekkertCore
import SwiftUI

/// Drawn by the system, as the round clock is, so it keeps going on a dimmed wrist. Past the
/// end it counts the time over, in orange.
struct RoundCountdownText: View {
    let clock: RoundClock
    @State private var isOver = false

    var body: some View {
        Group {
            if let endsAt = clock.endsAt {
                if isOver || Date() >= endsAt {
                    Text("+\(Text(timerInterval: endsAt ... .distantFuture, countsDown: false))")
                        .foregroundStyle(.orange)
                } else {
                    Text(timerInterval: Date() ... endsAt, countsDown: true)
                }
            } else {
                Text(Duration.seconds(max(0, clock.remaining(at: .now))), format: .time(pattern: .minuteSecond))
            }
        }
        .monospacedDigit()
        .task(id: clock.endsAt) {
            guard let endsAt = clock.endsAt else { return }
            isOver = Date() >= endsAt
            guard !isOver else { return }
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            if !Task.isCancelled { isOver = true }
        }
    }
}
