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

    /// A session written by an older build may no longer decode. Rather than failing every
    /// launch on the same file, it is set aside once and the app starts clean.
    public func loadActive() throws -> ActiveSession? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        do {
            return try decoder.decode(ActiveSession.self, from: data)
        } catch {
            let quarantine = directory.appending(path: "active-unreadable.json")
            try? FileManager.default.removeItem(at: quarantine)
            try? FileManager.default.moveItem(at: activeURL, to: quarantine)
            return nil
        }
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

    // MARK: - Player roster

    private var rosterURL: URL { directory.appending(path: "players.json") }

    public func loadRoster() -> PlayerRoster {
        guard let data = try? Data(contentsOf: rosterURL),
              let roster = try? decoder.decode(PlayerRoster.self, from: data)
        else { return PlayerRoster() }
        return roster
    }

    public func save(_ roster: PlayerRoster) throws {
        try write(try encoder.encode(roster), to: rosterURL)
    }

    // MARK: - Presets

    private var presetsURL: URL { directory.appending(path: "presets.json") }

    public func loadPresets() -> PresetLibrary {
        guard let data = try? Data(contentsOf: presetsURL),
              let library = try? decoder.decode(PresetLibrary.self, from: data)
        else { return PresetLibrary() }
        return library
    }

    public func save(_ library: PresetLibrary) throws {
        try write(try encoder.encode(library), to: presetsURL)
    }

    // MARK: - Plumbing

    private var encoder: JSONEncoder { JSONCoding.encoder }
    private var decoder: JSONDecoder { JSONCoding.decoder }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
