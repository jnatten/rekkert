import Foundation

public enum ShareAccess: String, Codable, Sendable, Hashable, CaseIterable {
    case readOnly
    case score
    case full

    public var canScore: Bool { self != .readOnly }
    public var canRunRounds: Bool { self == .full }

    public func mayUndo(_ kind: EventKind) -> Bool {
        switch self {
        case .full: true
        case .readOnly: false
        case .score:
            switch kind {
            case .point, .setScore: true
            default: false
            }
        }
    }

    public var title: String {
        switch self {
        case .readOnly: "Read-only"
        case .score: "Only score"
        case .full: "Full access"
        }
    }
}

public struct ShareAccessTable: Codable, Sendable, Hashable {
    public struct Grant: Codable, Sendable, Hashable {
        public var device: DeviceID
        public var access: ShareAccess

        public init(device: DeviceID, access: ShareAccess) {
            self.device = device
            self.access = access
        }
    }

    /// Minted when a share starts afresh, so a guest still holding the last share's table does
    /// not refuse the new one for having a lower revision.
    public var id: UUID
    public var revision: Int
    public var standard: ShareAccess
    /// Sorted by device, so equal tables encode to equal bytes.
    public private(set) var overrides: [Grant]
    /// Who the host said they are, for the guests to call the match by: "Ada's match".
    public private(set) var hostName: String?

    public init(
        id: UUID = UUID(), revision: Int = 0, standard: ShareAccess, overrides: [Grant] = [], hostName: String? = nil
    ) {
        self.id = id
        self.revision = revision
        self.standard = standard
        self.overrides = overrides.sorted { $0.device < $1.device }
        self.hostName = hostName
    }

    public func override(for device: DeviceID) -> ShareAccess? {
        overrides.first { $0.device == device }?.access
    }

    /// A watch is never named in the table, so it is asked after along with its phone.
    public func access(for devices: [DeviceID?]) -> ShareAccess {
        for device in devices.compactMap(\.self) {
            if let access = override(for: device) { return access }
        }
        return standard
    }

    public func setting(_ access: ShareAccess?, for device: DeviceID) -> ShareAccessTable {
        var next = self
        next.overrides.removeAll { $0.device == device }
        if let access {
            next.overrides.append(Grant(device: device, access: access))
            next.overrides.sort { $0.device < $1.device }
        }
        next.revision += 1
        return next
    }

    public func with(standard: ShareAccess) -> ShareAccessTable {
        var next = self
        next.standard = standard
        next.revision += 1
        return next
    }

    public func with(hostName: String?) -> ShareAccessTable {
        guard hostName != self.hostName else { return self }
        var next = self
        next.hostName = hostName
        next.revision += 1
        return next
    }

    public func supersedes(_ other: ShareAccessTable?) -> Bool {
        guard let other else { return true }
        return id != other.id || revision > other.revision
    }
}

public struct GuestCard: Codable, Sendable, Hashable, Identifiable {
    public var device: DeviceID
    public var name: String?
    /// The phone a watch is standing in for, so the host counts the two as one guest.
    public var pairedTo: DeviceID?

    public var id: DeviceID { device }

    public init(device: DeviceID, name: String?, pairedTo: DeviceID? = nil) {
        self.device = device
        self.name = name
        self.pairedTo = pairedTo
    }
}

extension SessionState {
    public var playerNames: [String] {
        let names: [String] = switch self {
        case .traditional(let session): session.teams.a.players + session.teams.b.players
        case .winnerCourt(let session): session.teams.a.players + session.teams.b.players
        case .pointCount(let session): session.teams.a.players + session.teams.b.players
        case .tournament(let tournament): tournament.players.map(\.name)
        case .friendly(let session): session.players.map(\.name)
        }
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
