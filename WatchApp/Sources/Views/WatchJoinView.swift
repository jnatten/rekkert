import RekkertCore
import SwiftUI
import WatchKit

/// Type the code the host read out, without reaching for the phone.
///
/// The watch cannot reach a stranger's phone — the local network and Bluetooth are both built
/// on iOS alone — so it hands the code to the phone in your pocket and that end does the
/// joining. Everything below the field is therefore hearsay: what the phone last said it was
/// up to, rather than anything this device can see for itself.
struct WatchJoinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    switch model.joining {
                    case .searching: waiting("Looking for the match…")
                    case .joined: waiting("Joined. Waiting for the match…")
                    case .failed(let failure): trouble(failure)
                    case .off: entry
                    }
                }
                .padding(.horizontal, 2)
            }
            .navigationTitle("Join")
            .onAppear(perform: openDemo)
            // The root swaps to the scoreboard the moment a session lands, so this only has to
            // get out of the way.
            .onChange(of: model.store.state == nil) { _, isEmpty in
                if !isEmpty { dismiss() }
            }
            .onDisappear {
                // Swiped away mid-look: a search left running on the phone would conclude with
                // nobody watching for it.
                if case .searching = model.joining { model.stopJoining() }
            }
        }
    }

    @ViewBuilder
    private var entry: some View {
        // A pad of its own rather than a field: watchOS has no number keyboard, and the sheet a
        // field opens puts the letters in front of the digits.
        Text(typed.isEmpty ? "···-···" : typed)
            .font(.system(.title3, design: .monospaced))
            .foregroundStyle(typed.isEmpty ? .tertiary : .primary)

        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self, content: key)
                }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                key("0")
                Button {
                    typed = SessionCode.grouped(String(SessionCode.folding(typed).dropLast()))
                } label: {
                    Image(systemName: "delete.left").padKey()
                }
                .disabled(typed.isEmpty)
            }
        }
        .buttonStyle(.plain)
        .font(.system(.body, design: .monospaced))

        Button("Join", action: submit)
            .buttonStyle(.borderedProminent)
            .font(.footnote)
            .disabled(SessionCode(typed) == nil || !model.store.isReachable)

        if model.store.isReachable {
            Text("Six digits, as the host reads them out.")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        } else {
            // The phone is the one that does the joining, so there is no version of this that
            // works without it.
            Label("iPhone not reachable", systemImage: "iphone.slash")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func key(_ digit: String) -> some View {
        Button {
            typed = SessionCode.grouped(typed + digit)
            if SessionCode(typed) != nil, model.store.isReachable { submit() }
        } label: {
            Text(digit).padKey()
        }
        .disabled(SessionCode.folding(typed).count == SessionCode.length)
    }

    private func waiting(_ title: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Cancel") {
                model.stopJoining()
                dismiss()
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
        .padding(.top, 8)
    }

    private func trouble(_ failure: SharingFailure) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(failure.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(failure.watchAdvice)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") {
                model.joining = .off
                typed = ""
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
    }

    private func submit() {
        guard let code = SessionCode(typed) else { return }
        WKInterfaceDevice.current().play(.click)
        model.join(code)
    }

    private func openDemo() {
        #if DEBUG
        guard let code = WatchDemoLaunch.joinCode else { return }
        typed = SessionCode.grouped(code)
        // WatchConnectivity is not up the instant the app is, and a join is live or nothing —
        // so wait for the phone the way the Join button does by being disabled.
        Task {
            while !model.store.isReachable {
                try? await Task.sleep(for: .milliseconds(100))
            }
            submit()
        }
        #endif
    }
}

private extension View {
    /// Bordered buttons are too tall to fit four rows and the code on one screen.
    func padKey() -> some View {
        frame(maxWidth: .infinity, minHeight: 32)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
    }
}

extension SharingFailure {
    var title: String {
        switch self {
        case .notFound: "Nothing found"
        case .rejected: "Code not accepted"
        case .blocked: "iPhone cannot look"
        case .unreachable: "iPhone did not hear"
        }
    }

    /// The phone's wording, cut to a screen this size — and pointing at the phone, since that
    /// is where both the looking and any fixing actually happen.
    var watchAdvice: String {
        switch self {
        case .notFound: "Check the code, and that the host is nearby with Rekkert open."
        case .rejected: "Ask the host to read the code out again."
        case .blocked: "Let Rekkert find devices on the local network, in Settings on your iPhone."
        case .unreachable: "Your iPhone does the looking, and it is out of touch. Bring it closer and try again."
        }
    }
}
