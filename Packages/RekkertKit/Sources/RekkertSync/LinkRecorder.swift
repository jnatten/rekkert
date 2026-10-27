import Foundation
import RekkertCore

/// Where the sharing record is written from: the store, the coordinator and the stand-in each say
/// what happened to a link as it happens.
public protocol LinkRecording: AnyObject {
    func record(_ kind: LinkEvent, link: LinkRecordEntry.Link, session: UUID?)
}

extension LinkRecording {
    public func note(_ kind: LinkEvent, on link: LinkRecordEntry.Link = .radio, in session: UUID? = nil) {
        record(kind, link: link, session: session)
    }
}

/// This device's sharing record (FR-012): a file a day, kept a week and never backed up.
///
/// It goes nowhere by itself. The watch's days go to its own phone, which merges them into its
/// own; from there they leave only if the owner shares them (FR-013).
public final class LinkRecorder: LinkRecording {
    public let device: LinkRecordEntry.Device
    /// On the watch: hands one day's file to its phone, by a transfer that outlives either app.
    public var send: ((_ day: String, _ contents: Data) -> Void)?

    private let directory: URL
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var prunedOn: String?

    public init(
        directory: URL, device: LinkRecordEntry.Device, now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.directory = directory
        self.device = device
        self.now = now
        self.calendar = calendar
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    /// Application Support, where nothing is shown to the user or backed up from here.
    public static var standardDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SharingRecord", isDirectory: true)
    }

    public func record(_ kind: LinkEvent, link: LinkRecordEntry.Link, session: UUID?) {
        let entry = LinkRecordEntry(time: now(), device: device, session: session, link: link, kind: kind)
        let day = LinkRecord.day(of: entry.time, in: calendar)
        if prunedOn != day { prune(today: entry.time) }
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        append(line, to: file(device, day))
        // Back in touch with the phone: the moment to bring it up to date.
        if device == .watch, kind == .proven, link == .pair { sendDays() }
    }

    /// Both halves of the pair, merged, once anything older than a week has gone.
    public func read() -> LinkRecord {
        prune(today: now())
        var record = LinkRecord()
        for url in dayFiles().map(\.url) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            record.merge(text.split(separator: "\n").compactMap {
                try? JSONDecoder().decode(LinkRecordEntry.self, from: Data($0.utf8))
            })
        }
        return record
    }

    /// The newest of the watch's entries to have reached this phone.
    public var watchUpTo: Date? {
        read().entries.last { $0.device == .watch }?.time
    }

    /// One of the watch's days, whole, in place of whatever of it came before.
    public func receive(watchDay day: String, contents: Data) {
        guard LinkRecord.isKept(day: day, today: now(), in: calendar) else { return }
        try? contents.write(to: file(.watch, day), options: .atomic)
        note(.recordReceived(from: .watch), on: .pair)
    }

    /// This device's own days, each handed to `send`.
    public func sendDays() {
        guard let send else { return }
        for (day, url, owner) in dayFiles() where owner == device {
            if let contents = try? Data(contentsOf: url) { send(day, contents) }
        }
    }

    private func file(_ owner: LinkRecordEntry.Device, _ day: String) -> URL {
        directory.appendingPathComponent("\(owner.rawValue)-\(day).jsonl")
    }

    private func dayFiles() -> [(day: String, url: URL, owner: LinkRecordEntry.Device)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard name.hasSuffix(".jsonl") else { return nil }
            let stem = name.dropLast(".jsonl".count)
            guard let dash = stem.firstIndex(of: "-"),
                  let owner = LinkRecordEntry.Device(rawValue: String(stem[..<dash]))
            else { return nil }
            return (String(stem[stem.index(after: dash)...]), directory.appendingPathComponent(name), owner)
        }
    }

    private func prune(today: Date) {
        prunedOn = LinkRecord.day(of: today, in: calendar)
        for (day, url, _) in dayFiles() where !LinkRecord.isKept(day: day, today: today, in: calendar) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func append(_ line: Data, to url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? line.write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
