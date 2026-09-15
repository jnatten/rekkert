import RekkertCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

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
            }
        }
        .environment(\.teamPalette, TeamPalette(isSwapped: model.store.display.areColorsSwapped))
        .sheet(isPresented: Binding(
            get: { model.showingShareCode },
            set: { model.showingShareCode = $0 }
        )) {
            ShareCodeSheet()
        }
        .sheet(isPresented: Binding(
            get: { model.showingJoin },
            set: { model.showingJoin = $0 }
        )) {
            #if DEBUG
            JoinMatchSheet(
                prefilled: DemoLaunch.joinCode ?? "",
                submitsImmediately: DemoLaunch.joinCode != nil
            )
            #else
            JoinMatchSheet()
            #endif
        }
        .onChange(of: model.sharing.isSharing, initial: true) { _, sharing in
            // Sharing stops the moment the system suspends the app, so a host whose screen
            // times out quietly drops everybody. Telling people to keep the phone awake was
            // advice standing in for this.
            sharing ? ScreenSleep.hold("sharing") : ScreenSleep.release("sharing")
        }
        .task {
            #if DEBUG
            // Here rather than on the start screen: a device that already has a match never
            // shows that screen, and joining from one is exactly the case worth exercising.
            if DemoLaunch.joinCode != nil { model.showingJoin = true }
            #endif
        }
        .alert(
            "Lost the shared match",
            isPresented: Binding(
                get: { model.sharing.hasLostTheMatch },
                set: { if !$0 { model.sharing.acknowledgeLostMatch() } }
            )
        ) {
            Button("Keep looking") { model.sharing.acknowledgeLostMatch() }
            Button("Leave", role: .destructive) {
                model.sharing.acknowledgeLostMatch()
                model.sharing.stop()
            }
        } message: {
            Text("Whoever shared this match is out of reach. The score here is the last that got through, and Rekkert will pick it up again if they come back.")
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
    }
}
