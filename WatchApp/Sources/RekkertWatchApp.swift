import HealthKit
import SwiftUI
import UserNotifications
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
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()

    /// Here as well as on the window: a workout started from the phone launches this app in the
    /// background, before there is a window to start anything.
    func applicationDidFinishLaunching() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: AppModel.followMatchCategory, actions: [], intentIdentifiers: []),
        ])
        model.start()
    }

    /// The phone joined while this app was closed. Opened by the tap, it asks for the match.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier == AppModel.followMatchCategory else { return }
        await MainActor.run { model.standIn.followThePhone() }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        model.workout.handle(workoutConfiguration)
    }
}
