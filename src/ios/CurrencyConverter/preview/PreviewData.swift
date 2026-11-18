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

/// Answers like our server would, without a network.
struct PreviewRatesAPI: RatesAPI {
    var rates: ExchangeRates = .sample

    func latestRates(base: String, ifNoneMatch etag: String?) async throws -> Conditional<ExchangeRates> {
        etag == nil ? .modified(rates, etag: "\"preview\"", maxAge: 3600) : .notModified(maxAge: 3600)
    }

    func history(base: String, target: String, start: Date, end: Date) async throws -> RateHistory {
        RateHistory.sample(base: base, target: target, from: start, to: end)
    }
}

/// The server is unreachable.
struct OfflineRatesAPI: RatesAPI {
    func latestRates(base: String, ifNoneMatch etag: String?) async throws -> Conditional<ExchangeRates> {
        throw URLError(.cannotConnectToHost)
    }

    func history(base: String, target: String, start: Date, end: Date) async throws -> RateHistory {
        throw URLError(.cannotConnectToHost)
    }
}

extension RateHistory {
    /// A plausible, deterministic USD→EUR-like curve over working days.
    static func sample(base: String = "USD", target: String = "EUR", from start: Date, to end: Date) -> RateHistory {
        let calendar = Calendar.current
        var points: [RatePoint] = []
        var day = calendar.startOfDay(for: start)
        var index = 0
        while day <= end {
            if !calendar.isDateInWeekend(day) {
                // Slow drift plus a wave, in exact decimals.
                let wave = Decimal(sin(Double(index) / 6) * 120 + Double(index) * 1.5).rounded(0)
                let rate = Decimal(string: "0.9050")! + wave / 100_000
                points.append(RatePoint(day: RateDay.string(from: day), date: day, rate: rate))
                index += 1
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return RateHistory(base: base, target: target, points: points)
    }

    static func sample(period: HistoryPeriod, endingOn end: Date = .now) -> RateHistory {
        sample(from: period.start(endingOn: end), to: end)
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}

extension RateHistoryRepository {
    static func preview(api: any RatesAPI = PreviewRatesAPI()) -> RateHistoryRepository {
        RateHistoryRepository(api: api)
    }
}

extension CachedRates {
    static func sample(at date: Date = .now) -> CachedRates {
        CachedRates(rates: .sample, etag: "\"preview\"", fetchedAt: date, validatedAt: date, expiresAt: date.addingTimeInterval(3600))
    }
}

extension ConverterViewModel {
    /// A model that already holds data, so previews render without waiting for `.task`.
    static func preview(
        api: any RatesAPI = PreviewRatesAPI(),
        snapshot: CachedRates? = .sample(),
        favorites: [String]? = nil
    ) -> ConverterViewModel {
        let suite = "preview.\(UUID().uuidString)"
        if let favorites {
            PreferencesStore(defaults: UserDefaults(suiteName: suite)!).favorites = favorites
        }
        return ConverterViewModel(
            repository: RatesRepository(
                api: api,
                cache: RatesCache(fileURL: URL.temporaryDirectory.appending(path: "\(suite).json"))
            ),
            defaults: UserDefaults(suiteName: suite)!,
            initialSnapshot: snapshot
        )
    }
}
#endif
