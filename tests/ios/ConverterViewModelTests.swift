import Foundation
import Testing
@testable import CurrencyConverter

@MainActor
struct ConverterViewModelTests {
    private func makeModel(
        api: MockRatesAPI = MockRatesAPI(),
        cache: RatesCache = makeTemporaryCache(),
        defaults: UserDefaults = makeIsolatedDefaults(),
        locale: Locale = Locale(identifier: "en_US")
    ) -> ConverterViewModel {
        ConverterViewModel(
            repository: RatesRepository(api: api, cache: cache),
            defaults: defaults,
            locale: locale
        )
    }

    @Test func loadFetchesRatesAndConverts() async {
        let model = makeModel()
        model.amountText = "10"

        await model.load()

        #expect(model.hasRates)
        #expect(model.errorMessage == nil)
        #expect(model.convertedAmount == 5) // 10 USD -> 5 EUR
        #expect(model.rateDescription == "1 USD = 0.5 EUR")
    }

    @Test func amountUsesLocale() {
        let model = makeModel(locale: Locale(identifier: "ru_RU"))
        model.amountText = "1\u{00A0}234,5"
        #expect(model.amount == Decimal(string: "1234.5"))
    }

    @Test func swapExchangesCurrencies() {
        let model = makeModel()
        model.sourceCode = "GBP"
        model.targetCode = "JPY"

        model.swapCurrencies()

        #expect(model.sourceCode == "JPY")
        #expect(model.targetCode == "GBP")
    }

    @Test func offlineFallsBackToCachedRates() async throws {
        let cache = makeTemporaryCache()
        // Expired cache, so loading tries the network.
        try await cache.save(.fixture(at: .now.addingTimeInterval(-7200)))
        let model = makeModel(
            api: MockRatesAPI(.failure(URLError(.cannotConnectToHost))),
            cache: cache
        )

        await model.load()

        #expect(model.hasRates)
        #expect(model.errorMessage != nil)
        #expect(model.convertedAmount != nil)
    }

    @Test func offlineWithoutCacheShowsError() async {
        let model = makeModel(api: MockRatesAPI(.failure(URLError(.cannotConnectToHost))))

        await model.load()

        #expect(!model.hasRates)
        #expect(model.errorMessage != nil)
    }

    @Test func launchWithFreshCacheWorksOfflineWithoutRequest() async throws {
        let cache = makeTemporaryCache()
        try await cache.save(.fixture())
        let api = MockRatesAPI(.failure(URLError(.cannotConnectToHost)))
        let model = makeModel(api: api, cache: cache)
        model.amountText = "10"

        await model.load()

        #expect(await api.requestCount == 0)
        #expect(model.errorMessage == nil)
        #expect(model.lastRefreshSource == .cache)
        #expect(model.convertedAmount == 5)
    }

    @Test func pullToRefreshRevalidatesWithETag() async throws {
        let cache = makeTemporaryCache()
        try await cache.save(.fixture())
        let api = MockRatesAPI(.notModified(maxAge: 3600))
        let model = makeModel(api: api, cache: cache)
        await model.load()

        await model.refresh()

        #expect(await api.receivedETags == ["\"v1\""])
        #expect(model.lastRefreshSource == .notModified)
        #expect(model.errorMessage == nil)
    }

    @Test func failedPullToRefreshKeepsShowingCachedRates() async throws {
        let cache = makeTemporaryCache()
        try await cache.save(.fixture())
        let model = makeModel(api: MockRatesAPI(.failure(URLError(.cannotConnectToHost))), cache: cache)
        await model.load()

        await model.refresh()

        #expect(model.hasRates)
        #expect(model.errorMessage != nil)
        #expect(model.convertedAmount != nil)
    }

    @Test func unsupportedSavedCurrencyFallsBack() async {
        let defaults = makeIsolatedDefaults()
        defaults.set("RUB", forKey: "converter.sourceCurrency")
        let model = makeModel(defaults: defaults)

        await model.load()

        #expect(model.sourceCode == "EUR")
    }

    @Test func selectionIsPersisted() {
        let defaults = makeIsolatedDefaults()
        let model = makeModel(defaults: defaults)
        model.sourceCode = "JPY"
        model.amountText = "42"

        let restored = makeModel(defaults: defaults)
        #expect(restored.sourceCode == "JPY")
        #expect(restored.amountText == "42")
    }
}
