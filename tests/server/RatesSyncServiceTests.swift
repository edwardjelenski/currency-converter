import Fluent
import Foundation
import Testing
import Vapor
@testable import App

@Suite(.serialized)
struct RatesSyncServiceTests {
    // Wednesday 2026-11-18, after the ECB publication.
    let wednesdayEvening = berlinTime(2026, 11, 18, 17, 0)

    @Test func firstRunBackfillsAYearOfPublicationDays() async throws {
        try await withTestApp { app in
            let today = date("2026-11-18")
            let history = weekdayRates(from: today.adding(days: -400), through: today)
            let upstream = StubUpstream(days: history)
            let service = makeService(app: app, upstream: upstream, clock: TestClock(wednesdayEvening))

            let outcome = try await service.sync(trigger: .startup)

            let expected = history.filter { $0.date >= today.adding(days: -365) }
            #expect(outcome.status == .success)
            #expect(outcome.requestedRange == date("2025-11-18")...today)
            #expect(outcome.datesAdded == expected.count)
            #expect(outcome.storedDays == expected.count)
            #expect(outcome.ratesWritten == expected.count * 3)
            #expect(outcome.latestDate == today)
            #expect(await upstream.currencyRequests == 1)
            #expect(try await CurrencyModel.query(on: app.db).count() == 3)
        }
    }

    @Test func restartCatchesUpOnlyMissedDays() async throws {
        try await withTestApp { app in
            let history = weekdayRates(from: date("2025-11-01"), through: date("2026-11-18"))
            let upstream = StubUpstream(days: history.filter { $0.date <= date("2026-11-13") })
            let clock = TestClock(berlinTime(2026, 11, 13, 17))
            let service = makeService(app: app, upstream: upstream, clock: clock)
            try await service.sync(trigger: .startup)

            // Server was down over the weekend and Monday–Tuesday.
            await upstream.setDays(history)
            clock.set(wednesdayEvening)
            let outcome = try await service.sync(trigger: .startup)

            #expect(outcome.requestedRange == date("2026-11-14")...date("2026-11-18"))
            #expect(outcome.datesAdded == 3) // Mon 16, Tue 17, Wed 18
            #expect(outcome.latestDate == date("2026-11-18"))
            #expect(await upstream.currencyRequests == 1, "Currencies are loaded only once")
        }
    }

    @Test func upToDateDatabaseMakesNoRequest() async throws {
        try await withTestApp { app in
            let upstream = StubUpstream(days: weekdayRates(from: date("2026-11-01"), through: date("2026-11-18")))
            let service = makeService(app: app, upstream: upstream, clock: TestClock(wednesdayEvening), backfillDays: 30)
            try await service.sync(trigger: .startup)
            let requestsBefore = await upstream.requestedRanges.count

            let outcome = try await service.sync(trigger: .scheduled)

            #expect(outcome.status == .noNewData)
            #expect(outcome.requestedRange == nil)
            #expect(await upstream.requestedRanges.count == requestsBefore)
        }
    }

    @Test func weekendAfterFridayMakesNoRequest() async throws {
        try await withTestApp { app in
            let upstream = StubUpstream(days: weekdayRates(from: date("2026-11-01"), through: date("2026-11-13")))
            let clock = TestClock(berlinTime(2026, 11, 13, 17)) // Friday
            let service = makeService(app: app, upstream: upstream, clock: clock, backfillDays: 30)
            try await service.sync(trigger: .startup)

            clock.set(berlinTime(2026, 11, 15, 12)) // Sunday
            let outcome = try await service.sync(trigger: .startup)

            #expect(outcome.requestedRange == nil)
            #expect(await upstream.requestedRanges.count == 1)
        }
    }

    @Test func nothingPublishedYetIsNoNewData() async throws {
        try await withTestApp { app in
            let upstream = StubUpstream(days: weekdayRates(from: date("2026-11-01"), through: date("2026-11-17")))
            let clock = TestClock(berlinTime(2026, 11, 17, 17))
            let service = makeService(app: app, upstream: upstream, clock: clock, backfillDays: 30)
            try await service.sync(trigger: .startup)

            clock.set(berlinTime(2026, 11, 18, 10)) // Wednesday morning, before publication
            let outcome = try await service.sync(trigger: .scheduled)

            #expect(outcome.status == .noNewData)
            #expect(outcome.requestedRange == date("2026-11-18")...date("2026-11-18"))
            #expect(outcome.latestDate == date("2026-11-17"))
        }
    }

    @Test func failureIsRecordedAndKeepsStoredRates() async throws {
        try await withTestApp { app in
            let upstream = StubUpstream(days: weekdayRates(from: date("2026-11-01"), through: date("2026-11-17")))
            let clock = TestClock(berlinTime(2026, 11, 17, 17))
            let service = makeService(app: app, upstream: upstream, clock: clock, backfillDays: 30)
            let before = try await service.sync(trigger: .startup)

            await upstream.setFailure(StubError())
            clock.set(wednesdayEvening)
            await #expect(throws: StubError.self) { try await service.sync(trigger: .scheduled) }

            let lastRun = try #require(try await SyncRun.query(on: app.db).sort(\.$id, .descending).first())
            #expect(lastRun.status == .failed)
            #expect(lastRun.trigger == .scheduled)
            #expect(lastRun.error == "upstream is down")
            #expect(lastRun.finishedAt != nil)
            #expect(try await RatesStore(database: app.db).storedDaysCount() == before.storedDays)
        }
    }

    @Test func ratesAreStoredAsExactDecimalText() async throws {
        try await withTestApp { app in
            let upstream = StubUpstream(days: [
                DailyRates(date: date("2026-11-18"), rates: ["JPY": Decimal(string: "174.85")!, "GBP": Decimal(string: "0.8329")!]),
            ])
            let service = makeService(app: app, upstream: upstream, clock: TestClock(wednesdayEvening), backfillDays: 3)
            try await service.sync(trigger: .startup)

            let store = RatesStore(database: app.db)
            #expect(try await store.rate(on: date("2026-11-18"), currency: "JPY") == "174.85")
            #expect(try await store.rate(on: date("2026-11-18"), currency: "GBP") == "0.8329")
        }
    }

    @Test func upsertOverwritesCorrectedRates() async throws {
        try await withTestApp { app in
            let store = RatesStore(database: app.db)
            let day = date("2026-11-18")
            try await store.upsert(days: [DailyRates(date: day, rates: ["USD": Decimal(string: "1.0968")!])])
            try await store.upsert(days: [DailyRates(date: day, rates: ["USD": Decimal(string: "1.0970")!])])

            #expect(try await store.rate(on: day, currency: "USD") == "1.097")
            #expect(try await store.storedDaysCount() == 1)
        }
    }
}
