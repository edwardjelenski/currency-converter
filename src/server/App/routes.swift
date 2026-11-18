import Vapor

/// REST endpoints, see docs/architecture.md section 3.
func routes(_ app: Application) throws {
    try app.register(collection: CurrenciesController())
    try app.register(collection: RatesController())
    try app.register(collection: TimeseriesController())
    try app.register(collection: HealthController())
}
