import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// The upstream is down, slow or returns garbage: stored rates must stay intact.
@Suite(.serialized)
struct UpstreamFailureTests {
    let wednesdayEvening = berlinTime(2026, 11, 18, 17)

    /// Stores rates up to Tuesday 2026-11-17 and returns a clock set to Wednesday evening.
    private func seedThroughTuesday(_ app: Application) async throws -> TestClock {
        let clock = TestClock(berlinTime(2026, 11, 17, 17))
        let upstream = StubUpstream(days: weekdayRates(from: date("2026-11-01"), through: date("2026-11-17")))
        try await makeService(app: app, upstream: upstream, clock: clock, backfillDays: 30).sync(trigger: .startup)
        clock.set(wednesdayEvening)
        return clock
    }

    private func frankfurter(_ app: Application, _ responses: [(HTTPStatus, String)], calls: Counter) -> FrankfurterSource {
        var source = FrankfurterSource(
            client: StubClient(eventLoop: app.eventLoopGroup.next(), responses: responses, calls: calls),
            baseURL: "https://upstream.test/v1/",
            logger: app.logger
        )
        source.retryDelay = .zero
        return source
    }

    private func service(_ app: Application, _ source: any UpstreamRatesSource, _ clock: TestClock) -> RatesSyncService {
        RatesSyncService(database: { app.db }, upstream: source, backfillDays: 30, timeZone: berlin, now: { clock.now }, logger: app.logger)
    }

    private func snapshot(_ app: Application) async throws -> [RateDate: [String: Decimal]] {
        try await RatesStore(database: app.db).rates(from: date("2026-01-01"), through: date("2026-12-31"), currencies: nil)
    }

    private func lastRun(_ app: Application) async throws -> SyncRun {
        try #require(try await SyncRun.query(on: app.db).sort(\.$id, .descending).first())
    }

    @Test(arguments: [
        "<html><body>502 Bad Gateway</body></html>",
        "{\"rates\": \"oops\"}",
        "",
    ])
    func malformedBodyFailsWithoutTouchingData(body: String) async throws {
        try await withApp(configure: configureForTests) { app in
            let clock = try await seedThroughTuesday(app)
            let before = try await snapshot(app)
            let source = frankfurter(app, [(.ok, body)], calls: Counter())

            await #expect(throws: (any Error).self) { try await service(app, source, clock).sync(trigger: .scheduled) }

            #expect(try await snapshot(app) == before)
            #expect(try await lastRun(app).status == .failed)
        }
    }

    @Test(arguments: [
        #"{"rates":{"2026-11-18":{"USD":-1.0968}}}"#,
        #"{"rates":{"2026-11-18":{"USD":0}}}"#,
        #"{"rates":{"2026-11-18":{}}}"#,
        #"{"rates":{"2026-11-18":{"usd!":1.1}}}"#,
        #"{"rates":{"2031-01-01":{"USD":1.1}}}"#,
    ])
    func implausibleRatesAreRejected(body: String) async throws {
        try await withApp(configure: configureForTests) { app in
            let clock = try await seedThroughTuesday(app)
            let before = try await snapshot(app)

            await #expect(throws: UpstreamDataError.self) {
                try await service(app, frankfurter(app, [(.ok, body)], calls: Counter()), clock).sync(trigger: .scheduled)
            }

            #expect(try await snapshot(app) == before)
            let run = try await lastRun(app)
            #expect(run.status == .failed)
            #expect(run.error?.hasPrefix("Upstream returned") == true)
        }
    }

    @Test func oneBadDayRejectsTheWholeBatch() async throws {
        try await withApp(configure: configureForTests) { app in
            let clock = try await seedThroughTuesday(app)
            clock.set(berlinTime(2026, 11, 20, 17)) // Friday: Wed, Thu, Fri are missing
            let upstream = StubUpstream(days: [
                DailyRates(date: date("2026-11-18"), rates: ["USD": 1.1]),
                DailyRates(date: date("2026-11-19"), rates: ["USD": 0]),
                DailyRates(date: date("2026-11-20"), rates: ["USD": 1.2]),
            ])

            await #expect(throws: UpstreamDataError.self) { try await service(app, upstream, clock).sync(trigger: .scheduled) }

            #expect(try await RatesStore(database: app.db).latestDate() == date("2026-11-17"))
        }
    }

    @Test func serverErrorsAreRetriedThenRecorded() async throws {
        try await withApp(configure: configureForTests) { app in
            let clock = try await seedThroughTuesday(app)
            let before = try await snapshot(app)
            let calls = Counter()

            await #expect(throws: FrankfurterSource.SourceError.self) {
                try await service(app, frankfurter(app, [(.badGateway, "")], calls: calls), clock).sync(trigger: .scheduled)
            }

            #expect(calls.count == 3)
            #expect(try await snapshot(app) == before)
            #expect(try await lastRun(app).error == "Frankfurter 2026-11-18..2026-11-18?base=EUR responded 502")
        }
    }

    @Test func transientErrorRecoversOnRetry() async throws {
        try await withApp(configure: configureForTests) { app in
            let clock = try await seedThroughTuesday(app)
            let calls = Counter()
            let body = #"{"rates":{"2026-11-18":{"USD":1.0968,"GBP":0.8329,"JPY":174.85}}}"#

            let outcome = try await service(app, frankfurter(app, [(.init(statusCode: 522), ""), (.ok, body)], calls: calls), clock)
                .sync(trigger: .scheduled)

            #expect(calls.count == 2)
            #expect(outcome.datesAdded == 1)
            #expect(try await RatesStore(database: app.db).rate(on: date("2026-11-18"), currency: "USD") == "1.0968")
        }
    }

    @Test func notFoundMeansNothingPublishedYet() async throws {
        try await withApp(configure: configureForTests) { app in
            let clock = try await seedThroughTuesday(app)
            let outcome = try await service(app, frankfurter(app, [(.notFound, #"{"message":"not found"}"#)], calls: Counter()), clock)
                .sync(trigger: .scheduled)

            #expect(outcome.status == .noNewData)
            #expect(try await lastRun(app).status == .noNewData)
        }
    }
}
