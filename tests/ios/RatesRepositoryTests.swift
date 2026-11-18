import Foundation
import Testing
@testable import CurrencyConverter

struct RatesRepositoryTests {
    @Test func cacheRoundTrip() async throws {
        let cache = makeTemporaryCache()
        #expect(await cache.load() == nil)

        let snapshot = CachedRates(rates: .fixture, fetchedAt: Date(timeIntervalSince1970: 1_000))
        try await cache.save(snapshot)
        #expect(await cache.load() == snapshot)
    }

    @Test func refreshStoresFetchedRates() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 42)
        let repository = RatesRepository(
            provider: StubRatesProvider(result: .success(.fixture)),
            cache: makeTemporaryCache(),
            now: { fetchedAt }
        )

        let result = try await repository.refresh()

        #expect(result == CachedRates(rates: .fixture, fetchedAt: fetchedAt))
        #expect(await repository.cached() == result)
    }

    @Test func failedRefreshKeepsPreviousCache() async throws {
        let cache = makeTemporaryCache()
        let previous = CachedRates(rates: .fixture, fetchedAt: .now)
        try await cache.save(previous)
        let repository = RatesRepository(
            provider: StubRatesProvider(result: .failure(URLError(.notConnectedToInternet))),
            cache: cache
        )

        await #expect(throws: URLError.self) { try await repository.refresh() }
        #expect(await repository.cached() == previous)
    }
}
