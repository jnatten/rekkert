import Foundation

/// One stretch of sharing read from the record: whether points were on time, which radio
/// dropped, and what it cost in battery (spec 005, FR-003).
public struct SharingSummary: Sendable, Hashable {
    public enum Role: String, Sendable, Hashable { case host, guest }

    /// FR-010 is judged on at least this many timed points.
    public static let enoughPoints = 100
    /// FR-006: above this share unknown, a run cannot be judged.
    public static let unknownLimit = 0.1

    public var start: Date
    public var end: Date
    public var role: Role
    public var points = 0
    public var knownDelays = 0
    /// Points from or through a 1.1 device, which sends no clock readings.
    public var olderPoints = 0
    public var medianDelay: TimeInterval?
    public var slowestDelay: TimeInterval?
    public var withinOne: Double?
    public var withinTwo: Double?
    public var unknownShare: Double?
    public var drops: [LinkRadio: Int] = [:]
    public var hostRestarts = 0
    public var unreachable: [String: TimeInterval] = [:]
    public var batteryPerHour: [LinkRecordEntry.Device: Double] = [:]
    public var watchUpTo: Date?
    /// Where the stint starts among the record's entries.
    public var firstEntry: UUID

    public var judgeable: Bool {
        knownDelays >= Self.enoughPoints && (unknownShare ?? 0) <= Self.unknownLimit
    }
}

extension LinkEvent {
    /// Sharing starting, coming back or joined, or it stopping or the guest leaving.
    public var boundsAStint: Bool { LinkRecord.starts(self) || LinkRecord.ends(self) }
}

extension LinkRecordEntry {
    /// The kind as the record writes it, with the drop's detail inside its parentheses.
    public var kindText: String {
        let text = kind.text
        guard let detail, text.hasSuffix(")") else { return text }
        return String(text.dropLast()) + "; \(detail))"
    }
}

extension LinkRecord {
    /// The record's entries under the stint they start, oldest first. Entries before the first
    /// stint have no summary; entries after one ends stay under it, as in the export.
    public struct Section: Identifiable, Sendable {
        public var summary: SharingSummary?
        public var entries: [LinkRecordEntry]
        public var id: UUID? { summary?.firstEntry ?? entries.first?.id }
    }

    public func sections(watchUpTo: Date? = nil) -> [Section] {
        let starts = Dictionary(summaries(watchUpTo: watchUpTo).map { ($0.firstEntry, $0) }) { first, _ in first }
        var sections: [Section] = []
        for entry in entries {
            if let summary = starts[entry.id] {
                sections.append(Section(summary: summary, entries: [entry]))
            } else if sections.isEmpty {
                sections.append(Section(summary: nil, entries: [entry]))
            } else {
                sections[sections.count - 1].entries.append(entry)
            }
        }
        return sections
    }

    /// A stint runs from sharing starting, coming back, or a join, until sharing stops, the
    /// guest leaves, or the record ends.
    public func summaries(watchUpTo: Date? = nil) -> [SharingSummary] {
        var stints: [[LinkRecordEntry]] = []
        var current: [LinkRecordEntry]?
        for entry in entries {
            if Self.starts(entry.kind) {
                if let current { stints.append(current) }
                current = [entry]
            } else if current != nil {
                current?.append(entry)
                if Self.ends(entry.kind) {
                    stints.append(current!)
                    current = nil
                }
            }
        }
        if let current { stints.append(current) }
        return stints.enumerated().map { index, stint in
            Self.summary(of: stint, watchUpTo: index == stints.count - 1 ? watchUpTo : nil)
        }
    }

    fileprivate static func starts(_ kind: LinkEvent) -> Bool {
        switch kind {
        case .sharingStarted, .sharingRestored, .joined: true
        default: false
        }
    }

    fileprivate static func ends(_ kind: LinkEvent) -> Bool {
        switch kind {
        case .sharingStopped, .idleStop, .endOfMatchAnswered(.leave), .endOfMatchAnswered(.stopSharing),
             .newMatchAnswered(.leave): true
        default: false
        }
    }

    private static func summary(of stint: [LinkRecordEntry], watchUpTo: Date?) -> SharingSummary {
        let first = stint[0]
        var summary = SharingSummary(
            start: first.time, end: stint.last!.time, role: first.kind == .joined ? .guest : .host,
            firstEntry: first.id
        )
        summary.watchUpTo = watchUpTo
        let phone = stint.filter { $0.device == .phone }
        let watch = stint.filter { $0.device == .watch }
        var known: [TimeInterval] = []
        var judged: [TimeInterval] = []
        var unknown = 0
        for entry in stint {
            guard case .pointArrived(let latency) = entry.kind else { continue }
            summary.points += 1
            if entry.detail == "older" {
                summary.olderPoints += 1
                continue
            }
            guard let latency else {
                unknown += 1
                continue
            }
            known.append(latency)
            let fine = ArrivalConditions.nothingWrong(
                arrivalAt: entry.time,
                on: entry.device,
                from: { if case .guest(let device) = entry.link { device } else { nil } }(),
                fromPairedDevice: entry.device == .phone && entry.link == .pair,
                entries: entry.device == .phone ? phone : watch,
                pairEntries: entry.device == .watch ? phone : nil
            )
            if fine { judged.append(latency) }
        }
        summary.knownDelays = known.count
        let counted = summary.points - summary.olderPoints
        summary.unknownShare = counted > 0 ? Double(unknown) / Double(counted) : nil
        let sorted = known.sorted()
        summary.medianDelay = sorted.isEmpty ? nil : sorted[sorted.count / 2]
        summary.slowestDelay = sorted.last
        if !judged.isEmpty {
            summary.withinOne = Double(judged.count { $0 <= 1 }) / Double(judged.count)
            summary.withinTwo = Double(judged.count { $0 <= 2 }) / Double(judged.count)
        }

        var outSince: [String: Date] = [:]
        for entry in stint {
            switch (entry.kind, entry.link) {
            case (.dropped(.radioOff), _):
                continue
            case (.dropped, .host), (.dropped, .guest):
                for radio in entry.radios ?? [] { summary.drops[radio, default: 0] += 1 }
            case (.radioOff, .radio):
                summary.hostRestarts += 1
            case (.outOfReach, .host(let device)), (.outOfReach, .guest(let device)):
                outSince[short(device)] = outSince[short(device)] ?? entry.time
            case (.backInStep, .host(let device)), (.backInStep, .guest(let device)):
                if let since = outSince.removeValue(forKey: short(device)) {
                    summary.unreachable[short(device), default: 0] += entry.time.timeIntervalSince(since)
                }
            default:
                break
            }
        }
        for (device, since) in outSince {
            summary.unreachable[device, default: 0] += summary.end.timeIntervalSince(since)
        }

        for device in [LinkRecordEntry.Device.phone, .watch] {
            let readings = stint.compactMap { entry -> (Date, Double)? in
                guard entry.device == device, case .battery(let level) = entry.kind else { return nil }
                return (entry.time, level)
            }
            guard let firstReading = readings.first, let lastReading = readings.last else { continue }
            let hours = lastReading.0.timeIntervalSince(firstReading.0) / 3_600
            guard hours > 0 else { continue }
            summary.batteryPerHour[device] = (firstReading.1 - lastReading.1) / hours
        }
        return summary
    }

