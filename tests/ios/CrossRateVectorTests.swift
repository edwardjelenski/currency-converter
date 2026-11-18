import Foundation
import Testing
@testable import CurrencyConverter

/// tests/fixtures/cross-rates.json — the same vectors run in tests/server.
struct CrossRateFixture: Decodable, Sendable {
    struct CrossRate: Decodable, Sendable, CustomTestStringConvertible {
        let from: String
        let to: String
        let rate: String?
        var testDescription: String { "\(from)→\(to)" }
    }

    struct Conversion: Decodable, Sendable, CustomTestStringConvertible {
        let amount: String
        let from: String
        let to: String
        let fractionDigits: Int
        let result: String
        var testDescription: String { "\(amount) \(from)→\(to)" }
    }

    let date: String
    let rates: [String: String]
    let crossRates: [CrossRate]
    let conversions: [Conversion]

    /// Copied into the test bundle by project.yml (Fixtures group).
    static let shared: CrossRateFixture = {
        guard let url = Bundle(for: FixtureAnchor.self).url(forResource: "cross-rates", withExtension: "json") else {
            fatalError("cross-rates.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(CrossRateFixture.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Can't decode cross-rates.json: \(error)")
        }
    }()

    var exchangeRates: ExchangeRates {
        ExchangeRates(base: "EUR", date: date, rates: rates.mapValues { decimal($0) })
    }

    /// The server's /rates body for these rates (strings, as on the wire).
    var ratesResponseJSON: String {
        let object: [String: Any] = ["base": "EUR", "date": date, "rates": rates]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

/// A class defined in the test target, so `Bundle(for:)` finds the test bundle.
private final class FixtureAnchor {}

func decimal(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

/// Half-up rounding, as the vectors were computed.
func rounded(_ value: Decimal, scale: Int) -> Decimal {
    var value = value
    var result = Decimal()
    NSDecimalRound(&result, &value, scale, .plain)
    return result
}

/// Half-up rounding to significant digits — the server's rule for cross rates.
func rounded(_ value: Decimal, significantDigits digits: Int) -> Decimal {
    guard value != 0 else { return 0 }
    let text = value.magnitude.description
    let integerDigits = value.magnitude >= 1
        ? text.prefix { $0 != "." }.count
        : -(text.split(separator: ".").last ?? "").prefix { $0 == "0" }.count
    return rounded(value, scale: digits - integerDigits)
}

struct CrossRateVectorTests {
    static let fixture = CrossRateFixture.shared

    @Test(arguments: fixture.crossRates)
    func crossRate(_ vector: CrossRateFixture.CrossRate) throws {
        let rate = Self.fixture.exchangeRates.rate(from: vector.from, to: vector.to)
        guard let expected = vector.rate.map(decimal) else {
            #expect(rate == nil)
            return
        }
        let actual = try #require(rate)
        if vector.from == "EUR" || vector.from == vector.to {
            // Published values (and 1 for the same currency) are exact.
            #expect(actual == expected)
        } else {
            // The client keeps full precision; the shared vectors carry the server's 6 digits.
            #expect(rounded(actual, significantDigits: 6) == expected, "client exact rate \(actual)")
        }
    }

    /// Wire JSON → ServerRatesAPI → RatesRepository → ConverterViewModel → converted amount.
    @MainActor
    @Test(arguments: fixture.conversions)
    func conversionThroughTheWholeClient(_ vector: CrossRateFixture.Conversion) async throws {
        let http = MockHTTPClient(status: 200, headers: ["ETag": "\"v\""], body: Self.fixture.ratesResponseJSON)
        let model = ConverterViewModel(
            repository: RatesRepository(api: ServerRatesAPI(baseURL: URL(string: "http://127.0.0.1:8080")!, http: http), cache: makeTemporaryCache()),
            defaults: makeIsolatedDefaults(),
            locale: Locale(identifier: "en_US")
        )
        await model.load()
        model.amountText = vector.amount
        model.selectSource(vector.from)
        model.selectTarget(vector.to)

        let converted = try #require(model.convertedAmount)
        #expect(rounded(converted, scale: vector.fractionDigits) == decimal(vector.result), "exact \(converted)")
    }
}
