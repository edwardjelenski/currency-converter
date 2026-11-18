import Foundation

/// The app's only way out to the network. Mocked in tests.
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession` without its own HTTP cache: caching (ETag, expiry, offline copy)
/// is done explicitly by `RatesRepository`, so `URLCache` must not answer for us
/// or evict the offline copy behind our back.
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
