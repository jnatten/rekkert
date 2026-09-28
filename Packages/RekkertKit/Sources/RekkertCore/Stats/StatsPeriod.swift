import Foundation

public enum PeriodUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case day
    case week
    case month
    case year

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    public func named(_ count: Int) -> String {
        count == 1 ? rawValue : rawValue + "s"
    }
}

public enum StatsPeriod: Codable, Sendable, Hashable {
    case allTime
    /// Counting today, so the last seven days are today and the six before it.
    case last(Int, PeriodUnit)
    case current(PeriodUnit)
    case previous(PeriodUnit)
    case year(Int)
    case since(Date)
    /// Whole days, both ends included.
    case between(Date, Date)

    /// Nil for all time. Half-open: a match belongs to it if it finished at or after the
    /// start and before the end.
    public func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        switch self {
        case .allTime:
            return nil

        case .last(let count, let unit):
            let back = calendar.date(byAdding: unit.component, value: -max(1, count), to: today) ?? today
            let start = calendar.date(byAdding: .day, value: 1, to: back) ?? back
            return DateInterval(start: start, end: tomorrow)

        case .current(let unit):
            let start = calendar.dateInterval(of: unit.component, for: now)?.start ?? today
            return DateInterval(start: start, end: tomorrow)

        case .previous(let unit):
            guard let current = calendar.dateInterval(of: unit.component, for: now),
                  let before = calendar.dateInterval(of: unit.component, for: current.start.addingTimeInterval(-1))
            else { return nil }
            return before

        case .year(let year):
            guard let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
            return calendar.dateInterval(of: .year, for: date)

        case .since(let date):
            let start = calendar.startOfDay(for: date)
            return DateInterval(start: start, end: max(start, tomorrow))

        case .between(let one, let two):
            let start = calendar.startOfDay(for: min(one, two))
            let last = calendar.startOfDay(for: max(one, two))
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: last) ?? last)
        }
    }

    public var title: String {
        switch self {
        case .allTime: "All time"
        case .last(let count, let unit) where count == 1: "Past \(unit.rawValue)"
        case .last(let count, let unit): "Last \(count) \(unit.named(count))"
        case .current(.day): "Today"
        case .current(.year): "Year to date"
        case .current(let unit): "This \(unit.rawValue)"
        case .previous(.day): "Yesterday"
        case .previous(let unit): "Last \(unit.rawValue)"
        case .year(let year): String(year)
        case .since(let date): "Since \(date.formatted(date: .abbreviated, time: .omitted))"
        case .between(let one, let two):
            "\(min(one, two).formatted(date: .abbreviated, time: .omitted)) – \(max(one, two).formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

extension DateInterval {
    func holds(_ date: Date) -> Bool {
        start <= date && date < end
    }
}
