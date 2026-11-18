import Fluent

struct CreateSyncRuns: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(SyncRun.schema)
            .field("id", .int, .identifier(auto: true))
            .field("trigger", .string, .required)
            .field("status", .string, .required)
            .field("started_at", .datetime, .required)
            .field("finished_at", .datetime)
            .field("range_start", .string)
            .field("range_end", .string)
            .field("dates_added", .int, .required)
            .field("latest_rate_date", .string)
            .field("error", .string)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(SyncRun.schema).delete()
    }
}
