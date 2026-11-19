import Foundation
import Testing
@testable import CurrencyConverter

@MainActor
struct ConverterViewModelTests {
    private func makeModel(
        api: any RatesAPI = MockRatesAPI(),
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
        #expect(!model.hasAttemptedLoad) // the view shows a spinner, not the error, until now

        await model.load()

        #expect(model.hasAttemptedLoad)
        #expect(!model.hasRates)
        #expect(model.errorMessage == String(localized: "Can't reach the rates server. Check your connection and try again."))
    }

    @Test func tinyRatesKeepSignificantDigits() {
        // Review I2: 0…4 decimal places showed "1 IDR = 0 EUR".
        let rates = ExchangeRates(base: "EUR", date: "2026-11-18", rates: ["IDR": 20000, "USD": 2])
        let model = ConverterViewModel(
            repository: RatesRepository(api: MockRatesAPI(), cache: makeTemporaryCache()),
            defaults: makeIsolatedDefaults(),
            locale: Locale(identifier: "en_US"),
            initialSnapshot: CachedRates(rates: rates, etag: nil, fetchedAt: .now, validatedAt: .now, expiresAt: .now)
        )
        model.selectSource("IDR")
        model.selectTarget("EUR")
        #expect(model.rateDescription == "1 IDR = 0.00005 EUR")
        model.selectSource("EUR")
        model.selectTarget("IDR")
        #expect(model.rateDescription == "1 EUR = 20,000 IDR")
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
        defaults.set("RUB", forKey: "converter.sourceCurrency") // target stays the default EUR
        let model = makeModel(defaults: defaults)

        await model.load()

        // Review I6: the replacement must not turn the pair into EUR → EUR.
        #expect(model.sourceCode == "USD")
        #expect(model.targetCode == "EUR")
    }

    @Test func unsupportedSavedTargetFallsBackToAnotherCurrency() async {
        let defaults = makeIsolatedDefaults()
        defaults.set("EUR", forKey: "converter.sourceCurrency")
        defaults.set("BGN", forKey: "converter.targetCurrency")
        let model = makeModel(defaults: defaults)

        await model.load()

        #expect(model.sourceCode == "EUR")
        #expect(model.targetCode == "USD")
    }

    @Test func pullToRefreshDuringARefreshStillRevalidates() async {
        let api = GatedRatesAPI()
        let model = makeModel(api: api)

        let launch = Task { await model.load() }
        await waitUntil { await api.callCount == 1 }
        #expect(model.isRefreshing)

        // Review I8: a pull to refresh while the launch refresh is in flight used to be
        // dropped. Now it waits for that request instead of racing it...
        let pull = Task { await model.refresh() }
        for _ in 0..<20 { await Task.yield() }
        #expect(await api.callCount == 1)

        // ...and revalidates once it is done.
        await api.releaseWaiting()
        await waitUntil { await api.callCount == 2 }
        await api.releaseWaiting()
        await launch.value
        await pull.value

        #expect(await api.callCount == 2)
        #expect(!model.isRefreshing)
        #expect(model.hasRates)
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
