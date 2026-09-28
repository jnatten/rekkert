import RekkertCore
import SwiftUI

struct StatsPeriodMenu: View {
    @Environment(AppModel.self) private var model
    @State private var customizing = false

    private static let presets: [[StatsPeriod]] = [
        [.allTime],
        [.last(7, .day), .last(30, .day), .last(90, .day), .last(12, .month), .last(5, .year)],
        [.current(.week), .current(.month), .current(.year)],
        [.previous(.week), .previous(.month), .previous(.year)],
    ]

    private var years: [Int] {
        let dates = model.allPlayerStats?.people.flatMap(\.appearances).map(\.date) ?? []
        return Set(dates.map { Calendar.current.component(.year, from: $0) }).sorted(by: >)
    }

    private var isPreset: Bool {
        if case .year = model.statsPeriod { return true }
        return Self.presets.joined().contains(model.statsPeriod)
    }

    var body: some View {
        Menu {
            ForEach(Self.presets, id: \.self) { group in
                Section {
                    ForEach(group, id: \.self, content: option)
                }
            }
            if !years.isEmpty {
                Menu("Year") {
                    ForEach(years, id: \.self) { option(.year($0)) }
                }
            }
            Section {
                if !isPreset {
                    option(model.statsPeriod)
                }
                Button("Custom…", systemImage: "slider.horizontal.3") { customizing = true }
            }
        } label: {
            Label(model.statsPeriod.title, systemImage: "calendar")
                .labelStyle(.iconOnly)
        }
        .sheet(isPresented: $customizing) {
            CustomPeriodView(period: model.statsPeriod)
        }
        .task {
            #if DEBUG
            if DemoLaunch.customPeriod { customizing = true }
            #endif
        }
    }

    private func option(_ period: StatsPeriod) -> some View {
        Toggle(isOn: Binding(
            get: { model.statsPeriod == period },
            set: { if $0 { model.statsPeriod = period } }
        )) {
            Text(period.title)
            if let span = period.span, span != period.title {
                Text(span)
            }
        }
    }
}

private struct CustomPeriodView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Kind: Hashable {
        case last
        case since
        case between
    }

    @State private var kind: Kind
    @State private var count: Int
    @State private var unit: PeriodUnit
    @State private var from: Date
    @State private var to: Date

    init(period: StatsPeriod) {
        let today = Date()
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: today) ?? today
        var kind = Kind.last
        var count = 30
        var unit = PeriodUnit.day
        var from = monthAgo
        var to = today
        switch period {
        case .last(let lastCount, let lastUnit):
            count = lastCount
            unit = lastUnit
        case .since(let date):
            kind = .since
            from = date
        case .between(let one, let two):
            kind = .between
            from = min(one, two)
            to = max(one, two)
        case .allTime, .current, .previous, .year:
            break
        }
        _kind = State(initialValue: kind)
        _count = State(initialValue: count)
        _unit = State(initialValue: unit)
        _from = State(initialValue: from)
        _to = State(initialValue: to)
    }

    private var period: StatsPeriod {
        switch kind {
        case .last: .last(max(1, count), unit)
        case .since: .since(from)
        case .between: .between(from, to)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        Text("Last").tag(Kind.last)
                        Text("Since").tag(Kind.since)
                        Text("Between").tag(Kind.between)
                    }
                    .pickerStyle(.segmented)
                }

                switch kind {
                case .last: lastSection
                case .since: sinceSection
                case .between: betweenSection
                }

                Section("Counts") {
                    LabeledContent(period.title, value: period.span ?? "")
                }
            }
            .navigationTitle("Custom period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.statsPeriod = period
                        dismiss()
                    }
                }
            }
        }
    }

    private var lastSection: some View {
        Section {
            HStack {
                TextField("Count", value: $count, format: .number)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                    .fixedSize()
                Text(unit.named(count))
                Spacer()
                Stepper("How many", value: $count, in: 1 ... 9_999)
                    .labelsHidden()
            }
            Picker("Unit", selection: $unit) {
                ForEach(PeriodUnit.allCases, id: \.self) { unit in
                    Text(unit.named(2).capitalized).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Counted back from today, today included.")
        }
    }

    private var sinceSection: some View {
        Section {
            DatePicker("From", selection: $from, in: ...Date(), displayedComponents: .date)
        } footer: {
            Text("Up to and including today, so it keeps growing as you play.")
        }
    }

    private var betweenSection: some View {
        Section {
            DatePicker("From", selection: $from, displayedComponents: .date)
            DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
        } footer: {
            Text("Both days are included.")
        }
    }
}

extension StatsPeriod {
    var span: String? {
        guard let interval = interval() else { return nil }
        let last = interval.end.addingTimeInterval(-1)
        return (interval.start ..< max(interval.start, last)).formatted(.interval.day().month(.abbreviated).year())
    }
}
