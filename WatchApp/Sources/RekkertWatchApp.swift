import HealthKit
import SwiftUI
import WatchKit

@main
struct RekkertWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(delegate.model)
                .task { delegate.model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { delegate.model.becameActive() }
        }
    }
}

/// Here for one callback. Starting a workout from the iPhone launches this app and hands the
/// configuration to the delegate, which exists before the scene does — so the model has to
/// live here rather than in an `@State` that would not yet have been made.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let model = AppModel()

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        model.workout.handle(workoutConfiguration)
    }
}
