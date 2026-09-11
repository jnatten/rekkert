import RekkertCore
import SwiftUI

struct WatchRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = 0

    var body: some View {
        switch model.store.state {
        case .none:
            WatchIdleView()
        case .traditional:
            WatchCourtPage(court: 0)
        case .tournament(let tournament):
            TabView(selection: $selection) {
                ForEach(tournament.currentRound?.matches ?? []) { match in
                    WatchCourtPage(court: match.courtIndex)
                        .tag(match.courtIndex)
                }
                WatchStandingsView(tournament: tournament)
                    .tag(-1)
            }
            .tabViewStyle(.page)
        }
    }
}

struct WatchIdleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: model.store.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No match running")
                    .font(.headline)
                Text(model.store.isReachable
                     ? "Start one on your iPhone, or tap below."
                     : "iPhone not reachable. You can still start here — it syncs when they reconnect.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("Quick match") {
                    model.store.configure(.traditional(
                        rules: TraditionalRules(),
                        teams: BySide(a: .home, b: .away)
                    ))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
    }
}
