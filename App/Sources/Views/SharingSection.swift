import RekkertCore
import RekkertSync
import SwiftUI

/// Home's "Play together": sharing, joining and leaving with no match on.
struct SharingSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingStop = false
    @State private var confirmingLeave = false

    var body: some View {
        Section {
            if model.store.role == .guest {
                guestRows
            } else if let code = model.sharing.code {
                hostRows(code)
            } else {
                Button {
                    model.sharing.host()
                    model.showingShareCode = true
                } label: {
                    row("Share", "Others at the court follow and score your matches until you stop", "person.2.wave.2")
                }
                joinRows
            }
        } header: {
            Text("Play together")
        } footer: {
            Text("Everyone at the court sees the same scoreboard and can score it. Sharing lasts until it's stopped, or until 30 minutes go by with no match on.")
        }
        .confirmationDialog(
            "Stop sharing? Everyone else stops following your matches.",
            isPresented: $confirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) { model.sharing.stop() }
        }
        .confirmationDialog(leaveTitle, isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { model.sharing.stop() }
        }
    }

    @ViewBuilder
    private func hostRows(_ code: SessionCode) -> some View {
        let on = model.store.participantStates().count
        Button {
            model.showingShareCode = true
        } label: {
            row("Sharing on \(code.readOut)", "\(on) on · until you stop", "person.2.wave.2")
        }
        .accessibilityLabel("Sharing on \(code.digitByDigit), \(on) on")
        Button(role: .destructive) {
            confirmingStop = true
        } label: {
            Label("Stop sharing", systemImage: "xmark.circle")
        }
    }

    @ViewBuilder
    private var guestRows: some View {
        let host = model.store.hostName
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.map { "On \($0)'s sharing" } ?? "On a shared match").foregroundStyle(.primary)
                Text(host.map { "Waiting for \($0)'s next match" } ?? "Waiting for the host's next match")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "person.2.wave.2")
        }
        .accessibilityElement(children: .combine)
        Button(role: .destructive) {
            confirmingLeave = true
        } label: {
            Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    @ViewBuilder
    private var joinRows: some View {
        Button {
            model.showingJoin = true
        } label: {
            row("Join a match", "Scan or type the host's code", "arrow.right.circle")
        }
        if let kept = model.sharing.keptGuestCode {
            Button {
                model.sharing.join(kept)
            } label: {
                row("Join again", "Back on \(kept.readOut), no code to type", "arrow.right.circle")
            }
            .accessibilityLabel("Join again on \(kept.digitByDigit), no code to type")
        }
    }

    private var leaveTitle: String {
        let whose = model.store.hostName.map { "\($0)'s sharing" } ?? "this sharing"
        return AppModel.canPairWatch ? "Leave \(whose)? Your watch leaves too." : "Leave \(whose)?"
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

/// Said where a match is started, so nobody is surprised it goes to the guests on (FR-020).
struct SharedWithLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let code = model.sharing.code {
            let on = model.store.participantStates().count
            Label("Shared with \(on) on \(code.readOut)", systemImage: "person.2.wave.2")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Shared with \(on) on \(code.digitByDigit)")
        }
    }
}

private struct StepOffConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    let start: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Start your own match? This takes you off \(model.store.hostName.map { "\($0)'s" } ?? "the host's") sharing.",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Start anyway", role: .destructive, action: start)
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension View {
    /// FR-021: a guest asked once before starting a match of its own takes it off the host's sharing.
    func stepOffConfirmation(isPresented: Binding<Bool>, start: @escaping () -> Void) -> some View {
        modifier(StepOffConfirmation(isPresented: isPresented, start: start))
    }
}
