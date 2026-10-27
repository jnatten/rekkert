import Foundation

/// How a guest is doing, as the host sees it. Worked out from when it was last heard from and
/// what it has, never stored or sent as the truth.
public enum ParticipantState: Codable, Sendable, Hashable {
    case inStep
    case catchingUp
    case outOfReach(since: Date)
}

/// One guest on the host's match: a phone, and its watch while that stands in for it.
public struct Participant: Codable, Sendable, Hashable, Identifiable {
    /// The guest's phone, or its watch if the watch joined on its own.
    public var id: DeviceID
    public var name: String?
    public var devices: Set<DeviceID>
    public var lastHeard: Date
    public var vector: VersionVector
    public var access: ShareAccess
    public var isOlderBuild: Bool

    /// How long a guest may say nothing before it counts as out of reach.
    public static let quietLimit: TimeInterval = 15

    public func state(now: Date, hostCoverage: VersionVector) -> ParticipantState {
        guard now.timeIntervalSince(lastHeard) <= Self.quietLimit else { return .outOfReach(since: lastHeard) }
        return vector.covers(hostCoverage) ? .inStep : .catchingUp
    }
}

/// Everybody on the host's match, in the order they arrived.
public struct Participants: Codable, Sendable, Hashable {
    /// Guests besides the host.
    public static let limit = 7

    public enum Admission: Sendable, Equatable {
        case admitted
        case known
        case full
    }

    public private(set) var all: [Participant] = []

    public init() {}

    public func participant(for device: DeviceID) -> Participant? {
        all.first { $0.id == device || $0.devices.contains(device) }
    }

    /// Something arrived from `device`. A watch names the phone it stands in for in `pairedTo`,
    /// and joins that guest rather than counting as another.
    @discardableResult
    public mutating func heard(
        from device: DeviceID,
        pairedTo: DeviceID? = nil,
        vector: VersionVector? = nil,
        name: String? = nil,
        access: ShareAccess = .full,
        isOlderBuild: Bool = false,
        at time: Date
    ) -> Admission {
        // Counted on its own until it named its phone, a watch joins that guest instead.
        if let pairedTo,
           all.contains(where: { $0.id != device && ($0.id == pairedTo || $0.devices.contains(pairedTo)) }),
           let alone = all.firstIndex(where: { $0.id == device && $0.devices == [device] }) {
            all.remove(at: alone)
        }
        if let index = all.firstIndex(where: { $0.id == device || $0.devices.contains(device) || (pairedTo != nil && $0.id == pairedTo) }) {
            all[index].devices.insert(device)
            all[index].lastHeard = max(all[index].lastHeard, time)
            if let vector { all[index].vector = vector }
            if let name { all[index].name = name }
            return .known
        }
        guard all.count < Self.limit else { return .full }
        all.append(Participant(
            id: pairedTo ?? device,
            name: name,
            devices: [device],
            lastHeard: time,
            vector: vector ?? VersionVector(),
            access: access,
            isOlderBuild: isOlderBuild
        ))
        return .admitted
    }

    public mutating func remove(_ id: DeviceID) {
        all.removeAll { $0.id == id || $0.devices.contains(id) }
    }

    public func states(now: Date, hostCoverage: VersionVector) -> [ParticipantSummary] {
        all.map { ParticipantSummary(id: $0.id, name: $0.name, state: $0.state(now: now, hostCoverage: hostCoverage)) }
    }
}
