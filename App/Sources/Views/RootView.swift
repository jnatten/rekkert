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
