import Foundation
import Testing
@testable import CurrencyConverter

struct ExchangeRatesTests {
    let rates = ExchangeRates.fixture

    @Test func baseCurrencyRateIsOne() {
        #expect(rates.rate(for: "EUR") == 1)
    }

    @Test func currencyCodesIncludeBaseAndAreSorted() {
        #expect(rates.currencyCodes == ["EUR", "GBP", "JPY", "USD"])
    }

    @Test(arguments: [
        ("EUR", "USD", Decimal(200)),
        ("USD", "EUR", Decimal(50)),
        ("USD", "GBP", Decimal(50)),
        ("GBP", "JPY", Decimal(20_000)),
        ("USD", "USD", Decimal(100)),
    ])
    func crossConversion(from source: String, to target: String, expected: Decimal) {
        #expect(rates.convert(100, from: source, to: target) == expected)
    }

    @Test func unknownCurrencyReturnsNil() {
        #expect(rates.convert(1, from: "USD", to: "XXX") == nil)
        #expect(rates.rate(from: "XXX", to: "USD") == nil)
    }

    @Test func parsesPublicationDate() throws {
        let date = try #require(rates.publishedAt)
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
        #expect(components.year == 2026)
        #expect(components.month == 11)
        #expect(components.day == 18)
    }
}
