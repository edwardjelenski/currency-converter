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
    /// Pauses before retrying after failed syncs (1st, 2nd, … failure); the last one repeats.
    var failureRetryDelays: [TimeInterval] = [60, 5 * 60, 15 * 60, 30 * 60, 60 * 60]

    /// How long to wait after `consecutiveFailures` failed syncs in a row (≥ 1).
    func retryDelay(afterFailures consecutiveFailures: Int) -> TimeInterval {
        failureRetryDelays[min(max(consecutiveFailures, 1), failureRetryDelays.count) - 1]
    }

    /// The next moment a scheduled sync should run, strictly after `now`.
    func nextAttempt(after now: Date, hasRatesForToday: Bool) -> Date {
        let calendar = self.calendar
        let today = calendar.startOfDay(for: now)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // Saturday (7) and Sunday (1) explicitly: `isDateInWeekend` follows the host's
            // locale, and the ECB's weekend doesn't.
            let weekday = calendar.component(.weekday, from: day)
            guard weekday != 1 && weekday != 7 else { continue }
            if offset == 0 && hasRatesForToday { continue }
            if let slot = attempts(on: day).first(where: { $0 > now }) {
                return slot
            }
        }
        // Unreachable with a valid schedule (a week has weekdays and each has ≥ 1 attempt);
        // never crash the server over it.
        return now.addingTimeInterval(24 * 3600)
    }

    /// All attempt times on `day`.
    func attempts(on day: Date) -> [Date] {
        let calendar = self.calendar
        guard let first = calendar.date(bySettingHour: firstAttempt.hour, minute: firstAttempt.minute, second: 0, of: day),
              let deadline = calendar.date(bySettingHour: lastAttemptBefore.hour, minute: lastAttemptBefore.minute, second: 0, of: day)
        else { return [] }
        // At least the first attempt, even if the configured time is past the cut-off.
        return first < deadline ? Array(stride(from: first, to: deadline, by: retryInterval)) : [first]
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
