import Foundation
import Observation

@MainActor
@Observable
final class ConverterViewModel {
    /// A favorite currency with the typed amount converted into it.
    struct FavoriteConversion: Identifiable, Hashable {
        let currency: Currency
        /// The typed amount in this currency; `nil` without a rate or without a valid amount.
        let amount: Decimal?
        /// `false` when there's no rate for this currency (e.g. no longer published).
        let hasRate: Bool
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
    /// `false` until the first load attempt (cache, then server) has finished; until then
    /// the screen shows a spinner, not the "no rates" error.
    private(set) var hasAttemptedLoad = false

    @ObservationIgnored private let repository: RatesRepository
    @ObservationIgnored private let preferences: PreferencesStore
    /// The refresh in flight, so a pull to refresh can wait for it instead of being dropped.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
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
        // Significant digits, not decimal places: 1 IDR = 0.000049946 EUR, not "0".
        let formattedRate = rate.formatted(.number.precision(.significantDigits(1...5)).locale(locale))
        return "1 \(sourceCode) = \(formattedRate) \(targetCode)"
    }

    /// The typed amount in each favorite currency, in the user's order.
    var favoriteConversions: [FavoriteConversion] {
        favorites.map { code in
            let hasRate = rates?.rate(from: sourceCode, to: code) != nil
            let converted = amount.flatMap { amount in rates?.convert(amount, from: sourceCode, to: code) }
            return FavoriteConversion(currency: Currency(code: code), amount: converted, hasRate: hasRate)
        }
    }

    /// Recently picked currencies that have rates, for the picker's first section.
    var recentCurrencies: [Currency] {
        let available = Set(rates?.currencyCodes ?? [])
        return recents.filter(available.contains).map(Currency.init(code:))
    }

    var hasRates: Bool { snapshot != nil }

    // MARK: Actions

    /// How the last refresh ended (cache, 200 or 304). Not shown in the UI; for tests and debugging.
    private(set) var lastRefreshSource: RatesRepository.Source?

    /// Shows cached rates immediately, then asks the server if the cache has expired.
    func load() async {
        if snapshot == nil, let cached = await repository.cached(), snapshot == nil {
            // Re-checked after the await: a foreground refresh may have landed meanwhile,
            // and the disk copy must not replace fresher rates.
            apply(cached)
        }
        await refresh(force: false)
        hasAttemptedLoad = true
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
        if let running = refreshTask {
            // A refresh is already running: wait for it. A non-forced request is covered by
            // it; a forced one (pull to refresh) still revalidates afterwards.
            await running.value
            guard force else { return }
        }
        let task = Task { await performRefresh(force: force) }
        refreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if refreshTask == task { refreshTask = nil }
    }

    private func performRefresh(force: Bool) async {
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
            errorMessage = UserFacingError.message(for: error)
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

    /// Tap on a favorite: make it the target, or swap if it is the source already.
    func selectFavorite(_ code: String) {
        if code == sourceCode {
            swapCurrencies()
        } else {
            selectTarget(code)
        }
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

    private func fallbackCode(in codes: Set<String>, excluding excluded: String) -> String {
        (["EUR", "USD"] + codes.sorted()).first { codes.contains($0) && $0 != excluded } ?? excluded
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
        // A saved currency that is no longer published (e.g. BGN) gets a replacement,
        // and the replacement never makes the pair X → X.
        let sourceReplaced = !codes.contains(sourceCode)
        if sourceReplaced {
            sourceCode = fallbackCode(in: codes, excluding: targetCode)
        }
        if !codes.contains(targetCode) || (sourceReplaced && targetCode == sourceCode) {
            targetCode = fallbackCode(in: codes, excluding: sourceCode)
        }
    }
}
