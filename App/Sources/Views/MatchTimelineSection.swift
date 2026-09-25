import Charts
import RekkertCore
import SwiftUI

/// A filed match told over time: who was on top, and what the heart was doing meanwhile. Two
/// charts on one clock rather than one chart with two scales, and a drag across either reads
/// both at that moment.
struct MatchTimelineSection: View {
    let record: HistoryRecord
    let timeline: MatchTimeline
    let series: WorkoutSeries?

    var body: some View {
        if case .tournament(let tournament) = record.state {
            if let series { TournamentHeart(tournament: tournament, timeline: timeline, series: series) }
        } else {
            PointByPoint(record: record, timeline: timeline, series: series)
        }
    }
}

// MARK: - Two sides

private struct PointByPoint: View {
    @Environment(\.teamPalette) private var palette
    let record: HistoryRecord
    let timeline: MatchTimeline
    let series: WorkoutSeries?

    @State private var round = 0
    @State private var selected: Date?

    /// A friendly's rounds are played by different pairs, so they are read one at a time;
    /// everything else is the same two sides from first point to last.
    private var rounds: [Int] {
        guard case .friendly = record.state else { return [] }
        return Array(Set(timeline.entries.map(\.round))).sorted()
    }

    private var roundFilter: Int? { rounds.isEmpty ? nil : round }
    private var entries: [MatchTimeline.Entry] { timeline.entries(round: roundFilter) }

    private var names: BySide<String> {
        ScoreboardSnapshot.make(from: record.state, round: roundFilter)?.teamNames ?? BySide(a: "Blue", b: "Orange")
    }

    private var leads: [(at: Date, lead: Int)] {
        var last = Date.distantPast
        return timeline.momentum(round: roundFilter).compactMap { step in
            guard let at = step.entry.at else { return nil }
            last = max(last, at)
            return (last, step.lead)
        }
    }

    private var domain: ClosedRange<Date>? {
        guard let first = entries.lazy.compactMap(\.at).first, let last = entries.compactMap(\.at).max() else { return nil }
        return first ... max(last, first.addingTimeInterval(60))
    }

    private var heart: [(at: Date, bpm: Int)] {
        guard let series, let domain else { return [] }
        return (0 ..< series.count).compactMap { index in
            let at = series.startOfStep(index).addingTimeInterval(series.interval / 2)
            guard domain.contains(at), let bpm = series.heartRate[index] else { return nil }
            return (at, bpm)
        }
    }

    var body: some View {
        if let domain, !leads.isEmpty {
            Section {
                if rounds.count > 1 {
                    Picker("Round", selection: $round) {
                        ForEach(rounds, id: \.self) { Text("Round \($0 + 1)").tag($0) }
                    }
                }
                readout
                momentum(domain)
                if !heart.isEmpty { heartRate(domain) }
                Stats(stats: timeline.stats(round: roundFilter), names: names, suddenDeath: suddenDeathName, breaks: countsBreaks)
            } header: {
                Text("Timeline")
            } footer: {
                if series == nil {
                    Text("Start a workout on your watch before you play, and the heart rate goes here too.")
                }
            }
            .onAppear { round = rounds.last ?? 0 }
        }
    }

    // MARK: Readout

