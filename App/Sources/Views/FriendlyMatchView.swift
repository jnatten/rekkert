import RekkertCore
import SwiftUI

/// A friendly: an ordinary match on the board, and underneath it the one button that ends
/// this round and the partnership waiting to play the next one.
struct FriendlyMatchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.teamPalette) private var palette
    @State private var showingEnd = false
    @State private var showingRounds = false
    @State private var fullscreen = false

    var body: some View {
        NavigationStack {
            Group {
                if let session, let snapshot {
                    VStack(spacing: 0) {
                        ScoreboardView(
                            snapshot: snapshot,
                            layout: .phone(snapshot, model.store.display),
                            // Addressed to the round on screen, so a tap that arrives late
                            // lands where it was aimed rather than on whatever is current.
                            onTap: { model.store.tap(round: session.currentIndex, court: 0, team: $0) },
                            onUndo: { model.store.undoLast() }
                        )
                        if snapshot.isSuddenDeath {
                            suddenDeathBanner(snapshot)
                        }
                        footer(session)
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else if let session, session.rounds.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on the board", systemImage: "sportscourt")
                    } description: {
                        Text("The first round was taken back.")
                    } actions: {
                        Button("Start round 1", systemImage: "play.fill") { model.store.nextRound() }
                            .buttonStyle(.borderedProminent)
                    }
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
                if sizeClass == .regular {
                    ToolbarItem(placement: .topBarTrailing) { BoardButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.store.undoLast() }
                        .disabled(!model.store.canUndo)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MatchOptionsMenu(
                        round: session?.currentIndex ?? 0,
                        onShowRounds: { showingRounds = true }
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EndSessionButton(title: "Finish", symbol: "stop.circle") { showingEnd = true }
                }
            }
            .fullScreenCover(isPresented: $fullscreen) {
                FullscreenScoreView()
            }
            .sheet(isPresented: $showingRounds) {
                if let session { FriendlyRoundsSheet(session: session) }
            }
            .task {
                #if DEBUG
                if DemoLaunch.fullscreen { fullscreen = true }
                if DemoLaunch.openRounds { showingRounds = true }
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

    private var session: FriendlySession? {
        guard case .friendly(let value)? = model.store.state else { return nil }
        return value
    }

    private var snapshot: ScoreboardSnapshot? {
        guard let session else { return nil }
        return ScoreboardSnapshot.make(from: .friendly(session), round: session.currentIndex)
    }

    /// Nothing played yet, so there is nothing worth filing.
    private var hasResults: Bool { model.store.state?.hasResults ?? false }

    private var endPrompt: String {
        hasResults ? "Finish this friendly?" : "Call this off?"
    }

    private var title: String {
        session.map { $0.name.isEmpty ? "Friendly" : $0.name } ?? "Friendly"
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(_ session: FriendlySession) -> some View {
        if let round = session.currentRound {
            VStack(spacing: 10) {
                if round.isFinished {
                    upNext(session, after: round)
                } else {
                    Button {
                        model.store.endRound()
                    } label: {
                        Label("End round \(round.index + 1) now", systemImage: "flag.pattern.checkered")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!round.wasPlayed)

                    bench(session, in: round)
                }
            }
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 34)
            .background(.thinMaterial)
        }
    }

    /// The partnership the next round will be played by, named before anybody commits to it.
    /// The draw is a pure function of the session, so this is exactly what the button draws.
    @ViewBuilder
    private func upNext(_ session: FriendlySession, after round: FriendlyRound) -> some View {
        VStack(spacing: 10) {
            if let next = session.nextDraw() {
                VStack(spacing: 3) {
                    Text("Up next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(session.names(.a, in: next)).foregroundStyle(palette.color(.a))
                        Text("vs").foregroundStyle(.secondary)
                        Text(session.names(.b, in: next)).foregroundStyle(palette.color(.b))
                    }
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    // The bench that goes with the round being offered, not the one just
                    // played — this whole block is about what happens next.
                    bench(session, in: next)
                }
            }

            Button {
                model.store.nextRound()
            } label: {
                Label("Start round \(round.index + 2)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func bench(_ session: FriendlySession, in round: FriendlyRound) -> some View {
        if !round.sitOuts.isEmpty {
            Text("Sitting out: \(session.sitOutNames(in: round).joined(separator: ", "))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

/// The evening so far: who is winning it, and every round that has been played.
struct FriendlyRoundsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.teamPalette) private var palette
    let session: FriendlySession

    private var played: [FriendlyRound] { session.rounds.filter(\.wasPlayed) }
    private var standings: [FriendlyStanding] { Leaderboard.standings(for: session) }

    var body: some View {
        NavigationStack {
            List {
                if !played.isEmpty {
                    Section("Standings") {
                        ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, alignment: .trailing)
                                Text(standing.player.name)
                                    .fontWeight(index == 0 ? .semibold : .regular)
                                Spacer()
                                Text("\(standing.roundsWon) won")
                                    .font(.callout.bold().monospacedDigit())
                                Text("\(standing.gamesFor) games")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                ForEach(played.reversed()) { round in
                    Section("Round \(round.index + 1)") {
                        ForEach(TeamSide.allCases, id: \.self) { side in
                            HStack {
                                Circle().fill(palette.color(side)).frame(width: 8, height: 8)
                                Text(session.names(side, in: round)).lineLimit(1)
                                Spacer()
                                Text("\(round.games[side])")
                                    .font(.body.bold().monospacedDigit())
                                    .foregroundStyle(palette.color(side))
                            }
                        }
                        if round.isStopped {
                            Text("Stopped part-way").font(.caption).foregroundStyle(.secondary)
                        }
                        if !round.sitOuts.isEmpty {
                            Text("Sitting out: \(session.sitOutNames(in: round).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if played.isEmpty {
                    ContentUnavailableView(
                        "Nothing played yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Rounds show up here as they are played.")
                    )
                }
            }
            .navigationTitle("Rounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
