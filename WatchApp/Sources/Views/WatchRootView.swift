import RekkertCore
import SwiftUI

struct WatchRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = 0

    var body: some View {
        content
            .environment(\.teamPalette, TeamPalette(isSwapped: model.store.display.areColorsSwapped))
            // The workout page is only in the deck while one is running, so stopping it from
            // that page would otherwise leave the selection pointing at a page that has gone.
            .onChange(of: model.workout.isTracking) { _, isTracking in
                if !isTracking, selection == workoutTag { selection = 0 }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.store.state {
        case .none:
            if let result = model.store.lastResult {
                WatchResultView(state: result)
            } else if model.workout.isTracking {
                // A workout does not need a match around it, and somebody who started one
                // with nothing on still wants somewhere to watch it.
                TabView(selection: $selection) {
                    WatchIdleView().tag(0)
                    workoutPage
                }
                .tabViewStyle(.page)
                // This deck is two pages where the one before it was four, so a selection
                // left on the menu would land on a page that is not here.
                .task { if selection != workoutTag { selection = 0 } }
            } else {
                WatchIdleView()
            }

        case .traditional, .winnerCourt, .pointCount:
            TabView(selection: $selection) {
                WatchCourtPage(court: 0, onShowWorkout: showWorkout).tag(0)
                workoutPage
                WatchMenuView().tag(menuTag)
            }
            .tabViewStyle(.page)
            .task { openDemoPage() }

        // Its own case rather than joining the deck above: the round index has to reach
        // the page, or a tap after round 1 lands on round 1.
        case .friendly(let session):
            TabView(selection: $selection) {
                WatchCourtPage(round: session.currentIndex, court: 0, onShowWorkout: showWorkout).tag(0)
                workoutPage
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
                            onShowWorkout: showWorkout
                        )
                        .tag(match.courtIndex)
                    }
                    WatchStandingsView(tournament: tournament).tag(standingsTag)
                    workoutPage
                    WatchMenuView().tag(menuTag)
                }
                .tabViewStyle(.page)
                .task { openDemoPage() }
            } else {
                WatchNoRoundView(tournament: tournament)
            }
        }
    }

    /// Last but one, just before the menu: a swipe from the score on the days there is one
    /// and never in the way on the days there is not.
    @ViewBuilder
    private var workoutPage: some View {
        if model.workout.isTracking {
            WatchWorkoutPage().tag(workoutTag)
        }
    }

    private func showWorkout() { selection = workoutTag }

    /// Fixed tags so the menu, the standings and the workout keep their place whatever the
    /// court count.
    private var standingsTag: Int { 1_000 }
    private var menuTag: Int { 1_001 }
    private var workoutTag: Int { 1_002 }

    private func openDemoPage() {
        #if DEBUG
        if WatchDemoLaunch.page == "menu" { selection = menuTag }
        if WatchDemoLaunch.page == "standings" { selection = standingsTag }
        if WatchDemoLaunch.page == "workout" { selection = workoutTag }
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

                // A workout is not tied to a match, so it has to be reachable with none on.
                WatchWorkoutButton(isMenuRow: false)

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
