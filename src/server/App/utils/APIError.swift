import Vapor

/// An error returned to API clients as
/// `{"error": {"code": "...", "message": "..."}}` (see docs/architecture.md, "Ошибки").
struct APIError: Error, Sendable, Equatable {
    let status: HTTPResponseStatus
    let code: String
    let message: String

    static func invalidParameter(_ message: String) -> APIError {
        APIError(status: .badRequest, code: "invalid_parameter", message: message)
    }

    static func unknownCurrency(_ code: String) -> APIError {
        APIError(status: .badRequest, code: "unknown_currency", message: "Currency '\(code)' is not supported.")
    }

    static func noData(_ message: String) -> APIError {
        APIError(status: .notFound, code: "no_data", message: message)
    }

    static let notReady = APIError(
        status: .serviceUnavailable,
        code: "not_ready",
        message: "Rates are still being loaded. Try again shortly."
    )
}

/// JSON body of every error response.
struct ErrorResponse: Codable, Sendable {
    struct Body: Codable, Sendable {
        let code: String
        let message: String
    }

    let error: Body
}
