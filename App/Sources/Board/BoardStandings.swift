import RekkertCore
import SwiftUI

struct BoardStandings: View {
    let standings: [SessionResult.Placing]
    let metrics: BoardMetrics
    var title = "Standings"

    private var unit: CGFloat { metrics.unit }
    private var rowHeight: CGFloat { 50 * unit }
    private var titleHeight: CGFloat { 56 * unit }

    var body: some View {
        GeometryReader { geometry in
            let room = max(0, geometry.size.height - titleHeight)
            let fit = rowHeight > 0 ? Int(room / rowHeight) : 0
            let shown = standings.count > fit ? max(0, fit - 1) : standings.count

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(metrics.font(30))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: titleHeight, alignment: .top)

                ForEach(standings.prefix(shown)) { placing in
                    row(placing)
                        .frame(height: rowHeight)
                }

                if shown < standings.count {
                    Text("+\(standings.count - shown) more")
                        .font(metrics.font(28, .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: rowHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(28 * unit)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 32 * unit, style: .continuous))
    }

    private func row(_ placing: SessionResult.Placing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16 * unit) {
            Text("\(placing.rank)")
                .font(metrics.font(30, .bold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 48 * unit, alignment: .trailing)
            Text(placing.name)
                .font(metrics.font(36))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 8 * unit)
            if let detail = placing.detail {
                Text(detail)
                    .font(metrics.font(26, .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(placing.value)
                .font(metrics.font(38, .bold))
                .lineLimit(1)
                .fixedSize()
        }
        .monospacedDigit()
    }
}
