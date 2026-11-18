import Foundation
import Testing
@testable import CurrencyConverter

struct RateHistoryTests {
    let history = makeHistory([
        ("2026-11-12", "1.25"),
        ("2026-11-13", "1.20"),
        ("2026-11-16", "1.60"),
        ("2026-11-17", "1.40"),
        ("2026-11-18", "1.50"),
    ])

    @Test func lowHighAndChangeAreExactDecimals() throws {
        #expect(history.minPoint?.day == "2026-11-13")
        #expect(history.minPoint?.rate == Decimal(string: "1.20"))
        #expect(history.maxPoint?.day == "2026-11-16")
        #expect(history.change == Decimal(string: "0.25"))
        #expect(history.changeRatio == Decimal(string: "0.2")) // 0.25 / 1.25
    }

    @Test func nearestPointSnapsToPublicationDay() {
        // Saturday 14th is closer to Friday 13th than to Monday 16th.
        let saturdayMorning = RateDay.date(from: "2026-11-14")!.addingTimeInterval(3600)
        #expect(history.point(nearest: saturdayMorning)?.day == "2026-11-13")
        let sundayEvening = RateDay.date(from: "2026-11-15")!.addingTimeInterval(20 * 3600)
        #expect(history.point(nearest: sundayEvening)?.day == "2026-11-16")
    }

    @Test func oneDayIsNotChartable() {
        #expect(!makeHistory([("2026-11-18", "1.1")]).isChartable)
        #expect(makeHistory([("2026-11-18", "1.1")]).changeRatio == 0)
        #expect(!makeHistory([]).isChartable)
        #expect(makeHistory([]).change == nil)
    }

    @Test(arguments: [
        (HistoryPeriod.week, "2026-11-11"),
        (.month, "2026-10-18"),
        (.quarter, "2026-08-18"),
        (.year, "2025-11-18"),
    ])
    func periodStart(period: HistoryPeriod, expected: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let end = RateDay.date(from: "2026-11-18", timeZone: calendar.timeZone)!
        let start = period.start(endingOn: end, calendar: calendar)
        #expect(RateDay.string(from: start, timeZone: calendar.timeZone) == expected)
    }

    @Test func rateDayRoundTrip() {
        let date = RateDay.date(from: "2026-03-29")!
        #expect(RateDay.string(from: date) == "2026-03-29")
        #expect(RateDay.date(from: "2026-13-01") == nil)
    }
}
