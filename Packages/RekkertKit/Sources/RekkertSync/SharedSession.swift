import Foundation
import Observation
import RekkertCore

/// Hosting and joining, as the screens see it.
///
/// Holds the one piece of state the match itself must never carry: the code. It is not in the
/// log, which travels to every peer and into History. It is kept only by `keeper`, on this
/// device, for at most twelve hours, so a host whose app was ended shares again on the same one
/// and a guest gets back on without it typed.
@MainActor
@Observable
public final class SharedSession {
    public enum Phase: Sendable, Equatable {
        case off
        /// Advertising, with the code to read out.
        case hosting(SessionCode)
        case searching
        case joined
        case failed(LocalNetworkTransport.Failure)
    }

    public private(set) var phase: Phase = .off {
        didSet {
            guard phase != oldValue else { return }
            publish?(phase.asShared)
            reportStandby()
            reportHostingStatus()
        }
    }

    /// Told to this device's own watch, when there is one waiting to hear how the code it
    /// handed over is getting on. Set from `AppModel`; nil on the watch, which has nobody to
    /// report its own join to.
    ///
    /// Hung on `phase` rather than on the transport's status, because half the transitions a
    /// watch cares about never go through it — `join`, `stop`, `cancelJoining` and
    /// `dismissFailure` all set the phase themselves.
    @ObservationIgnored public var publish: ((SharingState) -> Void)?
    @ObservationIgnored public var onStandby: ((SharingStandby?) -> Void)?
    /// A join got through, once per code dialled.
    @ObservationIgnored public var onJoined: (() -> Void)?
    /// What the host's watch shows, each time it changes (D-14). `isNews` when sharing started,
    /// stopped or changed code: worth queuing for a watch whose app is not running, and worth a
    /// fresh picture of the code.
    @ObservationIgnored public var onHostingStatus: ((_ status: HostingStatus, _ isNews: Bool) -> Void)?
    @ObservationIgnored private var reportedHosting: HostingStatus?
    @ObservationIgnored private var reportedStandby: SharingStandby?
    @ObservationIgnored private var hasReportedStandby = false
    public private(set) var standbyCode: SessionCode?
    /// How many other phones are on the match right now.
    public private(set) var peers = 0
    /// Set when a match this device had joined has been out of reach long enough that it is
    /// worth saying so. The scoreboard goes on showing the copy it holds, which is the point
    /// — but a score that has quietly stopped being true is worse than an honest notice.
    public private(set) var hasLostTheMatch = false
    /// Since when nothing has reached the host, once that has gone on for `hostGrace`. From then
    /// on the score here is this device's own, and the screens say so rather than pass it off as
    /// the match's.
    public private(set) var hostOutOfReachSince: Date? {
        didSet { if hostOutOfReachSince != oldValue { reportStandby() } }
    }
    /// The host stopped sharing and said so: the copy here went to History, and that is worth
    /// saying once.
    public private(set) var hostStoppedSharing = false

    /// Short of FR-026's fifteen seconds by the time a link can take to be found down.
    private static let hostGrace: Duration = .seconds(10)
    private var hostLostAt: Date?
    private var watchingTheHost: Task<Void, Never>?
    private var watchingTheRadio: Task<Void, Never>?
    private var hasRecordedJoin = false

    /// What `keeper` holds, read once and kept up as it changes.
    private var kept: KeptCode?

    /// A code this phone shared and still keeps while it is not sharing: everybody at the court
    /// already has it, so it is the one to offer again.
    public var keptHostCode: SessionCode? {
        guard hosted == nil, wanted == nil, let kept, kept.role == .host, kept.current(now: now()) != nil else { return nil }
        return kept.code
    }

    private var recorder: (any LinkRecording)? { store.recorder }
    private var hostLink: LinkRecordEntry.Link { store.hostDevice.map { .host($0) } ?? .radio }

