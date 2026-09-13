import RekkertCore
import SwiftUI

struct TraditionalMatchView: View {
    @Environment(AppModel.self) private var model
    @State private var showingEnd = false
    @State private var fullscreen = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    VStack(spacing: 0) {
                        ScoreboardView(
                            snapshot: snapshot,
                            layout: ScoreboardLayout(isMirrored: model.store.display.isMirrored),
                            onTap: { model.store.tap(team: $0) },
                            onUndo: { model.store.undoLast() }
                        )
                        if snapshot.isSuddenDeath {
                            suddenDeathBanner(snapshot)
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
                    Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                        fullscreen = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.store.undoLast() }
                        .disabled(!model.store.canUndo)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MatchOptionsMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End", systemImage: "flag.checkered") { showingEnd = true }
                }
            }
            .fullScreenCover(isPresented: $fullscreen) { FullscreenScoreView(mirrored: model.store.display.isMirrored) }
            .task {
                #if DEBUG
                if DemoLaunch.fullscreen { fullscreen = true }
                #endif
            }
            .announcesScore(snapshot)
            .confirmationDialog(endPrompt, isPresented: $showingEnd, titleVisibility: .visible) {
                if hasResults {
                    Button("Save to history", role: .destructive) { model.finishSession() }
                    Button("Discard", role: .destructive) { model.discard() }
                } else {
                    Button("Discard", role: .destructive) { model.discard() }
                }
                Button("Keep playing", role: .cancel) {}
            }
        }
    }

    private var snapshot: ScoreboardSnapshot? {
        model.store.state.flatMap { ScoreboardSnapshot.make(from: $0) }
    }

    /// Nothing played yet, so there is nothing worth filing.
    private var hasResults: Bool { model.store.state?.hasResults ?? false }

    private var endPrompt: String {
        hasResults ? "End this match?" : "Call this off?"
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
}

struct ConnectionBadge: View {
    let isReachable: Bool

    var body: some View {
        Image(systemName: isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
            .foregroundStyle(isReachable ? .green : .secondary)
            .accessibilityLabel(isReachable ? "Watch connected" : "Watch not reachable")
    }
}
