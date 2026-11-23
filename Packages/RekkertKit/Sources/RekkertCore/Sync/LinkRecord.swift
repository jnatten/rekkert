import Foundation

/// Which radio a link to the host or a guest is on.
public enum LinkRadio: String, Codable, Sendable, Hashable, Comparable {
    case bluetooth, wifi

    public static func < (lhs: LinkRadio, rhs: LinkRadio) -> Bool { lhs.rawValue < rhs.rawValue }

    var short: String { self == .bluetooth ? "bt" : "wifi" }
    public var title: String { self == .bluetooth ? "Bluetooth" : "Wi-Fi" }

    init?(short: String) {
        switch short {
        case "bt": self = .bluetooth
        case "wifi": self = .wifi
        default: return nil
        }
    }
}

/// What a device was running and how it was set, for the sharing record: enough to tell one
/// evening's watch from another's, and nothing that says whose it is.
public struct DeviceNote: Codable, Sendable, Hashable {
    /// `1.2 (82) 181886a`: version, build and commit.
    public var app: String
    /// `watchOS 27.2.1`
    public var system: String
    /// `Watch7,5`
    public var model: String
    public var lowPower: Bool
    public var reduceMotion: Bool

    public init(app: String, system: String, model: String, lowPower: Bool, reduceMotion: Bool) {
        self.app = app
        self.system = system
        self.model = model
        self.lowPower = lowPower
        self.reduceMotion = reduceMotion
    }

    private static let separator = " · "

    /// As an export reads it: `1.2 (82) 181886a · watchOS 27.2.1 · Watch7,5 · lowPower off · reduceMotion off`.
    public var text: String {
        [app, system, model, "lowPower \(lowPower ? "on" : "off")", "reduceMotion \(reduceMotion ? "on" : "off")"]
            .joined(separator: Self.separator)
    }

    public init?(text: String) {
        let parts = text.components(separatedBy: Self.separator)
        let switches: [String: Bool] = ["on": true, "off": false]
        guard parts.count == 5,
              parts[3].hasPrefix("lowPower "), let lowPower = switches[String(parts[3].dropFirst("lowPower ".count))],
              parts[4].hasPrefix("reduceMotion "), let reduceMotion = switches[String(parts[4].dropFirst("reduceMotion ".count))]
        else { return nil }
        self.init(app: parts[0], system: parts[1], model: parts[2], lowPower: lowPower, reduceMotion: reduceMotion)
    }
}

/// Something that happened to one of a device's links, for the sharing record.
///
/// Nothing in it can carry a player's name, a score or the code: the kinds are fixed, and
/// what goes with them is an id, a count or a time, or what the device itself was running.
public struct LinkRecordEntry: Codable, Sendable, Hashable, Identifiable {
    public enum Device: String, Codable, Sendable, Hashable {
        case phone, watch
    }

    public enum Link: Codable, Sendable, Hashable {
        /// The phone and the watch in the same pocket.
        case pair
        case host(DeviceID)
        case guest(DeviceID)
        /// The device as a whole: its radio, its launches.
        case radio
    }

    public var id: UUID
    public var time: Date
    public var device: Device
    public var session: UUID?
    public var link: Link
    public var kind: LinkEvent
    /// The radios the link was on: one for a link, the ones up for a guest or host as a whole.
    public var radios: [LinkRadio]?
    /// One short code with a drop (`ETIMEDOUT`), or `older` with a delay a 1.1 device left unknown.
    public var detail: String?
    /// With a delay, the part of the way FR-010 or FR-010a judges, where it is not from the tap.
    public var leg: Leg?

    /// `nil` inside is unknown.
    public enum Leg: Codable, Sendable, Hashable {
        /// A point tapped on a watch following its phone, from when that phone had it (FR-010).
        case link(TimeInterval?)
        /// On a watch following its phone, from when that phone had the point (FR-010a).
        case hop(TimeInterval?)

        var text: String {
            switch self {
            case .link(let seconds): "link " + Self.text(seconds)
            case .hop(let seconds): "hop " + Self.text(seconds)
            }
        }

        init?(text: String) {
            let words = text.split(separator: " ", maxSplits: 1).map(String.init)
            guard words.count == 2 else { return nil }
            let seconds: TimeInterval?? = words[1] == "unknown" ? .some(nil) : TimeInterval(words[1].dropLast()).map { .some($0) }
            guard let seconds else { return nil }
            switch words[0] {
            case "link": self = .link(seconds)
            case "hop": self = .hop(seconds)
            default: return nil
            }
        }

        private static func text(_ seconds: TimeInterval?) -> String {
            seconds.map { String(format: "%.3fs", $0) } ?? "unknown"
        }
    }

