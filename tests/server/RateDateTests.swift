import Foundation
import Testing
@testable import App

struct RateDateTests {
    @Test func parsesAndFormats() {
        #expect(RateDate("2026-11-18")?.description == "2026-11-18")
        #expect(RateDate("2026-02-30") == nil)
        #expect(RateDate("2026-1-18") == nil)
        #expect(RateDate("hello") == nil)
    }

    @Test func addsDaysAcrossMonthsAndYears() {
        #expect(date("2026-01-31").adding(days: 1) == date("2026-02-01"))
        #expect(date("2026-01-01").adding(days: -1) == date("2025-12-31"))
        #expect(date("2026-11-18").adding(days: -365) == date("2025-11-18"))
    }

    @Test func weekdays() {
        #expect(date("2026-11-18").isWeekday)  // Wednesday
        #expect(!date("2026-11-21").isWeekday) // Saturday
        #expect(!date("2026-11-22").isWeekday) // Sunday
        #expect(!RateDate.containsWeekday(from: date("2026-11-21"), through: date("2026-11-22")))
        #expect(RateDate.containsWeekday(from: date("2026-11-21"), through: date("2026-11-23")))
    }

    @Test func todayIsDecidedInBerlin() {
        // 23:30 UTC on the 18th is already the 19th in Berlin.
        let lateEvening = Date(timeIntervalSince1970: 1_795_044_600) // 2026-11-18T23:30:00Z
        #expect(RateDate(lateEvening, in: berlin) == date("2026-11-19"))
        #expect(RateDate(lateEvening, in: TimeZone(identifier: "UTC")!) == date("2026-11-18"))
    }
}
