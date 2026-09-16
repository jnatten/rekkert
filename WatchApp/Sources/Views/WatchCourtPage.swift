import RekkertCore
import SwiftUI
import WatchKit

struct WatchCourtPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.teamPalette) private var palette
    var round = 0
    let court: Int
    @State private var page = WatchCourtPage.startPage

    var body: some View {
        content
            .containerBackground(palette.color(layout.order[0]).gradient.opacity(0.25), for: .tabView)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            TabView(selection: $page) {
                scoreboard(snapshot).tag(0)
                controls(snapshot).tag(1)
            }
            .tabViewStyle(.verticalPage)
            // A court page is reused as the rounds go by, and each one should open on the
            // score rather than wherever the last one was left.
            .onChange(of: round) { page = 0 }
        } else {
            ProgressView()
        }
    }

    private func scoreboard(_ snapshot: ScoreboardSnapshot) -> some View {
        VStack(spacing: 4) {
            ScoreboardView(
                snapshot: snapshot,
                compact: true,
                layout: layout,
                onTap: { side in
                    WKInterfaceDevice.current().play(.click)
                    model.store.tap(round: round, court: court, team: side)
                },
                onUndo: undo
            )
            // Nothing scrolls on this page any more, so the numbers take the whole of it.
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) { undoButton }
            .overlay(alignment: .bottomTrailing) { heartRate }

            // The line above the score already says it is sudden death, so this row only has
            // to say whose call it is and take the answer.
            if snapshot.isSuddenDeath {
                HStack(spacing: 4) {
                    Text("Receivers pick")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    serveSideButton("Right", court: .deuce, snapshot: snapshot)
                    serveSideButton("Left", court: .ad, snapshot: snapshot)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// Present only while a workout is running, and gone entirely otherwise — playing
    /// without one is the ordinary case, not a thing to report. It follows the session
    /// rather than the first sample: waiting for a reading would have it blink into
    /// existence some seconds after the button, which reads as a fault.
    @ViewBuilder
    private var heartRate: some View {
        if model.workout.isTracking {
            HStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .symbolEffect(.pulse)
                if let beats = model.workout.heartRate {
                    Text(beats.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.pink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.4), in: .capsule)
            .padding(.trailing, 3)
            .padding(.bottom, 3)
            .accessibilityLabel(
                model.workout.heartRate.map { "\(Int($0)) beats per minute" } ?? "Workout running"
            )
        }
    }

    /// Undoing is a correction, not the thing you came here to do, so it sits in a corner
    /// as the icon alone rather than taking a row from the numbers. The score undoes on a
    /// long press too, and the menu carries it in full.
    private var undoButton: some View {
        Button(action: undo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                // Dark enough to read as a control over a team's colour as well as over the
                // black around it.
                .background(.black.opacity(0.4), in: .circle)
        }
        .buttonStyle(.plain)
        .opacity(model.store.canUndo ? 1 : 0.35)
        .disabled(!model.store.canUndo)
        .padding(.leading, 3)
        .padding(.bottom, 3)
        .accessibilityLabel("Undo")
    }

    /// The page below the score: everything you reach for between points rather than during
    /// them, kept off the scoreboard so it can hold still.
    private func controls(_ snapshot: ScoreboardSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                if let label = snapshot.courtLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                courtControls
                correction(snapshot)
            }
            .padding(.top, 6)
        }
    }

    private var snapshot: ScoreboardSnapshot? {
        model.store.state.flatMap { ScoreboardSnapshot.make(from: $0, round: round, court: court) }
    }

    /// Blue always reads first here. The watch is glanced at rather than studied, and on a
    /// screen this size the colour you are is the thing you are looking for — so swapping
    /// the colours swaps the sides with them.
    private var layout: ScoreboardLayout {
        ScoreboardLayout(isMirrored: model.store.display.areColorsSwapped)
    }

    private var courtControls: some View {
        VStack(spacing: 4) {
            Button("Swap serve", systemImage: "arrow.left.arrow.right") {
                WKInterfaceDevice.current().play(.click)
                model.store.swapServingTeam(round: round, court: court)
            }
            Button("Swap colours", systemImage: "circle.lefthalf.filled") {
                WKInterfaceDevice.current().play(.click)
                model.store.toggleTeamColors()
            }
        }
        .font(.footnote)
    }

    private func serveSideButton(_ title: String, court: ServeCourt, snapshot: ScoreboardSnapshot) -> some View {
        Button(title) { model.store.chooseServeSide(court) }
            .font(.system(size: 12))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            // Untinted where the orange has nothing to say: a grey tint paints the word grey
            // too, and this row is asking to be tapped.
            .tint(snapshot.suddenDeathCourt == court ? .orange : nil)
    }

    private func undo() {
        WKInterfaceDevice.current().play(.retry)
        model.store.undoLast()
    }

    /// Set before the tab view exists rather than in a task: handed a selection after its
    /// pages have registered, it falls back to the first one.
    private static var startPage: Int {
        #if DEBUG
        WatchDemoLaunch.page == "controls" ? 1 : 0
        #else
        0
        #endif
    }

    /// Crown-driven correction. watchOS Steppers bind to the Digital Crown when focused.
    @ViewBuilder
    private func correction(_ snapshot: ScoreboardSnapshot) -> some View {
        if case .tournament? = model.store.state, !snapshot.isLocked {
            VStack(spacing: 4) {
                Text("Fix score").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(layout.order, id: \.self) { side in
                    Stepper(value: binding(side, snapshot: snapshot), in: 0 ... 99) {
                        HStack {
                            Circle().fill(palette.color(side)).frame(width: 6, height: 6)
                            Text("\(points(snapshot)[side])").monospacedDigit()
                        }
                        .font(.footnote)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func points(_ snapshot: ScoreboardSnapshot) -> BySide<Int> {
        BySide(a: Int(snapshot.primary.a) ?? 0, b: Int(snapshot.primary.b) ?? 0)
    }

    private func binding(_ side: TeamSide, snapshot: ScoreboardSnapshot) -> Binding<Int> {
        Binding(
            get: { points(snapshot)[side] },
            set: { newValue in
                var updated = points(snapshot)
                updated[side] = newValue
                model.store.setScore(round: round, court: court, points: updated)
            }
        )
    }
}

struct WatchStandingsView: View {
    let tournament: Tournament

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Standings").font(.headline)
                ForEach(Array(Leaderboard.standings(for: tournament).enumerated()), id: \.element.id) { index, standing in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Text(standing.player.name).font(.footnote).lineLimit(1)
                        Spacer()
                        Text("\(standing.total)").font(.footnote.bold().monospacedDigit())
                    }
                }
            }
        }
    }
}
