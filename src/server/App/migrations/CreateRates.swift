import Fluent
import SQLKit

/// `rates` has no Fluent model: it is written with bulk upserts and read with
/// range queries, both of which are plain SQL (see `RatesStore`).
struct CreateRates: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RatesStore.table)
            .field("date", .string, .required)
            .field("currency", .string, .required)
            // SQLite has no decimal type (REAL is a Double), so the rate is kept
            // as the exact decimal text the ECB published.
            .field("rate", .string, .required)
            .compositeIdentifier(over: "date", "currency")
            .create()

        // Timeseries reads go by currency over a date range.
        try await (database as! any SQLDatabase)
            .create(index: "rates_currency_date")
            .on(RatesStore.table)
            .column("currency")
            .column("date")
            .run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RatesStore.table).delete()
    }
}
