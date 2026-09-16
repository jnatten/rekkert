import AVFoundation
import SwiftUI

/// Which voice the umpire has. Tapping one chooses it and says something in it at once,
/// because the only way to judge a voice is to hear it.
struct VoicePickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(groups, id: \.quality) { group in
                Section(group.quality.title) {
                    ForEach(group.voices, id: \.identifier) { voice in
                        Button { model.announcer.demonstrate(voice) } label: {
                            row(voice)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !model.announcer.hasVoiceWorthHaving {
                Section {
                } footer: {
                    Text("""
                        These are the compact voices built into iOS, and they are the reason \
                        the umpire sounds like a machine. For one that sounds like a person, \
                        go to Settings › Accessibility › Spoken Content › Voices › English, \
                        download an Enhanced or Premium voice, and come back here.
                        """)
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ voice: AVSpeechSynthesisVoice) -> some View {
        LabeledContent {
            if voice.identifier == model.announcer.currentVoice?.identifier {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        } label: {
            Text(voice.name)
            Text(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)
        }
        .contentShape(.rect)
    }

    /// Already sorted best first by the announcer, so grouping only has to keep that order.
    private var groups: [(quality: AVSpeechSynthesisVoiceQuality, voices: [AVSpeechSynthesisVoice])] {
        var groups: [(AVSpeechSynthesisVoiceQuality, [AVSpeechSynthesisVoice])] = []
        for voice in model.announcer.voices {
            if groups.last?.0 == voice.quality {
                groups[groups.count - 1].1.append(voice)
            } else {
                groups.append((voice.quality, [voice]))
            }
        }
        return groups
    }
}
