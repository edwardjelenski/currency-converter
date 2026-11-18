import Foundation
import NIOCore
import Vapor

/// ECB reference rates via the free Frankfurter API (https://frankfurter.dev).
///
/// Frankfurter answers `404` for a range in which nothing has been published yet
/// (e.g. today before ~16:00 CET) and occasionally `5xx` from its CDN, so `404`
/// means "no data" and `5xx`/transport errors are retried.
struct FrankfurterSource: UpstreamRatesSource {
    enum SourceError: Error, CustomStringConvertible {
        case unexpectedStatus(HTTPStatus, path: String)
        case serverError(HTTPStatus, path: String)
        case invalidDate(String)

        var description: String {
            switch self {
            case let .unexpectedStatus(status, path): "Frankfurter \(path) responded \(status.code)"
            case let .serverError(status, path): "Frankfurter \(path) responded \(status.code)"
            case let .invalidDate(value): "Frankfurter returned an invalid date '\(value)'"
            }
        }
    }

    let client: any Client
    /// Must end with `/`, e.g. `https://api.frankfurter.dev/v1/`.
    let baseURL: String
    let logger: Logger
    var maxAttempts = 3
    var retryDelay: Duration = .seconds(2)
    var requestTimeout: TimeAmount = .seconds(20)

    func currencies() async throws -> [String: String] {
        try await get("currencies").map { try JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func rates(from start: RateDate, to end: RateDate) async throws -> [DailyRates] {
        guard let body = try await get("\(start)..\(end)?base=EUR") else { return [] }
        // Frankfurter snaps a start on a non-publication day back to the previous one; drop those.
        return try Self.decodeTimeseries(body).filter { (start...end).contains($0.date) }
    }

    /// Decodes `{"base":"EUR","start_date":…,"rates":{"2026-11-18":{"USD":1.0968,…},…}}`.
    /// Numbers go straight into `Decimal`, so `1.0968` stays exactly `1.0968`.
    static func decodeTimeseries(_ data: Data) throws -> [DailyRates] {
        struct Response: Decodable {
            let rates: [String: [String: Decimal]]
        }
        return try JSONDecoder().decode(Response.self, from: data).rates
            .map { key, rates in
                guard let date = RateDate(key) else { throw SourceError.invalidDate(key) }
                return DailyRates(date: date, rates: rates)
            }
            .sorted { $0.date < $1.date }
    }

    /// GET with retries. Returns `nil` for `404`.
    private func get(_ path: String) async throws -> Data? {
        let uri = URI(string: baseURL + path)
        var attempt = 1
        while true {
            do {
                let response = try await client.get(uri) { request in
                    request.headers.replaceOrAdd(name: .accept, value: "application/json")
                    request.timeout = requestTimeout
                }
                switch response.status.code {
                case 200..<300:
                    return response.body.map { Data(buffer: $0) } ?? Data()
                case 404:
                    return nil
                case 500..<600, 429:
                    throw SourceError.serverError(response.status, path: path)
                default:
                    throw SourceError.unexpectedStatus(response.status, path: path)
                }
            } catch let error as SourceError {
                guard case .serverError = error, attempt < maxAttempts else { throw error }
                try await backOff(after: error, attempt: &attempt)
            } catch {
                // Transport errors: DNS, connection reset, timeout.
                guard attempt < maxAttempts else { throw error }
                try await backOff(after: error, attempt: &attempt)
            }
        }
    }

    private func backOff(after error: any Error, attempt: inout Int) async throws {
        logger.warning("Upstream request failed (attempt \(attempt) of \(maxAttempts)), retrying: \(error)")
        try await Task.sleep(for: retryDelay * attempt)
        attempt += 1
    }
}
