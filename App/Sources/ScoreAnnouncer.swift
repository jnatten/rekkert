import AVFoundation
import Foundation
import Observation
import RekkertCore
import SwiftUI

/// Reads the score out after every point, the way an umpire would.
///
/// The setting is per device rather than synced, and only the phone has it: the phone is the
/// one propped at the side of the court, and a wrist six inches from your ear is not where
/// you want an umpire.
@MainActor
@Observable
final class ScoreAnnouncer {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { synthesiser.stopSpeaking(at: .immediate) }
        }
    }

    /// Nil is "whichever is best", not "the built-in one" — so downloading a better voice in
    /// Settings improves the app without anyone having to come back here and choose it.
    var voiceIdentifier: String? {
        didSet {
            guard voiceIdentifier != oldValue else { return }
            let defaults = UserDefaults.standard
            if let voiceIdentifier {
                defaults.set(voiceIdentifier, forKey: Self.voiceKey)
            } else {
                defaults.removeObject(forKey: Self.voiceKey)
            }
        }
    }

    var speed: Speed {
        didSet {
            guard speed != oldValue else { return }
            UserDefaults.standard.set(speed.rawValue, forKey: Self.speedKey)
        }
    }

    enum Speed: String, CaseIterable, Identifiable {
        case slow, normal, fast

        var id: Self { self }

        var title: String {
            switch self {
            case .slow: "Slow"
            case .normal: "Normal"
            case .fast: "Fast"
            }
        }

        /// Normal is AVFoundation's own default, so the setting only ever moves somebody off
        /// it deliberately.
        var rate: Float {
            switch self {
            case .slow: AVSpeechUtteranceDefaultSpeechRate - 0.05
            case .normal: AVSpeechUtteranceDefaultSpeechRate
            case .fast: AVSpeechUtteranceDefaultSpeechRate + 0.05
            }
        }
    }

    /// Every English voice installed, best first.
    private(set) var voices: [AVSpeechSynthesisVoice] = []

    private static let enabledKey = "announcesScore"
    private static let voiceKey = "announcerVoice"
    private static let speedKey = "announcerSpeed"
    private let synthesiser = AVSpeechSynthesizer()
    /// Kept per court, so a tournament's other courts moving in the background cannot be
    /// mistaken for this one changing.
    private var lastSeen: [Int: ScoreboardSnapshot] = [:]
    private var hasPreparedAudio = false

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        voiceIdentifier = defaults.string(forKey: Self.voiceKey)
        speed = defaults.string(forKey: Self.speedKey).flatMap(Speed.init(rawValue:)) ?? .normal
        refreshVoices()
    }

    /// `callingOut: false` takes note of where the score stands without saying anything —
    /// what a scoreboard appearing should do, so opening a match already in progress does
    /// not blurt it out.
    func observe(_ snapshot: ScoreboardSnapshot?, callingOut: Bool = true) {
        guard let snapshot else { return }
        let previous = lastSeen[snapshot.courtIndex]
        lastSeen[snapshot.courtIndex] = snapshot

        guard isEnabled, callingOut, let previous else { return }
        guard let call = ScoreCaller.call(from: previous, to: snapshot) else { return }
        speak(call)
    }

    func forget() {
        lastSeen.removeAll()
        synthesiser.stopSpeaking(at: .immediate)
    }

    // MARK: - Voices

    /// `speechVoices()` only ever returns voices that are actually downloaded, so the quality
    /// read off one here is quality you can hear. Everything preinstalled is `.default` —
    /// the compact, robotic one — which is why the good ones have to be looked for.
    func refreshVoices() {
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { Self.rank(of: $0) < Self.rank(of: $1) }
    }

    /// A stored identifier is a preference rather than a promise: the voice behind it can be
    /// deleted in Settings, and the umpire should carry on rather than fall silent.
    var currentVoice: AVSpeechSynthesisVoice? {
        if let voiceIdentifier, let chosen = voices.first(where: { $0.identifier == voiceIdentifier }) {
            return chosen
        }
        return voices.first ?? AVSpeechSynthesisVoice(language: "en-GB")
    }

    /// The name and how good it is, since the quality is the whole point of choosing.
    var currentVoiceName: String {
        guard let voice = currentVoice else { return "Default" }
        return "\(voice.name) (\(voice.quality.title))"
    }

    var hasVoiceWorthHaving: Bool {
        voices.contains { $0.quality != .default }
    }

    /// Chooses a voice and says something in it. A voice is not a thing you can pick off a
    /// list by reading it.
    func demonstrate(_ voice: AVSpeechSynthesisVoice) {
        voiceIdentifier = voice.identifier
        speak(ScoreCall(phrases: ["Thirty, fifteen", "Game, Blue"]))
    }

    /// Premium before enhanced before compact; then an English umpire before an American one.
    private static func rank(of voice: AVSpeechSynthesisVoice) -> (Int, Int, String) {
        let quality = switch voice.quality {
        case .premium: 0
        case .enhanced: 1
        default: 2
        }
        let locale = switch voice.language {
        case "en-GB": 0
        case "en-US": 1
        default: 2
        }
        return (quality, locale, voice.name)
    }

    // MARK: - Speaking

    private func speak(_ call: ScoreCall) {
        prepareAudio()
        // A flurry of taps should leave the latest score spoken, not a backlog of stale
        // ones queued behind it.
        if synthesiser.isSpeaking { synthesiser.stopSpeaking(at: .word) }

        let voice = currentVoice
        for (index, phrase) in call.phrases.enumerated() {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = voice
            utterance.rate = speed.rate
            // A pause to separate the call from the tally that follows it, which carries
            // further across a court than the full stop a single string would have given.
            if index < call.phrases.count - 1 { utterance.postUtteranceDelay = 0.25 }
            synthesiser.speak(utterance)
        }
    }

    /// Ducks whatever is playing rather than stopping it — there is usually music on a
    /// padel court.
    private func prepareAudio() {
        guard !hasPreparedAudio else { return }
        hasPreparedAudio = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
    }
}

extension AVSpeechSynthesisVoiceQuality {
    var title: String {
        switch self {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Compact"
        }
    }
}

extension View {
    /// Calls out what just happened whenever `snapshot` changes.
    func announcesScore(_ snapshot: ScoreboardSnapshot?) -> some View {
        modifier(ScoreAnnouncing(snapshot: snapshot))
    }
}

private struct ScoreAnnouncing: ViewModifier {
    @Environment(AppModel.self) private var model
    let snapshot: ScoreboardSnapshot?

    func body(content: Content) -> some View {
        content
            .onAppear { model.announcer.observe(snapshot, callingOut: false) }
            .onChange(of: snapshot) { _, new in
                model.announcer.observe(new)
            }
    }
}
