import RekkertCore
import SwiftUI
import WatchKit

struct WatchWarmupPage: View {
    @Environment(AppModel.self) private var model
    let since: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Warm-up", systemImage: "figure.run")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(timerInterval: min(since, Date()) ... .distantFuture, countsDown: false)
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Warm-up time")
            if model.workout.isTracking {
                WatchHeartRate()
            }
            Spacer(minLength: 0)
            if model.store.canRunRounds {
                Button {
                    WKInterfaceDevice.current().play(.start)
                    model.store.endWarmup()
                } label: {
                    Label("Start game", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 2)
    }
}
