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

    private let store: MatchStore
    private let link: LocalNetworkTransport
    private var watching: Task<Void, Never>?
    /// Kept so sharing can be stood back up after the app has been put down. The code is
    /// never written to disk — this lasts exactly as long as the app is running.
    private var hosted: (code: SessionCode, share: UUID)?
    private var wanted: SessionCode?

    public init(store: MatchStore, link: LocalNetworkTransport) {
        self.store = store
        self.link = link
        watching = Task { [weak self] in
            for await status in link.status { self?.apply(status) }
        }
    }

    public var isSharing: Bool {
        if case .off = phase { return false }
        if case .failed = phase { return false }
        return true
    }

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
        phase = .hosting(code)
    }

    /// Puts sharing back up after the app has been in a pocket.
    ///
    /// iOS takes the listener and the browser away when an app is suspended, so a host who
    /// puts their phone down stops being reachable and does not come back on their own. Only
    /// rebuilt when the machinery has actually gone, so a working connection is never torn
    /// down just because the app was glanced away from.
    public func resume() {
        guard !link.isAlive else { return }
        switch phase {
        case .hosting(let code):
            guard let hosted else { return }
            link.startHosting(code: code, share: hosted.share)
        case .searching, .joined:
            guard let wanted else { return }
            link.startJoining(code: wanted)
        case .off, .failed:
            break
        }
    }

    public func join(_ code: SessionCode) {
        wanted = code
        store.beginJoining()
        link.startJoining(code: code)
        phase = .searching
    }

    /// Stops sharing, or steps off somebody else's match, depending which end this is.
    public func stop() {
        link.stop()
        switch store.role {
        case .host: store.stopSharing()
        case .guest: store.leaveSharedSession()
        case .solo: store.cancelJoining()
        }
        peers = 0
        phase = .off
        hosted = nil
        wanted = nil
    }

    /// Stops watching the transport. The app holds this for its whole life, so this is here
    /// for tests rather than for the app.
    public func close() {
        watching?.cancel()
        watching = nil
    }

    public func dismissFailure() {
        guard case .failed = phase else { return }
        stop()
    }

    private func apply(_ status: LocalNetworkTransport.Status) {
        switch status {
        case .idle:
            peers = 0
        case .hosting(let count):
            peers = count
            if case .hosting = phase {} else if let code { phase = .hosting(code) }
        case .searching:
            peers = 0
            if case .hosting = phase { return }
            phase = .searching
        case .joined(let count):
            peers = count
            if case .hosting = phase { return }
            phase = .joined
        case .failed(let failure):
            peers = 0
            store.cancelJoining()
            phase = .failed(failure)
        }
    }
}
