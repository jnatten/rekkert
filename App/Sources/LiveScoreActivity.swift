import ActivityKit
import Foundation
import Observation
import RekkertCore
import RekkertSync

/// The score on the Lock Screen and in the Dynamic Island while a session is live. Updated
/// from here as the store changes, which the phone is awake for whenever a point arrives —
/// over Bluetooth from the court or from its own watch — so nothing is ever pushed.
@MainActor
@Observable
final class LiveScoreActivity {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            reconcile()
        }
    }

    /// iOS's own switch for the app, which overrules this one.
    private(set) var isAllowed = ActivityAuthorizationInfo().areActivitiesEnabled

    private struct Situation: Sendable {
        var sessionID: UUID
        var state: SessionState?
        var lastResult: SessionState?
        var display: DisplayPreferences
    }

    @ObservationIgnored private var latest: Situation?
    /// By id rather than the activity itself, which is not `Sendable`: each call to it is
    /// made off the main actor, from an instance looked up there.
    @ObservationIgnored private var activity: (id: String, sessionID: UUID)?
    @ObservationIgnored private var sent: LiveScore?
    @ObservationIgnored private var hasAdopted = false
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var following: Task<Void, Never>?

    private static let enabledKey = "liveActivity"
    private static let resultLingers: TimeInterval = 15 * 60

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func follow(_ store: MatchStore) {
        guard following == nil else { return }
        let changes = Observations { @MainActor in
            Situation(
                sessionID: store.log.sessionID,
                state: store.state,
                lastResult: store.lastResult,
                display: store.display
            )
        }
        following = Task { [weak self] in
            for await situation in changes {
                guard let self else { return }
                latest = situation
                enqueue(situation)
            }
        }
    }

    /// For a session that turned up while the phone was in a bag: an activity can only be
    /// started from the front, so this is where it gets its first chance.
    func reconcile() {
        isAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        if let latest { enqueue(latest) }
    }

    /// One at a time, so an update cannot overtake the one before it or two requests race
    /// each other into two activities.
    private func enqueue(_ situation: Situation) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            await self?.apply(situation)
        }
    }

    private func apply(_ situation: Situation) async {
        if !hasAdopted {
            hasAdopted = true
            await adoptSurvivors(of: situation)
        }

        guard let state = situation.state, isEnabled, isAllowed else {
            await end(with: situation)
            return
        }
        let score = LiveScore.make(from: state, display: situation.display)

        if let activity, activity.sessionID == situation.sessionID {
            guard score != sent else { return }
            sent = score
            await Self.update(activity.id, to: score)
            return
        }
        if let stale = activity {
            await Self.end(stale.id, with: nil, dismissal: .immediate)
        }
        let started = try? Activity.request(
            attributes: ScoreActivityAttributes(sessionID: situation.sessionID),
            content: ActivityContent(state: score, staleDate: nil),
            pushType: nil
        )
        activity = started.map { ($0.id, situation.sessionID) }
        sent = started == nil ? nil : score
    }

    /// A finished match stays up long enough to be read in the car park; one that was
    /// thrown away, or a switch turned off, goes at once.
    private func end(with situation: Situation) async {
        guard let activity else { return }
        self.activity = nil
        sent = nil
        if situation.state == nil, isEnabled, let result = situation.lastResult {
            await Self.end(
                activity.id,
                with: LiveScore.final(from: result, display: situation.display),
                dismissal: .after(Date().addingTimeInterval(Self.resultLingers))
            )
        } else {
            await Self.end(activity.id, with: nil, dismissal: .immediate)
        }
    }

    /// Activities outlive the process. The one for the session still on the phone is picked
    /// back up rather than doubled; anything else still live belongs to nothing now.
    private func adoptSurvivors(of situation: Situation) async {
        let live = Activity<ScoreActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map { (id: $0.id, sessionID: $0.attributes.sessionID) }
        for survivor in live {
            if activity == nil, situation.state != nil, survivor.sessionID == situation.sessionID {
                activity = survivor
            } else {
                await Self.end(survivor.id, with: nil, dismissal: .immediate)
            }
        }
    }

    private nonisolated static func find(_ id: String) -> Activity<ScoreActivityAttributes>? {
        Activity<ScoreActivityAttributes>.activities.first { $0.id == id }
    }

    private nonisolated static func update(_ id: String, to score: LiveScore) async {
        await find(id)?.update(ActivityContent(state: score, staleDate: nil))
    }

    private nonisolated static func end(_ id: String, with score: LiveScore?, dismissal: ActivityUIDismissalPolicy) async {
        await find(id)?.end(score.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: dismissal)
    }
}
