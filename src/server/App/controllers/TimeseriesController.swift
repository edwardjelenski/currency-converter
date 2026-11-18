import Vapor

/// `GET /timeseries?base=USD&symbols=GBP,JPY&start=2026-08-18&end=2026-11-18`
struct TimeseriesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("timeseries", use: index)
    }

    func index(req: Request) async throws -> Response {
        let base = try req.currencyParameter("base") ?? "EUR"
        let symbols = try req.currencyListParameter("symbols")
        let start = try req.requiredDateParameter("start")
        let end = try req.requiredDateParameter("end")
        let (response, isFinal) = try await RatesService(database: req.db)
            .timeseries(base: base, symbols: symbols, start: start, end: end)
        return try JSONResponse.make(response, cache: isFinal ? .immutable : .short)
    }
}