    private let store: MatchStore
    private let link: LocalNetworkTransport
    /// The link that survives the screen going off. It has no status of its own worth showing —
    /// there is no browsing or advertising to report on, only whether anybody is there — so it
    /// contributes reachability and nothing else.
    private let bluetooth: (any SharedLink)?
    private var watching: Task<Void, Never>?
    private var watchingBluetooth: Task<Void, Never>?
    /// How many phones are on the match over Bluetooth. Kept apart from `peers` because the
    /// same phone is usually on both links and neither transport can tell that it is: a hello
    /// names its sender for the pair's sake, but the links count connections, not devices.
    /// Folding them with `max` undercounts a room where somebody is on one link only,
    /// which is better than telling four people there are eight of them.
    private var bluetoothPeers = 0
    /// Kept so sharing can be stood back up after the app has been put down. What outlives the
    /// app is in `keeper`.
    private var hosted: (code: SessionCode, share: UUID)?
    private var wanted: SessionCode?
    private let keeper: (any CodeKeeping)?
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    /// How long a join typed in has to find its match before it says why it could not.
    private let searchLimit: Duration
    private var searchDeadline: Task<Void, Never>?
    /// Whether this device has ever actually been on the match it is looking for. A search
    /// that follows a typed code may give up and say so; one that follows a link going away
    /// may not — there is a score on the screen, and it came from somewhere.
    private var hasJoinedBefore = false
    private var noticing: Task<Void, Never>?
    /// Long enough to ride out a phone glanced at or a moment of bad Wi-Fi, short enough that
    /// somebody looking at a stale score finds out before the game moves on.
    ///
    /// Twenty seconds rather than eight: the keepalive takes up to eight to call a peer dead
    /// and the redial runs every couple of seconds after that, so a shorter grace fired on
    /// drops that were already healing. The badge carries the short-term truth now, which is
    /// what lets this be reserved for a real absence.
    private let graceBeforeNotice: Duration
    /// How long the radio is still given once the network has found nothing: a host whose screen
    /// is off can only be reached over Bluetooth, and finding it there takes its own time.
    private let radioGrace: Duration
    private var waitingForTheRadio: Task<Void, Never>?

    public init(
        store: MatchStore,
        link: LocalNetworkTransport,
        bluetooth: (any SharedLink)? = nil,
        graceBeforeNotice: Duration = .seconds(20),
        radioGrace: Duration = .seconds(10),
        keeper: (any CodeKeeping)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        searchLimit: Duration = .seconds(14),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.link = link
        self.bluetooth = bluetooth
        self.graceBeforeNotice = graceBeforeNotice
        self.radioGrace = radioGrace
        self.keeper = keeper
        self.now = now
        self.searchLimit = searchLimit
        self.sleep = sleep
        kept = keeper?.read(now: now())
        watching = Task { [weak self] in
            for await status in link.status { self?.apply(status) }
        }
        // The watch stepped off and the store went with it. The link to the host is still up,
        // and left standing it would hand the match straight back on the next snapshot.
        //
        // Let go of there and then, not on a later turn: starting a match of your own steps off
        // on the way in, and the first snapshot of it goes out before a later turn comes round —
        // to a host with nothing on, which takes it up as its own.
        store.onLeft = { [weak self] in self?.letGo() }
        store.onRefused = { [weak self] _ in self?.turnedAway() }
        store.onStoppedByHost = { [weak self] in self?.stoppedByHost() }
        store.onParticipantsChanged = { [weak self] in self?.reportHostingStatus() }
        if let bluetooth {
            let availability = bluetooth.availabilityChanges
            watchingTheRadio = Task { [weak self] in
                for await change in availability {
                    switch change {
                    case .on: self?.recorder?.note(.radioOn)
                    case .off: self?.recorder?.note(.radioOff)
                    case .denied: self?.recorder?.note(.permissionDenied)
                    case .unknown: break
                    }
                }
            }
            let changes = bluetooth.reachability
            watchingBluetooth = Task { [weak self] in
                for await _ in changes {
                    guard let self else { return }
                    self.bluetoothPeers = bluetooth.reachableCount
                    if self.bluetoothPeers > 0 { self.noteProven() }
                    self.reportStandby()
                    if self.bluetoothPeers > 0, self.waitingForTheRadio != nil, let wanted = self.wanted {
                        self.keepLooking(for: wanted)
                    }
                    // The network may have been gone a while with the radio carrying the
                    // match. When the radio goes too, that is the moment it is lost.
                    if self.bluetoothPeers == 0, case .searching = self.phase, self.hasJoinedBefore {
                        self.beginNoticingTheLoss()
                    }
                    self.checkTheHost()
                }
            }
        }
    }

