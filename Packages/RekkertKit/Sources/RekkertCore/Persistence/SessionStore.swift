import Foundation

public struct ActiveSession: Codable, Sendable, Hashable {
    public var log: MatchLog
    public var outbox: Outbox
    /// Sessions that have been finished or replaced here. A counterpart that has not caught
    /// up yet will keep offering them back, and without this they would be adopted again.
    public var retired: [UUID]
    /// Which end of a shared session this is, so a guest that relaunches mid-match does not
    /// come back holding the whistle.
    public var role: SessionRole

    public init(
        log: MatchLog,
        outbox: Outbox = Outbox(),
        retired: [UUID] = [],
        role: SessionRole = .solo
    ) {
        self.log = log
        self.outbox = outbox
        self.retired = retired
        self.role = role
    }

    private enum CodingKeys: String, CodingKey { case log, outbox, retired, role }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        log = try container.decode(MatchLog.self, forKey: .log)
        outbox = try container.decode(Outbox.self, forKey: .outbox)
        retired = try container.decodeIfPresent([UUID].self, forKey: .retired) ?? []
        role = try container.decodeIfPresent(SessionRole.self, forKey: .role) ?? .solo
    }
}

public struct HistoryRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var finishedAt: Date
    public var title: String
    public var state: SessionState
    /// When the session was first configured, kept so a match can be lined up against a
    /// workout that was running at the time. Absent on anything filed before workouts
    /// existed, which `playedFrom` stands in for.
    public var startedAt: Date?

    public init(
        id: UUID = UUID(),
        finishedAt: Date = Date(),
        title: String,
        state: SessionState,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.finishedAt = finishedAt
        self.title = title
        self.state = state
        self.startedAt = startedAt
    }

    /// The stretch of time this was played over. A record from before start times were kept
    /// collapses to the instant it finished, which still lands inside a workout that was
    /// running then.
    public var playedFrom: Date { startedAt ?? finishedAt }

    private enum CodingKeys: String, CodingKey { case id, finishedAt, title, state, startedAt }

    /// Hand-rolled so that a record written before `startedAt` existed still decodes.
    /// `history()` drops what it cannot read without a word, so a synthesised decoder
    /// gaining a field would quietly empty the history.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        title = try container.decode(String.self, forKey: .title)
        state = try container.decode(SessionState.self, forKey: .state)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
    }
}

/// Atomic Codable JSON on disk. The active session is what makes an interrupted match
/// resume; history is archived once a session finishes.
public struct SessionStore: Sendable {
    public let directory: URL

    private var activeURL: URL { directory.appending(path: "active.json") }
    private var historyDirectory: URL { directory.appending(path: "history", directoryHint: .isDirectory) }
    private var workoutsDirectory: URL { directory.appending(path: "workouts", directoryHint: .isDirectory) }

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

    /// One record, without decoding the rest of the shelf — what a screen showing a single
    /// match needs on every redraw.
    public func historyRecord(_ id: UUID) -> HistoryRecord? {
        guard let data = try? Data(contentsOf: historyDirectory.appending(path: "\(id.uuidString).json"))
        else { return nil }
        return try? decoder.decode(HistoryRecord.self, from: data)
    }

    public func deleteHistory(_ id: UUID) throws {
        try? FileManager.default.removeItem(at: historyDirectory.appending(path: "\(id.uuidString).json"))
    }

    // MARK: - Workouts

    public func archive(_ workout: WorkoutRecord) throws {
        try write(
            try encoder.encode(workout),
            to: workoutsDirectory.appending(path: "\(workout.id.uuidString).json")
        )
    }

    /// Whether there is anything at all, without decoding it. The start screen asks on every
    /// redraw purely to decide whether a row exists, and reading the whole shelf for that is
    /// a cost `history()` already pays and this need not.
    public func hasWorkouts() -> Bool {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: workoutsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return urls.contains { $0.pathExtension == "json" }
    }

    public func workouts() throws -> [WorkoutRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: workoutsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(WorkoutRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func deleteWorkout(_ id: UUID) throws {
        try? FileManager.default.removeItem(at: workoutsDirectory.appending(path: "\(id.uuidString).json"))
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

    // MARK: - Display

    private var displayURL: URL { directory.appending(path: "display.json") }

    public func loadDisplay() -> DisplayPreferences {
        guard let data = try? Data(contentsOf: displayURL),
              let preferences = try? decoder.decode(DisplayPreferences.self, from: data)
        else { return DisplayPreferences() }
        return preferences
    }

    public func save(_ preferences: DisplayPreferences) throws {
        try write(try encoder.encode(preferences), to: displayURL)
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
