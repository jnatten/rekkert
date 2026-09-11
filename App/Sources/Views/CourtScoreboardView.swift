import RekkertCore
import SwiftUI

struct CourtScoreboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let court: Int

    @State private var manual: BySide<Int>?

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = model.store.state.flatMap({ ScoreboardSnapshot.make(from: $0, court: court) }) {
                    VStack(spacing: 0) {
                        ScoreboardView(
                            snapshot: snapshot,
                            onTap: { model.store.tap(court: court, team: $0) },
                            onUndo: { model.store.undoLast() }
                        )
                        manualEntry(snapshot)
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Court not in play", systemImage: "sportscourt")
                }
            }
            .navigationTitle("Court \(court + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.store.undoLast() }
                        .disabled(!model.store.canUndo)
                }
            }
        }
    }

    private func manualEntry(_ snapshot: ScoreboardSnapshot) -> some View {
        VStack(spacing: 12) {
            Text("Set the score").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(TeamSide.allCases, id: \.self) { side in
                    Stepper(value: binding(side, snapshot: snapshot), in: 0 ... 99) {
                        HStack {
                            Circle().fill(Color.team(side)).frame(width: 8, height: 8)
                            Text("\(current(snapshot)[side])").monospacedDigit()
                        }
                    }
                    .disabled(snapshot.isLocked)
                }
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private func current(_ snapshot: ScoreboardSnapshot) -> BySide<Int> {
        manual ?? BySide(
            a: Int(snapshot.primary.a) ?? 0,
            b: Int(snapshot.primary.b) ?? 0
        )
    }

    private func binding(_ side: TeamSide, snapshot: ScoreboardSnapshot) -> Binding<Int> {
        Binding(
            get: { current(snapshot)[side] },
            set: { newValue in
                var points = current(snapshot)
                points[side] = newValue
                manual = points
                model.store.setScore(court: court, points: points)
            }
        )
    }
}