    public var isSharing: Bool {
        if case .off = phase { return false }
        if case .failed = phase { return false }
        return true
    }

    /// Looking for a match this device was already on, as against one it has never found. The
    /// score on screen is the last that got through, and saying so is better than a badge that
    /// reads as "nobody has joined yet".
    public var isReconnecting: Bool {
        guard case .searching = phase else { return false }
        // Still carried, just not over the network. Saying "reconnecting" here would be a
        // worry about nothing while the score is going through perfectly well.
        guard bluetoothPeers == 0 else { return false }
        return hasJoinedBefore
    }

    /// How many phones are on this match, over whichever link reaches them.
    public var reachablePeers: Int { max(peers, bluetoothPeers) }

    /// The code being read out, if this device is the one reading it.
    public var code: SessionCode? {
        guard case .hosting(let code) = phase else { return nil }
        return code
    }

    /// Opens the match to the other phones at the court.
    ///
    /// The share id is minted here rather than taken from the session, so finishing one match
    /// and starting another keeps the same code — nobody has to be told a new one halfway
    /// through an evening.
    public func host(code requested: SessionCode? = nil) {
        guard store.state != nil else { return }
        // A search still running underneath — the join sheet swiped away mid-look — would
        // conclude on the first guest to say hello and make this phone a guest on its own
        // match.
        if wanted != nil { cancelJoining() }
        hostStoppedSharing = false
        store.startSharing()
        // Still sharing underneath, on a code everybody at the court already has: put back what
        // went rather than starting over on a new one.
        if let hosted, requested == nil || requested == hosted.code {
            link.resumeHosting(code: hosted.code, share: hosted.share)
            bluetooth?.resumeHosting(code: hosted.code, share: hosted.share)
            phase = .hosting(hosted.code)
            return
        }
        let code = requested ?? .random()
        let share = UUID()
        hosted = (code, share)
        link.startHosting(code: code, share: share)
        bluetooth?.startHosting(code: code, share: share)
        phase = .hosting(code)
        remember(.hosted(KeptCode(code: code, share: share, role: .host, startedAt: now())))
        recorder?.note(.sharingStarted, in: store.log.sessionID)
    }

    /// Puts back what this device was doing when its app was ended: hosting on the code it kept,
    /// or looking for the match it was a guest on. A guest that had left keeps its code for
    /// joining again, and is not put back on.
    public func restore() {
        guard case .off = phase, hosted == nil, wanted == nil, let kept = keeper?.read(now: now()) else { return }
        recorder?.note(.appHadBeenEnded)
        switch kept.role {
        case .host where store.role == .host:
            let share = kept.share ?? UUID()
            store.startSharing()
            hosted = (kept.code, share)
            link.startHosting(code: kept.code, share: share)
            bluetooth?.startHosting(code: kept.code, share: share)
            phase = .hosting(kept.code)
            recorder?.note(.sharingRestored, in: store.log.sessionID)
        case .guest where store.role == .guest:
            dial(kept.code)
            hasJoinedBefore = true
        default:
            break
        }
    }

    /// A join that got through, on whichever link: the code is worth keeping from here.
    private func noteProven() {
        guard let wanted, hosted == nil, store.role != .host else { return }
        if !hasRecordedJoin {
            hasRecordedJoin = true
            recorder?.note(.joined, on: hostLink, in: store.log.sessionID)
            onJoined?()
        }
        let kept = keeper?.read(now: now())
        guard kept?.code != wanted || kept?.role != .guest else { return }
        remember(.proven(KeptCode(code: wanted, share: nil, role: .guest, startedAt: now())))
    }

    private func remember(_ moment: KeptCode.Moment) {
        guard let keeper else { return }
        let current = keeper.read(now: now())
        let next = KeptCode.after(moment, kept: current)
        guard next != current else { return }
        if let next { keeper.keep(next) } else { keeper.forget() }
        kept = next
    }

    /// What the transport should be asked to put back when the app comes to the front.
    ///
    /// A value rather than a branch inside `resume()` so the decision can be asserted from the
    /// tests: there are no sockets on macOS, and the bug this replaced was entirely in the
    /// decision — a guard on whether the machinery *looked* alive, answered by a callback that
    /// had not arrived yet.
    enum Revival: Equatable {
        case nothing
        case hosting(SessionCode, UUID)
        case joining(SessionCode)
    }

