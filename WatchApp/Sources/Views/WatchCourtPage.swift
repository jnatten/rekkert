import RekkertCore
import SwiftUI
import WatchKit

struct WatchCourtPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.teamPalette) private var palette
    var round = 0
    let court: Int

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(spacing: 6) {
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
                    .frame(height: snapshot.games == nil ? 132 : 150)

                    if snapshot.isSuddenDeath {
                        VStack(spacing: 3) {
                            Text("Sudden death · receivers pick")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                            HStack(spacing: 4) {
                                serveSideButton("Right", court: .deuce, snapshot: snapshot)
                                serveSideButton("Left", court: .ad, snapshot: snapshot)
                            }
                        }
                    }

                    Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                        .disabled(!model.store.canUndo)
                        .font(.footnote)

                    courtControls
                    correction(snapshot)
                }
                .containerBackground(palette.color(layout.order[0]).gradient.opacity(0.25), for: .tabView)
            } else {
                ProgressView()
            }
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

    private var hasSeveralCourts: Bool { (model.store.state?.courtCount ?? 0) > 1 }

    /// Kept on the court itself once there is more than one. The menu is a page of its own
    /// and cannot say which court it means, which is exactly the thing you are correcting.
    @ViewBuilder
    private var courtControls: some View {
        if hasSeveralCourts {
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
            .padding(.top, 2)
        }
    }

    private func serveSideButton(_ title: String, court: ServeCourt, snapshot: ScoreboardSnapshot) -> some View {
        Button(title) { model.store.chooseServeSide(court) }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
            .tint(snapshot.suddenDeathCourt == court ? .orange : .gray)
    }

    private func undo() {
        WKInterfaceDevice.current().play(.retry)
        model.store.undoLast()
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
