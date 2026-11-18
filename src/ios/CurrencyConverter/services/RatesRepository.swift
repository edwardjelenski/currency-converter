import Foundation

/// Decides when to go to the server and keeps the offline copy.
///
/// - Cache still fresh (`max-age` not over) → no request.
/// - Otherwise a conditional `GET /rates?base=EUR` with `If-None-Match`:
///   `304` extends the cache's lifetime, `200` replaces it.
/// - The converter always asks for EUR and computes every pair locally
///   (docs/architecture.md, section 2), so one cached response covers all pairs offline.
struct RatesRepository: Sendable {
    enum Source: Sendable, Equatable {
        /// The cache was fresh; no request was made.
        case cache
        /// `200`: new rates downloaded.
        case network
        /// `304`: the server confirmed the cached rates.
        case notModified
    }

    struct Refresh: Sendable, Equatable {
        let snapshot: CachedRates
        let source: Source
    }

    static let base = "EUR"

    let api: any RatesAPI
    let cache: RatesCache
    var now: @Sendable () -> Date = { .now }
    /// Used when the server sends no `max-age`.
    var defaultMaxAge: TimeInterval = 3600

    func cached() async -> CachedRates? {
        await cache.load()
    }

    /// `force` skips the freshness check (pull to refresh) but still sends `If-None-Match`.
    @discardableResult
    func refresh(force: Bool) async throws -> Refresh {
        let current = await cache.load()
        let now = now()
        if !force, let current, current.isFresh(at: now) {
            return Refresh(snapshot: current, source: .cache)
        }

        switch try await api.latestRates(base: Self.base, ifNoneMatch: current?.etag) {
        case let .modified(rates, etag, maxAge):
            let snapshot = CachedRates(
                rates: rates,
                etag: etag,
                fetchedAt: now,
                validatedAt: now,
                expiresAt: now.addingTimeInterval(maxAge ?? defaultMaxAge)
            )
            try? await cache.save(snapshot)
            return Refresh(snapshot: snapshot, source: .network)

        case let .notModified(maxAge):
            guard let current else { throw RatesAPIError.unexpectedNotModified }
            let snapshot = current.revalidated(at: now, maxAge: maxAge ?? defaultMaxAge)
            try? await cache.save(snapshot)
            return Refresh(snapshot: snapshot, source: .notModified)
        }
    }
}

extension RatesRepository {
    static func live() -> RatesRepository {
        RatesRepository(
            api: ServerRatesAPI(baseURL: AppConfiguration.apiBaseURL, http: URLSessionHTTPClient()),
            cache: RatesCache()
        )
    }
}
