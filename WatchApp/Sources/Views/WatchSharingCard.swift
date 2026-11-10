import RekkertCore
import RekkertSync
import SwiftUI

/// The start screen's sharing: share, the code, who is on and stop for a host; whose sharing it
/// is and the way off for a guest waiting for the next match.
struct WatchSharingCard: View {
    @Environment(AppModel.self) private var model
    @State private var showingCode = false
    @State private var confirmingStop = false
    @State private var confirmingLeave = false

    var body: some View {
        VStack(spacing: 6) {
            if model.store.side == .guest {
                guest
            } else if let hosting = model.standIn.hosting, hosting.isSharing {
                Text("Sharing · \(hosting.countLine)")
                    .scaledFont(size: 13, weight: .semibold)
                Button("Code", systemImage: "qrcode") { showingCode = true }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                Button("Stop sharing", systemImage: "xmark.circle", role: .destructive) { confirmingStop = true }
                    .buttonStyle(.bordered)
                    .font(.footnote)
            } else {
                Button("Share", systemImage: "person.2.wave.2") {
                    model.standIn.startHosting()
                    showingCode = true
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
            if model.standIn.hostingTrouble == .cannotReachPhone, model.store.side != .guest {
                Text("Can't reach your iPhone")
                    .scaledFont(size: 11)
                    .foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $showingCode) { WatchCodeView() }
        .confirmationDialog(
            "Stop sharing? Everyone else stops following your matches.",
            isPresented: $confirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) { model.standIn.stopHosting() }
        }
        .confirmationDialog(
            "Leave \(hostName.map { "\($0)'s" } ?? "the host's") sharing? Your iPhone leaves too.",
            isPresented: $confirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) { model.sharing.leave() }
        }
    }

    private var hostName: String? { model.store.hostName ?? model.standIn.phonesHostName }

    private var guest: some View {
        VStack(spacing: 4) {
            Text(hostName.map { "On \($0)'s sharing" } ?? "On a shared match")
                .scaledFont(size: 13, weight: .semibold)
                .multilineTextAlignment(.center)
            Text("Waiting for the next match")
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
            Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                confirmingLeave = true
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
        .accessibilityElement(children: .contain)
    }
}

extension HostingStatus {
    /// "N of M" when the phone said how many it takes, "N on" from a phone that did not.
    var countLine: String {
        limit.map { "\(participants.count) of \($0)" } ?? "\(participants.count) on"
    }
}