    private static func short(_ device: DeviceID) -> String { String(device.raw.uuidString.prefix(4)) }
}

extension SharingSummary {
    /// The summary as an export prints it, ahead of the stint's rows.
    public func line(in calendar: Calendar) -> String {
        var parts = [role.rawValue, "\(clock(start, calendar))–\(clock(end, calendar))"]
        parts.append("\(points) points (\(knownDelays) timed, \(olderPoints) older)")
        parts.append("median \(seconds(medianDelay)) · slowest \(seconds(slowestDelay))")
        if knownDelays < Self.enoughPoints {
            parts.append("not enough timed points")
        } else if (unknownShare ?? 0) > Self.unknownLimit {
            parts.append("too many unknown")
        } else {
            parts.append("\(percent(withinOne)) within 1 s · \(percent(withinTwo)) within 2 s")
        }
        let radios = [LinkRadio.wifi, .bluetooth].map { "\($0.short) \(drops[$0, default: 0])" }
        parts.append("drops \(radios.joined(separator: ", "))")
        if hostRestarts > 0 { parts.append("host Bluetooth restarted \(hostRestarts)") }
        let away = unreachable.sorted { $0.key < $1.key }.map { "\($0.key) \(minutes($0.value))" }
        parts.append(away.isEmpty ? "nobody unreachable" : "unreachable \(away.joined(separator: ", "))")
        let battery = [LinkRecordEntry.Device.phone, .watch].compactMap { device in
            batteryPerHour[device].map { "\(device.rawValue) \(Int(($0 * 100).rounded()))%/h" }
        }
        if !battery.isEmpty { parts.append("battery \(battery.joined(separator: ", "))") }
        if let watchUpTo { parts.append("watch up to \(clock(watchUpTo, calendar))") }
        return "  summary  " + parts.joined(separator: " · ")
    }

    /// The stint's header on the phone's record screen (contracts/screens.md). Lines with no
    /// data are left out.
    public func headerLines(in calendar: Calendar) -> [String] {
        let day = calendar.dateComponents([.day, .month], from: start)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = months[max(0, min(11, (day.month ?? 1) - 1))]
        var lines = ["\(role == .host ? "Host" : "Guest") · \(day.day ?? 0) \(month), \(clock(start, calendar))–\(clock(end, calendar))"]
        if points > 0 {
            let timed = "\(Self.grouped(knownDelays)) of \(Self.grouped(points)) timed"
            if knownDelays < Self.enoughPoints {
                lines.append("Not enough timed points · \(timed)")
            } else if (unknownShare ?? 0) > Self.unknownLimit {
                lines.append("Too many unknown · \(timed)")
            } else {
                lines.append("\(percent(withinOne)) within 1 s · slowest \(String(format: "%.1f s", slowestDelay ?? 0)) · \(timed)")
            }
        }
        let wifi = drops[.wifi, default: 0]
        var reach = ["Wi-Fi dropped \(wifi == 1 ? "once" : "\(wifi) times")", "Bluetooth \(drops[.bluetooth, default: 0])"]
        if hostRestarts > 0 { reach.append("host's Bluetooth restarted \(hostRestarts)") }
        if unreachable.isEmpty {
            reach.append(role == .guest ? "host never unreachable" : "nobody unreachable")
        } else {
            reach += unreachable.sorted { $0.key < $1.key }.map { "\($0.key) unreachable \(minutes($0.value))" }
        }
        lines.append(reach.joined(separator: " · "))
        let battery = [(LinkRecordEntry.Device.phone, "iPhone"), (.watch, "Watch")].compactMap { device, name in
            batteryPerHour[device].map { "\(name) \(Int(($0 * 100).rounded()))%/h" }
        }
        if !battery.isEmpty { lines.append("Battery: " + battery.joined(separator: " · ")) }
        if let watchUpTo { lines.append("Watch entries up to \(clock(watchUpTo, calendar))") }
        return lines
    }

    private static func grouped(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    private func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func seconds(_ value: TimeInterval?) -> String {
        value.map { String(format: "%.2f s", $0) } ?? "–"
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded(.down)))%" } ?? "–"
    }

    private func minutes(_ value: TimeInterval) -> String {
        String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}
