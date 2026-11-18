import Foundation

// Response bodies of the REST API. Rates are decimal strings so they never pass
// through Double in any JSON parser (docs/architecture.md, section 3).

struct CurrenciesResponse: Codable, Sendable, Equatable {
    struct Currency: Codable, Sendable, Equatable {
        let code: String
        let name: String
    }

    let currencies: [Currency]
}

struct RatesResponse: Codable, Sendable, Equatable {
    let base: String
    /// The publication day the rates are from (may be earlier than the requested date).
    let date: String
    let rates: [String: String]
}

struct TimeseriesResponse: Codable, Sendable, Equatable {
    let base: String
    let start: String
    let end: String
    /// Date → currency → rate, publication days only.
    let rates: [String: [String: String]]
}

struct HealthResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        /// Rates are available and the last sync succeeded or found nothing new.
        case ok
        /// Rates are available but the last sync failed: we serve what's stored.
        case degraded
        /// No rates yet (first backfill still running or failed).
        case notReady = "not_ready"
    }

    struct LastSync: Codable, Sendable, Equatable {
        let trigger: String
        let status: String
        let startedAt: Date
        let finishedAt: Date?
        let datesAdded: Int
        let error: String?
    }

    let status: Status
    let latestRateDate: String?
    let storedDays: Int
    /// The last finished sync attempt.
    let lastSync: LastSync?
    let syncInProgress: Bool
    let nextSyncAt: Date?
}
