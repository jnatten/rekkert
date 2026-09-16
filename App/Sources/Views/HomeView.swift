import RekkertCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var newMatch: GameMode?
    @State private var path: [HomeRoute] = []

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
                    Button {
                        model.showingJoin = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Join a match").foregroundStyle(.primary)
                                Text("Type the code the host reads out")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.2.wave.2")
                        }
                    }
                } header: {
                    Text("Play together")
                } footer: {
                    Text("Everyone at the court sees the same scoreboard and can score it. Whoever shared it is the one who finishes it.")
                }

                if model.workout.isAvailable {
                    Section {
                        Button {
                            model.workout.isTracking ? model.workout.stop() : model.workout.start()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.workout.isTracking ? "Stop the workout" : "Start a workout")
                                        .foregroundStyle(.primary)
                                    Text(model.workout.isTracking
                                         ? "Running on your Apple Watch"
                                         : "On your Apple Watch")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: model.workout.isTracking ? "stop.circle" : "figure.tennis")
                            }
                        }
                    } header: {
                        Text("Workout")
                    } footer: {
                        Text(model.workout.failure ?? "Records your heart rate and energy on your Apple Watch and saves it to Health as tennis, the nearest thing Health has to padel. It runs on its own: start it when you walk on, stop it when you walk off, and play as many matches in between as you like.")
                    }
                }

                Section {
                    Toggle(isOn: $announcer.isEnabled) {
                        Label("Call the score", systemImage: "speaker.wave.2")
                    }
                    if announcer.isEnabled {
                        NavigationLink(value: HomeRoute.voice) {
                            LabeledContent("Voice", value: announcer.currentVoiceName)
                        }
                        Picker("Speed", selection: $announcer.speed) {
                            ForEach(ScoreAnnouncer.Speed.allCases) { speed in
                                Text(speed.title).tag(speed)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    Text("Reads every point out loud, server first: \"thirty, fifteen\", \"deuce\", \"game\". The phone does the talking; the watch stays quiet.")
                }

                if !model.history.isEmpty || model.hasWorkouts {
                    Section("History") {
                        if !model.history.isEmpty {
                            NavigationLink(value: HomeRoute.list) {
                                Label("Past matches", systemImage: "clock.arrow.circlepath")
                            }
                        }
                        if model.hasWorkouts {
                            NavigationLink(value: HomeRoute.workouts) {
                                Label("Workouts", systemImage: "figure.tennis")
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .list: HistoryView()
                case .record(let record): HistoryDetailView(record: record)
                case .voice: VoicePickerView()
                case .workouts: WorkoutsView()
                case .workout(let workout): WorkoutDetailView(workout: workout)
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
                if DemoLaunch.openVoices {
                    model.announcer.isEnabled = true
                    path = [.voice]
                }
                if DemoLaunch.openWorkouts {
                    path = [.workouts]
                    if let index = DemoLaunch.openWorkoutRecord, model.workouts.indices.contains(index) {
                        path.append(.workout(model.workouts[index]))
                    }
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
