import RekkertCore
import SwiftUI

struct PairingRulesSection: View {
    @Binding var rules: [PairingRule]
    let players: [Player]
    var forecast: PairingForecast?
    var kinds: [PairingRule.Kind] = [.apart]
    @State private var editing: EditedRule?

    private var session: FriendlySession { FriendlySession(players: players, pairingRules: rules) }

    var body: some View {
        Section {
            if players.count >= 4 {
                ForEach(rules) { rule in
                    Button { editing = EditedRule(kind: rule.kind, rule: rule) } label: {
                        Text(PairingText.rule(rule, in: session)).foregroundStyle(.primary)
                    }
                }
                .onDelete { rules.remove(atOffsets: $0) }

                if kinds.contains(.apart) {
                    Button("Keep players apart…", systemImage: "person.2.slash") { editing = EditedRule(kind: .apart) }
                }
                if kinds.contains(.together) {
                    Button("Keep two together…", systemImage: "person.2") { editing = EditedRule(kind: .together) }
                }
            }
        } header: {
            Text("Pairing")
        } footer: {
            footer
        }
        .sheet(item: $editing) { edited in
            PairingRuleSheet(kind: edited.kind, players: players, original: edited.rule) { saved in
                if let index = rules.firstIndex(where: { $0.id == saved.id }) {
                    rules[index] = saved
                } else {
                    rules.append(saved)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if players.count < 4 {
            Text("Pairing rules apply when four or more play doubles.")
        } else if rules.isEmpty {
            Text("Say who should never be partners, or who always should, to even the matches.")
        } else if let forecast, let line = PairingText.forecast(forecast, in: session) {
            Text(line)
        }
    }
}

private struct EditedRule: Identifiable {
    let id = UUID()
    var kind: PairingRule.Kind
    var rule: PairingRule?
}

struct PairingRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: PairingRule.Kind
    let players: [Player]
    let original: PairingRule?
    let onDone: (PairingRule) -> Void
    @State private var picked: [PlayerID]

    init(kind: PairingRule.Kind, players: [Player], original: PairingRule?, onDone: @escaping (PairingRule) -> Void) {
        self.kind = kind
        self.players = players
        self.original = original
        self.onDone = onDone
        _picked = State(initialValue: original?.players ?? [])
    }

    private var rule: PairingRule { PairingRule(id: original?.id ?? UUID(), kind: kind, players: picked) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(players) { player in
                        Button { toggle(player.id) } label: {
                            HStack {
                                Text(player.name).foregroundStyle(.primary)
                                Spacer()
                                if picked.contains(player.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityAddTraits(picked.contains(player.id) ? .isSelected : [])
                    }
                } footer: {
                    Text(kind == .apart
                        ? "None of these will be partners. They can still play against each other."
                        : "These two will be partners whenever both are on court. If one sits out, the other plays with whoever is drawn.")
                }
            }
            .navigationTitle(kind == .apart ? "Keep apart" : "Keep together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(rule)
                        dismiss()
                    }
                    .disabled(!rule.isWellFormed)
                }
            }
        }
    }

    private func toggle(_ id: PlayerID) {
        if let index = picked.firstIndex(of: id) {
            picked.remove(at: index)
            return
        }
        picked.append(id)
        if kind == .together, picked.count > 2 { picked.removeFirst() }
    }
}
