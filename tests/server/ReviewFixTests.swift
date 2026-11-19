import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Regression tests for the code review findings (docs/code-review.md, S1–S16).
@Suite(.serialized)
struct ReviewFixTests {
    // MARK: S1 — late SYNC_TIME

    @Test func lateFirstAttemptStillGetsOneSlotAndNeverCrashes() {
        var schedule = SyncSchedule()
        schedule.firstAttempt = TimeOfDay(hour: 19, minute: 30)
        let day = berlinTime(2026, 11, 18, 0)
        #expect(schedule.attempts(on: day) == [berlinTime(2026, 11, 18, 19, 30)])
        #expect(schedule.nextAttempt(after: berlinTime(2026, 11, 18, 20), hasRatesForToday: false) == berlinTime(2026, 11, 19, 19, 30))
    }

    @Test(arguments: ["19:00", "19:30", "23:59", "+9:15", "-0:15", "9", "ab:cd"])
    func invalidSyncTimeIsRejectedAtStartup(value: String) {
        #expect(throws: (any Error).self) { try AppConfig.syncTime(from: value) }
    }

    @Test func validSyncTimeIsAccepted() throws {
        #expect(try AppConfig.syncTime(from: "16:15") == TimeOfDay(hour: 16, minute: 15))
        #expect(try AppConfig.syncTime(from: "18:59") == TimeOfDay(hour: 18, minute: 59))
    }

    // MARK: S2 — retry after a failed sync

    @Test func retryDelaysGrowAndCap() {
        let schedule = SyncSchedule()
        #expect((1...7).map(schedule.retryDelay(afterFailures:)) == [60, 300, 900, 1800, 3600, 3600, 3600])
    }

    @Test func failedStartupSyncIsRetriedWithinAMinute() async throws {
        try await withApp(configure: configureForTests) { app async throws in
            let clock = TestClock(berlinTime(2026, 11, 18, 10)) // Wednesday morning, empty database
            let upstream = FlakyUpstream(failures: 1, wrapped: PublishingUpstream(clock: clock))
            let sleeper = FakeSleeper(clock: clock, limit: 2)
            let service = RatesSyncService(database: { app.db }, upstream: upstream, backfillDays: 7, timeZone: berlin, now: { clock.now }, logger: app.logger)
            let scheduler = SyncScheduler(service: service, schedule: SyncSchedule(), logger: app.logger) { target, _ in
                try sleeper.sleep(until: target)
            }

            await scheduler.runLoop()

            // Before: the next try would have been 16:15. Now: one minute after the failure,
            // then — the backfill succeeded — back to the normal schedule.
            #expect(sleeper.wakeUps == [berlinTime(2026, 11, 18, 10, 1), berlinTime(2026, 11, 18, 16, 15)])
            // The 16:15 wake-up also ran: the 18th (published at 16:00) is stored.
            #expect(try await RatesStore(database: app.db).latestDate() == date("2026-11-18"))
        }
    }

    // MARK: S3, S4 — interrupted syncs

    @Test func runsLeftRunningAreMarkedInterrupted() async throws {
        try await withApp(configure: configureForTests) { app async throws in
            try await seedRates(app)
            try await SyncRun(trigger: .startup, startedAt: .now, range: nil).create(on: app.db) // status running

            try await SyncRun.markInterrupted(on: app.db)

            #expect(try await SyncRun.query(on: app.db).filter(\.$status == .running).count() == 0)
            try await app.testing().test(.GET, "health") { res async throws in
                let body = try res.content.decode(HealthResponse.self, using: EndpointTests.isoDecoder)
                #expect(body.syncInProgress == false)
                #expect(body.status == .ok)
                #expect(body.lastSync?.status == "success", "An interrupted run is not the last result")
            }
        }
    }

    @Test func shutdownDuringSyncIsNotAnUpstreamFailure() async throws {
        try await withApp(configure: configureForTests) { app async throws in
            try await seedRates(app)
            let upstream = StubUpstream(days: [])
            await upstream.setFailure(CancellationError())
            let service = makeService(app: app, upstream: upstream, clock: TestClock(berlinTime(2026, 11, 19, 17)), backfillDays: 30)

            await #expect(throws: CancellationError.self) { try await service.sync(trigger: .scheduled) }

            let last = try #require(try await SyncRun.query(on: app.db).sort(\.$id, .descending).first())
            #expect(last.status == .interrupted)
            try await app.testing().test(.GET, "health") { res async throws in
                #expect(try res.content.decode(HealthResponse.self, using: EndpointTests.isoDecoder).status == .ok)
            }
        }
    }

