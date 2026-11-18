import Foundation
import OSLog

/// `RatesAPI` over HTTP against our server.
struct ServerRatesAPI: RatesAPI {
    let baseURL: URL
    let http: any HTTPClient

    private static let logger = Logger(subsystem: "com.eduardyelenskiy.currencyconverter", category: "network")

    func latestRates(base: String, ifNoneMatch etag: String?) async throws -> Conditional<ExchangeRates> {
        var components = URLComponents(url: baseURL.appending(path: "rates"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "base", value: base)]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let path = "/rates?base=\(base)"
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.send(request)
        } catch {
            Self.logger.error("GET \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let maxAge = Self.maxAge(fromCacheControl: response.value(forHTTPHeaderField: "Cache-Control"))
        Self.logger.notice("GET \(path, privacy: .public) → \(response.statusCode, privacy: .public) (If-None-Match: \(etag ?? "none", privacy: .public))")

        switch response.statusCode {
        case 200:
            let dto = try JSONDecoder().decode(RatesDTO.self, from: data)
            return .modified(try dto.exchangeRates(), etag: response.value(forHTTPHeaderField: "ETag"), maxAge: maxAge)
        case 304:
            guard etag != nil else { throw RatesAPIError.unexpectedNotModified }
            return .notModified(maxAge: maxAge)
        default:
            if let error = try? JSONDecoder().decode(ErrorDTO.self, from: data) {
                throw RatesAPIError.server(status: response.statusCode, code: error.error.code, message: error.error.message)
            }
            throw RatesAPIError.unexpectedStatus(response.statusCode)
        }
    }

    /// `max-age` in seconds from a `Cache-Control` header; `0` for `no-store` / `no-cache`.
    static func maxAge(fromCacheControl header: String?) -> TimeInterval? {
        guard let header else { return nil }
        var result: TimeInterval?
        for directive in header.split(separator: ",") {
            let parts = directive.trimmingCharacters(in: .whitespaces).lowercased().split(separator: "=", maxSplits: 1)
            switch parts.first {
            case "no-store", "no-cache":
                return 0
            case "max-age":
                if parts.count == 2, let seconds = TimeInterval(parts[1]) { result = seconds }
            default:
                continue
            }
        }
        return result
    }
}

// MARK: - Wire format

/// `{"base":"EUR","date":"2026-11-18","rates":{"USD":"1.0968",…}}` — rates are strings,
/// so they go straight into `Decimal` without passing through `Double`.
struct RatesDTO: Decodable {
    let base: String
    let date: String
    let rates: [String: String]

    func exchangeRates() throws -> ExchangeRates {
        var decimals: [String: Decimal] = [:]
        for (code, text) in rates {
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 else {
                throw RatesAPIError.invalidRate(currency: code, value: text)
            }
            decimals[code] = value
        }
        return ExchangeRates(base: base, date: date, rates: decimals)
    }
}

/// `{"error":{"code":"…","message":"…"}}`
struct ErrorDTO: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}
