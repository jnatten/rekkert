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

                // Only when one is actually running. Without it, finishing a match strands
                // a live workout on a screen with no way to end it, and the watch goes in a
                // bag still recording.
                if model.workout.isTracking {
                    WatchWorkoutButton(isMenuRow: false)
                }

                // Below the buttons deliberately: the way out of this screen should not be
                // at the bottom of a table somebody has to scroll past to reach it.
                if !result.placings.isEmpty { placings }
                if !result.rounds.isEmpty { rounds }
            }
            .padding(.horizontal, 4)
        }
    }

    private var placings: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Standings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(result.placings) { placing in
                HStack(spacing: 5) {
                    Text("\(placing.rank)")
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .trailing)
                    Text(placing.name).lineLimit(1)
                    Spacer()
                    Text(placing.value).fontWeight(.semibold)
                }
                .font(.system(size: 12).monospacedDigit())
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rounds: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Rounds")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(result.rounds) { round in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(round.title).foregroundStyle(.secondary)
                        Spacer()
                        Text(round.score).fontWeight(.semibold)
                    }
                    .font(.system(size: 11).monospacedDigit())
                    ForEach(TeamSide.allCases, id: \.self) { side in
                        HStack(spacing: 4) {
                            Circle().fill(palette.color(side)).frame(width: 5, height: 5)
                            Text(round.teams[side]).lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 11))
                    }
                }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
