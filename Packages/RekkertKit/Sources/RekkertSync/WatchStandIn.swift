import Foundation
import Observation
import RekkertCore

/// The phone does the joining whenever it can; the watch dials the host itself only while its
/// phone cannot, and lets go again once the phone is through.
nonisolated enum StandInPolicy {
    struct Timing: Sendable {
        /// Past the local network's own search timeout — and a phone suspended mid-search never
        /// reports at all.
        var phoneWait: Duration = .seconds(12)
        var ownWait: Duration = .seconds(20)
        var grace: Duration = .seconds(15)
    }

    enum Join: Equatable {
        case askedPhone(since: ContinuousClock.Instant)
        case own(since: ContinuousClock.Instant)
    }

    struct Circumstances: Equatable {
        var now: ContinuousClock.Instant
        var join: Join?
        var hasLanded = false
        var phoneFailure: SharingFailure?
        var isPairReachable = true
        var isPhoneThrough = false
        var phoneLastThrough: ContinuousClock.Instant
        var hasCode = false
        var isOnHostsMatch = false
        var isStandingIn = false
    }

    enum Move: Equatable {
        case nothing
        case landed
        case refused(SharingFailure)
        case lookOnTheWrist
        case giveUp
        case standIn
        case standDown
    }

    static func next(_ now: Circumstances, timing: Timing = Timing()) -> Move {
        if let join = now.join {
            if now.hasLanded { return .landed }
            switch join {
            case .askedPhone(let since):
                if now.phoneFailure == .rejected { return .refused(.rejected) }
                if now.phoneFailure != nil || !now.isPairReachable { return .lookOnTheWrist }
                return now.now - since >= timing.phoneWait ? .lookOnTheWrist : .nothing
            case .own(let since):
                return now.now - since >= timing.ownWait ? .giveUp : .nothing
            }
        }
        guard now.hasCode, now.isOnHostsMatch else { return .nothing }
        // Only on the phone's say-so: a phone that is merely back may be no nearer the host.
        if now.isPhoneThrough { return now.isStandingIn ? .standDown : .nothing }
        if now.isStandingIn { return .nothing }
        return now.now - now.phoneLastThrough >= timing.grace ? .standIn : .nothing
    }
}

/// The watch standing in for its phone on somebody else's match.
@MainActor
@Observable
public final class WatchStandIn {
    public private(set) var joining: SharingState = .off

    @ObservationIgnored private let store: MatchStore
    @ObservationIgnored private let sharing: SharedSession
    @ObservationIgnored private let timing: StandInPolicy.Timing
    @ObservationIgnored private let tick: Duration
    @ObservationIgnored private var pending: StandInPolicy.Join?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var phoneFailure: SharingFailure?
    @ObservationIgnored private var phoneHasJoined = false
    /// What was on the wrist when the code was typed, so the host's match arriving is told apart
    /// from the one already there.
    @ObservationIgnored private var sessionAtJoin: UUID?
    private var phoneStandby: SharingStandby?
    /// An older phone never says, and is trusted to be carrying the match as it always was.
    private var hasHeardStandby = false
    @ObservationIgnored private var phoneLastThrough = ContinuousClock.now

    /// Whether the score on the wrist is still reaching the host, for a match somebody else is
    /// hosting. `down` is a watch with no way back: no phone, and no code to dial with.
    public enum Link: Sendable, Equatable {
        case up, reconnecting, down
    }

    public var link: Link {
        guard store.state != nil, !store.canEndSession else { return .up }
        let isOwnLinkUp = sharing.isSharing && sharing.reachablePeers > 0
        let isPhoneCarrying = store.isPairReachable && (!hasHeardStandby || phoneStandby?.isThrough == true)
        if isOwnLinkUp || isPhoneCarrying { return .up }
        return sharing.isSharing || sharing.standbyCode != nil || store.isPairReachable ? .reconnecting : .down
    }

    public convenience init(store: MatchStore, sharing: SharedSession) {
        self.init(store: store, sharing: sharing, timing: StandInPolicy.Timing(), tick: .seconds(2))
    }

    init(store: MatchStore, sharing: SharedSession, timing: StandInPolicy.Timing, tick: Duration) {
        self.store = store
        self.sharing = sharing
        self.timing = timing
        self.tick = tick
        // No link of the wrist's own survives a relaunch, and a role kept from one is what left a
        // watch refusing its own phone's match.
        store.followPairedDevice()
    }

