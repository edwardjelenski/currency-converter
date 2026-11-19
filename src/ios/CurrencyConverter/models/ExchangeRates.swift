import Foundation

/// A snapshot of exchange rates relative to a single base currency.
///
/// `rates[code]` is how many units of `code` one unit of `base` buys.
/// The base currency itself is always treated as `1`.
struct ExchangeRates: Hashable, Sendable {
    let base: String
    /// The day the rates were published, `yyyy-MM-dd`.
    let date: String
    let rates: [String: Decimal]

    /// All currency codes covered by this snapshot, including the base, sorted.
    var currencyCodes: [String] {
        (Array(rates.keys) + [base]).uniqued().sorted()
    }

    /// Units of `code` per one unit of `base`.
    func rate(for code: String) -> Decimal? {
        code == base ? 1 : rates[code]
    }

    /// Cross rate: how many units of `target` one unit of `source` buys.
    func rate(from source: String, to target: String) -> Decimal? {
        guard let sourceRate = rate(for: source),
              let targetRate = rate(for: target),
              sourceRate != 0
        else { return nil }
        return targetRate / sourceRate
    }

    /// Converts `amount` of `source` into `target`, or `nil` if either currency is unknown.
    func convert(_ amount: Decimal, from source: String, to target: String) -> Decimal? {
        rate(from: source, to: target).map { amount * $0 }
    }

    /// Publication date parsed from `date`, as local midnight — formatted for display it
    /// shows the same calendar day everywhere (GMT midnight would be the previous day in
    /// the Americas).
    var publishedAt: Date? {
        RateDay.date(from: date)
    }
}

/// Stored with rates as decimal strings (`"1.0968"`) so they never pass through `Double`.
extension ExchangeRates: Codable {
    private enum CodingKeys: String, CodingKey {
        case base, date, rates
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        base = try container.decode(String.self, forKey: .base)
        date = try container.decode(String.self, forKey: .date)
        let texts = try container.decode([String: String].self, forKey: .rates)
        var rates: [String: Decimal] = [:]
        for (code, text) in texts {
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(forKey: .rates, in: container, debugDescription: "Invalid \(code) rate '\(text)'")
            }
            rates[code] = value
        }
        self.rates = rates
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(base, forKey: .base)
        try container.encode(date, forKey: .date)
        try container.encode(rates.mapValues(\.description), forKey: .rates)
    }
}
