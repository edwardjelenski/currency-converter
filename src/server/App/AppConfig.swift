import Foundation
import Vapor

/// Server settings, read from environment variables.
struct AppConfig: Sendable {
    /// SQLite file, or `:memory:` for an in-memory database.
    var databasePath = "data/rates.sqlite"
    var upstreamBaseURL = "https://api.frankfurter.dev/v1/"
    /// How far back to load history on the first start.
    var backfillDays = 365
    /// First daily attempt, Europe/Berlin.
    var syncTime = TimeOfDay(hour: 16, minute: 15)
    /// Turn off to run without background sync (tests).
    var syncEnabled = true
    var hostname = "127.0.0.1"
    var port = 8080

    static func fromEnvironment() throws -> AppConfig {
        var config = AppConfig()
        if let value = Environment.get("DATABASE_PATH") { config.databasePath = value }
        if let value = Environment.get("UPSTREAM_BASE_URL") {
            config.upstreamBaseURL = value.hasSuffix("/") ? value : value + "/"
        }
        if let value = Environment.get("BACKFILL_DAYS") {
            guard let days = Int(value), days > 0 else { throw Abort(.internalServerError, reason: "BACKFILL_DAYS must be a positive integer, got '\(value)'") }
            config.backfillDays = days
        }
        if let value = Environment.get("SYNC_TIME") {
            guard let time = TimeOfDay(value) else { throw Abort(.internalServerError, reason: "SYNC_TIME must be HH:mm, got '\(value)'") }
            config.syncTime = time
        }
        if let value = Environment.get("SYNC_ENABLED") { config.syncEnabled = !["0", "false", "no"].contains(value.lowercased()) }
        if let value = Environment.get("HOST") { config.hostname = value }
        if let value = Environment.get("PORT") {
            guard let port = Int(value) else { throw Abort(.internalServerError, reason: "PORT must be a number, got '\(value)'") }
            config.port = port
        }
        return config
    }
}
