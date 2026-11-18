import Fluent
import Foundation
import Vapor
@testable import App

/// In-memory upstream that records the ranges it was asked for.
actor StubUpstream: UpstreamRatesSource {
    private(set) var days: [DailyRates]
    private(set) var requestedRanges: [ClosedRange<RateDate>] = []
    private(set) var currencyRequests = 0
    var failure: (any Error)?

    let names: [String: String] = ["GBP": "British Pound", "JPY": "Japanese Yen", "USD": "United States Dollar"]

    init(days: [DailyRates]) {
        self.days = days
    }

    func setFailure(_ error: (any Error)?) { failure = error }
    func setDays(_ days: [DailyRates]) { self.days = days }

    func currencies() async throws -> [String: String] {
        currencyRequests += 1
        if let failure { throw failure }
        return names
    }

    func rates(from start: RateDate, to end: RateDate) async throws -> [DailyRates] {
        requestedRanges.append(start...end)
        if let failure { throw failure }
        return days.filter { (start...end).contains($0.date) }
    }
}

struct StubError: Error, CustomStringConvertible {
    var description: String { "upstream is down" }
}

func date(_ string: String) -> RateDate { RateDate(string)! }

/// Weekday rates for every day in `start...end`, with deterministic values.
func weekdayRates(from start: RateDate, through end: RateDate) -> [DailyRates] {
    var result: [DailyRates] = []
    var day = start
    var index = 0
    while day <= end {
        if day.isWeekday {
            result.append(DailyRates(date: day, rates: [
                "USD": Decimal(string: "1.0968")! + Decimal(index) / 10_000,
                "GBP": Decimal(string: "0.8329")!,
                "JPY": Decimal(string: "174.85")!,
            ]))
            index += 1
        }
        day = day.adding(days: 1)
    }
    return result
}

let berlin = TimeZone(identifier: "Europe/Berlin")!

/// A moment given as Berlin wall-clock time.
func berlinTime(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = berlin
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A mutable clock the sync service reads through a `@Sendable` closure.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

/// Boots an app with an in-memory database and no background sync.
func withTestApp(_ body: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
        var config = AppConfig()
        config.databasePath = ":memory:"
        config.syncEnabled = false
        try await configure(app, config: config, upstream: StubUpstream(days: []))
        try await body(app)
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

func makeService(app: Application, upstream: StubUpstream, clock: TestClock, backfillDays: Int = 365) -> RatesSyncService {
    RatesSyncService(
        database: { app.db },
        upstream: upstream,
        backfillDays: backfillDays,
        timeZone: berlin,
        now: { clock.now },
        logger: app.logger
    )
}
