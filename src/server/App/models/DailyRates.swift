import Foundation

/// Rates published for one day: units of each currency per 1 EUR.
struct DailyRates: Hashable, Sendable {
    let date: RateDate
    let rates: [String: Decimal]
}
