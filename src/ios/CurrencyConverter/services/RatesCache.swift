import Foundation

/// The last rates response on disk, with what's needed to revalidate it:
/// the server's `ETag` and how long it may be used without asking.
actor RatesCache {
    private let fileURL: URL

    init(fileURL: URL = RatesCache.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// v2: rates as decimal strings + ETag + expiry. v1 (`exchange-rates.json`) came from
    /// the direct Frankfurter client and is simply ignored and removed.
    static var defaultFileURL: URL {
        URL.cachesDirectory.appending(path: "rates-cache-v2.json")
    }

    private static var legacyFileURL: URL {
        URL.cachesDirectory.appending(path: "exchange-rates.json")
    }

    func load() -> CachedRates? {
        try? FileManager.default.removeItem(at: Self.legacyFileURL)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedRates.self, from: data)
    }

    func save(_ rates: CachedRates) throws {
        let data = try JSONEncoder().encode(rates)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Rates plus their HTTP caching metadata.
struct CachedRates: Codable, Hashable, Sendable {
    let rates: ExchangeRates
    /// The server's `ETag` for these rates, sent back as `If-None-Match`.
    let etag: String?
    /// When this body was downloaded (`200`).
    let fetchedAt: Date
    /// When the server last confirmed these rates (`200` or `304`).
    let validatedAt: Date
    /// Until when the rates are used without asking the server (`Cache-Control: max-age`).
    let expiresAt: Date

    func isFresh(at date: Date) -> Bool {
        date < expiresAt
    }

    /// The same rates after a `304 Not Modified`.
    func revalidated(at date: Date, maxAge: TimeInterval) -> CachedRates {
        CachedRates(rates: rates, etag: etag, fetchedAt: fetchedAt, validatedAt: date, expiresAt: date.addingTimeInterval(maxAge))
    }
}
