import Foundation

/// Persists the last successfully fetched rates so the app works offline.
actor RatesCache {
    private let fileURL: URL

    init(fileURL: URL = RatesCache.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        URL.cachesDirectory.appending(path: "exchange-rates.json")
    }

    func load() -> CachedRates? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedRates.self, from: data)
    }

    func save(_ rates: CachedRates) throws {
        let data = try JSONEncoder().encode(rates)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Rates together with the moment they were fetched.
struct CachedRates: Codable, Hashable, Sendable {
    let rates: ExchangeRates
    let fetchedAt: Date
}