    var revival: Revival {
        switch phase {
        case .hosting(let code): hosted.map { .hosting(code, $0.share) } ?? .nothing
        case .searching, .joined: wanted.map { Revival.joining($0) } ?? .nothing
        case .off, .failed: .nothing
        }
    }

    /// Puts sharing back up after the app has been in a pocket.
    ///
    /// iOS takes the listener and the browser away when an app is suspended, so a host who puts
    /// their phone down stops being reachable and does not come back on their own. There is no
    /// guard on whether it looked alive: the rebuilds leave a working link alone, so the honest
    /// answer to "did the system take it away?" is to stop asking a question nothing can answer
    /// in time and simply put it back every time.
    public func resume() {
        switch revival {
        case .nothing:
            break
        case .hosting(let code, let share):
            link.resumeHosting(code: code, share: share)
            bluetooth?.resumeHosting(code: code, share: share)
        case .joining(let code):
            link.resumeJoining(code: code)
            bluetooth?.resumeJoining(code: code)
        }
    }

    /// Whether joining `code` takes this device off a shared match it is on now: the one it
    /// hosts, or the one it follows while something on it can still be heard. A new code is
    /// another match only while the old one is in reach. With nothing on it, it is as likely
    /// to be this match shared again after the host relaunched.
    ///
    /// Public so a code that arrived whole, from a link or the camera, can be shown and left
    /// to a tap rather than sent straight on: for a host, joining is the end of sharing.
    public func joiningStepsOff(_ code: SessionCode) -> Bool {
        hosted != nil || (wanted != nil && wanted != code && reachablePeers > 0)
    }

    /// `forTheWatch` when the code was typed on the wrist and this phone only carries it out.
    public func join(_ code: SessionCode, forTheWatch: Bool = false) {
        let steppingOff = joiningStepsOff(code)
        // Joining somebody else's match is the end of hosting this one.
        let farewell = hosted != nil ? stop() : nil
        store.beginJoining(steppingOff: steppingOff, forThePair: forTheWatch)
        recorder?.note(.joinStarted)
        dial(code, limited: true, after: farewell)
    }

    /// `limited` for a code typed in: one that finds nothing in `searchLimit` says why. The links
    /// are only turned round once `farewell` has gone out on them.
    private func dial(_ code: SessionCode, limited: Bool = false, after farewell: Task<Void, Never>? = nil) {
        searchDeadline?.cancel()
        searchDeadline = nil
        if limited { watchTheSearch(for: code) }
        waitingForTheRadio?.cancel()
        waitingForTheRadio = nil
        noticing?.cancel()
        noticing = nil
        wanted = code
        hasJoinedBefore = false
        hasRecordedJoin = false
        hostStoppedSharing = false
        // Whatever was through belonged to the last code.
        peers = 0
        bluetoothPeers = 0
        if let farewell {
            Task { [weak self] in
                await farewell.value
                guard let self, self.wanted == code else { return }
                self.link.startJoining(code: code)
                self.bluetooth?.startJoining(code: code)
            }
        } else {
            link.startJoining(code: code)
            bluetooth?.startJoining(code: code)
        }
        phase = .searching
        reportStandby()
        checkTheHost()
    }

    /// Stops sharing, or steps off somebody else's match, depending which end this is. A host
    /// tells its guests before it lets go of them, or to each of them it looks like the host
    /// walking off; what comes back is that telling, done once it has gone out or given up.
    @discardableResult
    public func stop() -> Task<Void, Never>? {
        guard store.role == .host else {
            cutLinks()
            switch store.role {
            case .guest: store.leaveSharedSession()
            // Solo on a match this end cannot end is following its own watch onto somebody else's,
            // which the watch joined by itself. Leaving it is leaving it, whoever did the joining.
            case .solo where !store.canEndSession && !store.log.isEmpty: store.leaveSharedSession()
            case .solo, .host: store.cancelJoining()
            }
            forgetWhatWasAskedFor()
            standbyCode = nil
            return nil
        }
        recorder?.note(.sharingStopped, in: store.log.sessionID)
        let farewell = store.sayStoppedSharing()
        store.stopSharing()
        remember(.stoppedHosting)
        forgetWhatWasAskedFor()
        standbyCode = nil
        Task { [weak self] in
            await farewell.value
            guard let self, self.hosted == nil, self.wanted == nil else { return }
            self.cutLinks()
        }
        return farewell
    }

