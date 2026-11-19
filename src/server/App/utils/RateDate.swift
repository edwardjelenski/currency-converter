import Foundation

/// A calendar day in the ECB publication calendar, e.g. `2026-11-18`.
///
/// Stored and transferred as `yyyy-MM-dd` text. It has no time or time zone:
/// "today" is decided by the caller in a specific zone (Europe/Berlin for the ECB).
struct RateDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Parses `yyyy-MM-dd`, rejecting impossible dates like `2026-02-30`.
    init?(_ string: some StringProtocol) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Self.utc.date(from: components),
              Self.utc.dateComponents([.year, .month, .day], from: date) == components
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day that `date` falls on in `timeZone`.
    init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func adding(days: Int) -> RateDate {
        let shifted = Self.utc.date(byAdding: .day, value: days, to: midnightUTC)!
        return RateDate(shifted, in: Self.utc.timeZone)
    }

    /// Monday to Friday. ECB publishes only on these days (minus TARGET holidays).
    var isWeekday: Bool {
        let weekday = Self.utc.component(.weekday, from: midnightUTC)
        return weekday != 1 && weekday != 7
    }

    /// Whether any day in `start...end` is a weekday.
    static func containsWeekday(from start: RateDate, through end: RateDate) -> Bool {
        var day = start
        // At most two consecutive weekend days, so three steps are enough.
        for _ in 0..<3 where day <= end {
            if day.isWeekday { return true }
            day = day.adding(days: 1)
        }
        return false
    }

    static func < (lhs: RateDate, rhs: RateDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private var midnightUTC: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
