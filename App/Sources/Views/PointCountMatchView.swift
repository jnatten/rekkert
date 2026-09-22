import RekkertCore
import SwiftUI

/// A single counted round: the same scoring an americano court uses, without a tournament
/// around it.
struct PointCountMatchView: View {
    @Environment(AppModel.self) private var model
    @State private var showingEnd = false
    @State private var fullscreen = false

    var body: some View {
        NavigationStack {
            Group {
                if let session, let snapshot {
                    VStack(spacing: 0) {
                        ScoreboardView(
                            snapshot: snapshot,
                            layout: .phone(snapshot, model.store.display),
                            onTap: { model.store.tap(team: $0) },
                            onUndo: { model.store.undoLast() }
                        )
                        footer(session)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    ConnectionBadge()
                    SharingBadge()
                    WorkoutBadge()
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
                    EndSessionButton { showingEnd = true }
                }
            }
            .fullScreenCover(isPresented: $fullscreen) {
                FullscreenScoreView()
            }
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

    private var session: PointCountSession? {
        guard case .pointCount(let value)? = model.store.state else { return nil }
        return value
    }

    private var title: String { "Points" }

    private var hasResults: Bool { model.store.state?.hasResults ?? false }

    private var endPrompt: String {
        hasResults ? "End this round?" : "Call this off?"
    }

    private func footer(_ session: PointCountSession) -> some View {
        VStack(spacing: 12) {
            Text(remaining(session))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 34)
        .background(.thinMaterial)
    }

    private func remaining(_ session: PointCountSession) -> String {
        let left = session.engine.pointsRemaining(session.score)
        switch session.rules.targetKind {
        case .totalPointsPlayed:
            return "\(left) of \(session.rules.target) points left to play"
        case .firstToTarget:
            return "First to \(session.rules.target) — \(left) more to win it"
        }
    }
}
