import Fluent
import Foundation
import Vapor

/// Pulls rates from the upstream source into SQLite.
///
/// One code path covers every case: it asks only for the days after the latest
/// stored one, so the first run is a backfill (`BACKFILL_DAYS` back from today),
/// a restart after downtime catches up the missed days, and a weekday run picks
/// up today's publication.
struct RatesSyncService: Sendable {
    struct Outcome: Sendable, Equatable {
        let status: SyncRun.Status
        /// `nil` when no request was needed.
        let requestedRange: ClosedRange<RateDate>?
        let datesAdded: Int
        let ratesWritten: Int
        let latestDate: RateDate?
        let storedDays: Int
    }

    let database: @Sendable () -> any Database
    let upstream: any UpstreamRatesSource
    let backfillDays: Int
    /// The ECB's time zone: decides what "today" is.
    let timeZone: TimeZone
    let now: @Sendable () -> Date
    let logger: Logger

    func today() -> RateDate {
        RateDate(now(), in: timeZone)
    }

    func hasRatesForToday() async throws -> Bool {
        try await RatesStore(database: database()).latestDate() == today()
    }

    @discardableResult
    func sync(trigger: SyncRun.Trigger) async throws -> Outcome {
        let db = database()
        let store = RatesStore(database: db)
        let today = today()
        let latest = try await store.latestDate()
        let isBackfill = latest == nil
        let start = latest?.adding(days: 1) ?? today.adding(days: -backfillDays)

        let run = SyncRun(trigger: trigger, startedAt: now(), range: start <= today ? start...today : nil)
        try await run.create(on: db)

        // Nothing can have been published since the latest stored day.
        guard start <= today, RateDate.containsWeekday(from: start, through: today) else {
            let storedDays = try await store.storedDaysCount()
            try await finish(run, status: .noNewData, datesAdded: 0, latest: latest, on: db)
            logger.info("Sync (\(trigger.rawValue)): rates are up to date, latest \(latest?.description ?? "none"), \(storedDays) days in DB")
            return Outcome(status: .noNewData, requestedRange: nil, datesAdded: 0, ratesWritten: 0, latestDate: latest, storedDays: storedDays)
        }

        let mode = isBackfill ? "backfill" : "catch-up"
        logger.info("Sync (\(trigger.rawValue)) started: \(mode) \(start)...\(today)")

        do {
            if try await store.currencyCount() == 0 {
                let names = try await upstream.currencies()
                try await store.upsert(currencies: names)
                logger.info("Stored \(names.count) currencies")
            }

            let newDays = try await upstream.rates(from: start, to: today)
                .filter { latest == nil || $0.date > latest! }
            let written = try await db.transaction { tx in
                let txStore = RatesStore(database: tx)
                try await txStore.ensureCurrencies(Set(newDays.flatMap(\.rates.keys)))
                return try await txStore.upsert(days: newDays)
            }

            let newLatest = newDays.last?.date ?? latest
            let storedDays = try await store.storedDaysCount()
            let status: SyncRun.Status = newDays.isEmpty ? .noNewData : .success
            try await finish(run, status: status, datesAdded: newDays.count, latest: newLatest, on: db)

            if newDays.isEmpty {
                logger.info("Sync (\(trigger.rawValue)) finished: nothing published for \(start)...\(today) yet; \(storedDays) days in DB, latest \(newLatest?.description ?? "none")")
            } else {
                let first = newDays.first!.date, last = newDays.last!.date
                logger.info("Sync (\(trigger.rawValue)) finished: \(mode) added \(newDays.count) days (\(first)...\(last)), \(written) rates; \(storedDays) days in DB, latest \(last)")
            }
            return Outcome(
                status: status,
                requestedRange: start...today,
                datesAdded: newDays.count,
                ratesWritten: written,
                latestDate: newLatest,
                storedDays: storedDays
            )
        } catch {
            run.error = String(describing: error)
            try? await finish(run, status: .failed, datesAdded: 0, latest: latest, on: db)
            logger.error("Sync (\(trigger.rawValue)) failed for \(start)...\(today): \(error)")
            throw error
        }
    }

    private func finish(_ run: SyncRun, status: SyncRun.Status, datesAdded: Int, latest: RateDate?, on db: any Database) async throws {
        run.status = status
        run.datesAdded = datesAdded
        run.latestRateDate = latest?.description
        run.finishedAt = now()
        try await run.update(on: db)
    }
}
