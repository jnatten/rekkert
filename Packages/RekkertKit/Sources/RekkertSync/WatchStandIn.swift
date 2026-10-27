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
        /// Asked the phone, and looking on the wrist alongside it: a phone in a bag may not see a
        /// host the wrist can (RC-6), and one after the other would take twice FR-008's 15 s.
        case both(since: ContinuousClock.Instant)
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
        /// A workout running, or Rekkert in front: otherwise the system does not let the radio
        /// keep a link of the wrist's own.
        var mayUseTheRadio = true
        /// The wrist's own search gave up, and said why.
        var ownFailure: SharingFailure?
    }

    enum Move: Equatable {
        case nothing
        case landed
        case refused(SharingFailure)
        case lookOnTheWrist
        case giveUp
        case standIn
        case standDown
        case phoneNeedsOpening
    }

    static func next(_ now: Circumstances, timing: Timing = Timing()) -> Move {
        if let join = now.join {
            if now.hasLanded { return .landed }
            switch join {
            case .askedPhone(let since):
                if now.phoneFailure == .rejected { return .refused(.rejected) }
                if now.phoneFailure != nil || !now.isPairReachable { return .lookOnTheWrist }
                return now.now - since >= timing.phoneWait ? .lookOnTheWrist : .nothing
            case .both(let since):
                if now.phoneFailure == .rejected { return .refused(.rejected) }
                guard let own = now.ownFailure else {
                    return now.now - since >= timing.ownWait ? .giveUp : .nothing
                }
                let phoneHasSpoken = now.phoneFailure != nil || !now.isPairReachable || now.now - since >= timing.phoneWait
                guard phoneHasSpoken else { return .nothing }
                // The host turning it away is the answer whoever heard it. Otherwise the phone's,
                // since it carries the match, unless it could not look.
                for case let failure? in [now.phoneFailure, own] where failure == .rejected || failure == .noRoom {
                    return .refused(failure)
                }
                if let phone = now.phoneFailure, phone != .unreachable, phone != .blocked { return .refused(phone) }
                return .refused(own)
            case .own(let since):
                // Said as soon as the search has an answer, and in its words (FR-008).
                if let failure = now.ownFailure { return .refused(failure) }
                return now.now - since >= timing.ownWait ? .giveUp : .nothing
            }
        }
        guard now.hasCode, now.isOnHostsMatch else { return .nothing }
        // Only on the phone's say-so: a phone that is merely back may be no nearer the host.
        if now.isPhoneThrough { return now.isStandingIn ? .standDown : .nothing }
        if now.isStandingIn { return .nothing }
        guard now.now - now.phoneLastThrough >= timing.grace else { return .nothing }
        if now.mayUseTheRadio { return .standIn }
        // A phone whose app is running is still trying; one that is not has to be opened.
        return now.isPairReachable ? .nothing : .phoneNeedsOpening
    }
}

/// The watch standing in for its phone on somebody else's match.
@MainActor
@Observable
public final class WatchStandIn {
    public private(set) var joining: SharingState = .off
    /// Once per code typed here, when the host's match is on the wrist — not on landing, since
    /// the phone can be through to a host with nothing on yet.
    @ObservationIgnored public var onJoined: ((UUID) -> Void)?
    @ObservationIgnored private var owesJoined = false

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

    /// Whether the wrist may hold a link of its own just now: a workout running, or the app in
    /// front. Set by the app.
    @ObservationIgnored public var mayUseTheRadio: @MainActor () -> Bool = { true }
    /// The phone's app is not running and the wrist cannot stand in for it, so the score here goes
    /// nowhere until somebody opens it.
    public private(set) var phoneNeedsOpening = false

    /// What the wrist says about somebody else's match it is on, the most pressing first.
    public enum Status: Sendable, Equatable {
        case phoneBluetoothOff
        case phoneBluetoothDenied
        case hostOutOfReach(since: Date)
        case phoneNeedsOpening
        case followingOnTheWatch
        case lookingForTheMatch
        case onTheHostsPhone
        case phoneOutOfReach
    }

