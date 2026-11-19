import Fluent
import Foundation

/// Read side of the API: picks the stored EUR rates and converts them to the requested base.
///
/// EUR-based responses are the exact published values. For any other base the cross
/// rate `rate(X) / rate(base)` is computed in `Decimal` and rounded to 6 significant
/// digits (the ECB publishes 5, so no precision is lost).
struct RatesService: Sendable {
    static let significantDigits = 6
    /// Longest `/timeseries` range: 5 years.
    static let maxRangeDays = 5 * 366

    let database: any Database

    private var store: RatesStore { RatesStore(database: database) }

    /// Currencies with a rate on the latest publication day, plus EUR.
    func currencies() async throws -> CurrenciesResponse {
        let latest = try await requireLatestDate()
        let codes = Set(try await store.rates(on: latest).keys).union(["EUR"])
        let names = try await store.currencyNames()
        return CurrenciesResponse(currencies: codes.sorted().map {
            .init(code: $0, name: names[$0] ?? ($0 == "EUR" ? "Euro" : $0))
        })
    }

    /// Rates for `date` (or the latest day). `isFinal` is true when later publications
    /// can't change the answer, so it may be cached forever.
    func rates(base: String, date: RateDate?) async throws -> (response: RatesResponse, isFinal: Bool) {
        let latest = try await requireLatestDate()
        try await requireKnown([base])
        let target = date ?? latest
        guard let day = try await store.latestDate(onOrBefore: target) else {
            let first = try await store.firstDate()
            throw APIError.noData("No rates on or before \(target). History starts at \(first?.description ?? "-").")
        }
        let rates = try convert(try await store.rates(on: day), to: base, on: day)
        return (RatesResponse(base: base, date: day.description, rates: rates), date.map { $0 <= latest } ?? false)
    }

    func timeseries(base: String, symbols: [String]?, start: RateDate, end: RateDate) async throws -> (response: TimeseriesResponse, isFinal: Bool) {
        guard start <= end else {
            throw APIError.invalidParameter("'start' (\(start)) must not be after 'end' (\(end)).")
        }
        guard end <= start.adding(days: Self.maxRangeDays) else {
            throw APIError.invalidParameter("The range from 'start' to 'end' must not exceed 5 years.")
        }
        if let symbols, Set(symbols).subtracting([base]).isEmpty {
            throw APIError.invalidParameter("'symbols' must contain a currency other than the base '\(base)'.")
        }
        let latest = try await requireLatestDate()
        try await requireKnown([base] + (symbols ?? []))

        let wanted = symbols.map { Set($0).subtracting([base]) }
        let stored = try await store.rates(
            from: start,
            through: end,
            currencies: symbols.map { Array(Set($0 + [base]).subtracting(["EUR"])) }
        )
        var series: [String: [String: String]] = [:]
        for (day, eurRates) in stored {
            // A day without the base currency (e.g. BGN after 2025) can't be converted.
            guard let converted = try? convert(eurRates, to: base, on: day) else { continue }
            let filtered = wanted.map { wanted in converted.filter { wanted.contains($0.key) } } ?? converted
            if !filtered.isEmpty { series[day.description] = filtered }
        }
        guard !series.isEmpty else {
            throw APIError.noData("No rates for \(base) between \(start) and \(end).")
        }
        let response = TimeseriesResponse(base: base, start: start.description, end: end.description, rates: series)
        return (response, end <= latest)
    }

    // MARK: Private

    private func requireLatestDate() async throws -> RateDate {
        guard let latest = try await store.latestDate() else { throw APIError.notReady }
        return latest
    }

    private func requireKnown(_ codes: [String]) async throws {
        let known = Set(try await store.currencyNames().keys).union(["EUR"])
        if let unknown = codes.first(where: { !known.contains($0) }) {
            throw APIError.unknownCurrency(unknown)
        }
    }

    /// EUR-based rates → rates against `base`, as decimal strings, without `base` itself.
    private func convert(_ eurRates: [String: Decimal], to base: String, on day: RateDate) throws -> [String: String] {
        if base == "EUR" {
            return eurRates.mapValues(\.description)
        }
        guard let baseRate = eurRates[base], baseRate > 0 else {
            throw APIError.noData("No \(base) rate was published on \(day).")
        }
        var result = ["EUR": (1 / baseRate).rounded(significantDigits: Self.significantDigits).description]
        for (code, rate) in eurRates where code != base {
            result[code] = (rate / baseRate).rounded(significantDigits: Self.significantDigits).description
        }
        return result
    }
}
