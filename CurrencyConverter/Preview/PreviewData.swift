#if DEBUG
import Foundation

extension ExchangeRates {
    static let sample = ExchangeRates(
        base: "EUR",
        date: "2026-11-18",
        rates: [
            "AUD": 1.6294, "BRL": 6.3818, "CAD": 1.5690, "CHF": 0.92430, "CNY": 7.3127,
            "CZK": 24.386, "DKK": 7.4744, "GBP": 0.83290, "HKD": 8.6064, "HUF": 368.41,
            "IDR": 20021, "ILS": 3.5799, "INR": 102.49, "ISK": 137.00, "JPY": 174.85,
            "KRW": 1461.3, "MXN": 20.374, "MYR": 4.5145, "NOK": 10.605, "NZD": 1.9951,
            "PHP": 69.833, "PLN": 4.4118, "RON": 5.3467, "SEK": 11.143, "SGD": 1.4144,
            "THB": 37.512, "TRY": 47.850, "USD": 1.0968, "ZAR": 20.089,
        ]
    )
}

struct StaticRatesProvider: RatesProviding {
    var rates: ExchangeRates = .sample
    func latestRates() async throws -> ExchangeRates { rates }
}

struct FailingRatesProvider: RatesProviding {
    func latestRates() async throws -> ExchangeRates { throw URLError(.notConnectedToInternet) }
}

extension ConverterViewModel {
    /// A model that already holds data, so previews render without waiting for `.task`.
    static func preview(
        provider: any RatesProviding = StaticRatesProvider(),
        snapshot: CachedRates? = CachedRates(rates: .sample, fetchedAt: .now)
    ) -> ConverterViewModel {
        let suite = "preview.\(UUID().uuidString)"
        return ConverterViewModel(
            repository: RatesRepository(
                provider: provider,
                cache: RatesCache(fileURL: URL.temporaryDirectory.appending(path: "\(suite).json"))
            ),
            defaults: UserDefaults(suiteName: suite)!,
            initialSnapshot: snapshot
        )
    }
}
#endif