    public var statuses: [Status] {
        guard store.state != nil, !store.canEndSession else { return [] }
        var statuses: [Status] = []
        let isOwnLinkUp = sharing.isSharing && sharing.reachablePeers > 0
        // Before the host's line: it is why the host is out of reach, and what to do about it.
        if store.isPairReachable, !isOwnLinkUp, let trouble = phoneStandby?.radioTrouble {
            statuses.append(trouble == .bluetoothDenied ? .phoneBluetoothDenied : .phoneBluetoothOff)
        }
        if let since = hostOutOfReachSince { statuses.append(.hostOutOfReach(since: since)) }
        if phoneNeedsOpening { statuses.append(.phoneNeedsOpening) }
        if isOwnLinkUp, !store.isPairReachable { statuses.append(.followingOnTheWatch) }
        if hostOutOfReachSince == nil {
            switch link {
            case .up: statuses.append(.onTheHostsPhone)
            case .reconnecting, .down: if !phoneNeedsOpening { statuses.append(.lookingForTheMatch) }
            }
        }
        if !store.isPairReachable, !isOwnLinkUp { statuses.append(.phoneOutOfReach) }
        return statuses
    }

    /// Who the host of the match the phone is on said they are, for the wrist to call it by.
    public var phonesHostName: String? { phoneStandby?.hostName }

    /// What the phone is sharing, as it last said: the code, its picture, and who is on (D-14).
    public private(set) var hosting: HostingStatus?

    /// Why a request to share or stop sharing did nothing (FR-020).
    public enum HostingTrouble: Sendable, Equatable {
        case cannotReachPhone
        case nothingToShare
    }

    public private(set) var hostingTrouble: HostingTrouble?
    @ObservationIgnored private var isAskingToHost = false

    /// The wrist's own search, given up, and why.
    private var ownFailure: SharingFailure? {
        if case .failed(let failure) = sharing.phase.asShared { failure } else { nil }
    }

    /// The phone does the sharing; the wrist only asks.
    public func startHosting() {
        hostingTrouble = nil
        isAskingToHost = true
        Task { [store] in
            guard await store.send(.startHosting) else {
                isAskingToHost = false
                hostingTrouble = .cannotReachPhone
                return
            }
        }
    }

    public func stopHosting() {
        hostingTrouble = nil
        Task { [store] in
            if !(await store.send(.stopHosting)) { hostingTrouble = .cannotReachPhone }
        }
    }

    private func heard(hosting status: HostingStatus) {
        if let held = hosting?.issuedAt, let issued = status.issuedAt, issued < held { return }
        var status = status
        // A status whose picture could not be drawn keeps the last one of the same code.
        if status.qr == nil, status.code == hosting?.code { status.qr = hosting?.qr }
        hosting = status
        guard isAskingToHost else { return }
        if status.isSharing {
            isAskingToHost = false
        } else if !status.canShare {
            isAskingToHost = false
            hostingTrouble = .nothingToShare
        }
    }

    /// The phone is on a shared match the wrist is not on (FR-016): whether one tap can fix it,
    /// and if not, why not.
    public enum PhonesMatch: Sendable, Equatable {
        case canFollow
        case phoneOutOfReach
        case phoneCannotReachHost
    }

    public var phonesMatchElsewhere: PhonesMatch? {
        guard let match = store.pairsSharedMatch, match != store.log.sessionID else { return nil }
        if !store.isPairReachable { return .phoneOutOfReach }
        if hasHeardStandby, phoneStandby?.isThrough != true { return .phoneCannotReachHost }
        return .canFollow
    }

    /// "Get on it": the phone's match, without typing its code.
    public func followThePhone() {
        Task { [store] in _ = await store.followThePhone() }
    }

    /// Whether the score on the wrist is the match's: a match of its own always is.
    public var isInReachOfTheMatch: Bool {
        let statuses = statuses
        return statuses.isEmpty || statuses.contains(.onTheHostsPhone)
    }

