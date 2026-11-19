import Foundation

/// A period of the rate history screen.
enum HistoryPeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case week = "1W"
    case month = "1M"
    case quarter = "3M"
    case year = "1Y"

    var id: String { rawValue }

    /// The first day of the period that ends on `end`.
    func start(endingOn end: Date, calendar: Calendar = .current) -> Date {
        let component: (Calendar.Component, Int) = switch self {
        case .week: (.day, -7)
        case .month: (.month, -1)
        case .quarter: (.month, -3)
        case .year: (.year, -1)
        }
        return calendar.date(byAdding: component.0, value: component.1, to: end) ?? end
    }

    /// Short label for the period picker.
    var label: LocalizedStringResource {
        switch self {
        case .week: LocalizedStringResource("1W", comment: "Period picker: one week")
        case .month: LocalizedStringResource("1M", comment: "Period picker: one month")
        case .quarter: LocalizedStringResource("3M", comment: "Period picker: three months")
        case .year: LocalizedStringResource("1Y", comment: "Period picker: one year")
        }
    }

    /// For VoiceOver on the period picker: a standalone name ("1 week" alone reads wrong
    /// in Russian, where `displayName` is inflected for "за 1 неделю").
    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .week: LocalizedStringResource("One week", comment: "VoiceOver label of the 1W period")
        case .month: LocalizedStringResource("One month", comment: "VoiceOver label of the 1M period")
        case .quarter: LocalizedStringResource("Three months", comment: "VoiceOver label of the 3M period")
        case .year: LocalizedStringResource("One year", comment: "VoiceOver label of the 1Y period")
        }
    }

    /// Full name, as in "over 1 month".
    var displayName: String {
        switch self {
        case .week: String(localized: "1 week", comment: "History period, used in 'over 1 week'")
        case .month: String(localized: "1 month", comment: "History period, used in 'over 1 month'")
        case .quarter: String(localized: "3 months", comment: "History period, used in 'over 3 months'")
        case .year: String(localized: "1 year", comment: "History period, used in 'over 1 year'")
        }
    }
}

/// One publication day on the chart.
struct RatePoint: Identifiable, Hashable, Sendable {
    /// `yyyy-MM-dd` as sent by the server.
    let day: String
    /// Local midnight of `day`, for the chart's x axis.
    let date: Date
    /// Units of the target currency per 1 unit of the base.
    let rate: Decimal

    var id: String { day }

    /// Swift Charts plots only `Double`; this is used for drawing, never for money.
    var plotValue: Double { NSDecimalNumber(decimal: rate).doubleValue }
}

/// How one currency moved against another over a period.
struct RateHistory: Hashable, Sendable {
    let base: String
    let target: String
    /// Oldest first.
    let points: [RatePoint]

    var first: RatePoint? { points.first }
    var last: RatePoint? { points.last }
    var minPoint: RatePoint? { points.min { $0.rate < $1.rate } }
    var maxPoint: RatePoint? { points.max { $0.rate < $1.rate } }

    /// `last − first`.
    var change: Decimal? {
        guard let first, let last else { return nil }
        return last.rate - first.rate
    }

    /// `(last − first) / first`, as a fraction (0.0123 = +1.23 %).
    var changeRatio: Decimal? {
        guard let first, let change, first.rate != 0 else { return nil }
        return change / first.rate
    }

    /// A line needs at least two days.
    var isChartable: Bool { points.count >= 2 }

    /// The publication day closest to `date` (for drag selection).
    func point(nearest date: Date) -> RatePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

enum RateDay {
    /// `yyyy-MM-dd` in the user's calendar day.
    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
    }

    /// Local midnight of a `yyyy-MM-dd` day.
    static func date(from string: String, timeZone: TimeZone = .current) -> Date? {
        try? Date(string, strategy: Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
    }
}
