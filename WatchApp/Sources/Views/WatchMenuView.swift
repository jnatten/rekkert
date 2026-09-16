import RekkertCore
import SwiftUI
import WatchKit

/// The page to the right of the scoreboard: everything that ends something, kept off the
/// scoring screen so a stray tap cannot finish a round.
struct WatchMenuView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: Confirmation?

    private enum Confirmation: String, Identifiable {
        case endRound, nextRound, finish, discard
        var id: String { rawValue }

        var question: String {
            switch self {
            case .endRound: "End this round?"
            case .nextRound: "Finish the round and draw the next?"
            case .finish: "Finish and save?"
            case .discard: "Call this off without saving?"
            }
        }

        var confirmLabel: String {
            switch self {
            case .endRound: "End round"
            case .nextRound: "Next round"
            case .finish: "Finish"
            case .discard: "Discard"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(model.store.state?.title ?? "Rekkert")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                status

                WatchWorkoutButton()

                if isWinnerCourt {
                    action("End round", systemImage: "flag.pattern.checkered", tint: .orange) {
                        confirming = .endRound
                    }
                }
                if isTournament {
                    action("Next round", systemImage: "arrow.right.circle.fill", tint: .blue) {
                        confirming = .nextRound
                    }
                }

                // Flips the phone, not this watch: it is the phone that is propped up
                // somewhere with a side of the court in front of it.
                action("Swap phone sides", systemImage: "rectangle.2.swap") {
                    WKInterfaceDevice.current().play(.click)
                    model.store.toggleScoreboardMirrored()
                }

                action("Undo", systemImage: "arrow.uturn.backward") {
                    WKInterfaceDevice.current().play(.retry)
                    model.store.undoLast()
                }
                .disabled(!model.store.canUndo)

                if model.store.canEndSession {
                    if hasResults {
                        action("Finish & save", systemImage: "stop.circle", tint: .red) {
                            confirming = .finish
                        }
                    }

                    action(hasResults ? "Discard" : "Call it off", systemImage: "trash", tint: .red) {
                        confirming = .discard
                    }
                } else {
                    // Somebody else's match: step off it rather than end it for them.
                    action("Leave", systemImage: "rectangle.portrait.and.arrow.right") {
                        WKInterfaceDevice.current().play(.click)
                        model.store.leaveSharedSession()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        // `presenting:` hands the pending action to the builder, so the button closure
        // captures it. Reading `confirming` inside the action instead would race the
        // dialog's own dismissal, which clears it — and the button would do nothing.
        .confirmationDialog(
            confirming?.question ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { pending in
            Button(
                pending.confirmLabel,
                role: pending == .finish || pending == .discard ? .destructive : nil
            ) {
                perform(pending)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var status: some View {
        Label(
            model.store.isReachable ? "iPhone connected" : "iPhone not reachable",
            systemImage: model.store.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash"
        )
        .font(.system(size: 11))
        .foregroundStyle(model.store.isReachable ? .green : .secondary)
        .padding(.bottom, 2)
    }

    /// A tint paints the label as well as the pill, which on grey reads as a disabled
    /// button — so the plain ones go untinted, the watchOS default the scoreboard uses.
    /// The colours keep theirs: on those the tinted label is the point.
    private func action(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .font(.footnote)
    }

    private func perform(_ action: Confirmation) {
        switch action {
        case .endRound:
            WKInterfaceDevice.current().play(.success)
            model.store.endRound()
        case .nextRound:
            WKInterfaceDevice.current().play(.success)
            if case .tournament(let tournament)? = model.store.state,
               let round = tournament.currentRound {
                model.store.setRoundConfirmed(round.index, true)
            }
            model.store.nextRound()
        case .finish:
            WKInterfaceDevice.current().play(.success)
            model.finishSession()
        case .discard:
            WKInterfaceDevice.current().play(.success)
            model.discard()
        }
        confirming = nil
    }

    private var hasResults: Bool { model.store.state?.hasResults ?? false }

    private var isWinnerCourt: Bool {
        if case .winnerCourt? = model.store.state { return true }
        return false
    }

    private var isTournament: Bool {
        if case .tournament? = model.store.state { return true }
        return false
    }
}
