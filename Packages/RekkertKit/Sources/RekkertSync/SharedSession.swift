import Foundation
import Observation
import RekkertCore

/// Hosting and joining, as the screens see it.
///
/// Holds the one piece of state the match itself must never carry: the code. It is not in the
/// log, which travels to every peer and into History, and it is not on disk — sharing lasts as
/// long as the app is in front of you, and a host who quits shares again with a new one.
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

    public private(set) var phase: Phase = .off
    /// How many other phones are on the match right now.
    public private(set) var peers = 0
    /// Set when a match this device had joined has been out of reach long enough that it is
    /// worth saying so. The scoreboard goes on showing the copy it holds, which is the point
    /// — but a score that has quietly stopped being true is worse than an honest notice.
    public private(set) var hasLostTheMatch = false

    private let store: MatchStore
    private let link: LocalNetworkTransport
    /// The link that survives the screen going off. It has no status of its own worth showing —
    /// there is no browsing or advertising to report on, only whether anybody is there — so it
    /// contributes reachability and nothing else.
    private let bluetooth: (any SharedLink)?
    private var watching: Task<Void, Never>?
    private var watchingBluetooth: Task<Void, Never>?
    /// How many phones are on the match over Bluetooth. Kept apart from `peers` because the
    /// same phone is usually on both links and there is nothing on the wire to tell that it is:
    /// `Wire.hello` carries no sender, so the two transports cannot recognise each other's
    /// peers. Folding them with `max` undercounts a room where somebody is on one link only,
    /// which is better than telling four people there are eight of them.
    private var bluetoothPeers = 0
    /// Kept so sharing can be stood back up after the app has been put down. The code is
    /// never written to disk — this lasts exactly as long as the app is running.
    private var hosted: (code: SessionCode, share: UUID)?
    private var wanted: SessionCode?
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

    public init(
        store: MatchStore,
        link: LocalNetworkTransport,
        bluetooth: (any SharedLink)? = nil,
        graceBeforeNotice: Duration = .seconds(20)
    ) {
        self.store = store
        self.link = link
        self.bluetooth = bluetooth
        self.graceBeforeNotice = graceBeforeNotice
        watching = Task { [weak self] in
            for await status in link.status { self?.apply(status) }
        }
        if let bluetooth {
            watchingBluetooth = Task { [weak self] in
                for await _ in bluetooth.reachability {
                    self?.bluetoothPeers = bluetooth.reachableCount
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
    public func host(code: SessionCode = .random()) {
        guard store.state != nil else { return }
        hosted = (code, UUID())
        store.startSharing()
        link.startHosting(code: code, share: hosted!.share)
        bluetooth?.startHosting(code: code, share: hosted!.share)
        phase = .hosting(code)
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

    public func join(_ code: SessionCode) {
        wanted = code
        hasJoinedBefore = false
        store.beginJoining()
        link.startJoining(code: code)
        bluetooth?.startJoining(code: code)
        phase = .searching
    }

    /// Stops sharing, or steps off somebody else's match, depending which end this is.
    public func stop() {
        link.stop()
        bluetooth?.stop()
        bluetoothPeers = 0
        switch store.role {
        case .host: store.stopSharing()
        case .guest: store.leaveSharedSession()
        case .solo: store.cancelJoining()
        }
        peers = 0
        phase = .off
        hosted = nil
        wanted = nil
        hasLostTheMatch = false
        hasJoinedBefore = false
        noticing?.cancel()
        noticing = nil
    }

    /// Stops watching the transport. The app holds this for its whole life, so this is here
    /// for tests rather than for the app.
    public func close() {
        watching?.cancel()
        watching = nil
        watchingBluetooth?.cancel()
        watchingBluetooth = nil
    }

    public func acknowledgeLostMatch() {
        hasLostTheMatch = false
    }

    public func dismissFailure() {
        guard case .failed = phase else { return }
        stop()
    }

    private func beginNoticingTheLoss() {
        guard noticing == nil else { return }
        noticing = Task { [weak self, graceBeforeNotice] in
            try? await Task.sleep(for: graceBeforeNotice)
            guard let self, !Task.isCancelled else { return }
            guard case .searching = self.phase else { return }
            // Nothing has been lost if Bluetooth is still carrying it.
            guard self.bluetoothPeers == 0 else { return }
            self.hasLostTheMatch = true
            self.noticing = nil
        }
    }

    /// Internal rather than private so the tests can drive the states a socket would.
    func apply(_ status: LocalNetworkTransport.Status) {
        switch status {
        case .idle:
            peers = 0
        case .hosting(let count):
            peers = count
            if case .hosting = phase {} else if let code { phase = .hosting(code) }
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
        case .failed(let failure):
            // A failure after the match has once been found is a drop, not a refusal. The
            // transport is meant never to send one now; if it ever does, the answer here is to
            // go on looking rather than to throw away a match somebody is in the middle of
            // playing and send them back to the keyboard.
            guard !hasJoinedBefore else { return apply(.searching) }
            peers = 0
            store.cancelJoining()
            phase = .failed(failure)
        }
    }
}
