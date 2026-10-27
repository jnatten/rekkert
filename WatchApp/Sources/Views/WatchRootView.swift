import RekkertCore
import RekkertSync
import SwiftUI
import WatchKit

struct WatchRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = 0
    @State private var askingToStartWorkout = false

    var body: some View {
        content
            .environment(\.teamPalette, TeamPalette(isSwapped: model.store.display.areColorsSwapped))
            // The workout page is only in the deck while one is running, so stopping it from
            // that page would otherwise leave the selection pointing at a page that has gone.
            .onChange(of: model.workout.isTracking) { _, isTracking in
                if !isTracking, selection == workoutTag { selection = 0 }
            }
            // The presets page is only in the idle deck, so starting one from it would leave
            // the match opening on a page it does not have.
            .onChange(of: model.store.state == nil) { selection = 0 }
            // Delayed so the join sheet that may have brought the match has gone.
            .task(id: model.follower.isAskingToStart) {
                guard model.follower.isAskingToStart else {
                    askingToStartWorkout = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(600))
                askingToStartWorkout = model.follower.isAskingToStart
            }
            .alert("Start a workout?", isPresented: $askingToStartWorkout) {
                Button("Start") {
                    WKInterfaceDevice.current().play(.start)
                    model.follower.answerStart(true)
                }
                Button("Not now", role: .cancel) { model.follower.answerStart(false) }
            }
            .sheet(item: Binding(
                get: { model.workout.askingForEffort },
                set: { if $0 == nil { model.workout.skipEffort() } }
            )) { _ in
                WatchEffortSheet()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let since = model.store.state?.warmingUpSince {
            TabView(selection: $selection) {
                workoutPage
                WatchWarmupPage(since: since).tag(0)
                WatchMenuView().tag(menuTag)
            }
            .tabViewStyle(.page)
        } else {
            playing
        }
    }

    @ViewBuilder
    private var playing: some View {
        switch model.store.state {
        case .none:
            if let result = model.store.lastResult {
                WatchResultView(state: result)
            } else {
                // A workout does not need a match around it, and somebody who started one
                // with nothing on still wants somewhere to watch it.
                TabView(selection: $selection) {
                    workoutPage
                    WatchIdleView().tag(0)
                    WatchPresetsView().tag(presetsTag)
                }
                .tabViewStyle(.page)
                // A selection left on the menu would land on a page that is not here.
                .task {
                    if ![0, presetsTag, workoutTag].contains(selection) { selection = 0 }
                    openDemoPage()
                }
            }

        case .traditional, .winnerCourt, .pointCount:
            TabView(selection: $selection) {
                workoutPage
                WatchCourtPage(court: 0, onShowWorkout: showWorkout).tag(0)
                WatchMenuView().tag(menuTag)
            }
            .tabViewStyle(.page)
            .task { openDemoPage() }

        // Its own case rather than joining the deck above: the round index has to reach
        // the page, or a tap after round 1 lands on round 1.
        case .friendly(let session):
            TabView(selection: $selection) {
                workoutPage
                WatchCourtPage(round: session.currentIndex, court: 0, onShowWorkout: showWorkout).tag(0)
                WatchMenuView().tag(menuTag)
            }
            .tabViewStyle(.page)
            .task { openDemoPage() }

        case .tournament(let tournament):
            if let round = tournament.currentRound {
                TabView(selection: $selection) {
                    workoutPage
                    ForEach(round.matches) { match in
                        WatchCourtPage(
                            round: round.index,
                            court: match.courtIndex,
                            onShowWorkout: showWorkout
                        )
                        .tag(match.courtIndex)
                    }
                    WatchStandingsView(tournament: tournament).tag(standingsTag)
                    WatchMenuView().tag(menuTag)
                }
                .tabViewStyle(.page)
                .task {
                    showMyCourt(tournament, round: round.index)
                    openDemoPage()
                }
                .onChange(of: round.index) { showMyCourt(tournament, round: round.index) }
                .onChange(of: model.store.me) { showMyCourt(tournament, round: round.index) }
            } else {
                WatchNoRoundView(tournament: tournament)
            }
        }
    }

    /// First, to the left of the score: one swipe from the court on the days there is one,
    /// and never in the way on the days there is not.
    @ViewBuilder
    private var workoutPage: some View {
        if model.workout.isTracking {
            WatchWorkoutPage().tag(workoutTag)
        }
    }

    private func showWorkout() { selection = workoutTag }

    /// A new draw moves you to another court, and the wrist goes with you.
    private func showMyCourt(_ tournament: Tournament, round: Int) {
        guard let me = model.store.me, let court = tournament.court(of: me, round: round) else { return }
        selection = court
    }

    /// Fixed tags so the menu, the standings and the workout keep their place whatever the
    /// court count.
    private var standingsTag: Int { 1_000 }
    private var menuTag: Int { 1_001 }
    private var workoutTag: Int { 1_002 }
    private var presetsTag: Int { 1_003 }

    private func openDemoPage() {
        #if DEBUG
        if WatchDemoLaunch.page == "presets" { selection = presetsTag }
        if WatchDemoLaunch.page == "menu" { selection = menuTag }
        if WatchDemoLaunch.page == "standings" { selection = standingsTag }
        if WatchDemoLaunch.page == "workout" { selection = workoutTag }
        #endif
    }
}

