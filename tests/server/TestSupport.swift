import Fluent
import Foundation
import Vapor
import VaporTesting
@testable import App

/// In-memory upstream that records the ranges it was asked for.
actor StubUpstream: UpstreamRatesSource {
    private(set) var days: [DailyRates]
    private(set) var requestedRanges: [ClosedRange<RateDate>] = []
    private(set) var currencyRequests = 0
    var failure: (any Error)?
    /// Fails only the names request.
    var namesFailure: (any Error)?

    let names: [String: String] = ["GBP": "British Pound", "JPY": "Japanese Yen", "USD": "United States Dollar"]

    init(days: [DailyRates]) {
        self.days = days
    }

    func setFailure(_ error: (any Error)?) { failure = error }
    func setNamesFailure(_ error: (any Error)?) { namesFailure = error }
    func setDays(_ days: [DailyRates]) { self.days = days }

    func currencies() async throws -> [String: String] {
        currencyRequests += 1
        if let failure { throw failure }
        if let namesFailure { throw namesFailure }
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

/// Configures an app with an in-memory database and no background sync.
func configureForTests(_ app: Application) async throws {
    var config = AppConfig()
    config.databasePath = ":memory:"
    config.syncEnabled = false
    try await configure(app, config: config, upstream: StubUpstream(days: []))
}

/// Boots a test app (VaporTesting `withApp`) with an in-memory database and no background sync.
func withTestApp(_ body: (Application) async throws -> Void) async throws {
    try await withApp(configure: configureForTests, body)
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

/// Thread-safe counter for `@Sendable` closures.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    @discardableResult func increment() -> Int { lock.withLock { value += 1; return value } }
    var count: Int { lock.withLock { value } }
}

/// A Vapor `Client` that answers from a script instead of the network.
/// The n-th request gets `responses[n]` (the last one repeats).
struct StubClient: Client {
    let eventLoop: any EventLoop
    let responses: [(HTTPStatus, String)]
    let calls: Counter

    func delegating(to eventLoop: any EventLoop) -> any Client {
        StubClient(eventLoop: eventLoop, responses: responses, calls: calls)
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        let index = min(calls.increment() - 1, responses.count - 1)
        let (status, body) = responses[index]
        return eventLoop.makeSucceededFuture(ClientResponse(status: status, body: ByteBuffer(string: body)))
    }
}

/// An upstream that behaves like the ECB over time: a weekday's rates appear at
/// 16:00 Berlin, never on weekends or `holidays`.
struct PublishingUpstream: UpstreamRatesSource {
    let clock: TestClock
    var holidays: Set<RateDate> = []

    func currencies() async throws -> [String: String] {
        ["GBP": "British Pound", "USD": "United States Dollar"]
    }

    func rates(from start: RateDate, to end: RateDate) async throws -> [DailyRates] {
        var result: [DailyRates] = []
        var day = start
        while day <= end {
            if day.isWeekday, !holidays.contains(day),
               berlinTime(day.year, day.month, day.day, 16) <= clock.now {
                result.append(DailyRates(date: day, rates: ["USD": Decimal(string: "1.1")!, "GBP": Decimal(string: "0.83")!]))
            }
            day = day.adding(days: 1)
        }
        return result
    }
}

/// Replaces `Task.sleep` in `SyncScheduler`: records each wake-up time and jumps
/// the clock there instantly. Throws (like a cancelled sleep) after `limit` wake-ups.
final class FakeSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Date] = []
    let clock: TestClock
    let limit: Int

    init(clock: TestClock, limit: Int) {
        self.clock = clock
        self.limit = limit
    }

    var wakeUps: [Date] { lock.withLock { recorded } }

    func sleep(until target: Date) throws {
        try lock.withLock {
            guard recorded.count < limit else { throw CancellationError() }
            recorded.append(target)
        }
        clock.set(target)
    }
}

/// Rates used by the endpoint tests. 2026-11-18 is a Wednesday; BGN stops after 2025.
func seedRates(_ app: Application) async throws {
    let store = RatesStore(database: app.db)
    try await store.upsert(currencies: [
        "BGN": "Bulgarian Lev", "GBP": "British Pound", "JPY": "Japanese Yen", "USD": "United States Dollar",
    ])
    func day(_ text: String, _ usd: String, _ gbp: String, _ jpy: String, bgn: String? = nil) -> DailyRates {
        var rates = ["USD": Decimal(rateText: usd)!, "GBP": Decimal(rateText: gbp)!, "JPY": Decimal(rateText: jpy)!]
        if let bgn { rates["BGN"] = Decimal(rateText: bgn)! }
        return DailyRates(date: date(text), rates: rates)
    }
    try await store.upsert(days: [
        day("2025-12-31", "1.0389", "0.8297", "162.5", bgn: "1.9558"),
        day("2026-11-12", "1.1081", "0.83595", "176.4"),
        day("2026-11-13", "1.1052", "0.83559", "176.01"),
        day("2026-11-16", "1.1014", "0.8345", "175.32"),
        day("2026-11-17", "1.0981", "0.8335", "175.1"),
        day("2026-11-18", "1.0968", "0.8329", "174.85"),
    ])
    let run = SyncRun(trigger: .startup, startedAt: Date(timeIntervalSince1970: 1_795_015_800), range: date("2025-11-18")...date("2026-11-18"))
    run.status = .success
    run.datesAdded = 6
    run.latestRateDate = "2026-11-18"
    run.finishedAt = Date(timeIntervalSince1970: 1_795_015_802)
    try await run.create(on: app.db)
}

extension TestingHTTPResponse {
    var errorBody: ErrorResponse.Body? {
        (try? content.decode(ErrorResponse.self))?.error
    }
}
