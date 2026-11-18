import Foundation
import Observation

@MainActor
@Observable
final class ConverterViewModel {
    /// A favorite currency with the typed amount converted into it.
    struct FavoriteConversion: Identifiable, Hashable {
        let currency: Currency
        /// `nil` when there's no rate for this currency (e.g. no longer published).
        let amount: Decimal?
        var id: String { currency.code }
    }

    // MARK: Input (persisted)

    var amountText: String {
        didSet { preferences.amountText = amountText }
    }

    var sourceCode: String {
        didSet { preferences.sourceCode = sourceCode }
    }

    var targetCode: String {
        didSet { preferences.targetCode = targetCode }
    }

    /// Ordered list of currencies shown under the converter.
    private(set) var favorites: [String] {
        didSet { preferences.favorites = favorites }
    }

    /// Currencies picked recently, most recent first; shown on top of the picker.
    private(set) var recents: [String] {
        didSet { preferences.recents = recents }
    }

    // MARK: State

    private(set) var snapshot: CachedRates?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let repository: RatesRepository
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored let locale: Locale

    init(
        repository: RatesRepository,
        defaults: UserDefaults = .standard,
        locale: Locale = .current,
        initialSnapshot: CachedRates? = nil
    ) {
        let preferences = PreferencesStore(defaults: defaults)
        self.repository = repository
        self.preferences = preferences
        self.locale = locale
        self.snapshot = initialSnapshot
        self.amountText = preferences.amountText
        self.sourceCode = preferences.sourceCode
        self.targetCode = preferences.targetCode
        self.favorites = preferences.favorites
        self.recents = preferences.recents
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

    /// The typed amount in each favorite currency, in the user's order.
    var favoriteConversions: [FavoriteConversion] {
        favorites.map { code in
            let converted = amount.flatMap { amount in rates?.convert(amount, from: sourceCode, to: code) }
            return FavoriteConversion(currency: Currency(code: code), amount: converted)
        }
    }

    /// Recently picked currencies that have rates, for the picker's first section.
    var recentCurrencies: [Currency] {
        let available = Set(rates?.currencyCodes ?? [])
        return recents.filter(available.contains).map(Currency.init(code:))
    }

    func isFavorite(_ code: String) -> Bool {
        favorites.contains(code)
    }

    var hasRates: Bool { snapshot != nil }

    // MARK: Actions

    /// How the last refresh ended; for diagnostics and the UI's "updated" line.
    private(set) var lastRefreshSource: RatesRepository.Source?

    /// Shows cached rates immediately, then asks the server if the cache has expired.
    func load() async {
        if snapshot == nil, let cached = await repository.cached() {
            apply(cached)
        }
        await refresh(force: false)
    }

    /// Pull to refresh: always asks the server (conditionally, so usually a cheap `304`).
    func refresh() async {
        await refresh(force: true)
    }

    /// App returned to the foreground: ask only if the cache has expired.
    func refreshIfNeeded() async {
        await refresh(force: false)
    }

    private func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await repository.refresh(force: force)
            apply(result.snapshot)
            lastRefreshSource = result.source
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

    // MARK: Picking currencies

    func selectSource(_ code: String) {
        sourceCode = code
        noteRecent(code)
    }

    func selectTarget(_ code: String) {
        targetCode = code
        noteRecent(code)
    }

    /// From the picker in favorites mode: adds at the end, or removes if already there.
    func toggleFavorite(_ code: String) {
        if let index = favorites.firstIndex(of: code) {
            favorites.remove(at: index)
        } else {
            favorites.append(code)
            noteRecent(code)
        }
    }

    /// Swipe to delete.
    func removeFavorites(at offsets: IndexSet) {
        favorites = favorites.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Drag to reorder; same semantics as SwiftUI's `onMove` (destination is an index
    /// in the list before the move).
    func moveFavorites(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { favorites[$0] }
        var remaining = favorites.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertionIndex = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertionIndex)
        favorites = remaining
    }

    private func noteRecent(_ code: String) {
        recents = [code] + recents.filter { $0 != code }.prefix(PreferencesStore.maxRecents - 1)
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
}
