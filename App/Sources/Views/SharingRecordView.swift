import RekkertCore
import RekkertSync
import SwiftUI
import UIKit

/// What happened to this phone's links and its watch's over the last week, newest first
/// (FR-013). It leaves the phone through the Share button and no other way.
struct SharingRecordView: View {
    @Environment(AppModel.self) private var model
    @State private var record = LinkRecord()
    @State private var file: URL?

    var body: some View {
        List {
            if record.entries.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Joins, drops, reconnects, refusals and catch-ups on a shared match show here for a week, with your watch's once it is back in touch.")
                )
            }
            ForEach(record.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.kind.text)
                        .font(.body.monospaced())
                    Text("\(entry.time.formatted(date: .abbreviated, time: .standard)) · \(entry.device == .watch ? "Watch" : "iPhone") · \(entry.link.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sharing record")
        .toolbar {
            if let file {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: file)
                }
            }
        }
        .task { load() }
    }

    private func load() {
        record = model.recorder.read()
        let now = Date()
        let header = LinkRecord.Header(
            app: [
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                "(\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))",
                CommitLabel.commit ?? "",
            ].joined(separator: " ").trimmingCharacters(in: .whitespaces),
            phoneSystem: "iOS \(UIDevice.current.systemVersion)",
            phone: DeviceIdentity.current(),
            watch: model.store.pairDevice,
            watchUpTo: model.store.isPairReachable ? nil : model.recorder.watchUpTo
        )
        let name = "rekkert-sharing-\(LinkRecord.day(of: now, in: .current)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let text = record.export(header, now: now, in: .current)
        file = (try? text.write(to: url, atomically: true, encoding: .utf8)) == nil ? nil : url
    }
}

private extension LinkRecordEntry.Link {
    var title: String {
        switch self {
        case .pair: "Watch link"
        case .radio: "This device"
        case .host(let device): "Host \(device.raw.uuidString.prefix(4))"
        case .guest(let device): "Guest \(device.raw.uuidString.prefix(4))"
        }
    }
}
