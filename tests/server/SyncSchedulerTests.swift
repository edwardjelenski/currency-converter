import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Runs the real scheduler loop with a fake clock: each "sleep" jumps straight
/// to the scheduled time, so a week of schedule runs in milliseconds.
@Suite(.serialized)
struct SyncSchedulerTests {
    private func runScheduler(
        app: Application,
        startingAt start: Date,
        holidays: Set<RateDate> = [],
        wakeUps limit: Int
    ) async -> FakeSleeper {
        let clock = TestClock(start)
        let sleeper = FakeSleeper(clock: clock, limit: limit)
        let service = RatesSyncService(
            database: { app.db },
            upstream: PublishingUpstream(clock: clock, holidays: holidays),
            backfillDays: 7,
            timeZone: berlin,
            now: { clock.now },
            logger: app.logger
        )
        let scheduler = SyncScheduler(service: service, schedule: SyncSchedule(), logger: app.logger) { target, _ in
            try sleeper.sleep(until: target)
        }
        await scheduler.runLoop()
        return sleeper
    }

    @Test(arguments: [
        // Spring forward on Sun 2026-03-29: Monday's 16:15 CEST is 14:15 UTC.
        (berlinTime(2026, 3, 27, 17), Date(timeIntervalSince1970: 1_774_880_100), date("2026-03-31")),
        // Fall back on Sun 2026-10-25: Monday's 16:15 CET is 15:15 UTC.
        (berlinTime(2026, 10, 23, 17), Date(timeIntervalSince1970: 1_793_027_700), date("2026-10-27")),
    ])
    func weekendAcrossDaylightSavingChange(fridayEvening: Date, mondayAttempt: Date, expectedLatest: RateDate) async throws {
        try await withApp(configure: configureForTests) { app async throws in
            let sleeper = await runScheduler(app: app, startingAt: fridayEvening, wakeUps: 2)

            #expect(sleeper.wakeUps == [mondayAttempt, mondayAttempt.addingTimeInterval(24 * 3600)])
            #expect(try await RatesStore(database: app.db).latestDate() == expectedLatest)
        }
    }

    @Test func easterHolidaysAreRetriedAndSkipped() async throws {
        // TARGET holidays: Good Friday 2026-04-03 and Easter Monday 2026-04-06.
        let holidays: Set<RateDate> = [date("2026-04-03"), date("2026-04-06")]
        try await withApp(configure: configureForTests) { app async throws in
            let sleeper = await runScheduler(app: app, startingAt: berlinTime(2026, 4, 2, 17), holidays: holidays, wakeUps: 14)

            let retryTimes = [(16, 15), (16, 45), (17, 15), (17, 45), (18, 15), (18, 45)]
            let expected =
                retryTimes.map { berlinTime(2026, 4, 3, $0.0, $0.1) } +   // Good Friday: nothing published
                retryTimes.map { berlinTime(2026, 4, 6, $0.0, $0.1) } +   // Easter Monday: nothing published
                [berlinTime(2026, 4, 7, 16, 15), berlinTime(2026, 4, 8, 16, 15)]
            #expect(sleeper.wakeUps == expected)

            let store = RatesStore(database: app.db)
            #expect(try await store.latestDate() == date("2026-04-08"))
            #expect(try await store.rates(on: date("2026-04-03")).isEmpty)
            #expect(try await store.rates(on: date("2026-04-06")).isEmpty)

            let scheduled = try await SyncRun.query(on: app.db).filter(\.$trigger == .scheduled).all()
            #expect(scheduled.filter { $0.status == .noNewData }.count == 12)
            #expect(scheduled.filter { $0.status == .success }.count == 2)
        }
    }
}
