import Fluent
import Foundation
import SQLKit

/// SQL access to the `rates` and `currencies` tables.
///
/// Rates are written in bulk with `INSERT … ON CONFLICT DO UPDATE` (upsert), which
/// Fluent's model API doesn't offer, so this uses SQLKit on the same connection.
struct RatesStore: Sendable {
    static let table = "rates"
    /// Rows per INSERT; 3 binds per row keeps well under SQLite's variable limit.
    static let batchSize = 300

    let database: any Database

    private var sql: any SQLDatabase { database as! any SQLDatabase }

    func latestDate() async throws -> RateDate? {
        let row = try await sql.raw("SELECT MAX(date) AS latest FROM rates").first()
        return try row?.decode(column: "latest", as: String?.self).flatMap { RateDate($0) }
    }

    func storedDaysCount() async throws -> Int {
        let row = try await sql.raw("SELECT COUNT(DISTINCT date) AS days FROM rates").first()
        return try row?.decode(column: "days", as: Int.self) ?? 0
    }

    func currencyCount() async throws -> Int {
        try await CurrencyModel.query(on: database).count()
    }

    /// Inserts or renames currencies.
    func upsert(currencies: [String: String]) async throws {
        guard !currencies.isEmpty else { return }
        let insert = sql.insert(into: CurrencyModel.schema).columns("code", "name")
        for (code, name) in currencies.sorted(by: { $0.key < $1.key }) {
            insert.values(SQLBind(code), SQLBind(name))
        }
        try await insert
            .onConflict(with: ["code"]) { $0.set(excludedValueOf: "name") }
            .run()
    }

    /// Makes sure every code exists in `currencies`, using the code as a placeholder name.
    func ensureCurrencies(_ codes: Set<String>) async throws {
        guard !codes.isEmpty else { return }
        let insert = sql.insert(into: CurrencyModel.schema).columns("code", "name")
        for code in codes.sorted() {
            insert.values(SQLBind(code), SQLBind(code))
        }
        try await insert.ignoringConflicts(with: ["code"]).run()
    }

    /// Upserts all rates of `days`. Returns the number of rate rows written.
    @discardableResult
    func upsert(days: [DailyRates]) async throws -> Int {
        let rows = days.flatMap { day in
            day.rates.map { (date: day.date.description, currency: $0.key, rate: $0.value.description) }
        }
        var start = rows.startIndex
        while start < rows.endIndex {
            let end = min(start + Self.batchSize, rows.endIndex)
            let insert = sql.insert(into: Self.table).columns("date", "currency", "rate")
            for row in rows[start..<end] {
                insert.values(SQLBind(row.date), SQLBind(row.currency), SQLBind(row.rate))
            }
            try await insert
                .onConflict(with: ["date", "currency"]) { $0.set(excludedValueOf: "rate") }
                .run()
            start = end
        }
        return rows.count
    }

    /// The stored rate text, for tests and diagnostics.
    func rate(on date: RateDate, currency: String) async throws -> String? {
        try await sql.select()
            .column("rate")
            .from(Self.table)
            .where("date", .equal, date.description)
            .where("currency", .equal, currency)
            .first()?
            .decode(column: "rate", as: String.self)
    }
}
