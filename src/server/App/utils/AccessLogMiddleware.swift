import Vapor

/// One line per request with the final status, e.g.
/// `GET /rates?base=EUR → 304 (If-None-Match) 2ms`.
/// Replaces Vapor's `RouteLoggingMiddleware`, which logs only method and path, so a
/// `304` can't be told apart from a full `200` in the logs.
struct AccessLogMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let start = ContinuousClock.now
        let response = try await next.respond(to: request)
        let elapsed = start.duration(to: .now)
        let milliseconds = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        let conditional = request.headers.first(name: .ifNoneMatch) == nil ? "" : " (If-None-Match)"
        request.logger.info("\(request.method) \(request.url) → \(response.status.code)\(conditional) \(milliseconds)ms")
        return response
    }
}
