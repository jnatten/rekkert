import RekkertCore
import RekkertSync
import SwiftUI
import VisionKit

/// Type the code the host read out.
struct JoinMatchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var prefilled = ""
    var submitsImmediately = false

    @State private var typed = ""
    /// Whether this sheet has sent a code. A guest whose host shared the match again on a new
    /// code opens it while still looking for the old one, and was shown that search, not a field.
    @State private var submitted = false
    @State private var scanning = false
    @State private var choosingWho = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Group {
                if choosingWho {
                    whoAreYou
                } else {
                    switch submitted ? model.sharing.phase : .off {
                    case .searching: waiting("Looking for the match…")
                    case .joined: waiting("Joined. Waiting for the match…")
                    case .failed(let failure): trouble(failure)
                    default: entry
                    }
                }
            }
            .navigationTitle(choosingWho ? "Who are you?" : "Join a match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if choosingWho {
                        Button("Skip") { dismiss() }
                    } else {
                        // Not `stop()`, which for a guest back from a relaunch would leave the
                        // match it still holds. And only a join sent from here: a guest that opened
                        // this and thought better of it goes on looking for the host it had.
                        Button("Cancel") {
                            if submitted { model.sharing.cancelJoining() }
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $scanning) {
                CodeScannerView { code in
                    scanning = false
                    receive(code)
                }
            }
        }
        // Keyed so a link opened while this is already up still lands here.
        .task(id: prefilled) {
            if submitsImmediately, let code = SessionCode(prefilled) {
                receive(code)
            } else {
                typed = SessionCode.grouped(prefilled)
                typing = true
            }
        }
        .onChange(of: model.store.isJoining) { _, joining in
            // Keyed on the join concluding rather than on the role changing, which it
            // does not for a guest walking back in. The scoreboard is already behind this.
            guard !joining, model.store.role == .guest, !hasFailed else { return }
            let names = model.store.state?.playerNames ?? []
            if let identity = model.store.identity, names.contains(identity) {
                model.store.identify(as: identity)
                dismiss()
            } else if names.isEmpty {
                dismiss()
            } else {
                choosingWho = true
            }
        }
        .onDisappear {
            // Swiped away mid-search: a search left running would conclude with nobody
            // watching, or make a phone that goes on to share a guest of its own guests.
            if submitted, model.store.isJoining { model.sharing.cancelJoining() }
        }
    }

    private var whoAreYou: some View {
        Form {
            Section {
                ForEach(model.store.state?.playerNames ?? [], id: \.self) { name in
                    Button(name) { identify(as: name) }
                }
            } footer: {
                Text("The host sees your name beside your phone, to decide what it may do.")
            }
            Section {
                Button("Just watching") { identify(as: nil) }
            }
        }
    }

    private func identify(as name: String?) {
        model.store.identify(as: name)
        dismiss()
    }

    private var hasFailed: Bool {
        if case .failed = model.sharing.phase { return true }
        return false
    }

    private var entry: some View {
        Form {
            if let cost {
                Section {
                    Label(cost, systemImage: "exclamationmark.triangle")
                }
            }

            if DataScannerViewController.isSupported {
                Section {
                    Button("Scan the host's code", systemImage: "qrcode.viewfinder") {
                        typing = false
                        scanning = true
                    }
                }
            }

            Section {
                TextField("···-···", text: $typed)
                    .font(.system(.largeTitle, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($typing)
                    .onSubmit(submit)
                    // Not in the binding's setter: a field being typed into does not show
                    // what the setter changes, so the hyphen never appeared.
                    .onChange(of: typed) { _, new in
                        let grouped = SessionCode.grouped(new)
                        if grouped != new { typed = grouped }
                    }
            } header: {
                Text("Code")
            } footer: {
                Text("Six digits, as the host reads them out.")
            }

            Section {
                Button(joinTitle, role: stepsOff ? .destructive : nil, action: submit)
                    .disabled(SessionCode(typed) == nil)
            }
        }
    }

    /// Whether the code in the field would take this phone off a shared match it is on.
    private var stepsOff: Bool {
        SessionCode(typed).map(model.sharing.joiningStepsOff) ?? false
    }

    /// What joining the code in the field costs, when it costs a match. For a host that is
    /// the sharing, and everybody on it; for a guest, the match being followed.
    private var cost: String? {
        guard stepsOff else { return nil }
        guard model.store.role == .host else {
            return "You are following a shared match. Joining another one leaves it."
        }
        switch model.sharing.reachablePeers {
        case 0: return "You are sharing this match. Joining another one stops that."
        case 1: return "You are sharing this match with 1 phone. Joining another one stops that for them."
        case let count: return "You are sharing this match with \(count) phones. Joining another one stops that for all of them."
        }
    }

    private var joinTitle: String {
        guard stepsOff else { return "Join" }
        return model.store.role == .host ? "Stop sharing and join" : "Leave and join"
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
                submitted = false
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

    /// A code that came in whole, from a link or the camera, rather than being typed. Sent on
    /// unless joining it would take this phone off a shared match: then it is shown with what
    /// that costs, and the tap is left to whoever is holding the phone.
    private func receive(_ code: SessionCode) {
        typed = code.description
        if model.sharing.joiningStepsOff(code) { typing = false } else { submit() }
    }

    private func submit() {
        guard let code = SessionCode(typed) else { return }
        typing = false
        submitted = true
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
