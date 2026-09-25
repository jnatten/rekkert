import RekkertCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var newMatch: GameMode?
    @State private var path: [HomeRoute] = []
    @State private var editMode: EditMode = .inactive
    @State private var editingPreset: Preset?
    @State private var renaming: Preset?
    @State private var renameText = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !model.store.presets.isEmpty {
                    Section {
                        ForEach(model.store.presets.presets) { preset in
                            Button {
                                if editMode.isEditing {
                                    editingPreset = preset
                                } else {
                                    model.store.start(preset)
                                }
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
                            .contextMenu {
                                Button("Edit…", systemImage: "slider.horizontal.3") { editingPreset = preset }
                                Button("Rename…", systemImage: "pencil") {
                                    renameText = preset.name
                                    renaming = preset
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    model.store.removePreset(preset.id)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { model.store.presets.presets[$0].id }
                            ids.forEach(model.store.removePreset)
                        }
                        .onMove { model.store.movePresets(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Presets")
                    } footer: {
                        Text(editMode.isEditing
                             ? "Drag to reorder. Tap one to change it."
                             : "Saved setups, ready on your Apple Watch in the same order. Press and hold one to edit or rename it.")
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
                        if model.workout.isTracking {
                            Button {
                                model.workout.isPaused ? model.workout.resume() : model.workout.pause()
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.workout.isPaused ? "Pick it back up" : "Hold the workout")
                                            .foregroundStyle(.primary)
                                        Text(model.workout.isPaused
                                             ? "The clock is stopped and nothing is being collected"
                                             : "For a break that should not count towards it")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: model.workout.isPaused ? "play.circle" : "pause.circle")
                                }
                            }
                        }
                        Button {
                            model.workout.isTracking ? model.workout.stop() : model.workout.start()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.workout.isTracking ? "Stop the workout" : "Start a workout")
                                        .foregroundStyle(.primary)
                                    Text(subtitle)
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
            .environment(\.editMode, $editMode)
            .onChange(of: model.store.presets.isEmpty) { _, isEmpty in
                if isEmpty { editMode = .inactive }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .list: HistoryView()
                case .record(let id): HistoryDetailView(id: id)
                case .voice: VoicePickerView()
                case .settings: SettingsView()
                case .workouts: WorkoutsView()
                case .workout(let workout): WorkoutDetailView(workout: workout)
                }
            }
            .navigationTitle("Rekkert")
            .toolbar {
                if !model.store.presets.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { path.append(.settings) }
                }
            }
            .sheet(item: $newMatch) { mode in
                NewSessionView(mode: mode)
            }
            .sheet(item: $editingPreset) { preset in
                NewSessionView(editing: preset)
            }
            .alert(
                "Rename preset",
                isPresented: Binding(
                    get: { renaming != nil },
                    set: { if !$0 { renaming = nil } }
                )
            ) {
                TextField("Name", text: $renameText)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") { rename() }
            }
            .task {
                #if DEBUG
                if let raw = DemoLaunch.newSession {
                    newMatch = GameMode(rawValue: raw)
                }
                if DemoLaunch.openSettings {
                    path = [.settings]
                }
                if DemoLaunch.openVoices {
                    model.announcer.isEnabled = true
                    path = [.settings, .voice]
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
                        path.append(.record(model.history[index].id))
                    }
                }
                #endif
            }
        }
    }

    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard let renaming, !name.isEmpty else { return }
        model.store.updatePreset(renaming.id) { $0.name = name }
    }

    private var subtitle: String {
        switch (model.workout.isTracking, model.workout.isPaused) {
        case (false, _): "On your Apple Watch"
        case (true, false): "Running on your Apple Watch"
        case (true, true): "Paused on your Apple Watch"
        }
    }
}

enum GameMode: String, CaseIterable, Identifiable {
    case traditional
    case pointCount
    case winnerCourt
    case friendly
    case americano
    case mexicano

    var id: String { rawValue }

    init(_ configuration: PresetConfiguration) {
        switch configuration {
        case .traditional: self = .traditional
        case .pointCount: self = .pointCount
        case .winnerCourt: self = .winnerCourt
        case .friendly: self = .friendly
        case .tournament(let format, _, _, _):
            switch format {
            case .americano: self = .americano
            case .mexicano: self = .mexicano
            }
        }
    }

    var title: String {
        switch self {
        case .traditional: "Match"
        case .pointCount: "Points"
        case .winnerCourt: "Winner court"
        case .friendly: "Friendly"
        case .americano: "Americano"
        case .mexicano: "Mexicano"
        }
    }

    var subtitle: String {
        switch self {
        case .traditional: "Games, sets and match"
        case .pointCount: "One round, counted 1, 2, 3 to a target"
        case .winnerCourt: "Games until the whistle, round after round"
        case .friendly: "Rotating teams, match after match"
        case .americano: "Everyone partners everyone"
        case .mexicano: "Re-paired by standings each round"
        }
    }

    var symbol: String {
        switch self {
        case .traditional: "figure.tennis"
        case .pointCount: "number"
        case .winnerCourt: "arrow.up.arrow.down"
        case .friendly: "shuffle"
        case .americano: "arrow.triangle.2.circlepath"
        case .mexicano: "list.number"
        }
    }

    var tournamentFormat: TournamentFormat? {
        switch self {
        case .traditional, .pointCount, .winnerCourt, .friendly: nil
        case .americano: .americano
        case .mexicano: .mexicano
        }
    }
}
