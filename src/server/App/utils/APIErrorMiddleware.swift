import Vapor

/// Turns every error into the API's single error format.
/// Replaces Vapor's default `ErrorMiddleware`, whose body is `{"error": true, "reason": …}`.
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            let apiError = Self.apiError(for: error)
            if apiError.status.code >= 500, apiError.code != APIError.notReady.code {
                request.logger.report(error: error)
            }
            let body = ErrorResponse(error: .init(code: apiError.code, message: apiError.message))
            return try JSONResponse.make(body, status: apiError.status, cache: .noStore)
        }
    }

    static func apiError(for error: any Error) -> APIError {
        switch error {
        case let error as APIError:
            return error
        case let abort as any AbortError:
            let code = switch abort.status {
            case .badRequest: "invalid_parameter"
            case .notFound: "not_found"
            case .methodNotAllowed: "method_not_allowed"
            case _ where abort.status.code < 500: "bad_request"
            default: "internal_error"
            }
            return APIError(status: abort.status, code: code, message: abort.reason)
        default:
            return APIError(status: .internalServerError, code: "internal_error", message: "Internal server error.")
        }
    }
}
