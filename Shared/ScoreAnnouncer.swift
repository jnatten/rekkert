import AVFoundation
import Foundation
import Observation
import RekkertCore
import SwiftUI

/// Reads the score out after every point, the way an umpire would.
///
/// The setting is per device rather than synced: the phone propped at the side of the court
/// and the watch on your wrist should not both be talking, and whichever one you can hear is
/// the one to ask.
@MainActor
@Observable
final class ScoreAnnouncer {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            if !isEnabled { synthesiser.stopSpeaking(at: .immediate) }
        }
    }

    private static let defaultsKey = "announcesScore"
    private let synthesiser = AVSpeechSynthesizer()
    /// Kept per court, so a tournament's other courts moving in the background cannot be
    /// mistaken for this one changing.
    private var lastSeen: [Int: ScoreboardSnapshot] = [:]
    private var hasPreparedAudio = false

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
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
        speak(call.spoken)
    }

    func forget() {
        lastSeen.removeAll()
        synthesiser.stopSpeaking(at: .immediate)
    }

    private func speak(_ line: String) {
        prepareAudio()
        // A flurry of taps should leave the latest score spoken, not a backlog of stale
        // ones queued behind it.
        if synthesiser.isSpeaking { synthesiser.stopSpeaking(at: .word) }

        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = Self.voice
        synthesiser.speak(utterance)
    }

    /// The scoring vocabulary is English whatever the device's language is set to, and a
    /// Norwegian voice reading "forty" makes a poor umpire.
    private static let voice = AVSpeechSynthesisVoice(language: "en-GB")
        ?? AVSpeechSynthesisVoice(language: "en-US")

    /// Ducks whatever is playing rather than stopping it — there is usually music on a
    /// padel court.
    private func prepareAudio() {
        guard !hasPreparedAudio else { return }
        hasPreparedAudio = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        #if os(watchOS)
        session.activate(options: []) { _, _ in }
        #else
        try? session.setActive(true)
        #endif
    }
}

extension View {
    /// Calls out what just happened whenever `snapshot` changes. `isActive` is for the
    /// watch's court pages, which all stay alive behind whichever one is on screen.
    func announcesScore(_ snapshot: ScoreboardSnapshot?, isActive: Bool = true) -> some View {
        modifier(ScoreAnnouncing(snapshot: snapshot, isActive: isActive))
    }
}

private struct ScoreAnnouncing: ViewModifier {
    @Environment(AppModel.self) private var model
    let snapshot: ScoreboardSnapshot?
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { model.announcer.observe(snapshot, callingOut: false) }
            .onChange(of: snapshot) { _, new in
                model.announcer.observe(new, callingOut: isActive)
            }
    }
}
