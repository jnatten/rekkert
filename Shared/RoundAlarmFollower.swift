import Foundation
import Observation
import RekkertCore
import RekkertSync
import UserNotifications
#if os(watchOS)
import WatchKit
#endif

/// Says so when a timed ladder round runs out: a buzz on the wrist and the announcer on the
/// phone while the app is open, and a notification for a phone in a pocket or a lowered wrist.
@MainActor
@Observable
final class RoundAlarmFollower {
    private(set) var timeIsUp = false
    @ObservationIgnored var onRing: (() -> Void)?
    @ObservationIgnored private var alarm = RoundAlarm()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var following: Task<Void, Never>?
    @ObservationIgnored private var notified: RoundAlarm.Bell?
    @ObservationIgnored private var asking: Task<Bool, Never>?

    private struct Situation: Sendable {
        var session: UUID
        var state: SessionState?
    }

    func follow(_ store: MatchStore) {
        guard following == nil else { return }
        let changes = Observations { @MainActor in
            Situation(session: store.log.sessionID, state: store.state)
        }
        following = Task { [weak self] in
            for await situation in changes {
                self?.heard(situation.state, session: situation.session)
            }
        }
    }

    private func heard(_ state: SessionState?, session: UUID) {
        alarm.heard(state, session: session, at: .now)
        refresh()
        notify(alarm.armed)
    }

    private func refresh() {
        timeIsUp = alarm.armed.map { Date() >= $0.endsAt } ?? false
        timer?.cancel()
        guard let deadline = alarm.armed?.endsAt, deadline > .now || alarm.nextDeadline != nil else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    private func tick() {
        if alarm.tick(at: .now) { ring() }
        refresh()
    }

    private func ring() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            WKInterfaceDevice.current().play(.notification)
        }
        #endif
        onRing?()
    }

    /// One request per round, so a snooze replaces it and a pause or the whistle takes it
    /// away. The phone and the watch name it alike, so a wrist that gets both shows one.
    private func notify(_ bell: RoundAlarm.Bell?) {
        guard bell != notified else { return }
        if let notified {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier(notified)])
        }
        notified = bell
        guard let bell, bell.endsAt > .now else { return }
        Task {
            // Added before the first answer it would be turned away, and by the time there is
            // one the round may have been snoozed or paused: only the bell still standing goes.
            guard await mayNotify(), notified == bell, bell.endsAt > .now else { return }
            try? await UNUserNotificationCenter.current().add(Self.request(for: bell))
        }
    }

    /// Asked the first time a device sees a timed round. Shared while the question is up, so
    /// a snooze before the answer waits on the same one.
    private func mayNotify() async -> Bool {
        let question = asking ?? Task { await Self.askToNotify() }
        asking = question
        let answer = await question.value
        asking = nil
        return answer
    }

    /// Also how joining asks, so the question is put once whichever comes first.
    nonisolated static func askToNotify() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            guard !isDemo else { return false }
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    nonisolated private static func request(for bell: RoundAlarm.Bell) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Time"
        content.body = "Round \(bell.round + 1) is up. Finish the point, then end the round."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, bell.endsAt.timeIntervalSinceNow), repeats: false)
        return UNNotificationRequest(identifier: identifier(bell), content: content, trigger: trigger)
    }

    /// A demo is screenshotted, and a permission prompt over it is nothing simctl can tap away.
    nonisolated private static var isDemo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-rekkert-demo")
        #else
        false
        #endif
    }

    nonisolated private static func identifier(_ bell: RoundAlarm.Bell) -> String {
        "round-\(bell.session.uuidString)-\(bell.round)"
    }
}
