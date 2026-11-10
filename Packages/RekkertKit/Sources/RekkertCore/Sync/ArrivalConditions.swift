import Foundation

/// Whether nothing was wrong for one point arriving on one device (spec 005, FR-010), read from
/// the sharing record alone.
public enum ArrivalConditions {
    public static let window: TimeInterval = 30

    /// `from` is the guest the point came from, on the host. `pairEntries` are the phone's
    /// entries, for a watch following that phone. A point from the device's own phone or watch
    /// needs only the link between the two.
    public static func nothingWrong(
        arrivalAt time: Date,
        on device: LinkRecordEntry.Device,
        from guest: DeviceID? = nil,
        fromPairedDevice: Bool = false,
        entries: [LinkRecordEntry],
        pairEntries: [LinkRecordEntry]? = nil
    ) -> Bool {
        let entries = entries.filter { $0.time <= time }.sorted { $0.time < $1.time }
        if fromPairedDevice { return isUp(entries, on: { $0 == .pair }) }
        if device == .watch, let pairEntries {
            return isUp(entries, on: { $0 == .pair })
                && nothingWrong(arrivalAt: time, on: .phone, entries: pairEntries)
        }
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

    private static func isUp(_ entries: [LinkRecordEntry], on relevant: (LinkRecordEntry.Link) -> Bool) -> Bool {
        var open = 0
        for entry in entries where relevant(entry.link) {
            switch entry.kind {
            case .proven: open += 1
            case .dropped: open = max(0, open - 1)
            default: break
            }
        }
        return open > 0
    }
}
