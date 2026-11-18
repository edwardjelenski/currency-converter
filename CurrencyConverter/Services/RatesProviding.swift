import Foundation

/// A source of the latest exchange rates.
protocol RatesProviding: Sendable {
    func latestRates() async throws -> ExchangeRates
}
