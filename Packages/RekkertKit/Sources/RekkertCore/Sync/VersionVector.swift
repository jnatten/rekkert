/// Highest sequence number seen per device. Encoded as a sorted array so the bytes are
/// stable across runs — `Dictionary` ordering is not, and these payloads go over the wire.
public struct VersionVector: Sendable, Hashable, Codable {
    private var entries: [DeviceID: UInt32]

    public init(_ entries: [DeviceID: UInt32] = [:]) {
        self.entries = entries
    }

    public subscript(device: DeviceID) -> UInt32 {
        get { entries[device] ?? 0 }
        set { entries[device] = max(entries[device] ?? 0, newValue) }
    }

    public var isEmpty: Bool { entries.isEmpty }

    private struct Entry: Codable, Sendable {
        let device: DeviceID
        let seq: UInt32
    }

    public init(from decoder: any Decoder) throws {
        let list = try decoder.singleValueContainer().decode([Entry].self)
        entries = Dictionary(uniqueKeysWithValues: list.map { ($0.device, $0.seq) })
    }

    public func encode(to encoder: any Encoder) throws {
        let list = entries
            .map { Entry(device: $0.key, seq: $0.value) }
            .sorted { $0.device < $1.device }
        var container = encoder.singleValueContainer()
        try container.encode(list)
    }
}
