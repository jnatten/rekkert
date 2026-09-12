import RekkertCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var newMatch: GameMode?

    var body: some View {
        NavigationStack {
            List {
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

                if !model.history.isEmpty {
                    Section("History") {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            Label("Past matches", systemImage: "clock.arrow.circlepath")
                        }
                    }
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
                #endif
            }
        }
    }
}

enum GameMode: String, CaseIterable, Identifiable {
    case traditional
    case winnerCourt
    case americano
    case mexicano

    var id: String { rawValue }

    var title: String {
        switch self {
        case .traditional: "Match"
        case .winnerCourt: "Winner court"
        case .americano: "Americano"
        case .mexicano: "Mexicano"
        }
    }

    var subtitle: String {
        switch self {
        case .traditional: "Games, sets and match"
        case .winnerCourt: "Games until the whistle, round after round"
        case .americano: "Everyone partners everyone"
        case .mexicano: "Re-paired by standings each round"
        }
    }

    var symbol: String {
        switch self {
        case .traditional: "figure.tennis"
        case .winnerCourt: "arrow.up.arrow.down"
        case .americano: "arrow.triangle.2.circlepath"
        case .mexicano: "list.number"
        }
    }

    var tournamentFormat: TournamentFormat? {
        switch self {
        case .traditional, .winnerCourt: nil
        case .americano: .americano
        case .mexicano: .mexicano
        }
    }
}
