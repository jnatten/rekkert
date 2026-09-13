import RekkertCore
import SwiftUI

/// The watch's curtain call: how it finished, and a way to clear it.
struct WatchResultView: View {
    @Environment(AppModel.self) private var model
    let state: SessionState

    private var result: SessionResult { SessionResult.make(from: state) }
    private var tint: Color { result.winningSide.map(Color.team) ?? .gray }

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
            }
            .padding(.horizontal, 4)
        }
    }
}
