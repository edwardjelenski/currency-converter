import Foundation
import Testing
@testable import CurrencyConverter

struct RatesRepositoryTests {
    private func makeRepository(api: MockRatesAPI, cache: RatesCache = makeTemporaryCache(), clock: TestClock) -> RatesRepository {
        RatesRepository(api: api, cache: cache, now: { clock.now })
    }

    @Test func cacheRoundTripKeepsETagAndExactRates() async throws {
        let cache = makeTemporaryCache()
        #expect(await cache.load() == nil)

        let snapshot = CachedRates.fixture(at: Date(timeIntervalSince1970: 1_000))
        try await cache.save(snapshot)

        #expect(await cache.load() == snapshot)
    }

    @Test func ratesAreStoredAsDecimalStrings() throws {
        let rates = ExchangeRates(base: "EUR", date: "2026-11-18", rates: ["USD": Decimal(string: "1.0968")!])
        let json = String(decoding: try JSONEncoder().encode(rates), as: UTF8.self)
        #expect(json.contains(#""USD":"1.0968""#))
        #expect(try JSONDecoder().decode(ExchangeRates.self, from: Data(json.utf8)) == rates)
    }

    @Test func coldStartDownloadsWithoutETagAndStores() async throws {
        let api = MockRatesAPI(.ok(.fixture, etag: "\"v1\"", maxAge: 3600))
        let clock = TestClock()
        let repository = makeRepository(api: api, clock: clock)

        let result = try await repository.refresh(force: false)

        #expect(result.source == .network)
        #expect(await api.receivedETags == [nil])
        #expect(result.snapshot.etag == "\"v1\"")
        #expect(result.snapshot.expiresAt == clock.now.addingTimeInterval(3600))
        #expect(await repository.cached() == result.snapshot)
    }

    @Test func freshCacheMakesNoRequest() async throws {
        let api = MockRatesAPI()
        let clock = TestClock()
        let repository = makeRepository(api: api, clock: clock)
        try await repository.refresh(force: false)

        clock.advance(by: 3599)
        let result = try await repository.refresh(force: false)

        #expect(result.source == .cache)
        #expect(await api.requestCount == 1)
    }

    @Test func expiredCacheRevalidatesWithETagAnd304ExtendsIt() async throws {
        let api = MockRatesAPI()
        let clock = TestClock()
        let repository = makeRepository(api: api, clock: clock)
        let first = try await repository.refresh(force: false).snapshot

        clock.advance(by: 3601)
        await api.setReply(.notModified(maxAge: 3600))
        let result = try await repository.refresh(force: false)

        #expect(result.source == .notModified)
        #expect(await api.receivedETags == [nil, "\"v1\""])
        #expect(result.snapshot.rates == first.rates)
        #expect(result.snapshot.fetchedAt == first.fetchedAt)
        #expect(result.snapshot.validatedAt == clock.now)
        #expect(result.snapshot.expiresAt == clock.now.addingTimeInterval(3600))
        #expect(await repository.cached() == result.snapshot)
    }

    @Test func forceRefreshAsksEvenWhenFresh() async throws {
        let api = MockRatesAPI()
        let repository = makeRepository(api: api, clock: TestClock())
        try await repository.refresh(force: false)
        await api.setReply(.notModified(maxAge: 3600))

        let result = try await repository.refresh(force: true)

        #expect(result.source == .notModified)
        #expect(await api.receivedETags == [nil, "\"v1\""])
    }

    @Test func newRatesReplaceCacheAndETag() async throws {
        let api = MockRatesAPI()
        let repository = makeRepository(api: api, clock: TestClock())
        try await repository.refresh(force: false)
        await api.setReply(.ok(.nextDay, etag: "\"v2\"", maxAge: 3600))

        let result = try await repository.refresh(force: true)

        #expect(result.source == .network)
        #expect(result.snapshot.rates == .nextDay)
        #expect(await repository.cached()?.etag == "\"v2\"")
    }

    @Test func missingMaxAgeUsesDefault() async throws {
        let api = MockRatesAPI(.ok(.fixture, etag: "\"v1\"", maxAge: nil))
        let clock = TestClock()
        let result = try await makeRepository(api: api, clock: clock).refresh(force: false)
        #expect(result.snapshot.expiresAt == clock.now.addingTimeInterval(3600))
    }

    @Test func networkFailureKeepsCache() async throws {
        let api = MockRatesAPI()
        let clock = TestClock()
        let repository = makeRepository(api: api, clock: clock)
        let stored = try await repository.refresh(force: false).snapshot

        await api.setReply(.failure(URLError(.cannotConnectToHost)))
        await #expect(throws: URLError.self) { try await repository.refresh(force: true) }

        #expect(await repository.cached() == stored)
    }

    @Test func notModifiedWithoutCacheIsAnError() async {
        let api = MockRatesAPI(.notModified(maxAge: 3600))
        await #expect(throws: RatesAPIError.unexpectedNotModified) {
            try await makeRepository(api: api, clock: TestClock()).refresh(force: false)
        }
    }

    @Test func unreadableCacheFileIsIgnored() async throws {
        let url = URL.temporaryDirectory.appending(path: "rates-\(UUID().uuidString).json")
        // Old format: numeric rates, no ETag.
        try Data(#"{"rates":{"base":"EUR","date":"2026-11-18","rates":{"USD":1.1}},"fetchedAt":0}"#.utf8).write(to: url)
        #expect(await RatesCache(fileURL: url).load() == nil)
    }
}
