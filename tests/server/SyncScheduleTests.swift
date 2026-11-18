import Foundation
import Testing
@testable import App

struct SyncScheduleTests {
    let schedule = SyncSchedule()

    @Test func weekdayMorningWaitsForFirstAttempt() {
        let next = schedule.nextAttempt(after: berlinTime(2026, 11, 18, 10), hasRatesForToday: false)
        #expect(next == berlinTime(2026, 11, 18, 16, 15))
    }

    @Test func retriesEveryThirtyMinutesWhileRatesAreMissing() {
        let next = schedule.nextAttempt(after: berlinTime(2026, 11, 18, 16, 15), hasRatesForToday: false)
        #expect(next == berlinTime(2026, 11, 18, 16, 45))
    }

    @Test func givesUpAfterSevenAndTriesNextWeekday() {
        let next = schedule.nextAttempt(after: berlinTime(2026, 11, 18, 18, 50), hasRatesForToday: false)
        #expect(next == berlinTime(2026, 11, 19, 16, 15))
    }

    @Test func todaysRatesStoredMovesToNextWeekday() {
        let next = schedule.nextAttempt(after: berlinTime(2026, 11, 18, 16, 20), hasRatesForToday: true)
        #expect(next == berlinTime(2026, 11, 19, 16, 15))
    }

    @Test func fridaySkipsWeekend() {
        let next = schedule.nextAttempt(after: berlinTime(2026, 11, 20, 17), hasRatesForToday: true)
        #expect(next == berlinTime(2026, 11, 23, 16, 15))
    }

    @Test func saturdayWaitsForMonday() {
        let next = schedule.nextAttempt(after: berlinTime(2026, 11, 21, 12), hasRatesForToday: false)
        #expect(next == berlinTime(2026, 11, 23, 16, 15))
    }

    @Test func attemptTimesFollowBerlinAcrossDaylightSaving() {
        // Winter: 16:15 CET is 15:15 UTC. Summer (after 2026-03-29): 16:15 CEST is 14:15 UTC.
        let winter = schedule.nextAttempt(after: berlinTime(2026, 3, 27, 12), hasRatesForToday: false)
        let summer = schedule.nextAttempt(after: berlinTime(2026, 3, 28, 12), hasRatesForToday: false)
        #expect(winter == Date(timeIntervalSince1970: 1_774_624_500)) // 2026-03-27T15:15:00Z
        #expect(summer == Date(timeIntervalSince1970: 1_774_880_100)) // 2026-03-30T14:15:00Z
    }

    @Test func dayHasSixAttempts() {
        let times = schedule.attempts(on: berlinTime(2026, 11, 18, 0))
        #expect(times.count == 6) // 16:15 … 18:45
        #expect(times.last == berlinTime(2026, 11, 18, 18, 45))
    }
}
