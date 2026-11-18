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

    @Test func decodesFrankfurterResponse() throws {
        let json = Data("""
        {"amount":1.0,"base":"EUR","date":"2026-11-18","rates":{"GBP":0.8329,"JPY":174.85,"USD":1.0968}}
        """.utf8)
        let decoded = try JSONDecoder().decode(ExchangeRates.self, from: json)
        #expect(decoded.base == "EUR")
        #expect(decoded.date == "2026-11-18")
        #expect(decoded.rates.count == 3)
        #expect(decoded.rates["USD"] == Decimal(string: "1.0968"))
    }

    @Test func parsesPublicationDate() throws {
        let date = try #require(rates.publishedAt)
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
        #expect(components.year == 2026)
        #expect(components.month == 11)
        #expect(components.day == 18)
    }
}
