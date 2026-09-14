import RekkertCore
import SwiftUI

/// The curtain call. A finished session used to vanish the instant the last point landed,
/// dropping straight back to the start screen with no word of how it went.
struct MatchResultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.teamPalette) private var palette
    let state: SessionState

    private var result: SessionResult { SessionResult.make(from: state) }
    private var tint: Color { result.winningSide.map(palette.color) ?? .accentColor }

    private var symbol: String {
        switch result.outcome {
        case .won: "trophy.fill"
        case .drawn: "equal.circle.fill"
        case .stopped: "flag.checkered"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.35), tint.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    banner
                    if !result.placings.isEmpty { placings }
                }
                .padding(.horizontal)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
    }

    private var banner: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(result.headline)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)

            if !result.score.isEmpty {
                Text(result.score)
                    .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            if let detail = result.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var placings: some View {
        VStack(spacing: 0) {
            ForEach(result.placings) { placing in
                HStack(spacing: 12) {
                    Text("\(placing.rank)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(placing.name)
                        .fontWeight(placing.rank == 1 ? .semibold : .regular)
                    Spacer()
                    Text(placing.value)
                        .font(.callout.bold().monospacedDigit())
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                if placing.id != result.placings.last?.id {
                    Divider().padding(.leading, 50)
                }
            }
        }
        .background(.thinMaterial, in: .rect(cornerRadius: 14))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                model.store.acknowledgeResult()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint)

            if let rewind = model.store.resultRewind {
                Button(
                    rewind.undoesAPoint ? "Undo last point" : "Back to the match",
                    systemImage: "arrow.uturn.backward"
                ) {
                    model.store.undoResult()
                }
                .font(.callout)
            }

            if model.keepsFinishedSessions {
                Text(model.store.resultRewind == nil
                     ? "Saved to History."
                     : "Saved to History — undoing takes it back out.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }
}
