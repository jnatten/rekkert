import RekkertCore
import SwiftUI

/// Who sits the round in play out, for when the draw benched somebody who is here and not
/// somebody who is late. The round is drawn again around the pick, so this is only offered
/// while nothing has been played in it.
struct SitOutPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<PlayerID> = []

    var body: some View {
        NavigationStack {
            Group {
                if let tournament = TournamentView.tournament(model), let round = tournament.currentRound {
                    List {
                        playerSection(tournament, round)
                        previewSection(tournament, round)
                    }
                } else {
                    ContentUnavailableView("No round", systemImage: "sportscourt")
                }
            }
            .navigationTitle("Who sits out?")
            .task {
                #if DEBUG
                if let name = DemoLaunch.sitOutPick,
                   let player = TournamentView.tournament(model)?.players.first(where: { $0.name == name }) {
                    chosen = [player.id]
                }
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Redraw", action: redraw)
                        .disabled(redrawn == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func playerSection(_ tournament: Tournament, _ round: Round) -> some View {
        let before = earlier(tournament)
        let tallies = Dictionary(uniqueKeysWithValues: Leaderboard.standings(for: before).map { ($0.player.id, $0.sitOuts) })
        let lastBench = Set(before.rounds.last { !$0.isCancelled }?.sitOuts ?? [])
        let hasHistory = before.rounds.contains { !$0.isCancelled }
        let isFull = chosen.count >= tournament.benchSize

        Section {
            ForEach(tournament.players) { player in
                let isChosen = chosen.contains(player.id)
                Button {
                    toggle(player.id, in: tournament)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .foregroundStyle(Color.primary)
                            let note = history(
                                hasHistory ? tallies[player.id] ?? 0 : nil,
                                satOutLast: lastBench.contains(player.id),
                                drawn: round.sitOuts.contains(player.id)
                            )
                            if !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        Spacer()
                        if isChosen {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .disabled(isFull && !isChosen && tournament.benchSize > 1)
            }
        } header: {
            Text("Round \(round.index + 1)")
        } footer: {
            let count = tournament.benchSize
            if count == 1 {
                Text("One player sits out. The courts are drawn again around whoever you pick.")
            } else {
                Text("\(count) sit out. Any you leave open are chosen fairly: whoever has sat out least, then whoever sat out longest ago. The courts are drawn again around them.")
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ tournament: Tournament, _ round: Round) -> some View {
        if !tournament.canRedrawCurrentRound {
            Section {
                Text("Play has started in this round, so it can't be drawn again.")
                    .foregroundStyle(.secondary)
            }
        } else if let bench = preview(tournament) {
            Section("Sitting out") {
                ForEach(bench, id: \.self) { id in
                    HStack {
                        Text(tournament.player(id)?.name ?? "")
                        Spacer()
                        Text(chosen.contains(id) ? "Picked" : "Chosen fairly")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// `tally` is nil before any round has counted, when nobody has sat out and saying so on
    /// every row says nothing.
    private func history(_ tally: Int?, satOutLast: Bool, drawn: Bool) -> String {
        var parts: [String] = []
        if drawn { parts.append("Drawn to sit out") }
        switch tally {
        case nil: break
        case 0: parts.append("Hasn't sat out yet")
        case let tally?: parts.append(satOutLast ? "Sat out last round (\(tally)× in all)" : "Sat out \(tally)×")
        }
        return parts.joined(separator: " · ")
    }

    private func toggle(_ id: PlayerID, in tournament: Tournament) {
        if chosen.contains(id) {
            chosen.remove(id)
        } else if chosen.count < tournament.benchSize {
            chosen.insert(id)
        } else if tournament.benchSize == 1 {
            chosen = [id]
        }
    }

    /// The tournament as it stood before the round in play was drawn, which is what the
    /// redraw is drawn from and what the tallies are counted over.
    private func earlier(_ tournament: Tournament) -> Tournament {
        var before = tournament
        _ = before.rounds.popLast()
        return before
    }

    private func picked(in tournament: Tournament) -> [PlayerID] {
        tournament.players.map(\.id).filter(chosen.contains)
    }

    private func preview(_ tournament: Tournament) -> [PlayerID]? {
        guard !chosen.isEmpty else { return nil }
        return try? TournamentEngine.redrawingLastRound(of: tournament, sitOuts: picked(in: tournament)).currentRound?.sitOuts
    }

    /// The bench to redraw around, or nil when there is nothing to do: nobody picked, play
    /// has started, or the pick is the bench the round already has.
    private var redrawn: [PlayerID]? {
        guard let tournament = TournamentView.tournament(model), tournament.canRedrawCurrentRound,
              let current = tournament.currentRound, let bench = preview(tournament),
              Set(bench) != Set(current.sitOuts) else { return nil }
        return bench
    }

    private func redraw() {
        guard let bench = redrawn else { return }
        model.store.redrawRound(sittingOut: bench)
        dismiss()
    }
}
