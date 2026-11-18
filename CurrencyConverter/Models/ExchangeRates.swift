import Foundation

/// A snapshot of exchange rates relative to a single base currency.
///
/// `rates[code]` is how many units of `code` one unit of `base` buys.
/// The base currency itself is always treated as `1`.
struct ExchangeRates: Codable, Hashable, Sendable {
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

    /// Publication date parsed from `date`.
    var publishedAt: Date? {
        try? Date(date, strategy: Date.ISO8601FormatStyle().year().month().day())
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
