import RekkertCore
import SwiftUI

/// Laid out for a 1080p TV and scaled from there, so an iPad gets the same board smaller
/// rather than a different one. Dynamic Type has no say: this is read from across a hall.
struct BoardMetrics {
    let size: CGSize

    var unit: CGFloat { min(max(size.width, size.height) / 1920, min(size.width, size.height) / 1080) }
    var isLandscape: Bool { size.width >= size.height * 1.15 }
    var margin: CGFloat { 40 * unit }

    func font(_ points: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: points * unit, weight: weight, design: .rounded)
    }
}

struct BoardView: View {
    @Environment(\.teamPalette) private var palette
    let board: TVBoard

    var body: some View {
        GeometryReader { geometry in
            let metrics = BoardMetrics(size: geometry.size)
            VStack(spacing: 28 * metrics.unit) {
                if board.content != .idle {
                    header(metrics)
                }
                content(metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(metrics.margin)
            .foregroundStyle(.white)
        }
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(_ metrics: BoardMetrics) -> some View {
        switch board.content {
        case .idle:
            idle(metrics)
        case .waiting:
            waiting(metrics)
        case .match(let court):
            BoardMatchView(board: board, court: court, metrics: metrics)
        case .courts(let courts):
            BoardCourtsView(board: board, courts: courts, metrics: metrics)
        case .result(let result):
            self.result(result, metrics: metrics)
        }
    }

    private func header(_ metrics: BoardMetrics) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20 * metrics.unit) {
            Image(systemName: board.symbol)
                .foregroundStyle(.white.opacity(0.6))
            Text(board.title == board.mode ? board.title : "\(board.mode) · \(board.title)")
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer(minLength: 24 * metrics.unit)

            if !board.detail.isEmpty {
                Text(board.detail)
                    .foregroundStyle(isSuddenDeath ? Color.orange : .white.opacity(0.75))
                    .lineLimit(1)
            }
            if let start = board.clockStart {
                Text(timerInterval: min(start, Date()) ... .distantFuture, countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 20 * metrics.unit)
                    .padding(.vertical, 6 * metrics.unit)
                    .background(.white.opacity(0.12), in: .capsule)
                    .fixedSize()
            }
        }
        .font(metrics.font(44))
    }

    private var isSuddenDeath: Bool {
        guard case .match(let court) = board.content else { return false }
        return court.isSuddenDeath
    }

    private func idle(_ metrics: BoardMetrics) -> some View {
        VStack(spacing: 24 * metrics.unit) {
            Image(systemName: "sportscourt")
                .font(metrics.font(120, .regular))
                .foregroundStyle(.white.opacity(0.5))
            Text("Rekkert")
                .font(metrics.font(110, .heavy))
            Text("The score shows up here as soon as a match starts.")
                .font(metrics.font(36, .medium))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    private func waiting(_ metrics: BoardMetrics) -> some View {
        HStack(spacing: 32 * metrics.unit) {
            VStack(spacing: 20 * metrics.unit) {
                Image(systemName: "dice")
                    .font(metrics.font(100, .regular))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Waiting for the draw")
                    .font(metrics.font(64, .bold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if metrics.isLandscape, !board.standings.isEmpty {
                BoardStandings(standings: board.standings, metrics: metrics)
                    .frame(width: metrics.size.width * 0.28)
            }
        }
    }

    private func result(_ result: SessionResult, metrics: BoardMetrics) -> some View {
        HStack(spacing: 32 * metrics.unit) {
            VStack(spacing: 20 * metrics.unit) {
                Image(systemName: symbol(for: result.outcome))
                    .font(metrics.font(110, .regular))
                    .foregroundStyle(result.winningSide.map { palette.color($0) } ?? .white.opacity(0.7))
                Text(result.headline)
                    .font(metrics.font(96, .heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if !result.score.isEmpty {
                    Text(result.score)
                        .font(metrics.font(80, .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let detail = result.detail {
                    Text(detail)
                        .font(metrics.font(38, .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !result.placings.isEmpty {
                BoardStandings(standings: result.placings, metrics: metrics, title: "Final standings")
                    .frame(width: metrics.size.width * (metrics.isLandscape ? 0.34 : 0.45))
            }
        }
    }

    private func symbol(for outcome: SessionResult.Outcome) -> String {
        switch outcome {
        case .won: "trophy.fill"
        case .drawn: "equal.circle.fill"
        case .stopped: "flag.checkered"
        }
    }
}
