import Foundation

/// Whether nothing was wrong for one point arriving on one device (spec 005, FR-010), or for one
/// hop between a watch and its own phone (FR-010a), read from the sharing record alone.
public enum ArrivalConditions {
    public static let window: TimeInterval = 30

    /// On a device on the shared link: a phone, or a watch standing in for it on its own link.
    /// `from` is the guest the point came from, on the host.
    public static func nothingWrong(
        arrivalAt time: Date,
        from guest: DeviceID? = nil,
        entries: [LinkRecordEntry]
    ) -> Bool {
        let entries = entries.filter { $0.time <= time }.sorted { $0.time < $1.time }
        let relevant: (LinkRecordEntry.Link) -> Bool = { link in
            switch (link, guest) {
            case (.guest(let device), let guest?): device == guest
            case (.host, nil): true
            default: false
            }
        }
        guard isUp(entries, on: relevant) else { return false }
        let since = time.addingTimeInterval(-window)
        var outOfReach = false
        for entry in entries where relevant(entry.link) {
            switch entry.kind {
            case .outOfReach:
                outOfReach = true
                if entry.time >= since { return false }
            case .backInStep:
                outOfReach = false
            case .caughtUp where entry.time >= since:
                return false
            default:
                break
            }
        }
        return !outOfReach
    }

    /// `entries` are the device's own, the watch's or the phone's: the hop needs only the link
    /// between the two, up and not lost or caught up over in the half minute before.
    public static func hopNothingWrong(arrivalAt time: Date, entries: [LinkRecordEntry]) -> Bool {
        let entries = entries.filter { $0.time <= time && $0.link == .pair }.sorted { $0.time < $1.time }
        guard isUp(entries, on: { $0 == .pair }) else { return false }
        let since = time.addingTimeInterval(-window)
        return !entries.contains { entry in
            guard entry.time >= since else { return false }
            switch entry.kind {
            case .dropped, .wroteOff, .redialled, .caughtUp: return true
            default: return false
            }
        }
    }

    private static func isUp(_ entries: [LinkRecordEntry], on relevant: (LinkRecordEntry.Link) -> Bool) -> Bool {
        var open = 0
        for entry in entries where relevant(entry.link) {
            switch entry.kind {
            case .proven: open += 1
            case .dropped, .wroteOff, .redialled: open = max(0, open - 1)
            default: break
            }
        }
        return open > 0
    }
}
