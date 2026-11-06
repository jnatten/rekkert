import Foundation

public struct BetweenMatches: Codable, Sendable, Hashable {
    public static let idleLimit: TimeInterval = 30 * 60
    private static let answersKept = 20

    public private(set) var idleSince: Date?
    public private(set) var ask: EndOfMatchAsk?
    public private(set) var newMatch: NewMatchNotice?
    public private(set) var answeredSessions: [UUID]

    public init(idleSince: Date? = nil, ask: EndOfMatchAsk? = nil, newMatch: NewMatchNotice? = nil, answeredSessions: [UUID] = []) {
        self.idleSince = idleSince
        self.ask = ask
        self.newMatch = newMatch
        self.answeredSessions = answeredSessions
    }

    public static func side(role: SessionRole, pairedRole: SessionRole, isWatch: Bool) -> SessionRole? {
        let side = isWatch && role == .solo ? pairedRole : role
        return side == .solo ? nil : side
    }

    public static func wantsNotification(appIsActive: Bool, watchReachable: Bool) -> Bool {
        !appIsActive && !watchReachable
    }

    public var blocksScoring: Bool { newMatch != nil }

    public func isIdleExpired(now: Date, matchOn: Bool) -> Bool {
        guard !matchOn, let idleSince else { return false }
        return now >= idleSince.addingTimeInterval(Self.idleLimit)
    }

    @discardableResult
    public mutating func matchEnded(session: UUID, side: EndOfMatchAsk.Side?, now: Date) -> Bool {
        idleSince = now
        newMatch = nil
        guard let side, !answeredSessions.contains(session), ask?.session != session else { return false }
        ask = EndOfMatchAsk(session: session, side: side, askedAt: now)
        return true
    }

    @discardableResult
    public mutating func answered(_ answer: BetweenMatchesAnswer) -> Bool {
        var closed = false
        if ask?.session == answer.session {
            ask = nil
            closed = true
        }
        if newMatch?.session == answer.session {
            newMatch = nil
            closed = true
        }
        remember(answer.session)
        return closed
    }

    public mutating func hostKeepsSharing(after session: UUID) {
        guard let open = ask, open.session == session, case .guest(let name, false) = open.side else { return }
        ask = EndOfMatchAsk(session: session, side: .guest(hostName: name, hostKeepsSharing: true), askedAt: open.askedAt)
    }

    @discardableResult
    public mutating func hostsNextMatchArrived(_ notice: NewMatchNotice) -> Bool {
        let unanswered = ask != nil
        if let ask { remember(ask.session) }
        ask = nil
        idleSince = nil
        if !answeredSessions.contains(notice.session) { newMatch = notice }
        return unanswered
    }

    public mutating func matchBegan() {
        if let ask { remember(ask.session) }
        ask = nil
        idleSince = nil
    }

    /// A clock already running keeps its start, so a share put back after a relaunch does not
    /// buy itself another half hour.
    public mutating func sharingStarted(now: Date) {
        if idleSince == nil { idleSince = now }
    }

    public mutating func joinedBetweenMatches(now: Date) {
        idleSince = now
    }

    public mutating func sharingEnded() {
        if let ask { remember(ask.session) }
        idleSince = nil
        ask = nil
        newMatch = nil
    }

    private mutating func remember(_ session: UUID) {
        guard !answeredSessions.contains(session) else { return }
        answeredSessions.append(session)
        if answeredSessions.count > Self.answersKept { answeredSessions.removeFirst(answeredSessions.count - Self.answersKept) }
    }
}

public struct EndOfMatchAsk: Codable, Sendable, Hashable {
    public enum Side: Codable, Sendable, Hashable {
        case host(guestsOn: Int)
        case guest(hostName: String?, hostKeepsSharing: Bool)
    }

    public var session: UUID
    public var side: Side
    public var askedAt: Date

    public init(session: UUID, side: Side, askedAt: Date) {
        self.session = session
        self.side = side
        self.askedAt = askedAt
    }
}

public struct NewMatchNotice: Codable, Sendable, Hashable {
    public var session: UUID
    public var hostName: String?
    public var arrivedAt: Date

    public init(session: UUID, hostName: String?, arrivedAt: Date) {
        self.session = session
        self.hostName = hostName
        self.arrivedAt = arrivedAt
    }
}

public struct BetweenMatchesAnswer: Codable, Sendable, Hashable {
    public enum Choice: String, Codable, Sendable, Hashable {
        case keepSharing, stopSharing, stay, leave, ok
    }

    public var session: UUID
    public var choice: Choice

    public init(session: UUID, choice: Choice) {
        self.session = session
        self.choice = choice
    }
}