    private var readout: some View {
        Group {
            if let selected, let entry = entries.last(where: { ($0.at ?? .distantPast) <= selected }) {
                HStack(spacing: 6) {
                    Text(selected, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                    Text(score(of: entry.board)).fontWeight(.semibold)
                    if let bpm = bpm(at: selected) {
                        Text(WorkoutFormat.beats(Double(bpm))).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Drag across to see the score at any moment.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func score(of board: MatchTimeline.Board) -> String {
        let games = (board.sets + (board.games.map { [$0] } ?? [])).map { "\($0.a)–\($0.b)" }
        return (games + ["\(board.points.a)–\(board.points.b)"]).joined(separator: "  ")
    }

    private func bpm(at moment: Date) -> Int? {
        guard let series else { return nil }
        let index = Int(moment.timeIntervalSince(series.start) / series.interval)
        return series.heartRate.indices.contains(index) ? series.heartRate[index] : nil
    }

    // MARK: Momentum

    private func momentum(_ domain: ClosedRange<Date>) -> some View {
        let steps = [(at: domain.lowerBound, lead: 0)] + leads
        let reach = max(2, steps.map { abs($0.lead) }.max() ?? 0)
        let sets = entries.filter { if case .set = $0.ended { true } else if case .match = $0.ended { true } else { false } }
        let games = entries.filter { if case .game = $0.ended { true } else { false } }

        return Chart {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                AreaMark(x: .value("Time", step.at), yStart: .value("Lead", 0), yEnd: .value("Lead", max(step.lead, 0)), series: .value("Side", "a"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(palette.color(.a).opacity(0.5))
                AreaMark(x: .value("Time", step.at), yStart: .value("Lead", 0), yEnd: .value("Lead", min(step.lead, 0)), series: .value("Side", "b"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(palette.color(.b).opacity(0.5))
                LineMark(x: .value("Time", step.at), y: .value("Lead", step.lead), series: .value("Side", "lead"))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            ForEach(Array(games.enumerated()), id: \.offset) { _, entry in
                if let at = entry.at {
                    RuleMark(x: .value("Time", at), yStart: .value("Lead", -Double(reach) * 0.15), yEnd: .value("Lead", Double(reach) * 0.15))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            ForEach(Array(sets.enumerated()), id: \.offset) { _, entry in
                if let at = entry.at, let set = entry.board.sets.last {
                    RuleMark(x: .value("Time", at))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("\(set.a)–\(set.b)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                }
            }
            RuleMark(y: .value("Lead", 0)).foregroundStyle(Color.secondary.opacity(0.5))
            if let selected {
                RuleMark(x: .value("Time", selected)).foregroundStyle(Color.primary.opacity(0.35))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: -Double(reach) ... Double(reach))
        .chartYAxis(.hidden)
        .chartXAxis(heart.isEmpty ? .automatic : .hidden)
        .chartXSelection(value: $selected)
        .overlay(alignment: .topLeading) { sideLabel(.a) }
        .overlay(alignment: .bottomLeading) { sideLabel(.b) }
        .frame(height: 150)
        .padding(.top, 8)
        .accessibilityLabel("Who was ahead")
        .accessibilityValue("\(names.a) led by up to \(max(0, leads.map(\.lead).max() ?? 0)), \(names.b) by up to \(max(0, -(leads.map(\.lead).min() ?? 0)))")
    }

    private func sideLabel(_ side: TeamSide) -> some View {
        HStack(spacing: 4) {
            Circle().fill(palette.color(side)).frame(width: 7, height: 7)
            Text("\(names[side]) ahead")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: Heart rate

    private func heartRate(_ domain: ClosedRange<Date>) -> some View {
        let held = (series?.pauses ?? []).filter { $0.end > domain.lowerBound && $0.start < domain.upperBound }
        return Chart {
            ForEach(Array(held.enumerated()), id: \.offset) { _, pause in
                RectangleMark(xStart: .value("Time", max(pause.start, domain.lowerBound)), xEnd: .value("Time", min(pause.end, domain.upperBound)))
                    .foregroundStyle(Color.secondary.opacity(0.15))
            }
            ForEach(Array(heart.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.at), y: .value("Heart rate", point.bpm))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(.pink)
            }
            if let selected {
                RuleMark(x: .value("Time", selected)).foregroundStyle(Color.primary.opacity(0.35))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .chartXAxis { AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
        .chartXSelection(value: $selected)
        .frame(height: 110)
        .accessibilityLabel("Heart rate")
        .accessibilityValue("From \(heart.map(\.bpm).min() ?? 0) to \(heart.map(\.bpm).max() ?? 0) beats per minute")
    }

    private var rules: DeuceRule? {
        switch record.state {
        case .traditional(let session): session.rules.deuceRule
        case .friendly(let session): session.rules.deuceRule
        case .winnerCourt(let session): session.rules.deuceRule
        case .pointCount, .tournament: nil
        }
    }

    private var suddenDeathName: String? {
        switch rules {
        case .goldenPoint: "Golden points"
        case .starPoint: "Star points"
        case .advantage, nil: nil
        }
    }

    private var countsBreaks: Bool {
        if case .pointCount = record.state { false } else { true }
    }
}

/// Side by side, one row a figure, so every number sits under the name it belongs to.
private struct Stats: View {
    @Environment(\.teamPalette) private var palette
    let stats: MatchTimeline.Stats
    let names: BySide<String>
    let suddenDeath: String?
    let breaks: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(TeamSide.allCases, id: \.self) { side in
                    HStack(spacing: 4) {
                        Circle().fill(palette.color(side)).frame(width: 7, height: 7)
                        Text(names[side]).lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .gridColumnAlignment(.trailing)
                }
            }
            row("Points won", stats.pointsWon)
            row("Longest run", stats.longestRun)
            if let suddenDeath, stats.suddenDeathPlayed > 0 {
                row("\(suddenDeath) (\(stats.suddenDeathPlayed))", stats.suddenDeathWon)
            }
            if breaks { row("Breaks", stats.breaks) }
        }
        .padding(.vertical, 4)
    }

    private func row(_ label: String, _ value: BySide<Int>) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text("\(value.a)").monospacedDigit().gridColumnAlignment(.trailing)
            Text("\(value.b)").monospacedDigit().gridColumnAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

// MARK: - Tournament

/// A tournament is too many courts to follow point by point, so it gets the heart rate with
/// each round marked on it — and, when the phone knew who you were, your court's score.
private struct TournamentHeart: View {
    let tournament: Tournament
    let timeline: MatchTimeline
    let series: WorkoutSeries

    private struct Span: Identifiable {
        var id: Int
        var start: Date
        var end: Date
        var label: String
    }

    private var spans: [Span] {
        tournament.rounds.compactMap { round in
            let times = timeline.entries(round: round.index).compactMap(\.at)
            guard let start = round.startedAt ?? times.min(), let end = times.max(), end > start else { return nil }
            return Span(id: round.index, start: start, end: end, label: label(for: round))
        }
    }

    private func label(for round: Round) -> String {
        guard let me = timeline.me, let match = round.matches.first(where: { $0.side(of: me) != nil }),
              let side = match.side(of: me) else { return "R\(round.index + 1)" }
        return "R\(round.index + 1) \(match.state.points[side])–\(match.state.points[side.other])"
    }

    private var domain: ClosedRange<Date>? {
        guard let first = spans.first?.start, let last = spans.map(\.end).max() else { return nil }
        return first ... last
    }

    var body: some View {
        if let domain {
            let heart = (0 ..< series.count).compactMap { index -> (at: Date, bpm: Int)? in
                let at = series.startOfStep(index).addingTimeInterval(series.interval / 2)
                guard domain.contains(at), let bpm = series.heartRate[index] else { return nil }
                return (at, bpm)
            }
            if !heart.isEmpty {
                Section("Heart rate") {
                    Chart {
                        ForEach(spans) { span in
                            RectangleMark(xStart: .value("Time", span.start), xEnd: .value("Time", span.end))
                                .foregroundStyle(Color.secondary.opacity(span.id.isMultiple(of: 2) ? 0.14 : 0.06))
                                .annotation(position: .top, alignment: .leading, spacing: 2) {
                                    Text(span.label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                        }
                        ForEach(Array(heart.enumerated()), id: \.offset) { _, point in
                            LineMark(x: .value("Time", point.at), y: .value("Heart rate", point.bpm))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .foregroundStyle(.pink)
                        }
                    }
                    .chartXScale(domain: domain)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .chartXAxis { AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
                    .frame(height: 140)
                    .padding(.top, 12)
                    .accessibilityLabel("Heart rate, round by round")
                }
            }
        }
    }
}
