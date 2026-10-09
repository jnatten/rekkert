import RekkertCore
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var askingToStartWorkout = false
    /// A code that arrived as a link, for the join sheet to send as it opens — or to show
    /// first, when joining it would take this phone off a shared match.
    @State private var linkedCode: SessionCode?

    var body: some View {
        Group {
            switch model.store.state {
            case .none:
                if let result = model.store.lastResult {
                    MatchResultView(state: result)
                } else {
                    HomeView()
                }
            case .traditional:
                TraditionalMatchView()
            case .tournament:
                TournamentView()
            case .winnerCourt:
                WinnerCourtView()
            case .pointCount:
                PointCountMatchView()
            case .friendly:
                FriendlyMatchView()
            }
        }
        .environment(\.teamPalette, TeamPalette(isSwapped: model.store.display.areColorsSwapped))
        .externalBoard(model)
        .sheet(isPresented: Binding(
            get: { model.showingShareCode },
            set: { model.showingShareCode = $0 }
        )) {
            ShareCodeSheet()
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.showingBoard },
            set: { model.showingBoard = $0 }
        )) {
            BoardCover()
        }
        .sheet(isPresented: Binding(
            get: { model.showingTVGuide },
            set: { model.showingTVGuide = $0 }
        )) {
            TVGuideSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.showingHelp },
            set: { model.showingHelp = $0 }
        )) {
            HelpSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.showingJoin },
            set: { model.showingJoin = $0 }
        ), onDismiss: { linkedCode = nil }) {
            JoinMatchSheet(
                prefilled: linkedCode?.letters ?? "",
                submitsImmediately: linkedCode != nil
            )
        }
        .onOpenURL(perform: open)
        // A link from the Camera arrives as a browsing activity, which `onOpenURL` never sees.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { open(url) }
        }
        .onChange(of: model.sharing.isSharing, initial: true) { _, sharing in
            // Sharing stops the moment the system suspends the app, so a host whose screen
            // times out quietly drops everybody. Telling people to keep the phone awake was
            // advice standing in for this.
            sharing ? ScreenSleep.hold("sharing") : ScreenSleep.release("sharing")
        }
        .onChange(of: model.isBoardOnTV, initial: true) { _, onTV in
            // Mirroring ends when the phone locks, taking the board off the TV with it.
            onTV ? ScreenSleep.hold("tv") : ScreenSleep.release("tv")
        }
        .task {
            #if DEBUG
            // Here rather than on the start screen: a device that already has a match never
            // shows that screen, and joining from one is exactly the case worth exercising.
            if let code = DemoLaunch.joinCode.flatMap(SessionCode.init) { open(code.joinLink) }
            if DemoLaunch.board { model.showingBoard = true }
            if DemoLaunch.tvGuide { model.showingTVGuide = true }
            if DemoLaunch.help { model.showingHelp = true }
            if DemoLaunch.tvShot { BoardCapture.start() }
            if DemoLaunch.isLandscape, let scene = UIApplication.shared.phoneScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            #endif
        }
        .alert(
            "Still looking for the shared match",
            isPresented: Binding(
                get: { model.sharing.hasLostTheMatch },
                set: { if !$0 { model.sharing.acknowledgeLostMatch() } }
            )
        ) {
            Button("Keep looking") { model.sharing.acknowledgeLostMatch() }
            Button("Enter a new code") {
                model.sharing.acknowledgeLostMatch()
                model.showingJoin = true
            }
            Button("Leave", role: .destructive) {
                model.sharing.acknowledgeLostMatch()
                model.sharing.stop()
            }
        } message: {
            Text("Whoever shared this match is out of reach. The score here is the last that got through, and Rekkert will pick it up again if they come back. If they shared it again on a new code, enter that one.")
        }
        .alert(
            "Switched to the newer match",
            isPresented: Binding(
                get: { model.store.replacedSessionTitle != nil },
                set: { if !$0 { model.store.acknowledgeReplacedSession() } }
            )
        ) {
            Button("OK") { model.store.acknowledgeReplacedSession() }
        } message: {
            Text("“\(model.store.replacedSessionTitle ?? "")” was started earlier elsewhere and has been saved to History.")
        }
        // Delayed so the sheet the match was started or joined from has gone; an alert put up
        // under it never shows.
        .task(id: model.follower.isAskingToStart) {
            guard model.follower.isAskingToStart else {
                askingToStartWorkout = false
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
            askingToStartWorkout = model.follower.isAskingToStart
        }
        .alert("Start a workout?", isPresented: $askingToStartWorkout) {
            Button("Start workout") { model.follower.answerStart(true) }
            Button("Not now", role: .cancel) { model.follower.answerStart(false) }
        } message: {
            Text("It runs on your watch while you play.")
        }
    }

    private func open(_ url: URL) {
        guard let code = SessionCode(joinLink: url) else { return }
        // Joining would end the sharing this code belongs to.
        if model.sharing.code == code {
            if !model.showingShareCode { present { model.showingShareCode = true } }
            return
        }
        linkedCode = code
        if !model.showingJoin { present { model.showingJoin = true } }
    }

    /// A sheet from here cannot go up over one that is already showing, wherever that one
    /// came from, so whatever is up is put away first.
    private func present(_ show: @escaping () -> Void) {
        guard
            let root = UIApplication.shared.phoneScene?.keyWindow?.rootViewController,
            root.presentedViewController != nil
        else { return show() }
        root.dismiss(animated: true) { Task { show() } }
    }
}
