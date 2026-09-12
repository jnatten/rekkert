import RekkertCore
import SwiftUI

struct WatchRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = 0

    var body: some View {
        switch model.store.state {
        case .none:
            WatchIdleView()

        case .traditional, .winnerCourt:
            TabView(selection: $selection) {
                WatchCourtPage(court: 0).tag(0)
                WatchMenuView().tag(menuTag)
            }
            .tabViewStyle(.page)
            .task { openDemoPage() }

        case .tournament(let tournament):
            if let round = tournament.currentRound {
                TabView(selection: $selection) {
                    ForEach(round.matches) { match in
                        WatchCourtPage(round: round.index, court: match.courtIndex)
                            .tag(match.courtIndex)
                    }
                    WatchStandingsView(tournament: tournament).tag(standingsTag)
                    WatchMenuView().tag(menuTag)
                }
                .tabViewStyle(.page)
                .task { openDemoPage() }
            } else {
                WatchNoRoundView(tournament: tournament)
            }
        }
    }

    /// Fixed tags so the menu and standings keep their place whatever the court count.
    private var standingsTag: Int { 1_000 }
    private var menuTag: Int { 1_001 }

    private func openDemoPage() {
        #if DEBUG
        if WatchDemoLaunch.page == "menu" { selection = menuTag }
        if WatchDemoLaunch.page == "standings" { selection = standingsTag }
        #endif
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

struct WatchNoRoundView: View {
    @Environment(AppModel.self) private var model
    let tournament: Tournament

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "sportscourt")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(tournament.name.isEmpty ? tournament.format.displayName : tournament.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if tournament.playableCourts < 1 {
                    Text("Needs four players — add them on your iPhone.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No round drawn yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Draw round") { model.store.nextRound() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
