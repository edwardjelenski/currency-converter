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

    // MARK: Reads

    func firstDate() async throws -> RateDate? {
        let row = try await sql.raw("SELECT MIN(date) AS first FROM rates").first()
        return try row?.decode(column: "first", as: String?.self).flatMap { RateDate($0) }
    }

    /// The latest publication day on or before `date`.
    func latestDate(onOrBefore date: RateDate) async throws -> RateDate? {
        let row = try await sql.raw("SELECT MAX(date) AS latest FROM rates WHERE date <= \(bind: date.description)").first()
        return try row?.decode(column: "latest", as: String?.self).flatMap { RateDate($0) }
    }

    /// EUR-based rates published on `date`.
    func rates(on date: RateDate) async throws -> [String: Decimal] {
        let rows = try await sql.select()
            .columns("currency", "rate")
            .from(Self.table)
            .where("date", .equal, date.description)
            .all()
        return try Dictionary(uniqueKeysWithValues: rows.map { row in
            (try row.decode(column: "currency", as: String.self), try Self.decimal(row))
        })
    }

    /// EUR-based rates per day in `start...end`, optionally only for `currencies`.
    func rates(from start: RateDate, through end: RateDate, currencies: [String]?) async throws -> [RateDate: [String: Decimal]] {
        let query = sql.select()
            .columns("date", "currency", "rate")
            .from(Self.table)
            .where("date", .greaterThanOrEqual, start.description)
            .where("date", .lessThanOrEqual, end.description)
        if let currencies {
            query.where("currency", .in, currencies)
        }
        var result: [RateDate: [String: Decimal]] = [:]
        for row in try await query.all() {
            let dateText = try row.decode(column: "date", as: String.self)
            guard let date = RateDate(dateText) else { continue }
            result[date, default: [:]][try row.decode(column: "currency", as: String.self)] = try Self.decimal(row)
        }
        return result
    }

    /// Code → name for every currency we have ever stored.
    func currencyNames() async throws -> [String: String] {
        let currencies = try await CurrencyModel.query(on: database).all()
        return Dictionary(uniqueKeysWithValues: currencies.compactMap { model in model.id.map { ($0, model.name) } })
    }

    private static func decimal(_ row: any SQLRow) throws -> Decimal {
        let text = try row.decode(column: "rate", as: String.self)
        guard let value = Decimal(rateText: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Stored rate '\(text)' is not a decimal"))
        }
        return value
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