    public init(
        id: UUID = UUID(), time: Date, device: Device, session: UUID? = nil, link: Link = .radio,
        kind: LinkEvent, radios: [LinkRadio]? = nil, detail: String? = nil, leg: Leg? = nil
    ) {
        self.id = id
        self.time = time
        self.device = device
        self.session = session
        self.link = link
        self.kind = kind
        self.radios = radios.map { Array(Set($0)).sorted() }
        self.detail = detail
        self.leg = leg
    }
}

public enum LinkEvent: Codable, Sendable, Hashable {
    public enum Launch: String, Codable, Sendable, Hashable {
        case user, background, restored
    }

    public enum Refusal: String, Codable, Sendable, Hashable {
        case wrongCode, noRoom, access, needsUpdate
    }

    case launched(Launch)
    /// A launch that found a kept code: the only trace an ended app can leave.
    case appHadBeenEnded
    case sharingStarted, sharingRestored, sharingStopped
    case joinStarted, joined, proven
    case refused(Refusal)
    case dropped(LinkDropReason)
    case outOfReach, backInStep
    case caughtUp(events: Int)
    case wroteOff, redialled
    case standIn, standDown
    case radioOff, radioOn, permissionDenied
    case notificationPosted
    case recordReceived(from: LinkRecordEntry.Device)
    /// How long after it was tapped a point reached this device, or `nil` when the clocks
    /// could not bound it within a tenth of a second (spec 005, FR-006).
    case pointArrived(latency: TimeInterval?)
    /// The device's battery, 0 to 1.
    case battery(level: Double)
    /// What the device was running, so a fault seen on one watch can be set against its build,
    /// its system and how it was set (bug shared-guest-half-board).
    case device(DeviceNote)
    case endOfMatchAsked
    case endOfMatchAnswered(BetweenMatchesAnswer.Choice)
    case endOfMatchUnanswered
    case newMatchShown
    case newMatchAnswered(BetweenMatchesAnswer.Choice)
    case idleStop

    /// As an export reads it: `dropped(timeout)`, `caughtUp(12)`.
    public var text: String {
        switch self {
        case .launched(let launch): "launched(\(launch.rawValue))"
        case .appHadBeenEnded: "appHadBeenEnded"
        case .sharingStarted: "sharingStarted"
        case .sharingRestored: "sharingRestored"
        case .sharingStopped: "sharingStopped"
        case .joinStarted: "joinStarted"
        case .joined: "joined"
        case .proven: "proven"
        case .refused(let refusal): "refused(\(refusal.rawValue))"
        case .dropped(let reason): "dropped(\(reason.rawValue))"
        case .outOfReach: "outOfReach"
        case .backInStep: "backInStep"
        case .caughtUp(let events): "caughtUp(\(events))"
        case .wroteOff: "wroteOff"
        case .redialled: "redialled"
        case .standIn: "standIn"
        case .standDown: "standDown"
        case .radioOff: "radioOff"
        case .radioOn: "radioOn"
        case .permissionDenied: "permissionDenied"
        case .notificationPosted: "notificationPosted"
        case .recordReceived(let device): "recordReceived(\(device.rawValue))"
        case .pointArrived(let latency?): "pointArrived(\(String(format: "%.3f", latency))s)"
        case .pointArrived(nil): "pointArrived(unknown)"
        case .battery(let level): "battery(\(Int((level * 100).rounded()))%)"
        case .device(let note): "device(\(note.text))"
        case .endOfMatchAsked: "endOfMatchAsked"
        case .endOfMatchAnswered(let choice): "endOfMatchAnswered(\(choice.rawValue))"
        case .endOfMatchUnanswered: "endOfMatchUnanswered"
        case .newMatchShown: "newMatchShown"
        case .newMatchAnswered(let choice): "newMatchAnswered(\(choice.rawValue))"
        case .idleStop: "idleStop"
        }
    }

