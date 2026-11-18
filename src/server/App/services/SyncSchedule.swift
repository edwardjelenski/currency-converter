import Foundation

/// When to try pulling the day's rates.
///
/// The ECB publishes around 16:00 CET on weekdays (except TARGET holidays).
/// The first attempt is at `firstAttempt`, then every `retryInterval` while today's
/// rates are still missing, with the last attempt before `lastAttemptBefore`.
/// If they never show up, it was a holiday and we wait for the next weekday.
struct SyncSchedule: Sendable {
    var timeZone = TimeZone(identifier: "Europe/Berlin")!
    var firstAttempt = TimeOfDay(hour: 16, minute: 15)
    var retryInterval: TimeInterval = 30 * 60
    var lastAttemptBefore = TimeOfDay(hour: 19, minute: 0)

    /// The next moment a scheduled sync should run, strictly after `now`.
    func nextAttempt(after now: Date, hasRatesForToday: Bool) -> Date {
        let calendar = self.calendar
        let today = calendar.startOfDay(for: now)
        for offset in 0..<8 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            guard !calendar.isDateInWeekend(day) else { continue }
            if offset == 0 && hasRatesForToday { continue }
            if let slot = attempts(on: day).first(where: { $0 > now }) {
                return slot
            }
        }
        preconditionFailure("A week always contains a weekday")
    }

    /// All attempt times on `day`.
    func attempts(on day: Date) -> [Date] {
        let calendar = self.calendar
        guard let first = calendar.date(bySettingHour: firstAttempt.hour, minute: firstAttempt.minute, second: 0, of: day),
              let deadline = calendar.date(bySettingHour: lastAttemptBefore.hour, minute: lastAttemptBefore.minute, second: 0, of: day)
        else { return [] }
        return Array(stride(from: first, to: deadline, by: retryInterval))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
