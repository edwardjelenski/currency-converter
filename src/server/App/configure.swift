import Fluent
import FluentSQLiteDriver
import Foundation
import SQLKit
import Vapor

/// Sets up the database, migrations and background sync.
/// `upstream` replaces the real Frankfurter source in tests.
func configure(
    _ app: Application,
    config: AppConfig,
    upstream: (any UpstreamRatesSource)? = nil
) async throws {
    app.http.server.configuration.hostname = config.hostname
    app.http.server.configuration.port = config.port

    // Middleware: access log with final status, our error format instead of Vapor's
    // default, then ETag / 304.
    app.middleware = .init()
    app.middleware.use(AccessLogMiddleware())
    app.middleware.use(APIErrorMiddleware())
    app.middleware.use(HTTPCachingMiddleware())

    // Database
    if config.databasePath == ":memory:" {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let directory = URL(fileURLWithPath: config.databasePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        app.databases.use(.sqlite(.file(config.databasePath)), as: .sqlite)
        app.logger.info("Database: \(config.databasePath)")
    }
    app.migrations.add(CreateCurrencies(), CreateRates(), CreateSyncRuns())
    try await app.autoMigrate()
    // A previous process may have died mid-sync; its run must not look in progress forever.
    try await SyncRun.markInterrupted(on: app.db)
    if config.databasePath != ":memory:" {
        // WAL lets API reads proceed while a sync is writing.
        try await (app.db as! any SQLDatabase).raw("PRAGMA journal_mode=WAL").run()
    }

    // Sync
    let source = upstream ?? FrankfurterSource(client: app.client, baseURL: config.upstreamBaseURL, logger: app.logger)
    var schedule = SyncSchedule()
    schedule.firstAttempt = config.syncTime
    let service = RatesSyncService(
        database: { app.db },
        upstream: source,
        backfillDays: config.backfillDays,
        timeZone: schedule.timeZone,
        now: { Date() },
        logger: app.logger
    )
    if config.syncEnabled {
        let scheduler = SyncScheduler(service: service, schedule: schedule, logger: app.logger)
        app.syncScheduler = scheduler
        app.lifecycle.use(SyncSchedulerLifecycle(scheduler: scheduler))
    }

    try routes(app)
}
