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
}
