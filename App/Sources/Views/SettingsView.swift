import RekkertCore
import SwiftUI

/// What is not about any one match: how the full-screen board is drawn, and whether the
/// score is read out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var announcer = model.announcer
        @Bindable var fullscreen = model.fullscreen
        @Bindable var liveScore = model.liveScore
        List {
            Section {
                Toggle(isOn: $fullscreen.isBlackout) {
                    Label("Black out the colours", systemImage: "moon.fill")
                }
            } header: {
                Text("Full screen")
            } footer: {
                Text("Draws both halves of the full-screen board black, with the names in the team colours, so the score stands out on a phone propped up in the sun. The moon button on the board switches it too.")
            }

            Section {
                Toggle(isOn: $liveScore.isEnabled) {
                    Label("Score on the Lock Screen", systemImage: "lock.iphone")
                }
            } footer: {
                Text(liveScoreFooter)
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

            if AppModel.canPairWatch {
                Section {
                    Picker(selection: hapticMode) {
                        ForEach(HapticMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    } label: {
                        Label("Buzz on a point", systemImage: "hand.tap")
                    }
                    if model.store.haptics.mode != .off {
                        Toggle("Only when someone else scores", isOn: onlyOthers)
                        Picker("Strength", selection: hapticStrength) {
                            ForEach(HapticStrength.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    Text(hapticFooter)
                }

                Section {
                    Toggle(isOn: tapAnywhere) {
                        Label("Tap anywhere to score", systemImage: "applewatch")
                    }
                } header: {
                    Text("Watch")
                } footer: {
                    Text("Takes the undo button off the watch and makes its whole score screen the target: tap once for your point, twice for theirs, and hold to take the last one back. The phone's board stays as it is.")
                }

                if model.workout.isAvailable {
                    Section {
                        Picker(selection: workoutOnMatchStart) {
                            ForEach(WorkoutCue.allCases, id: \.self) { Text($0.startTitle).tag($0) }
                        } label: {
                            Label("When a match starts", systemImage: "figure.tennis")
                        }
                        Picker(selection: workoutOnMatchEnd) {
                            ForEach(WorkoutCue.allCases, id: \.self) { Text($0.endTitle).tag($0) }
                        } label: {
                            Label("When a match ends", systemImage: "flag.checkered")
                        }
                    } header: {
                        Text("Workout on your watch")
                    } footer: {
                        Text(workoutFooter)
                    }
                }
            }

            Section {
                NavigationLink(value: HomeRoute.sharingRecord) {
                    Label("Sharing record", systemImage: "doc.text.magnifyingglass")
                }
            } footer: {
                Text("What happened to this iPhone's links and its watch's on shared matches this past week, to send to the developer if sharing went wrong. It stays on your devices unless you share it.")
            }

            #if DEBUG
            Section {
                Button("End app as the system would", role: .destructive) { kill(getpid(), SIGKILL) }
            } footer: {
                Text("Ends Rekkert the way iOS does to free memory, not the way swiping it away does, so Bluetooth can bring it back. Debug builds only.")
            }
            #endif

            Section {} footer: {
                CommitLabel()
            }
        }
        .navigationTitle("Settings")
    }

    /// Written through the store rather than bound to it: the value travels to the watch and
    /// back, and every change has to go out as the whole answer rather than as a nudge.
    private var hapticMode: Binding<HapticMode> {
        Binding(
            get: { model.store.haptics.mode },
            set: { model.store.setHaptics(mode: $0) }
        )
    }

    private var onlyOthers: Binding<Bool> {
        Binding(
            get: { model.store.haptics.onlyWhenSomeoneElseScores },
            set: { model.store.setHaptics(onlyWhenSomeoneElseScores: $0) }
        )
    }

    private var hapticStrength: Binding<HapticStrength> {
        Binding(
            get: { model.store.haptics.strength },
            set: { model.store.setHaptics(strength: $0) }
        )
    }

    private var tapAnywhere: Binding<Bool> {
        Binding(
            get: { model.store.haptics.tapAnywhere },
            set: { model.store.setHaptics(tapAnywhere: $0) }
        )
    }

    private var workoutOnMatchStart: Binding<WorkoutCue> {
        Binding(
            get: { model.store.haptics.workoutOnMatchStart },
            set: {
                model.store.setHaptics(workoutOnMatchStart: $0)
                if $0 != .off { model.workout.prepare() }
            }
        )
    }

    private var workoutOnMatchEnd: Binding<WorkoutCue> {
        Binding(
            get: { model.store.haptics.workoutOnMatchEnd },
            set: { model.store.setHaptics(workoutOnMatchEnd: $0) }
        )
    }

    private var workoutFooter: String {
        let start: String? = switch model.store.haptics.workoutOnMatchStart {
        case .off: nil
        case .ask: "Starting or joining a match asks whether to start a workout on your watch."
        case .automatic: "Starting or joining a match starts a workout on your watch."
        }
        let end: String? = switch model.store.haptics.workoutOnMatchEnd {
        case .off: nil
        case .ask: "When a match ends, the watch taps your wrist and asks whether to stop the workout."
        case .automatic: "When a match ends, the watch stops the workout a minute later, unless another match starts or you keep it going."
        }
        guard start != nil || end != nil else {
            return "A workout can start when you start or join a match, and stop when it ends, or Rekkert can ask you first. Nothing happens to a workout unless you choose it here."
        }
        return [start, end].compactMap(\.self).joined(separator: " ")
    }

    private var liveScoreFooter: String {
        guard model.liveScore.isAllowed else {
            return "Live Activities are turned off for Rekkert in the iPhone's Settings, so nothing shows on the Lock Screen until they are turned back on there."
        }
        return "Keeps the score on the Lock Screen and in the Dynamic Island while a match is on, so a phone in a pocket can be checked without opening the app. The phone updates it itself as the points arrive; nothing goes through a server."
    }

    private var hapticFooter: String {
        guard model.store.haptics.mode != .off else {
            return "Taps your wrist when a point goes on the board. The watch does the buzzing; the phone stays still."
        }
        return "\(model.store.haptics.mode.explanation) The watch does the buzzing; the phone stays still, and it feels every point while a workout is running."
    }
}
