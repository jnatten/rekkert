import RekkertCore
import SwiftUI

struct CourtScoreboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.teamPalette) private var base
    let round: Int
    let court: Int

    private var palette: TeamPalette { base.court(court) }

    /// What the text fields hold while they are being typed into. Committed on submit or
    /// when focus leaves, so a three-digit typo does not become three synced events.
    @State private var draft: BySide<Int>?
    @State private var fullscreen = false
    @FocusState private var typing: TeamSide?

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = snapshot {
                    VStack(spacing: 0) {
                        ScoreboardView(
                            snapshot: snapshot,
                            layout: .phone(snapshot, model.store.display),
                            takesTaps: model.store.canScore,
                            onTap: { model.store.tap(round: round, court: court, team: $0) },
                            onUndo: { model.store.undoLast(round: round, court: court) }
                        )
                        if model.store.canScore {
                            if let tournament, tournament.isLadder {
                                ladderEntry(snapshot, tournament: tournament)
                            } else {
                                entry(snapshot)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Court not in play", systemImage: "sportscourt")
                }
            }
            .announcesScore(snapshot)
            .fullScreenCover(isPresented: $fullscreen) {
                FullscreenScoreView(round: round, court: court)
            }
            .navigationTitle("Round \(round + 1) · Court \(court + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.teamPalette, palette)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MatchOptionsMenu(round: round, court: court)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commit()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.store.undoLast(round: round, court: court) }
                        .disabled(!model.store.canUndo(round: round, court: court))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                        fullscreen = true
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Set") {
                        commit()
                        typing = nil
                    }
                }
            }
        }
    }

    private var snapshot: ScoreboardSnapshot? {
        model.store.state.flatMap { ScoreboardSnapshot.make(from: $0, round: round, court: court) }
    }

    private var tournament: Tournament? {
        guard case .tournament(let tournament)? = model.store.state else { return nil }
        return tournament
    }

    private var rules: PointCountRules? {
        guard let tournament, !tournament.isLadder else { return nil }
        return tournament.config.pointRules
    }

    // MARK: - Ladder

    /// A timed court's games can be set by hand, for a court nobody kept: after the whistle
    /// too, settled or not, until the next round is drawn from it. A match court is only ever
    /// scored point by point.
    @ViewBuilder
    private func ladderEntry(_ snapshot: ScoreboardSnapshot, tournament: Tournament) -> some View {
        let status = tournament.status(round: round, court: court)
        let canSetGames = tournament.ladder?.isTimed == true && round == tournament.latestRoundIndex
            && tournament.round(at: round)?.isCancelled == false
        if snapshot.isSuddenDeath, !snapshot.isLocked {
            suddenDeathBanner(snapshot, deciding: status?.awaitsDecider == true)
        }
        if canSetGames {
            panel {
                Text("Games")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(TeamSide.allCases, id: \.self) { side in
                    entryRow(side, snapshot: snapshot)
                }
            }
        } else if snapshot.isLocked {
            panel {
                Label("This court is settled.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func panel(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 14, content: content)
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 42)
            .background(.thinMaterial)
    }

    private func suddenDeathBanner(_ snapshot: ScoreboardSnapshot, deciding: Bool) -> some View {
        VStack(spacing: 8) {
            Text(deciding ? "Deciding point — receivers choose the side" : "Sudden death — receivers choose the side")
                .font(.footnote.weight(.semibold))
            Picker("Serve to", selection: Binding(
                get: { snapshot.suddenDeathCourt ?? .deuce },
                set: { model.store.chooseServeSide($0, round: round, court: court) }
            )) {
                Text("Right (deuce)").tag(ServeCourt.deuce)
                Text("Left (ad)").tag(ServeCourt.ad)
            }
            .pickerStyle(.segmented)
            .disabled(!model.store.canScore)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.orange.opacity(0.2))
    }

    // MARK: - Entry

    @ViewBuilder
    private func entry(_ snapshot: ScoreboardSnapshot) -> some View {
        VStack(spacing: 14) {
            if snapshot.isLocked {
                Label("This round is finished. Reopen it to change the score.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(TeamSide.allCases, id: \.self) { side in
                    entryRow(side, snapshot: snapshot)
                }
                if let rules, rules.targetKind == .totalPointsPlayed {
                    quickPick(rules)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 42)
        .background(.thinMaterial)
    }

    private func entryRow(_ side: TeamSide, snapshot: ScoreboardSnapshot) -> some View {
        HStack(spacing: 12) {
            Circle().fill(palette.color(side)).frame(width: 10, height: 10)
            Text(snapshot.teamNames[side])
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("0", value: binding(side), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title3.bold().monospacedDigit())
                .frame(width: 64)
                .padding(.vertical, 6)
                .background(palette.color(side).opacity(0.12), in: .rect(cornerRadius: 8))
                .focused($typing, equals: side)
                .onSubmit(commit)

            Stepper("", value: binding(side), in: 0 ... 999)
                .labelsHidden()
        }
    }

    /// In this mode both scores add up to the target, so one tap fixes a whole court.
    private func quickPick(_ rules: PointCountRules) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Or pick a result")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(0 ... rules.target, id: \.self) { a in
                        let points = BySide(a: rules.target - a, b: a)
                        Button("\(points.a)–\(points.b)") {
                            draft = nil
                            typing = nil
                            model.store.setScore(round: round, court: court, points: points)
                        }
                        .font(.callout.monospacedDigit())
                        .buttonStyle(.bordered)
                        .tint(current == points ? .accentColor : .secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Draft handling

    private var current: BySide<Int> {
        if let draft { return draft }
        if let tournament, tournament.isLadder {
            return tournament.status(round: round, court: court)?.line ?? BySide(both: 0)
        }
        return BySide(
            a: Int(snapshot?.primary.a ?? "0") ?? 0,
            b: Int(snapshot?.primary.b ?? "0") ?? 0
        )
    }

    private func binding(_ side: TeamSide) -> Binding<Int> {
        Binding(
            get: { current[side] },
            set: { newValue in
                var points = current
                points[side] = max(0, newValue)
                draft = points
                // A stepper tap is a finished edit; typing waits for submit.
                if typing == nil { commit() }
            }
        )
    }

    private func commit() {
        guard let points = draft else { return }
        draft = nil
        model.store.setScore(round: round, court: court, points: points)
    }
}