    public init?(text: String) {
        let name = String(text.prefix { $0 != "(" })
        let argument = text.count > name.count + 1
            ? String(text.dropFirst(name.count + 1).dropLast()).components(separatedBy: "; ").first
            : nil
        switch (name, argument) {
        case ("launched", let argument?): guard let launch = Launch(rawValue: argument) else { return nil }
            self = .launched(launch)
        case ("refused", let argument?): guard let refusal = Refusal(rawValue: argument) else { return nil }
            self = .refused(refusal)
        case ("dropped", let argument?): guard let reason = LinkDropReason(rawValue: argument) else { return nil }
            self = .dropped(reason)
        case ("caughtUp", let argument?): guard let events = Int(argument) else { return nil }
            self = .caughtUp(events: events)
        case ("recordReceived", let argument?): guard let device = LinkRecordEntry.Device(rawValue: argument) else { return nil }
            self = .recordReceived(from: device)
        case ("pointArrived", "unknown"):
            self = .pointArrived(latency: nil)
        case ("pointArrived", let argument?): guard let latency = TimeInterval(argument.dropLast()) else { return nil }
            self = .pointArrived(latency: latency)
        case ("battery", let argument?): guard let percent = Double(argument.dropLast()) else { return nil }
            self = .battery(level: percent / 100)
        case ("device", let argument?): guard let note = DeviceNote(text: argument) else { return nil }
            self = .device(note)
        case ("endOfMatchAnswered", let argument?): guard let choice = BetweenMatchesAnswer.Choice(rawValue: argument) else { return nil }
            self = .endOfMatchAnswered(choice)
        case ("newMatchAnswered", let argument?): guard let choice = BetweenMatchesAnswer.Choice(rawValue: argument) else { return nil }
            self = .newMatchAnswered(choice)
        case (_, nil):
            let plain: [String: LinkEvent] = [
                "appHadBeenEnded": .appHadBeenEnded, "sharingStarted": .sharingStarted,
                "sharingRestored": .sharingRestored, "sharingStopped": .sharingStopped,
                "joinStarted": .joinStarted, "joined": .joined, "proven": .proven,
                "outOfReach": .outOfReach, "backInStep": .backInStep, "wroteOff": .wroteOff,
                "redialled": .redialled, "standIn": .standIn, "standDown": .standDown,
                "radioOff": .radioOff, "radioOn": .radioOn, "permissionDenied": .permissionDenied,
                "notificationPosted": .notificationPosted, "endOfMatchAsked": .endOfMatchAsked,
                "endOfMatchUnanswered": .endOfMatchUnanswered, "newMatchShown": .newMatchShown, "idleStop": .idleStop,
            ]
            guard let event = plain[name] else { return nil }
            self = event
        default:
            return nil
        }
    }
}

/// A phone's record of its links, with its watch's merged in: in time order, each entry once.
public struct LinkRecord: Sendable, Hashable {
    /// How many days back a record goes.
    public static let keptDays = 7

    public private(set) var entries: [LinkRecordEntry]

    public init(_ entries: some Sequence<LinkRecordEntry> = []) {
        self.entries = []
        merge(entries)
    }

    /// The watch's copy arrives whole each time, so most of it is already here.
    public mutating func merge(_ more: some Sequence<LinkRecordEntry>) {
        var byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in more where byID[entry.id] == nil { byID[entry.id] = entry }
        entries = byID.values.sorted { ($0.time, $0.id.uuidString) < ($1.time, $1.id.uuidString) }
    }

