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
            try await refreshCurrencyNamesIfNeeded(store)

            let fetched = try await upstream.rates(from: start, to: today)
            // Reject the whole batch before writing anything if the source sent garbage.
            try Self.validate(fetched, requested: start...today)
            // Defensive: a source might not honour the range; never rewrite stored days.
            let newDays = fetched.filter { day in latest.map { day.date > $0 } ?? true }
            let newLatest = newDays.last?.date ?? latest
            let status: SyncRun.Status = newDays.isEmpty ? .noNewData : .success
            // Rates and the run's outcome are committed together.
            let (written, storedDays) = try await db.transaction { tx in
                let txStore = RatesStore(database: tx)
                try await txStore.ensureCurrencies(Set(newDays.flatMap(\.rates.keys)))
                let written = try await txStore.upsert(days: newDays)
                try await finish(run, status: status, datesAdded: newDays.count, latest: newLatest, on: tx)
                return (written, try await txStore.storedDaysCount())
            }

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
            if error is CancellationError || Task.isCancelled {
                // Shutdown, not an upstream problem: don't make /health "degraded".
                run.error = "Interrupted: the server stopped during this sync"
                try? await finish(run, status: .interrupted, datesAdded: 0, latest: latest, on: db)
                logger.notice("Sync (\(trigger.rawValue)) interrupted by shutdown")
                throw CancellationError()
            }
            // The full error goes to the log; /health shows only a safe summary.
            run.error = Self.publicDescription(of: error)
            try? await finish(run, status: .failed, datesAdded: 0, latest: latest, on: db)
            logger.error("Sync (\(trigger.rawValue)) failed for \(start)...\(today): \(String(reflecting: error))")
            throw error
        }
    }

    /// Short, non-sensitive description for `/health` (no hosts, paths or SQL).
    static func publicDescription(of error: any Error) -> String {
        switch error {
        case let error as UpstreamDataError: error.description
        case let error as FrankfurterSource.SourceError: error.description
        case is DecodingError: "Upstream returned data that isn't valid rates JSON"
        default: "Upstream request failed"
        }
    }

    /// Names are cosmetic: fetch them when missing (first run, or a currency stored with its
    /// code as a placeholder name), and never fail the sync over them.
    private func refreshCurrencyNamesIfNeeded(_ store: RatesStore) async throws {
        var needsNames = try await store.currencyCount() == 0
        if !needsNames {
            needsNames = try await store.hasPlaceholderNames()
        }
        guard needsNames else { return }
        do {
            let names = try await upstream.currencies()
            guard !names.isEmpty else {
                logger.warning("Upstream returned no currency names; keeping codes as names")
                return
            }
            try await store.upsert(currencies: names)
            logger.info("Stored \(names.count) currency names")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("Couldn't load currency names, keeping codes as names: \(error)")
        }
    }

    /// What the source returned must look like ECB rates: dates inside the requested
    /// range, 3-letter codes, positive values, no empty days.
    static func validate(_ days: [DailyRates], requested range: ClosedRange<RateDate>) throws {
        for day in days {
            guard range.contains(day.date) else {
                throw UpstreamDataError.dateOutOfRange(day.date, requested: range)
            }
            guard !day.rates.isEmpty else { throw UpstreamDataError.emptyDay(day.date) }
            for (code, rate) in day.rates {
                guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isUppercase }) else {
                    throw UpstreamDataError.invalidCurrency(code, on: day.date)
                }
                guard rate > 0, !rate.isNaN else {
                    throw UpstreamDataError.invalidRate(rate, currency: code, on: day.date)
                }
            }
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

/// The upstream answered, but with data that can't be ECB rates.
enum UpstreamDataError: Error, Equatable, CustomStringConvertible {
    case dateOutOfRange(RateDate, requested: ClosedRange<RateDate>)
    case emptyDay(RateDate)
    case invalidCurrency(String, on: RateDate)
    case invalidRate(Decimal, currency: String, on: RateDate)

    var description: String {
        switch self {
        case let .dateOutOfRange(date, range): "Upstream returned \(date) outside the requested \(range.lowerBound)...\(range.upperBound)"
        case let .emptyDay(date): "Upstream returned no rates for \(date)"
        case let .invalidCurrency(code, date): "Upstream returned an invalid currency code '\(code)' on \(date)"
        case let .invalidRate(rate, code, date): "Upstream returned an invalid rate \(rate) for \(code) on \(date)"
        }
    }
}
