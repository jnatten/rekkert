import RekkertCore
import SwiftUI

/// Who is still at an Americano or Mexicano. Marking somebody as gone takes them out of the
/// draw from the next round, and their points stay theirs (spec 008).
struct WhosHereView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var asking: PlayerID?

    var body: some View {
        NavigationStack {
            Group {
                if let tournament = TournamentView.tournament(model) {
                    List {
                        Section {
                            ForEach(tournament.players) { player in
                                row(player, in: tournament)
                            }
                        } footer: {
                            if !canMark(tournament) {
                                Text(AwayText.onlyBetweenRounds)
                            }
                        }
                    }
                    // On the list rather than the section: a section hands a presentation to every
                    // row, and several at once throw the sheet away (bug pairing-rule-sheet-closes).
                    .confirmationDialog(
                        askingName(in: tournament).map(AwayText.leaveTitle) ?? "",
                        isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                        titleVisibility: .visible,
                        presenting: asking
                    ) { player in
                        Button(AwayText.leaveButton(tournament.player(player)?.name ?? ""), role: .destructive) {
                            model.store.setAway(player, isAway: true)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: { player in
                        if let message = message(for: player, in: tournament) {
                            Text(message)
                        }
                    }
                } else {
                    ContentUnavailableView("No tournament", systemImage: "sportscourt")
                }
            }
            .navigationTitle(AwayText.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ player: Player, in tournament: Tournament) -> some View {
        let isAway = tournament.isAway(player.id)
        return Button {
            asking = player.id
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .foregroundStyle(isAway ? .secondary : .primary)
                if let away = AwayText.stretches(tournament.awayStretches(of: player.id)) {
                    Text(away)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .tint(.primary)
        .disabled(isAway || !canMark(tournament))
    }

    /// Between rounds only, for now: the round in play is settled by leaving mid-round.
    private func canMark(_ tournament: Tournament) -> Bool {
        guard let round = tournament.currentRound else { return true }
        return round.isCancelled || tournament.isDone(round)
    }

    private func askingName(in tournament: Tournament) -> String? {
        asking.flatMap { tournament.player($0)?.name }
    }

    private func message(for player: PlayerID, in tournament: Tournament) -> String? {
        let lines = [AwayText.turnedAway(model.store.olderPeersTurnedAway(ifNeeding: 4))].compactMap(\.self)
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}
