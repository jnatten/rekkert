import RekkertCore
import SwiftUI
import WatchKit

struct WatchCourtPage: View {
    @Environment(AppModel.self) private var model
    var round = 0
    let court: Int
    /// Every court page stays alive behind the one on screen, so only the one being looked
    /// at should be talking.
    var isActive = true

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(spacing: 6) {
                    ScoreboardView(
                        snapshot: snapshot,
                        compact: true,
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

                    correction(snapshot)
                }
                .containerBackground(Color.team(.a).gradient.opacity(0.25), for: .tabView)
            } else {
                ProgressView()
            }
        }
        .announcesScore(snapshot, isActive: isActive)
    }

    private var snapshot: ScoreboardSnapshot? {
        model.store.state.flatMap { ScoreboardSnapshot.make(from: $0, round: round, court: court) }
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
                ForEach(TeamSide.allCases, id: \.self) { side in
                    Stepper(value: binding(side, snapshot: snapshot), in: 0 ... 99) {
                        HStack {
                            Circle().fill(Color.team(side)).frame(width: 6, height: 6)
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
