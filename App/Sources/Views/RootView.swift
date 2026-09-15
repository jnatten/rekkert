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
        .task {
            #if DEBUG
            // Here rather than on the start screen: a device that already has a match never
            // shows that screen, and joining from one is exactly the case worth exercising.
            if DemoLaunch.joinCode != nil { model.showingJoin = true }
            #endif
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
