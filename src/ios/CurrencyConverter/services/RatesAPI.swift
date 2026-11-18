import Foundation

/// Our server's REST API (docs/architecture.md, section 3).
protocol RatesAPI: Sendable {
    /// `GET /rates?base=…`, conditional on `etag` when given.
    func latestRates(base: String, ifNoneMatch etag: String?) async throws -> Conditional<ExchangeRates>
}

/// Result of a conditional GET.
enum Conditional<Value: Sendable>: Sendable {
    /// `200`: a new body, its `ETag`, and `max-age` from `Cache-Control` if any.
    case modified(Value, etag: String?, maxAge: TimeInterval?)
    /// `304`: what we have is still current for another `maxAge` seconds.
    case notModified(maxAge: TimeInterval?)
}

enum RatesAPIError: LocalizedError, Equatable {
    /// The server answered with its JSON error format.
    case server(status: Int, code: String, message: String)
    /// Any other unexpected status.
    case unexpectedStatus(Int)
    /// `304` although we sent no `If-None-Match`.
    case unexpectedNotModified
    /// A rate in the body isn't a decimal number.
    case invalidRate(currency: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .server(_, _, message): message
        case let .unexpectedStatus(status): "The server responded with status \(status)."
        case .unexpectedNotModified: "The server responded 304 to an unconditional request."
        case let .invalidRate(currency, value): "The server sent an invalid \(currency) rate '\(value)'."
        }
    }
}
