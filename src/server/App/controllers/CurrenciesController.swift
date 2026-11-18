import Vapor

/// `GET /currencies`
struct CurrenciesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("currencies", use: index)
    }

    func index(req: Request) async throws -> Response {
        let response = try await RatesService(database: req.db).currencies()
        return try JSONResponse.make(response, cache: .day)
    }
}