    /// Since when the host has been out of reach: by the wrist's own link while it stands in, and
    /// otherwise by what its phone last said.
    public var hostOutOfReachSince: Date? {
        if sharing.isSharing { return sharing.hostOutOfReachSince }
        return store.isPairReachable ? phoneStandby?.hostOutOfReachSince : nil
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
        owesJoined = true
        // A link held for the last match would stop the new code being dialled, and would go
        // on feeding the old match in over the one the phone is fetching.
        if sharing.isSharing { sharing.standDown() }
        sharing.keepOnStandby(code)

        guard store.isPairReachable else {
            lookOnTheWrist()
            return
        }
        if mayUseTheRadio() {
            pending = .both(since: .now)
            sharing.join(code)
        } else {
            pending = .askedPhone(since: .now)
        }
        Task {
            let landed = await store.send(.join(code))
            guard !landed, attempt == self.attempt, isAskingThePhone else { return }
            phoneFailure = .unreachable
            evaluate()
        }
    }

    private var isAskingThePhone: Bool {
        switch pending {
        case .askedPhone, .both: true
        case .own, nil: false
        }
    }

    /// Off the match whose code is kept, and on nobody else's: one tap puts the wrist back on
    /// (FR-024).
    public var canJoinAgain: Bool {
        sharing.keptGuestCode != nil && joining != .searching && (store.state == nil || store.canEndSession)
    }

    public func joinAgain() {
        guard let code = sharing.keptGuestCode else { return }
        join(code)
    }

    /// The phone is sharing this match, and joining another stops that for everyone on it
    /// (FR-021), so the wrist asks first.
    public var joiningStopsSharing: Bool { hosting?.isSharing == true }

    public func cancel() {
        attempt += 1
        switch pending {
        case .askedPhone: Task { [store] in await store.send(.cancel) }
        case .both:
            Task { [store] in await store.send(.cancel) }
            sharing.cancelJoining()
        case .own: sharing.cancelJoining()
        // Through to a host with nothing on yet: the phone is still waiting on it.
        case nil where joining == .joined && store.state == nil: Task { [store] in await store.send(.cancel) }
        case nil: break
        }
        pending = nil
        joining = .off
        owesJoined = false
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
            guard isAskingThePhone else { return }
            switch state {
            case .joined: phoneHasJoined = true
            case .failed(let failure): phoneFailure = failure
            // Off can be the phone putting its own sharing away on the way to looking.
            case .searching, .off: break
            }
        case .standby(let standby):
            phoneStandby = standby
            hasHeardStandby = true
            if let standby { sharing.keep(fromThePhone: standby) }
            // The phone going quiet about a code the wrist is using is usually the wrist
            // having told it to stop.
            if pending == nil, let standby {
                sharing.keepOnStandby(standby.code)
            } else if pending == nil, !sharing.isSharing {
                sharing.keepOnStandby(nil)
            }
        case .hostingStatus(let status):
            heard(hosting: status)
        case .join, .cancel, .startHosting, .stopHosting, .followPhone:
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
        case .askedPhone, .both: phoneHasJoined || isPhoneThrough || isHandedTheHostsMatch
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
            isStandingIn: sharing.isSharing,
            mayUseTheRadio: mayUseTheRadio(),
            ownFailure: ownFailure
        ), timing: timing)
        phoneNeedsOpening = move == .phoneNeedsOpening

        switch move {
        case .nothing, .phoneNeedsOpening:
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
            owesJoined = false
        case .lookOnTheWrist:
            Task { [store] in await store.send(.cancel) }
            lookOnTheWrist()
        case .giveUp:
            if case .both = pending { Task { [store] in await store.send(.cancel) } }
            sharing.cancelJoining()
            pending = nil
            joining = .failed(.notFound)
            owesJoined = false
        case .standIn:
            store.recorder?.note(.standIn, on: .pair, in: store.log.sessionID)
            sharing.standIn()
        case .standDown:
            store.recorder?.note(.standDown, on: .pair, in: store.log.sessionID)
            sharing.standDown()
            store.followPairedDevice()
        }

        store.standsInForThePair = sharing.isSharing

        if owesJoined, joining == .joined, isHandedTheHostsMatch {
            owesJoined = false
            onJoined?(store.log.sessionID)
        }
    }

    private func lookOnTheWrist() {
        pending = .own(since: .now)
        guard let code = sharing.standbyCode, !sharing.isSharing else { return }
        sharing.join(code)
    }
}
