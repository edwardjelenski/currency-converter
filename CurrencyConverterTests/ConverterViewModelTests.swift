import Foundation
import Testing
@testable import CurrencyConverter

@MainActor
struct ConverterViewModelTests {
    private func makeModel(
        provider: StubRatesProvider = StubRatesProvider(result: .success(.fixture)),
        cache: RatesCache = makeTemporaryCache(),
        defaults: UserDefaults = makeIsolatedDefaults(),
        locale: Locale = Locale(identifier: "en_US")
    ) -> ConverterViewModel {
        ConverterViewModel(
            repository: RatesRepository(provider: provider, cache: cache),
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

    @Test func otherConversionsExcludeSelectedPair() async {
        let model = makeModel()
        await model.load()

        #expect(model.otherConversions.map(\.currency.code) == ["GBP", "JPY"])
    }

    @Test func offlineFallsBackToCachedRates() async throws {
        let cache = makeTemporaryCache()
        try await cache.save(CachedRates(rates: .fixture, fetchedAt: .now))
        let model = makeModel(
            provider: StubRatesProvider(result: .failure(URLError(.notConnectedToInternet))),
            cache: cache
        )

        await model.load()

        #expect(model.hasRates)
        #expect(model.errorMessage != nil)
        #expect(model.convertedAmount != nil)
    }

    @Test func offlineWithoutCacheShowsError() async {
        let model = makeModel(provider: StubRatesProvider(result: .failure(URLError(.notConnectedToInternet))))

        await model.load()

        #expect(!model.hasRates)
        #expect(model.errorMessage != nil)
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
