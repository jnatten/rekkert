import RekkertCore
import RekkertSync
import SwiftUI

/// The code to read out, and who has turned up so far.
struct ShareCodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let code = model.sharing.code {
                        JoinQRCode(code: code)
                            .padding(.top, 12)

                        Text(code.description)
                            .font(.system(size: 46, weight: .semibold, design: .monospaced))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    Text("Let them scan this with their camera, or read the code out. \(model.store.defaultAccess.invitation)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // Read again every second: a guest going quiet changes nothing until somebody looks.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let participants = model.store.participantStates()
                        VStack(spacing: 12) {
                            Label(joinedDescription(participants), systemImage: "person.2.fill")
                                .font(.headline)
                                .foregroundStyle(participants.isEmpty ? .secondary : Color.accentColor)
                            if !participants.isEmpty { whoIsOn(participants) }
                        }
                    }

                    whoMayDoWhat

                    VStack(spacing: 6) {
                        Text("Only you can finish this match.")
                        Text("Keep this phone nearby. The score keeps up over Bluetooth even when your phone is locked or in a bag, and the screen will not sleep while you are sharing.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding()
            }
            .safeAreaBar(edge: .bottom) {
                Button("Stop sharing", role: .destructive) {
                    model.sharing.stop()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.bottom)
            }
            .navigationTitle("Share this match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var whoMayDoWhat: some View {
        VStack(spacing: 0) {
            LabeledContent("New phones join as") {
                Picker("New phones join as", selection: defaultAccess) {
                    ForEach(ShareAccess.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .padding(.vertical, 6)
            ForEach(Array(model.store.guests.enumerated()), id: \.element.id) { index, guest in
                Divider()
                LabeledContent(guest.name ?? "Phone \(index + 1)") {
                    Picker(selection: access(of: guest)) {
                        Text("Default (\(model.store.defaultAccess.title))").tag(ShareAccess?.none)
                        ForEach(ShareAccess.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    } label: {
                        Text(guest.name ?? "Phone \(index + 1)")
                    } currentValueLabel: {
                        Text(model.store.accessTable?.override(for: guest.device)?.title ?? "Default")
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private var defaultAccess: Binding<ShareAccess> {
        Binding(get: { model.store.defaultAccess }, set: { model.store.setDefaultAccess($0) })
    }

    private func access(of guest: GuestCard) -> Binding<ShareAccess?> {
        Binding(
            get: { model.store.accessTable?.override(for: guest.device) },
            set: { model.store.setAccess($0, for: guest.device) }
        )
    }

    /// People, not links: a guest on two radios, or with its watch standing in, is one of them.
    private func joinedDescription(_ participants: [ParticipantSummary]) -> String {
        if model.sharing.isReconnecting { return "Looking for them again" }
        switch participants.count {
        case 0: return "Nobody has joined yet"
        case 1: return "1 guest joined"
        case let count: return "\(count) guests joined"
        }
    }

    private func whoIsOn(_ participants: [ParticipantSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                if index > 0 { Divider() }
                LabeledContent(participant.name ?? "Phone \(index + 1)") {
                    Text(participant.state.title)
                        .foregroundStyle(participant.state.tint)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

private extension ParticipantState {
    var title: String {
        switch self {
        case .inStep: "In step"
        case .catchingUp: "Catching up"
        case .outOfReach(let since): "Out of reach since \(since.formatted(date: .omitted, time: .shortened))"
        }
    }

    var tint: Color {
        switch self {
        case .inStep: .green
        case .catchingUp: .secondary
        case .outOfReach: .orange
        }
    }
}

private extension ShareAccess {
    var invitation: String {
        switch self {
        case .full: "Anyone at the court can join to follow the match and score it."
        case .score: "Anyone at the court can join to follow the match and keep the score."
        case .readOnly: "Anyone at the court can join to follow the match."
        }
    }
}
