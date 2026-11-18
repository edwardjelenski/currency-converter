import Vapor

/// `GET /rates?base=EUR&date=2026-11-18`
struct RatesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("rates", use: index)
    }

    func index(req: Request) async throws -> Response {
        let base = try req.currencyParameter("base") ?? "EUR"
        let date = try req.dateParameter("date")
        let (response, isFinal) = try await RatesService(database: req.db).rates(base: base, date: date)
        return try JSONResponse.make(response, cache: isFinal ? .immutable : .short)
    }
}
