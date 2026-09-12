import RekkertCore
import SwiftUI
import WatchKit

/// The page to the right of the scoreboard: everything that ends something, kept off the
/// scoring screen so a stray tap cannot finish a round.
struct WatchMenuView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: Confirmation?

    private enum Confirmation: String, Identifiable {
        case endRound, nextRound, finish
        var id: String { rawValue }

        var question: String {
            switch self {
            case .endRound: "End this round?"
            case .nextRound: "Finish the round and draw the next?"
            case .finish: "Finish and save?"
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

                action("Undo", systemImage: "arrow.uturn.backward", tint: .gray) {
                    WKInterfaceDevice.current().play(.retry)
                    model.store.undoLast()
                }
                .disabled(!model.store.canUndo)

                action("Finish & save", systemImage: "stop.circle", tint: .red) {
                    confirming = .finish
                }
            }
            .padding(.horizontal, 2)
        }
        .confirmationDialog(
            confirming?.question ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button(confirmLabel, role: confirming == .finish ? .destructive : nil) { perform() }
            Button("Cancel", role: .cancel) { confirming = nil }
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

    private func action(
        _ title: String,
        systemImage: String,
        tint: Color,
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

    private var confirmLabel: String {
        switch confirming {
        case .endRound: "End round"
        case .nextRound: "Next round"
        case .finish: "Finish"
        case .none: ""
        }
    }

    private func perform() {
        switch confirming {
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
        case .none:
            break
        }
        confirming = nil
    }

    private var isWinnerCourt: Bool {
        if case .winnerCourt? = model.store.state { return true }
        return false
    }

    private var isTournament: Bool {
        if case .tournament? = model.store.state { return true }
        return false
    }
}
