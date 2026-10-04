import SwiftUI
import WatchKit

/// Inline rather than a dialog, so "Undo last point" stays in reach underneath it.
struct WatchWorkoutFollowCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let stopsAt = model.follower.stopsAt {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Text("Stopping workout in")
                    Text(timerInterval: Date.now ... max(.now, stopsAt), countsDown: true)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                keepGoing
            }
        } else if model.follower.isAskingToStop {
            VStack(spacing: 4) {
                Text("Stop the workout?")
                    .font(.system(size: 12, weight: .semibold))
                Button("Stop workout", systemImage: "stop.circle") {
                    WKInterfaceDevice.current().play(.stop)
                    model.follower.answerStop(true)
                }
                .buttonStyle(.bordered)
                .tint(.pink)
                .font(.footnote)
                keepGoing
            }
        }
    }

    private var keepGoing: some View {
        Button("Keep going", systemImage: "figure.tennis") {
            WKInterfaceDevice.current().play(.click)
            model.follower.keepGoing()
        }
        .buttonStyle(.bordered)
        .font(.footnote)
    }
}
