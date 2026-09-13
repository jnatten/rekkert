import RekkertCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var newMatch: GameMode?
    @State private var path: [HistoryRoute] = []

    var body: some View {
        @Bindable var announcer = model.announcer
        NavigationStack(path: $path) {
            List {
                if !model.store.presets.isEmpty {
                    Section {
                        ForEach(model.store.presets.ordered) { preset in
                            Button {
                                model.store.start(preset)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name).foregroundStyle(.primary)
                                        Text(preset.configuration.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: preset.configuration.symbol)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                model.store.removePreset(model.store.presets.ordered[index].id)
                            }
                        }
                    } header: {
                        Text("Presets")
                    } footer: {
                        Text("Saved setups, ready on your Apple Watch too. Swipe to delete.")
                    }
                }

                Section("Start") {
                    ForEach(GameMode.allCases) { mode in
                        Button {
                            newMatch = mode
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title).foregroundStyle(.primary)
                                    Text(mode.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: mode.symbol)
                            }
                        }
                    }
                }

                Section {
                    Toggle(isOn: $announcer.isEnabled) {
                        Label("Call the score", systemImage: "speaker.wave.2")
                    }
                } footer: {
                    Text("Reads every point out loud, server first: \"thirty, fifteen\", \"deuce\", \"game\". This device only — set it separately on your Apple Watch.")
                }

                if !model.history.isEmpty {
                    Section("History") {
                        NavigationLink(value: HistoryRoute.list) {
                            Label("Past matches", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
            .navigationDestination(for: HistoryRoute.self) { route in
                switch route {
                case .list: HistoryView()
                case .record(let record): HistoryDetailView(record: record)
                }
            }
            .navigationTitle("Rekkert")
            .sheet(item: $newMatch) { mode in
                NewSessionView(mode: mode)
            }
            .task {
                #if DEBUG
                if let raw = DemoLaunch.newSession {
                    newMatch = GameMode(rawValue: raw)
                }
                if DemoLaunch.openHistory {
                    path = [.list]
                    if let index = DemoLaunch.openHistoryRecord, model.history.indices.contains(index) {
                        path.append(.record(model.history[index]))
                    }
                }
                #endif
            }
        }
    }
}

enum GameMode: String, CaseIterable, Identifiable {
    case traditional
    case pointCount
    case winnerCourt
    case americano
    case mexicano

    var id: String { rawValue }

    var title: String {
        switch self {
        case .traditional: "Match"
        case .pointCount: "Points"
        case .winnerCourt: "Winner court"
        case .americano: "Americano"
        case .mexicano: "Mexicano"
        }
    }

    var subtitle: String {
        switch self {
        case .traditional: "Games, sets and match"
        case .pointCount: "One round, counted 1, 2, 3 to a target"
        case .winnerCourt: "Games until the whistle, round after round"
        case .americano: "Everyone partners everyone"
        case .mexicano: "Re-paired by standings each round"
        }
    }

    var symbol: String {
        switch self {
        case .traditional: "figure.tennis"
        case .pointCount: "number"
        case .winnerCourt: "arrow.up.arrow.down"
        case .americano: "arrow.triangle.2.circlepath"
        case .mexicano: "list.number"
        }
    }

    var tournamentFormat: TournamentFormat? {
        switch self {
        case .traditional, .pointCount, .winnerCourt: nil
        case .americano: .americano
        case .mexicano: .mexicano
        }
    }
}
