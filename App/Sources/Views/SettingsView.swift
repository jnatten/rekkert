import RekkertCore
import SwiftUI

/// What is not about any one match: how the full-screen board is drawn, and whether the
/// score is read out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var announcer = model.announcer
        @Bindable var fullscreen = model.fullscreen
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

    private var hapticFooter: String {
        guard model.store.haptics.mode != .off else {
            return "Taps your wrist when a point goes on the board. The watch does the buzzing; the phone stays still."
        }
        return "\(model.store.haptics.mode.explanation) The watch does the buzzing; the phone stays still, and it feels every point while a workout is running."
    }
}