    @Test func stopWaitsForTheLoopToFinish() async throws {
        try await withApp(configure: configureForTests) { app async throws in
            let clock = TestClock(berlinTime(2026, 11, 18, 17))
            let service = RatesSyncService(database: { app.db }, upstream: PublishingUpstream(clock: clock), backfillDays: 3, timeZone: berlin, now: { clock.now }, logger: app.logger)
            let scheduler = SyncScheduler(service: service, schedule: SyncSchedule(), logger: app.logger) // real sleep

            await scheduler.start()
            await scheduler.stop()

            #expect(await scheduler.nextRunAt == nil)
            #expect(try await SyncRun.query(on: app.db).filter(\.$status == .running).count() == 0)
        }
    }

    // MARK: S5 — currency names

    @Test func placeholderNamesAreRepaired() async throws {
        try await withApp(configure: configureForTests) { app async throws in
            let store = RatesStore(database: app.db)
            try await store.ensureCurrencies(["USD", "GBP"]) // names = codes
            try await store.upsert(days: weekdayRates(from: date("2026-11-10"), through: date("2026-11-17")))
            let upstream = StubUpstream(days: weekdayRates(from: date("2026-11-10"), through: date("2026-11-18")))

            try await makeService(app: app, upstream: upstream, clock: TestClock(berlinTime(2026, 11, 18, 17))).sync(trigger: .scheduled)

            #expect(try await store.currencyNames()["USD"] == "United States Dollar")
            #expect(try await store.hasPlaceholderNames() == false)
        }
    }

    @Test func failingNamesDoNotFailTheSync() async throws {
        try await withApp(configure: configureForTests) { app async throws in
            let upstream = StubUpstream(days: weekdayRates(from: date("2026-11-10"), through: date("2026-11-18")))
            await upstream.setNamesFailure(StubError())

            let outcome = try await makeService(app: app, upstream: upstream, clock: TestClock(berlinTime(2026, 11, 18, 17)), backfillDays: 10)
                .sync(trigger: .startup)

            #expect(outcome.status == .success)
            #expect(try await RatesStore(database: app.db).currencyNames()["USD"] == "USD", "Placeholder until names load")
        }
    }

    // MARK: S9 — no internals in /health

    @Test func publicErrorTextHidesInternals() {
        struct DatabaseError: Error, CustomStringConvertible { var description: String { "SQLITE_ERROR at /data/rates.sqlite: SELECT …" } }
        #expect(RatesSyncService.publicDescription(of: DatabaseError()) == "Upstream request failed")
        #expect(RatesSyncService.publicDescription(of: UpstreamDataError.emptyDay(date("2026-11-18"))) == "Upstream returned no rates for 2026-11-18")
    }

    // MARK: S11 — only `serve` syncs

    @Test(arguments: [
        (["App"], true),
        (["App", "serve"], true),
        (["App", "serve", "--env", "production"], true),
        (["App", "--env", "production"], true),
        (["App", "routes"], false),
        (["App", "migrate", "--yes"], false),
    ])
    func schedulerRunsOnlyForServe(arguments: [String], expected: Bool) {
        #expect(SyncSchedulerLifecycle.isServeCommand(arguments) == expected)
    }

    // MARK: S16 — strict parsing

    @Test(arguments: ["2026-+1-05", "+026-01-05", "2026-01-+5", "2026-1-5"])
    func signedOrShortDatePartsAreRejected(text: String) {
        #expect(RateDate(text) == nil)
    }
}

/// Fails the first `failures` rate requests, then answers like `wrapped`.
actor FlakyUpstream: UpstreamRatesSource {
    private var failures: Int
    private let wrapped: PublishingUpstream

    init(failures: Int, wrapped: PublishingUpstream) {
        self.failures = failures
        self.wrapped = wrapped
    }

    func currencies() async throws -> [String: String] {
        try await wrapped.currencies()
    }

    func rates(from start: RateDate, to end: RateDate) async throws -> [DailyRates] {
        if failures > 0 {
            failures -= 1
            throw StubError()
        }
        return try await wrapped.rates(from: start, to: end)
    }
}
