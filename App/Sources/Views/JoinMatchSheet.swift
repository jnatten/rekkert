import RekkertCore
import RekkertSync
import SwiftUI

/// Type the code the host read out.
struct JoinMatchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var prefilled = ""
    var submitsImmediately = false

    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch model.sharing.phase {
                case .searching: waiting("Looking for the match…")
                case .joined: waiting("Joined. Waiting for the match…")
                case .failed(let failure): trouble(failure)
                default: entry
                }
            }
            .navigationTitle("Join a match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Not `stop()`, which for a guest back from a relaunch would leave the
                    // match it still holds.
                    Button("Cancel") {
                        model.sharing.cancelJoining()
                        dismiss()
                    }
                }
            }
            .task {
                typed = SessionCode.grouped(prefilled)
                typing = true
                if submitsImmediately { submit() }
            }
            .onChange(of: model.store.isJoining) { _, joining in
                // Keyed on the join concluding rather than on the role changing, which it
                // does not for a guest walking back in. The scoreboard is already behind this.
                if !joining, model.store.role == .guest, !hasFailed { dismiss() }
            }
            .onDisappear {
                // Swiped away mid-search: a search left running would conclude with nobody
                // watching, or make a phone that goes on to share a guest of its own guests.
                if model.store.isJoining { model.sharing.cancelJoining() }
            }
        }
    }

    private var hasFailed: Bool {
        if case .failed = model.sharing.phase { return true }
        return false
    }

    private var entry: some View {
        Form {
            Section {
                TextField("", text: Binding(get: { typed }, set: { typed = SessionCode.grouped($0) }))
                    .font(.system(.largeTitle, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.oneTimeCode)
                    .focused($typing)
                    .onSubmit(submit)
            } header: {
                Text("Code")
            } footer: {
                Text("Six characters, as the host reads them out. It does not matter whether you type capitals.")
            }

            Section {
                Button("Join", action: submit)
                    .disabled(SessionCode(typed) == nil)
            }
        }
    }

    private func waiting(_ title: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trouble(_ failure: LocalNetworkTransport.Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(failure.advice)
        } actions: {
            Button("Try again") {
                model.sharing.dismissFailure()
                typed = ""
                typing = true
            }
            if failure == .blocked || failure == .notFound {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private func submit() {
        guard let code = SessionCode(typed) else { return }
        typing = false
        model.sharing.join(code)
    }
}

extension LocalNetworkTransport.Failure {
    var title: String {
        switch self {
        case .notFound: "Nothing found"
        case .rejected: "Code not accepted"
        case .blocked: "Cannot see the local network"
        }
    }

    /// A mistyped code and an absent host are the same observation from in here, so the
    /// wording covers both rather than guessing confidently at one.
    var advice: String {
        switch self {
        case .notFound:
            "No shared match with that code. Check the code, that the host is nearby with Rekkert open, and that Rekkert may find devices on the local network."
        case .rejected:
            "A match was there but would not accept that code. Ask the host to read it out again."
        case .blocked:
            "Rekkert needs permission to find devices on the local network before it can join a match."
        }
    }
}
