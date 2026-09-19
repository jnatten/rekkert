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
        }
        .navigationTitle("Settings")
    }
}
