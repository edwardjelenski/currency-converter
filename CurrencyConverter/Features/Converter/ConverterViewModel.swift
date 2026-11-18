import Foundation
import Observation

@MainActor
@Observable
final class ConverterViewModel {
    struct Conversion: Identifiable, Hashable {
        let currency: Currency
        let amount: Decimal
        var id: String { currency.code }
    }

    // MARK: Input

    var amountText: String {
        didSet { defaults.set(amountText, forKey: Keys.amount) }
    }

    var sourceCode: String {
        didSet { defaults.set(sourceCode, forKey: Keys.source) }
    }

    var targetCode: String {
        didSet { defaults.set(targetCode, forKey: Keys.target) }
    }

    // MARK: State

    private(set) var snapshot: CachedRates?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let repository: RatesRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let locale: Locale

    init(
        repository: RatesRepository,
        defaults: UserDefaults = .standard,
        locale: Locale = .current,
        initialSnapshot: CachedRates? = nil
    ) {
        self.repository = repository
        self.defaults = defaults
        self.locale = locale
        self.snapshot = initialSnapshot
        self.amountText = defaults.string(forKey: Keys.amount) ?? "100"
        self.sourceCode = defaults.string(forKey: Keys.source) ?? "USD"
        self.targetCode = defaults.string(forKey: Keys.target) ?? "EUR"
    }

    // MARK: Derived values

    var rates: ExchangeRates? { snapshot?.rates }

    var currencies: [Currency] {
        (rates?.currencyCodes ?? []).map(Currency.init(code:))
    }

    var source: Currency { Currency(code: sourceCode) }
    var target: Currency { Currency(code: targetCode) }

    /// The typed amount, parsed in the user's locale. See `AmountParser`.
    var amount: Decimal? {
        AmountParser.parse(amountText, locale: locale)
    }

    var convertedAmount: Decimal? {
        guard let amount, let rates else { return nil }
        return rates.convert(amount, from: sourceCode, to: targetCode)
    }

    var formattedResult: String {
        guard let convertedAmount else { return "—" }
        return format(convertedAmount, currency: targetCode)
    }

    /// e.g. "1 USD = 0.9117 EUR"
    var rateDescription: String? {
        guard let rate = rates?.rate(from: sourceCode, to: targetCode) else { return nil }
        let formattedRate = rate.formatted(.number.precision(.fractionLength(0...4)).locale(locale))
        return "1 \(sourceCode) = \(formattedRate) \(targetCode)"
    }

    /// The amount converted into every other currency, for the list below the converter.
    var otherConversions: [Conversion] {
        guard let amount, let rates else { return [] }
        return rates.currencyCodes
            .filter { $0 != sourceCode && $0 != targetCode }
            .compactMap { code in
                rates.convert(amount, from: sourceCode, to: code).map {
                    Conversion(currency: Currency(code: code), amount: $0)
                }
            }
    }

    var hasRates: Bool { snapshot != nil }

    // MARK: Actions

    /// Shows cached rates immediately, then fetches fresh ones.
    func load() async {
        if snapshot == nil, let cached = await repository.cached() {
            apply(cached)
        }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            apply(try await repository.refresh())
            errorMessage = nil
        } catch is CancellationError {
            // The view went away or the user released pull-to-refresh early.
        } catch let error as URLError where error.code == .cancelled {
            // Same as above, surfaced by URLSession.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func swapCurrencies() {
        (sourceCode, targetCode) = (targetCode, sourceCode)
    }

    func format(_ value: Decimal, currency code: String) -> String {
        value.formatted(.currency(code: code).locale(locale))
    }

    // MARK: Private

    private func apply(_ snapshot: CachedRates) {
        self.snapshot = snapshot
        let codes = Set(snapshot.rates.currencyCodes)
        if !codes.contains(sourceCode) { sourceCode = snapshot.rates.base }
        if !codes.contains(targetCode) {
            targetCode = codes.contains("USD") && sourceCode != "USD" ? "USD" : snapshot.rates.base
        }
    }

    private enum Keys {
        static let amount = "converter.amount"
        static let source = "converter.sourceCurrency"
        static let target = "converter.targetCurrency"
    }
}
