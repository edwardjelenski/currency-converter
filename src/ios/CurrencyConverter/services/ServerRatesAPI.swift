import Foundation
import OSLog

/// `RatesAPI` over HTTP against our server.
struct ServerRatesAPI: RatesAPI {
    let baseURL: URL
    let http: any HTTPClient

    static func live() -> ServerRatesAPI {
        ServerRatesAPI(baseURL: AppConfiguration.apiBaseURL, http: URLSessionHTTPClient())
    }

    private static let logger = Logger(subsystem: "com.eduardyelenskiy.currencyconverter", category: "network")

    func latestRates(base: String, ifNoneMatch etag: String?) async throws -> Conditional<ExchangeRates> {
        guard var components = URLComponents(url: baseURL.appending(path: "rates"), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "base", value: base)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
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
            throw Self.error(status: response.statusCode, body: data)
        }
    }

    func history(base: String, target: String, start: Date, end: Date) async throws -> RateHistory {
        guard var components = URLComponents(url: baseURL.appending(path: "timeseries"), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "symbols", value: target),
            URLQueryItem(name: "start", value: RateDay.string(from: start)),
            URLQueryItem(name: "end", value: RateDay.string(from: end)),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let path = "/timeseries?\(components.percentEncodedQuery ?? "")"
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.send(request)
        } catch {
            Self.logger.error("GET \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        Self.logger.notice("GET \(path, privacy: .public) → \(response.statusCode, privacy: .public)")

        guard response.statusCode == 200 else { throw Self.error(status: response.statusCode, body: data) }
        return try JSONDecoder().decode(TimeseriesDTO.self, from: data).history(target: target)
    }

    private static func error(status: Int, body: Data) -> RatesAPIError {
        if let error = try? JSONDecoder().decode(ErrorDTO.self, from: body) {
            return .server(status: status, code: error.error.code, message: error.error.message)
        }
        return .unexpectedStatus(status)
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

/// `{"base":"USD","start":…,"end":…,"rates":{"2026-11-17":{"GBP":"0.759038"},…}}`
struct TimeseriesDTO: Decodable {
    let base: String
    let rates: [String: [String: String]]

    func history(target: String) throws -> RateHistory {
        var points: [RatePoint] = []
        for (day, values) in rates {
            guard let text = values[target] else { continue }
            guard let date = RateDay.date(from: day) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid date '\(day)'"))
            }
            guard let rate = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), rate > 0 else {
                throw RatesAPIError.invalidRate(currency: target, value: text)
            }
            points.append(RatePoint(day: day, date: date, rate: rate))
        }
        return RateHistory(base: base, target: target, points: points.sorted { $0.day < $1.day })
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
