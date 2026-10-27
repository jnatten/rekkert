import RekkertCore
import RekkertSync
import SwiftUI

/// Who is on the host's match, and how each of them is doing (FR-010, FR-020).
struct WatchGuestsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let participants = model.standIn.hosting?.participants ?? []
        List {
            if participants.isEmpty {
                Text("Nobody has joined yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                let name = participant.name ?? "Phone \(index + 1)"
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(participant.state.title)
                        .font(.system(size: 11))
                        .foregroundStyle(participant.state.tint)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(participant.state.title)")
            }
        }
        .navigationTitle("Who's on")
    }
}

extension ParticipantState {
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
