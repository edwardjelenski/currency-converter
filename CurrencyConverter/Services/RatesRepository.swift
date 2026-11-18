import Foundation

/// Combines the network provider with the on-disk cache.
struct RatesRepository: Sendable {
    let provider: any RatesProviding
    let cache: RatesCache
    var now: @Sendable () -> Date = { .now }

    func cached() async -> CachedRates? {
        await cache.load()
    }

    /// Fetches fresh rates and stores them. Cache write failures are not fatal.
    func refresh() async throws -> CachedRates {
        let rates = try await provider.latestRates()
        let result = CachedRates(rates: rates, fetchedAt: now())
        try? await cache.save(result)
        return result
    }
}

extension RatesRepository {
    static let live = RatesRepository(provider: FrankfurterClient(), cache: RatesCache())
}