    /// The host let everybody go, and said so first: nothing to look for, and no code to keep.
    private func stoppedByHost() {
        cutLinks()
        recorder?.note(.sharingStopped, on: hostLink, in: store.log.sessionID)
        remember(.sharingStopped)
        forgetWhatWasAskedFor()
        standbyCode = nil
        hostStoppedSharing = true
    }

    public func acknowledgeStoppedSharing() {
        hostStoppedSharing = false
    }

    /// The store is stepping off as it says so, so there is nothing left to decide — only the
    /// links to let go of. Not `stop()`, which decides by what is on the store
    /// when it runs, and by then that can be the match this end has just started.
    private func letGo() {
        cutLinks()
        store.cancelJoining()
        forgetWhatWasAskedFor()
        standbyCode = nil
    }

    /// Gives up looking, and nothing more. A guest that is back from a relaunch still holds
    /// the match and typed the code to reach the host again; a search that finds nothing must
    /// not throw the match away, which is what `stop()` would do for a guest.
    public func cancelJoining() {
        standDown()
        standbyCode = nil
    }

    /// The wrist called off the join it asked for. Only a join still waiting is called off: one
    /// that landed while the word was on its way is a link to a host that has to be kept.
    public func cancelJoiningFromTheWatch() {
        guard store.isJoining else { return }
        cancelJoining()
    }

    /// Not `stop()`, which goes by the role: a watch following its phone's match is solo on it.
    public func leave() {
        cutLinks()
        store.leaveSharedSession()
        forgetWhatWasAskedFor()
        standbyCode = nil
    }

    public func keepOnStandby(_ code: SessionCode?) {
        standbyCode = code
    }

    /// A link of its own to the match already on the wrist. Not a join: the watch is on that
    /// match through its phone, and stays a follower of the phone while it carries it.
    public func standIn() {
        guard let standbyCode, !isSharing else { return }
        dial(standbyCode)
    }

    public func standDown() {
        cutLinks()
        store.cancelJoining()
        forgetWhatWasAskedFor()
    }

    /// Links first, store second: what the store says on its way off a match must not go out
    /// over a link to the host that is about to close anyway.
    private func cutLinks() {
        link.stop()
        bluetooth?.stop()
        bluetoothPeers = 0
    }

    private func forgetWhatWasAskedFor() {
        peers = 0
        phase = .off
        hosted = nil
        wanted = nil
        hasLostTheMatch = false
        hasJoinedBefore = false
        noticing?.cancel()
        noticing = nil
        waitingForTheRadio?.cancel()
        waitingForTheRadio = nil
        searchDeadline?.cancel()
        searchDeadline = nil
        checkTheHost()
    }

    /// A guest with a match on screen and nothing reaching the host is on its own. Said so once
    /// that has lasted `hostGrace`, as from when it began.
    private func checkTheHost() {
        let isOnItsOwn = wanted != nil && hosted == nil && !store.isJoining && store.state != nil
            && !store.canEndSession && reachablePeers == 0
        guard isOnItsOwn else {
            if hostOutOfReachSince != nil, reachablePeers > 0 {
                recorder?.note(.backInStep, on: hostLink, in: store.log.sessionID)
            }
            hostLostAt = nil
            watchingTheHost?.cancel()
            watchingTheHost = nil
            hostOutOfReachSince = nil
            return
        }
        guard hostLostAt == nil else { return }
        let lost = now()
        hostLostAt = lost
        watchingTheHost = Task { [weak self, sleep] in
            await sleep(Self.hostGrace)
            guard let self, !Task.isCancelled, self.hostLostAt == lost else { return }
            self.hostOutOfReachSince = lost
            self.recorder?.note(.outOfReach, on: self.hostLink, in: self.store.log.sessionID)
        }
    }

