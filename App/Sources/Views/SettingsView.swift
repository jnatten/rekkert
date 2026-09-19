import SwiftUI

/// What is not about any one match: whether the score is read out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var announcer = model.announcer
        List {
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