/// The phone is on a shared match and the wrist is not (FR-016): one tap where that can be put
/// right, and why not where it cannot.
struct WatchPhonesMatchBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let elsewhere = model.standIn.phonesMatchElsewhere {
            VStack(spacing: 4) {
                Text("Your iPhone is on a shared match")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                switch elsewhere {
                case .canFollow:
                    Button("Get on it", systemImage: "arrow.right.circle") {
                        WKInterfaceDevice.current().play(.click)
                        model.standIn.followThePhone()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.footnote)
                case .phoneOutOfReach:
                    Text(WatchStandIn.Status.phoneOutOfReach.line)
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                case .phoneCannotReachHost:
                    Text("Your iPhone can't reach the host")
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A guest's wrist starting a match of its own takes its phone off the shared one (FR-030), so it
/// asks first. Whether it has to is the store's to say.
private struct AsksBeforeTakingThePhoneOff: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var pending: (() -> Void)?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "This takes your iPhone off the shared match.",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Start anyway", role: .destructive) {
                pending?()
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }
}

private extension View {
    func asksBeforeTakingThePhoneOff(_ pending: Binding<(() -> Void)?>) -> some View {
        modifier(AsksBeforeTakingThePhoneOff(pending: pending))
    }
}

struct WatchIdleView: View {
    @Environment(AppModel.self) private var model
    @State private var joining = false
    @State private var pendingStart: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // A match called off has no result screen to show it on.
                WatchWorkoutFollowCard()

                WatchPhonesMatchBanner()

                connection

                Button("Quick match", systemImage: "bolt") {
                    let start = { [store = model.store] in
                        store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
                    }
                    if model.store.startingOwnMatchTakesPhoneOff { pendingStart = start } else { start() }
                }
                .buttonStyle(.bordered)
                .font(.footnote)

                // Most people at a shared match only ever join one, and this is the whole of
                // what they have to do. Worth not making them find the phone for it.
                Button("Join a match", systemImage: "person.2") { joining = true }
                    .buttonStyle(.bordered)
                    .font(.footnote)

                // Back on the match whose code is kept, without typing it (FR-024).
                if model.standIn.canJoinAgain {
                    Button("Join again", systemImage: "arrow.right.circle") {
                        WKInterfaceDevice.current().play(.click)
                        model.standIn.joinAgain()
                        joining = true
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }

                // A workout is not tied to a match, so it has to be reachable with none on.
                WatchWorkoutButton(isMenuRow: false)

                CommitLabel()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 2)
        }
        .sheet(isPresented: $joining) { WatchJoinView() }
        .asksBeforeTakingThePhoneOff($pendingStart)
        .task {
            #if DEBUG
            if WatchDemoLaunch.joinCode != nil { joining = true }
            #endif
        }
    }

    private var connection: some View {
        Label(
            model.store.isPairReachable ? "iPhone connected" : "iPhone not reachable",
            systemImage: model.store.isPairReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash"
        )
        .scaledFont(size: 10)
        .foregroundStyle(model.store.isPairReachable ? .green : .secondary)
    }
}

/// One swipe from the idle screen, so a long list of presets never pushes the three
/// things everybody reaches for out of sight.
struct WatchPresetsView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingStart: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if model.store.presets.isEmpty {
                    empty
                } else {
                    Text("Presets")
                        .font(.headline)
                    ForEach(model.store.presets.presets) { preset in
                        Button {
                            let start = { [store = model.store] in store.start(preset) }
                            if model.store.startingOwnMatchTakesPhoneOff { pendingStart = start } else { start() }
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
            }
            .padding(.horizontal, 2)
        }
        .asksBeforeTakingThePhoneOff($pendingStart)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No presets yet")
                .font(.headline)
            Text("Save a preset on your iPhone and it shows up here, ready to start.")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
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
                    if model.store.canRunRounds {
                        Button("Draw round") { model.store.nextRound() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