    /// The day an entry is filed under, `2026-10-27`.
    public static func day(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func isKept(day: String, today: Date, in calendar: Calendar) -> Bool {
        guard let oldest = calendar.date(byAdding: .day, value: -keptDays, to: today) else { return true }
        return day >= Self.day(of: oldest, in: calendar)
    }

    // MARK: - Export

    public struct Header: Sendable, Hashable {
        /// `1.0 (56) abc1234`: version, build and commit.
        public var app: String
        public var phoneSystem: String
        public var watchSystem: String?
        public var phone: DeviceID
        public var watch: DeviceID?
        /// The last of the watch's entries to have reached the phone, while the two are out of touch.
        public var watchUpTo: Date?

        public init(
            app: String, phoneSystem: String, watchSystem: String? = nil, phone: DeviceID,
            watch: DeviceID? = nil, watchUpTo: Date? = nil
        ) {
            self.app = app
            self.phoneSystem = phoneSystem
            self.watchSystem = watchSystem
            self.phone = phone
            self.watch = watch
            self.watchUpTo = watchUpTo
        }
    }

    /// One line read back from an export. Ids there are cut to four hex digits, so the link and
    /// the session come back as written.
    public struct Line: Sendable, Hashable {
        public var time: Date
        public var device: LinkRecordEntry.Device
        public var link: String
        public var kind: LinkEvent
        public var session: String?
        public var radios: [LinkRadio]? = nil
        public var detail: String? = nil
        public var leg: LinkRecordEntry.Leg? = nil
    }

    /// The plain text of `contracts/sharing-record.md`.
    public func export(_ header: Header, now: Date, in calendar: Calendar) -> String {
        let oldest = calendar.date(byAdding: .day, value: -Self.keptDays, to: now) ?? now
        var lines = [
            "Rekkert sharing record",
            (["App \(header.app)", header.phoneSystem] + [header.watchSystem].compactMap { $0 }).joined(separator: " · "),
            (["This phone \(header.phone.raw.uuidString)"] + [header.watch.map { "its watch \($0.raw.uuidString)" }].compactMap { $0 })
                .joined(separator: " · "),
            "Covers \(Self.day(of: oldest, in: calendar)) to \(Self.day(of: now, in: calendar))",
        ]
        // The phone's own line above is as it is now. The watch's is as it last said, which is
        // all the phone knows of it.
        let watchNote = entries.reversed().lazy.compactMap { entry -> DeviceNote? in
            guard entry.device == .watch, case .device(let note) = entry.kind else { return nil }
            return note
        }.first
        if let watchNote {
            lines.insert("Its watch: App \(watchNote.app) · \(watchNote.system) · \(watchNote.model)", at: 3)
        }
        if let upTo = header.watchUpTo {
            let parts = calendar.dateComponents([.hour, .minute], from: upTo)
            lines.append(String(format: "Watch entries up to %02d:%02d (not in touch since)", parts.hour ?? 0, parts.minute ?? 0))
        }
        lines.append("")
        let starts = Dictionary(summaries(watchUpTo: header.watchUpTo).map { ($0.firstEntry, $0) }) { first, _ in first }
        for entry in entries {
            if let summary = starts[entry.id] { lines.append(summary.line(in: calendar)) }
            lines.append(Self.line(for: entry, in: calendar))
        }
        return lines.joined(separator: "\n")
    }

    public static func parse(_ text: String, in calendar: Calendar) -> [Line] {
        let body = text.components(separatedBy: "\n").drop { !$0.isEmpty }.dropFirst()
        return body.compactMap { row in
            let columns = row.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard columns.count >= 4, let time = time(from: columns[0], in: calendar),
                  let device = LinkRecordEntry.Device(rawValue: columns[1]),
                  let kind = LinkEvent(text: columns[3])
            else { return nil }
            let session = columns.count > 4 && columns[4].hasPrefix("match ")
                ? String(columns[4].dropFirst("match ".count).prefix(4))
                : nil
            var link = columns[2]
            var radios: [LinkRadio]?
            let words = link.split(separator: " ")
            if words.count > 1 {
                let named = words.last!.split(separator: "+").map { LinkRadio(short: String($0)) }
                if !named.contains(where: { $0 == nil }) {
                    radios = named.compactMap { $0 }
                    link = words.dropLast().joined(separator: " ")
                }
            }
            let extras = columns[3].range(of: "; ").map { String(columns[3][$0.upperBound...].dropLast()).components(separatedBy: "; ") } ?? []
            let leg = extras.lazy.compactMap(LinkRecordEntry.Leg.init(text:)).first
            let detail = extras.first { LinkRecordEntry.Leg(text: $0) == nil }
            return Line(time: time, device: device, link: link, kind: kind, session: session, radios: radios, detail: detail, leg: leg)
        }
    }

    private static func line(for entry: LinkRecordEntry, in calendar: Calendar) -> String {
        let link = switch entry.link {
        case .pair: "pair"
        case .radio: "radio"
        case .host(let device): "host \(short(device.raw))"
        case .guest(let device): "guest \(short(device.raw))"
        }
        let radios = entry.radios.map { " " + $0.map(\.short).joined(separator: "+") } ?? ""
        let columns = "\(stamp(entry.time, in: calendar))  \(entry.device.rawValue)  \((link + radios).padded(to: 10))  "
        let kind = entry.kindText
        guard let session = entry.session else { return columns + kind }
        return columns + kind.padded(to: 26) + "  match \(short(session))…"
    }

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(4)) }

    /// Milliseconds counted rather than formatted, which would cut 19:41:57.006 to .005.
    private static func stamp(_ time: Date, in calendar: Calendar) -> String {
        let milliseconds = Int64((time.timeIntervalSince1970 * 1_000).rounded())
        let whole = Date(timeIntervalSince1970: TimeInterval(milliseconds.quotientAndRemainder(dividingBy: 1_000).quotient))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
            Int(milliseconds % 1_000)
        )
    }

    private static func time(from stamp: String, in calendar: Calendar) -> Date? {
        let numbers = stamp.split(whereSeparator: { "- :.".contains($0) }).compactMap { Int($0) }
        guard numbers.count == 7 else { return nil }
        let whole = calendar.date(from: DateComponents(
            year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4], second: numbers[5]
        ))
        return whole?.addingTimeInterval(TimeInterval(numbers[6]) / 1_000)
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
