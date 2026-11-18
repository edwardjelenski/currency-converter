import Foundation
@testable import CurrencyConverter

struct StubRatesProvider: RatesProviding {
    var result: Result<ExchangeRates, URLError>
    func latestRates() async throws -> ExchangeRates { try result.get() }
}

extension ExchangeRates {
    /// Simple, exact numbers so assertions don't depend on floating point.
    static let fixture = ExchangeRates(
        base: "EUR",
        date: "2026-11-18",
        rates: ["USD": 2, "GBP": 1, "JPY": 200]
    )
}

func makeTemporaryCache() -> RatesCache {
    RatesCache(fileURL: URL.temporaryDirectory.appending(path: "rates-\(UUID().uuidString).json"))
}

func makeIsolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
}
