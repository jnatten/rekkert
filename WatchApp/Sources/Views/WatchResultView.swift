import RekkertCore
import SwiftUI
import WatchKit

/// The watch's curtain call: how it finished, and a way to clear it.
struct WatchResultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.teamPalette) private var palette
    let state: SessionState

    private var result: SessionResult { SessionResult.make(from: state) }
    private var tint: Color { result.winningSide.map(palette.color) ?? .gray }

    private var symbol: String {
        switch result.outcome {
        case .won: "trophy.fill"
        case .drawn: "equal.circle.fill"
        case .stopped: "flag.checkered"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)

                Text(result.headline)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)

                if !result.score.isEmpty {
                    Text(result.score)
                        .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                if let detail = result.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Done") { model.store.acknowledgeResult() }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .padding(.top, 4)

                if let rewind = model.store.resultRewind {
                    Button(rewind.undoesAPoint ? "Undo last point" : "Back to it") {
                        WKInterfaceDevice.current().play(.retry)
                        model.store.undoResult()
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
