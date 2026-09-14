import RekkertCore
import SwiftUI

struct WatchRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = 0
    /// The court page last looked at, so the menu acts on that one rather than always the
    /// first.
    @State private var lastCourt = 0

    var body: some View {
        content
            .environment(\.teamPalette, TeamPalette(isSwapped: model.store.display.areColorsSwapped))
    }

    @ViewBuilder
    private var content: some View {
        switch model.store.state {
        case .none:
            if let result = model.store.lastResult {
                WatchResultView(state: result)
            } else {
                WatchIdleView()
            }

        case .traditional, .winnerCourt, .pointCount:
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
                        WatchCourtPage(
                            round: round.index,
                            court: match.courtIndex,
                            isActive: lastCourt == match.courtIndex
                        )
                        .tag(match.courtIndex)
                    }
                    WatchStandingsView(tournament: tournament).tag(standingsTag)
                    WatchMenuView(round: round.index, court: lastCourt).tag(menuTag)
                }
                .tabViewStyle(.page)
                .task { openDemoPage() }
                .onChange(of: selection) { _, new in
                    if new != standingsTag, new != menuTag { lastCourt = new }
                }
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
            VStack(spacing: 8) {
                if model.store.presets.isEmpty {
                    empty
                } else {
                    Text("Start")
                        .font(.headline)
                    ForEach(model.store.presets.ordered) { preset in
                        Button {
                            model.store.start(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                Text(preset.configuration.summary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            // The pill's corner radius eats into the leading edge, so the
                            // text needs its own inset to stop looking pushed against it.
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Button("Quick match") {
                    model.store.configure(.traditional(
                        rules: TraditionalRules(),
                        teams: BySide(a: .home, b: .away)
                    ))
                }
                .buttonStyle(.bordered)
                .font(.footnote)
                .padding(.top, 2)

                connection
            }
            .padding(.horizontal, 2)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.tennis")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No match running")
                .font(.headline)
            Text("Save a preset on your iPhone and it shows up here, ready to start.")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var connection: some View {
        Label(
            model.store.isReachable ? "iPhone connected" : "iPhone not reachable",
            systemImage: model.store.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash"
        )
        .font(.system(size: 10))
        .foregroundStyle(model.store.isReachable ? .green : .secondary)
        .padding(.top, 2)
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
