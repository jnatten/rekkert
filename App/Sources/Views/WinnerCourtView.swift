import RekkertCore
import SwiftUI

struct WinnerCourtView: View {
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
                            layout: ScoreboardLayout(isMirrored: model.store.display.isMirrored),
                            onTap: { model.store.tap(team: $0) },
                            onUndo: { model.store.undoLast() }
                        )
                        if snapshot.isSuddenDeath {
                            suddenDeathBanner(snapshot)
                        }
                        footer(session)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(title)
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
                    Button("Finish", systemImage: "stop.circle") { showingEnd = true }
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
        hasResults ? "Finish this session?" : "Call this off?"
    }

    private var session: WinnerCourtSession? {
        guard case .winnerCourt(let value)? = model.store.state else { return nil }
        return value
    }

    private var title: String { "Winner court" }

    private func footer(_ session: WinnerCourtSession) -> some View {
        VStack(spacing: 12) {
            Button {
                model.store.endRound()
            } label: {
                Label("Whistle — end round \(session.roundNumber)", systemImage: "flag.pattern.checkered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.score.games.total == 0 && session.score.points.total == 0)

            tally(session)
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 34)
        .background(.thinMaterial)
    }

    private func tally(_ session: WinnerCourtSession) -> some View {
        HStack(spacing: 18) {
            summary("Rounds won", session.roundsWon)
            Divider().frame(height: 26)
            summary("Games won", session.totalGames)
        }
        .font(.footnote)
    }

    private func summary(_ label: String, _ value: BySide<Int>) -> some View {
        VStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("\(value.a)").foregroundStyle(Color.teamA)
                Text("–").foregroundStyle(.secondary)
                Text("\(value.b)").foregroundStyle(Color.teamB)
            }
            .fontWeight(.semibold)
            .monospacedDigit()
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
        .padding(12)
        .background(.orange.opacity(0.2))
    }
}
