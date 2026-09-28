import RekkertCore
import SwiftUI

struct PlayersView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var people: [PersonStats] {
        (model.playerStats?.people ?? []).filter { $0.matches(query) }
    }

    var body: some View {
        List {
            ForEach(people) { person in
                NavigationLink(value: HomeRoute.player(person.id)) {
                    PlayerRow(person: person)
                }
            }
        }
        .navigationTitle("Players")
        .searchable(text: $query)
        .overlay {
            if model.playerStats == nil {
                ProgressView()
            } else if model.playerStats?.people.isEmpty == true {
                ContentUnavailableView(
                    "No players yet",
                    systemImage: "person.2",
                    description: Text("Anybody named in a match you keep shows up here.")
                )
            } else if people.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task { await model.refreshPlayerStats() }
    }
}

struct PlayerRow: View {
    let person: PersonStats

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(person.name)
                    if !person.clashes.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Shares a name with somebody they played with")
                    }
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let rate = person.overall.rate {
                Text(rate)
                    .font(.callout.bold().monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let record = person.overall.played == 0
            ? "No finished games yet"
            : "\(person.overall.line) · \(person.overall.played) played"
        return [person.note, record].compactMap { $0 }.joined(separator: " · ")
    }
}

extension Tally {
    var line: String {
        drawn == 0 ? "\(won)–\(lost)" : "\(won)–\(lost), \(drawn) drawn"
    }

    var rate: String? {
        winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) }
    }
}
