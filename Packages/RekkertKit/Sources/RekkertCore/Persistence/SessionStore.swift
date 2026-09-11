import Foundation

public struct ActiveSession: Codable, Sendable, Hashable {
    public var log: MatchLog
    public var outbox: Outbox

    public init(log: MatchLog, outbox: Outbox = Outbox()) {
        self.log = log
        self.outbox = outbox
    }
}

public struct HistoryRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var finishedAt: Date
    public var title: String
    public var state: SessionState

    public init(id: UUID = UUID(), finishedAt: Date = Date(), title: String, state: SessionState) {
        self.id = id
        self.finishedAt = finishedAt
        self.title = title
        self.state = state
    }
}

/// Atomic Codable JSON on disk. The active session is what makes an interrupted match
/// resume; history is archived once a session finishes.
public struct SessionStore: Sendable {
    public let directory: URL

    private var activeURL: URL { directory.appending(path: "active.json") }
    private var historyDirectory: URL { directory.appending(path: "history", directoryHint: .isDirectory) }

    public init(directory: URL) {
        self.directory = directory
    }

    public static func applicationSupport(
        bundleFolder: String = "Rekkert",
        fileManager: FileManager = .default
    ) throws -> SessionStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return SessionStore(directory: base.appending(path: bundleFolder, directoryHint: .isDirectory))
    }

    // MARK: - Active session

    public func loadActive() throws -> ActiveSession? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        return try decoder.decode(ActiveSession.self, from: data)
    }

    public func save(_ session: ActiveSession) throws {
        try write(try encoder.encode(session), to: activeURL)
    }

    public func clearActive() throws {
        try? FileManager.default.removeItem(at: activeURL)
    }

    // MARK: - History

    public func archive(_ record: HistoryRecord) throws {
        try write(
            try encoder.encode(record),
            to: historyDirectory.appending(path: "\(record.id.uuidString).json")
        )
    }

    public func history() throws -> [HistoryRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: historyDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(HistoryRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.finishedAt > $1.finishedAt }
    }

    public func deleteHistory(_ id: UUID) throws {
        try? FileManager.default.removeItem(at: historyDirectory.appending(path: "\(id.uuidString).json"))
    }

    // MARK: - Plumbing

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
