import RekkertCore
import SwiftUI

struct TraditionalMatchView: View {
    @Environment(AppModel.self) private var model
    @State private var showingEnd = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = model.store.state.flatMap({ ScoreboardSnapshot.make(from: $0) }) {
                    VStack(spacing: 0) {
                        ScoreboardView(
                            snapshot: snapshot,
                            onTap: { model.store.tap(team: $0) },
                            onUndo: { model.store.undoLast() }
                        )
                        if snapshot.isSuddenDeath {
                            suddenDeathBanner(snapshot)
                        }
                        if snapshot.isFinished {
                            finishedBanner(snapshot)
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionBadge(isReachable: model.store.isReachable)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.store.undoLast() }
                        .disabled(!model.store.canUndo)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End", systemImage: "flag.checkered") { showingEnd = true }
                }
            }
            .confirmationDialog("End this match?", isPresented: $showingEnd, titleVisibility: .visible) {
                Button("Save to history", role: .destructive) { model.archiveAndReset() }
                Button("Keep playing", role: .cancel) {}
            }
        }
    }

    private func suddenDeathBanner(_ snapshot: ScoreboardSnapshot) -> some View {
        VStack(spacing: 8) {
            Text("Sudden death — receivers choose the side")
                .font(.footnote.weight(.semibold))
            Picker("Serve to", selection: Binding(
                get: { snapshot.suddenDeathCourt ?? .deuce },
                set: { model.store.chooseServeSide($0) }
            )) {
                Text("Right (deuce)").tag(ServeCourt.deuce)
                Text("Left (ad)").tag(ServeCourt.ad)
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 30)
        .background(.orange.opacity(0.2))
    }

    private func finishedBanner(_ snapshot: ScoreboardSnapshot) -> some View {
        VStack(spacing: 10) {
            Text(snapshot.detail).font(.title3.bold())
            Button("Save to history") { model.archiveAndReset() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 30)
        .background(.thinMaterial)
    }
}

struct ConnectionBadge: View {
    let isReachable: Bool

    var body: some View {
        Image(systemName: isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
            .foregroundStyle(isReachable ? .green : .secondary)
            .accessibilityLabel(isReachable ? "Watch connected" : "Watch not reachable")
    }
}
