import RekkertCore
import SwiftUI

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
                        }
                    }
                    // On the list rather than the section: a section hands a presentation to every
                    // row, and several at once throw the sheet away (bug pairing-rule-sheet-closes).
                    .confirmationDialog(
                        asking.flatMap { title(for: $0, in: tournament) } ?? "",
                        isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                        titleVisibility: .visible,
                        presenting: asking
                    ) { player in
                        actions(for: player, in: tournament)
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
        let raced = racedCourt(of: player.id, in: tournament)
        return Button {
            asking = player.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .foregroundStyle(isAway ? .secondary : .primary)
                    if let away = AwayText.stretches(tournament.awayStretches(of: player.id)) {
                        Text(away)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let raced {
                        Text(AwayText.stillOnCourt(court: raced, round: tournament.latestRoundIndex + 1))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if raced != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Still on a court")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .tint(.primary)
        .disabled(tournament.isFinished)
    }

    private func racedCourt(of player: PlayerID, in tournament: Tournament) -> Int? {
        guard tournament.awayPlayersOnCourt(inRound: tournament.latestRoundIndex).contains(player),
              let court = tournament.court(of: player, round: tournament.latestRoundIndex) else { return nil }
        return court + 1
    }

    private func title(for player: PlayerID, in tournament: Tournament) -> String? {
        guard let name = tournament.player(player)?.name else { return nil }
        guard tournament.isAway(player) else { return AwayText.leaveTitle(name) }
        return racedCourt(of: player, in: tournament) == nil ? AwayText.backTitle(name) : name
    }

    @ViewBuilder
    private func actions(for player: PlayerID, in tournament: Tournament) -> some View {
        let name = tournament.player(player)?.name ?? ""
        if tournament.isAway(player) {
            if racedCourt(of: player, in: tournament) != nil {
                Button(AwayText.takeOff(name, round: tournament.latestRoundIndex + 1), role: .destructive) {
                    model.store.setAway(player, isAway: true)
                }
            }
            Button(AwayText.backButton(name)) {
                model.store.setAway(player, isAway: false)
            }
        } else {
            Button(AwayText.leaveButton(name), role: .destructive) {
                model.store.setAway(player, isAway: true)
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func message(for player: PlayerID, in tournament: Tournament) -> String? {
        let name = tournament.player(player)?.name ?? ""
        var lines: [String] = []
        let leaving = !tournament.isAway(player) || racedCourt(of: player, in: tournament) != nil
        if let preview = TournamentEngine.awayPreview(player, isAway: leaving, in: tournament) {
            lines += AwayText.inPlay(preview, name: name, roundInPlay: tournament.latestRoundIndex + 1)
            if !preview.isAway, !preview.redrawsRoundInPlay {
                lines.append(AwayText.playsAgain(name, from: preview.fromRound))
            }
            if let shape = AwayText.shape(preview) { lines.append(shape) }
        }
        if !tournament.isAway(player), let older = AwayText.turnedAway(model.store.olderPeersTurnedAway(ifNeeding: 4)) {
            lines.append(older)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}