    public func join(_ code: SessionCode) {
        attempt += 1
        let attempt = attempt
        joining = .searching
        phoneFailure = nil
        phoneHasJoined = false
        phoneStandby = nil
        sessionAtJoin = store.log.sessionID
        // A link held for the last match would stop the new code being dialled, and would go
        // on feeding the old match in over the one the phone is fetching.
        if sharing.isSharing { sharing.standDown() }
        sharing.keepOnStandby(code)

        guard store.isPairReachable else {
            lookOnTheWrist()
            return
        }
        pending = .askedPhone(since: .now)
        Task {
            let landed = await store.send(.join(code))
            guard !landed, attempt == self.attempt, case .askedPhone = pending else { return }
            phoneFailure = .unreachable
            evaluate()
        }
    }

    public func cancel() {
        attempt += 1
        switch pending {
        case .askedPhone: Task { [store] in await store.send(.cancel) }
        case .own: sharing.cancelJoining()
        // Through to a host with nothing on yet: the phone is still waiting on it.
        case nil where joining == .joined && store.state == nil: Task { [store] in await store.send(.cancel) }
        case nil: break
        }
        pending = nil
        joining = .off
    }

    /// The join screen went away. A join that has landed is left alone, whatever the phone has
    /// got round to saying about it: the screen goes the moment a match arrives, and calling the
    /// search off then would cut the phone's link to the host it has just reached.
    public func joinScreenClosed() {
        evaluate()
        guard case .searching = joining else { return }
        cancel()
    }

    public func heard(_ signal: SharingSignal) {
        switch signal {
        case .state(let state):
            guard case .askedPhone = pending else { return }
            switch state {
            case .joined: phoneHasJoined = true
            case .failed(let failure): phoneFailure = failure
            // Off can be the phone putting its own sharing away on the way to looking.
            case .searching, .off: break
            }
        case .standby(let standby):
            phoneStandby = standby
            hasHeardStandby = true
            // The phone going quiet about a code the wrist is using is usually the wrist
            // having told it to stop.
            if pending == nil, let standby {
                sharing.keepOnStandby(standby.code)
            } else if pending == nil, !sharing.isSharing {
                sharing.keepOnStandby(nil)
            }
        case .join, .cancel:
            break
        }
        evaluate()
    }

    public func run() async {
        while !Task.isCancelled {
            evaluate()
            try? await Task.sleep(for: tick)
        }
    }

    func evaluate() {
        let now = ContinuousClock.now
        let isPairReachable = store.isPairReachable
        // Said before it went. It says it again on the way back.
        if !isPairReachable, phoneStandby?.isThrough == true { phoneStandby?.isThrough = false }
        let isPhoneThrough = isPairReachable && phoneStandby?.isThrough == true
            && phoneStandby?.code == sharing.standbyCode
        if isPhoneThrough { phoneLastThrough = now }

        let isHandedTheHostsMatch = store.state != nil && !store.canEndSession && store.log.sessionID != sessionAtJoin
        let hasLanded = switch pending {
        case .askedPhone: phoneHasJoined || isPhoneThrough || isHandedTheHostsMatch
        case .own: !store.isJoining && store.state != nil
        case nil: false
        }
        let move = StandInPolicy.next(StandInPolicy.Circumstances(
            now: now,
            join: pending,
            hasLanded: hasLanded,
            phoneFailure: phoneFailure,
            isPairReachable: isPairReachable,
            isPhoneThrough: isPhoneThrough,
            phoneLastThrough: phoneLastThrough,
            hasCode: sharing.standbyCode != nil,
            isOnHostsMatch: store.state != nil && !store.canEndSession,
            isStandingIn: sharing.isSharing
        ), timing: timing)

        switch move {
        case .nothing:
            break
        case .landed:
            pending = nil
            joining = .joined
            phoneLastThrough = now
        case .refused(let failure):
            Task { [store] in await store.send(.cancel) }
            sharing.cancelJoining()
            pending = nil
            joining = .failed(failure)
        case .lookOnTheWrist:
            Task { [store] in await store.send(.cancel) }
            lookOnTheWrist()
        case .giveUp:
            sharing.cancelJoining()
            pending = nil
            joining = .failed(.notFound)
        case .standIn:
            sharing.standIn()
        case .standDown:
            sharing.standDown()
            store.followPairedDevice()
        }
    }

    private func lookOnTheWrist() {
        pending = .own(since: .now)
        guard let code = sharing.standbyCode, !sharing.isSharing else { return }
        sharing.join(code)
    }
}
