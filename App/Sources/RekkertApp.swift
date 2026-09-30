import SwiftUI
import UIKit

@main
struct RekkertApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.model)
                .task { delegate.model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { delegate.model.becameActive() }
        }
    }
}

/// The TV's scene delegate is made by UIKit from the Info.plist, not by SwiftUI, and needs the
/// one model the app has — so the model lives here rather than in an `@State` it cannot reach.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    override init() {
        super.init()
        BoardSceneDelegate.model = model
    }

    /// Here as well as on the window: the system launches the app in the background for the
    /// watch or the radio, and no window is made then, so nothing would be listening.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        model.start()
        return true
    }
}
