import Foundation

/// The user's choices that survive a relaunch, in `UserDefaults`.
///
/// Small, ordered and read on every launch — `UserDefaults` is the right tool;
/// the keys of the first version are kept so existing installs keep their pair and amount.
struct PreferencesStore {
    static let defaultFavorites = ["EUR", "GBP", "JPY", "CHF"]
    static let maxRecents = 5

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var amountText: String {
        get { defaults.string(forKey: Keys.amount) ?? "100" }
        nonmutating set { defaults.set(newValue, forKey: Keys.amount) }
    }

    var sourceCode: String {
        get { defaults.string(forKey: Keys.source) ?? "USD" }
        nonmutating set { defaults.set(newValue, forKey: Keys.source) }
    }

    var targetCode: String {
        get { defaults.string(forKey: Keys.target) ?? "EUR" }
        nonmutating set { defaults.set(newValue, forKey: Keys.target) }
    }

    /// Ordered. A first launch gets `defaultFavorites`; an emptied list stays empty.
    var favorites: [String] {
        get { defaults.stringArray(forKey: Keys.favorites) ?? Self.defaultFavorites }
        nonmutating set { defaults.set(newValue, forKey: Keys.favorites) }
    }

    /// Most recent first, at most `maxRecents`.
    var recents: [String] {
        get { defaults.stringArray(forKey: Keys.recents) ?? [] }
        nonmutating set { defaults.set(Array(newValue.prefix(Self.maxRecents)), forKey: Keys.recents) }
    }

    private enum Keys {
        static let amount = "converter.amount"
        static let source = "converter.sourceCurrency"
        static let target = "converter.targetCurrency"
        static let favorites = "converter.favorites"
        static let recents = "picker.recentCurrencies"
    }
}
