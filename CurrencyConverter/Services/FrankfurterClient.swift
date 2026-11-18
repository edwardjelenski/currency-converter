import Foundation

/// Fetches European Central Bank reference rates from the free
/// [Frankfurter API](https://frankfurter.dev). No API key required.
struct FrankfurterClient: RatesProviding {
    enum ClientError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "The rates server responded with status \(code)."
            }
        }
    }

    var baseURL = URL(string: "https://api.frankfurter.dev/v1/")!
    /// All rates are fetched against one base and cross-converted locally,
    /// so a single request covers every currency pair.
    var base = "EUR"
    var session: URLSession = .shared

    func latestRates() async throws -> ExchangeRates {
        var components = URLComponents(
            url: baseURL.appending(path: "latest"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "base", value: base)]

        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(ExchangeRates.self, from: data)
    }
}
