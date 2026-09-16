import SwiftUI
import WatchKit

/// Starting and stopping the workout, on whichever screen the watch happens to be showing.
///
/// Absent altogether where Health is not available. Nothing here reports a workout that is
/// not running: not running one is the ordinary case, not a thing gone wrong.
struct WatchWorkoutButton: View {
    @Environment(AppModel.self) private var model
    /// The menu page dresses its rows through its own helper; the idle screen uses plain
    /// bordered buttons. Same button, two houses.
    var isMenuRow = true

    var body: some View {
        if model.workout.isAvailable {
            VStack(spacing: 2) {
                button
                if let failure = model.workout.failure {
                    // The one thing worth saying, and only ever just after a press: a button
                    // that visibly does nothing reads as a broken app rather than as a
                    // setting. It says nothing at rest and nothing about a workout that is
                    // simply not running.
                    Text(failure)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var button: some View {
        Button(action: toggle) {
            Label(title, systemImage: symbol)
                .padding(.horizontal, isMenuRow ? 6 : 0)
                .frame(maxWidth: .infinity, alignment: isMenuRow ? .leading : .center)
        }
        .buttonStyle(.bordered)
        // The colour of a heart rather than the red the menu keeps for destructive things.
        // Stopping a workout destroys nothing — it is what saves it.
        .tint(model.workout.isTracking ? .pink : nil)
        .font(.footnote)
    }

    private var title: String { model.workout.isTracking ? "Stop workout" : "Start workout" }
    private var symbol: String { model.workout.isTracking ? "stop.circle" : "figure.tennis" }

    /// No confirmation either way. The menu's dialogs guard things that cannot be taken
    /// back; a workout started by mistake is stopped again, and one stopped by mistake has
    /// already been saved.
    private func toggle() {
        if model.workout.isTracking {
            WKInterfaceDevice.current().play(.stop)
            model.workout.stop()
        } else {
            model.workout.acknowledgeFailure()
            WKInterfaceDevice.current().play(.start)
            model.workout.start()
        }
    }
}