    /// Stops watching the transport. The app holds this for its whole life, so this is here
    /// for tests rather than for the app.
    public func close() {
        watching?.cancel()
        watching = nil
        watchingBluetooth?.cancel()
        watchingBluetooth = nil
        watchingTheRadio?.cancel()
        watchingTheRadio = nil
    }

    public func acknowledgeLostMatch() {
        hasLostTheMatch = false
    }

    /// Back to the keyboard, or back to the match. A failed search is only ever a search: a
    /// guest that already held the match keeps it.
    public func dismissFailure() {
        guard case .failed = phase else { return }
        if store.role == .host { stop() } else { cancelJoining() }
    }

    private func beginNoticingTheLoss() {
        guard noticing == nil else { return }
        noticing = Task { [weak self, graceBeforeNotice] in
            try? await Task.sleep(for: graceBeforeNotice)
            guard let self, !Task.isCancelled else { return }
            // Let go of first, whatever is decided: a task still on the books after it has
            // run would stop the next loss from ever being noticed.
            self.noticing = nil
            guard case .searching = self.phase else { return }
            // Nothing has been lost if Bluetooth is still carrying it.
            guard self.bluetoothPeers == 0 else { return }
            self.hasLostTheMatch = true
        }
    }

    /// Whether the store has the match this coordinator went looking for, whichever link
    /// brought it. The role alone cannot say: a guest walking back in was a guest already.
    private var hasTheMatch: Bool {
        !store.isJoining && store.role == .guest
    }

    /// Internal rather than private so the tests can drive the states a socket would.
    func apply(_ status: LocalNetworkTransport.Status) {
        defer {
            checkTheHost()
            reportStandby()
        }
        // The transport reports on its own queue and this reads it later, so a status from
        // before `stop()` can land after it. Nothing asked for is nothing to report on.
        guard hosted != nil || wanted != nil else {
            peers = 0
            return
        }
        switch status {
        case .idle:
            peers = 0
        case .hosting(let count):
            peers = count
            // Back up after a listener that failed and was put back.
            if case .hosting = phase {} else if let hosted { phase = .hosting(hosted.code) }
        case .searching:
            peers = 0
            if case .hosting = phase { return }
            // Coming back to searching having been joined means the host went away. Give the
            // redial a moment before saying so — most drops heal on their own.
            if case .joined = phase { beginNoticingTheLoss() }
            phase = .searching
        case .joined(let count):
            peers = count
            if case .hosting = phase { return }
            noticing?.cancel()
            noticing = nil
            hasLostTheMatch = false
            hasJoinedBefore = true
            phase = .joined
            noteProven()
        case .failed(let failure):
            // A host's listener giving up is the network gone, not the match: the radio is still
            // advertising the same code, and the listener is put back when the app next comes to
            // the front. Saying sharing had failed dropped the code off the screen, and sharing
            // again read out a new one that nobody already on the match had.
            if hosted != nil { return }
            // A failure after the match has once been found is a drop, not a refusal. The
            // transport is meant never to send one now; if it ever does, the answer here is to
            // go on looking rather than to throw away a match somebody is in the middle of
            // playing and send them back to the keyboard.
            guard !hasJoinedBefore else { return apply(.searching) }
            // The network gave up, but the match is here — over Bluetooth, which is the only
            // way in when the host's phone is locked and off the network altogether. That is
            // a link to keep looking for, not a code to send somebody back to the keyboard
            // over; and the transport stopped itself to say so, so it is put back to looking.
            if let wanted, hasTheMatch || bluetoothPeers > 0 {
                return keepLooking(for: wanted)
            }
            if let wanted, bluetooth != nil, hosted == nil, failure != .rejected {
                peers = 0
                return waitForTheRadio(wanted, else: failure)
            }
            giveUp(failure)
        }
    }

    private func keepLooking(for code: SessionCode) {
        waitingForTheRadio?.cancel()
        waitingForTheRadio = nil
        hasJoinedBefore = true
        link.resumeJoining(code: code)
        apply(.searching)
    }

    private func waitForTheRadio(_ code: SessionCode, else failure: LocalNetworkTransport.Failure) {
        guard waitingForTheRadio == nil else { return }
        waitingForTheRadio = Task { [weak self, radioGrace] in
            try? await Task.sleep(for: radioGrace)
            guard let self, !Task.isCancelled, self.wanted == code else { return }
            self.waitingForTheRadio = nil
            if self.hasTheMatch || self.bluetoothPeers > 0 {
                self.keepLooking(for: code)
            } else {
                self.giveUp(failure)
            }
        }
    }

