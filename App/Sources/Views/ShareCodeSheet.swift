import RekkertCore
import RekkertSync
import SwiftUI

/// The code to read out, and who has turned up so far.
struct ShareCodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if let code = model.sharing.code {
                    Text(code.description)
                        .font(.system(size: 46, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .padding(.top, 24)
                }

                Text("Read this out. Anyone at the court can type it in to follow the match and score it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Label(joinedDescription, systemImage: "person.2.fill")
                    .font(.headline)
                    .foregroundStyle(model.sharing.reachablePeers > 0 ? Color.accentColor : .secondary)

                VStack(spacing: 6) {
                    Text("Only you can finish this match.")
                    Text("Keep this phone nearby. Sharing pauses while the app is put away and picks itself back up when you return. The screen will not sleep while you are sharing.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Spacer()

                Button("Stop sharing", role: .destructive) {
                    model.sharing.stop()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Share this match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var joinedDescription: String {
        if model.sharing.isReconnecting { return "Looking for them again" }
        switch model.sharing.reachablePeers {
        case 0: return "Nobody has joined yet"
        case 1: return "1 phone joined"
        case let count: return "\(count) phones joined"
        }
    }
}
