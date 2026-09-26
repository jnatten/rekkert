import RekkertCore
import SwiftUI
import UIKit

final class BoardSceneDelegate: UIResponder, UIWindowSceneDelegate {
    static weak var model: AppModel?
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, let model = Self.model else { return }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: BoardRoot().environment(model))
        window.isHidden = false
        self.window = window
        model.isBoardOnTV = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        Self.model?.isBoardOnTV = false
    }
}

extension View {
    /// From iOS 27 a connected screen only gets a scene of its own when the app registers
    /// for one; without this it goes on mirroring the phone.
    @ViewBuilder
    func externalBoard(_ model: AppModel) -> some View {
        if #available(iOS 27.0, *) {
            sceneAccessory {
                ExternalNonInteractiveAccessory {
                    BoardRoot()
                        .environment(model)
                        .onAppear { model.isBoardOnTV = true }
                        .onDisappear { model.isBoardOnTV = false }
                }
            }
        } else {
            self
        }
    }
}

struct BoardRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        BoardView(board: TVBoard.make(
            from: model.store.state,
            lastResult: model.store.lastResult,
            display: model.store.display
        ))
        .environment(\.teamPalette, TeamPalette(isSwapped: model.store.display.areColorsSwapped))
        .preferredColorScheme(.dark)
    }
}

extension UIApplication {
    /// With a TV connected there are two scenes, and `connectedScenes` has no order.
    var phoneScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowApplication }
    }
}