    /// With no Wi-Fi the network never says it has given up, so the search keeps its own time.
    private func watchTheSearch(for code: SessionCode) {
        searchDeadline = Task { [weak self, searchLimit, sleep] in
            await sleep(searchLimit)
            guard let self, !Task.isCancelled, self.wanted == code else { return }
            self.searchDeadline = nil
            guard !self.hasJoinedBefore, !self.hasTheMatch, self.bluetoothPeers == 0, self.peers == 0 else { return }
            switch self.bluetooth?.availability {
            case .off?: self.giveUp(.bluetoothOff)
            case .denied?: self.giveUp(.bluetoothDenied)
            default: self.giveUp(.notFound)
            }
        }
    }

    /// The host has as many guests as it takes. Whatever of its match came through first is
    /// let go of the way a Leave would.
    private func turnedAway() {
        guard wanted != nil else { return }
        if store.role == .guest { store.leaveSharedSession() }
        giveUp(.noRoom)
    }

    /// Nothing is left dialling: a radio still looking after the screen said "not found" would
    /// hand over the match later to a phone that no longer thinks it is joining.
    private func giveUp(_ failure: LocalNetworkTransport.Failure) {
        // The radio's own state is recorded as it changes.
        switch failure {
        case .rejected: recorder?.note(.refused(.wrongCode))
        case .noRoom: recorder?.note(.refused(.noRoom), on: hostLink)
        case .notFound, .blocked, .bluetoothOff, .bluetoothDenied: break
        }
        peers = 0
        if hosted == nil { cutLinks() }
        store.cancelJoining()
        phase = .failed(failure)
    }

    /// What the host's watch shows, without the picture of the code, which the phone draws.
    public var hostingStatus: HostingStatus {
        HostingStatus(
            isSharing: code != nil,
            code: code,
            joinLink: code?.joinLink,
            participants: code == nil ? [] : store.participantStates(),
            canShare: store.state != nil && store.role != .guest
        )
    }

    /// The host's watch asked to share. Only a match that is on can be: otherwise it is told so.
    public func startHostingFromTheWatch() {
        guard store.state != nil, store.role != .guest else { return reportHostingStatus(force: true) }
        if code == nil { host() } else { reportHostingStatus(force: true) }
    }

    public func stopHostingFromTheWatch() {
        guard code != nil else { return reportHostingStatus(force: true) }
        stop()
    }

    private func reportHostingStatus(force: Bool = false) {
        let status = hostingStatus
        guard force || status != reportedHosting else { return }
        let isNews = status.isSharing != reportedHosting?.isSharing || status.code != reportedHosting?.code
        reportedHosting = status
        var stamped = status
        stamped.issuedAt = now()
        onHostingStatus?(stamped, isNews)
    }

    private func reportStandby() {
        let standby: SharingStandby?
        switch phase {
        case .searching, .joined:
            standby = wanted.map {
                SharingStandby(code: $0, isThrough: reachablePeers > 0, hostOutOfReachSince: hostOutOfReachSince)
            }
        case .off, .hosting, .failed: standby = nil
        }
        guard !hasReportedStandby || standby != reportedStandby else { return }
        hasReportedStandby = true
        reportedStandby = standby
        onStandby?(standby)
    }
}

extension SharedSession.Phase {
    /// As much of it as means anything on a wrist. Hosting is not one of them: a watch cannot
    /// advertise, so it can never be the phase a watch is being told about.
    var asShared: SharingState {
        switch self {
        case .off, .hosting: .off
        case .searching: .searching
        case .joined: .joined
        case .failed(let failure): .failed(failure.asShared)
        }
    }
}

extension LocalNetworkTransport.Failure {
    var asShared: SharingFailure {
        switch self {
        case .notFound: .notFound
        case .rejected: .rejected
        case .blocked: .blocked
        case .noRoom: .noRoom
        case .bluetoothOff: .bluetoothOff
        case .bluetoothDenied: .bluetoothDenied
        }
    }
}
