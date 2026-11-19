import Fluent
import Vapor

/// `GET /health`: what's in the database and how the last sync went.
/// `503` until the first rates are stored, so the Compose healthcheck reflects readiness.
struct HealthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("health", use: index)
    }

    func index(req: Request) async throws -> Response {
        let store = RatesStore(database: req.db)
        let latest = try await store.latestDate()
        let storedDays = try await store.storedDaysCount()
        let lastFinished = try await SyncRun.query(on: req.db)
            .filter(\.$status !~ [.running, .interrupted])
            .sort(\.$id, .descending)
            .first()
        let inProgress = try await SyncRun.query(on: req.db)
            .filter(\.$status == .running)
            .count() > 0
        let nextSyncAt = await req.application.syncScheduler?.nextRunAt

        let status: HealthResponse.Status =
            if latest == nil { .notReady }
            else if lastFinished?.status == .failed { .degraded }
            else { .ok }

        let body = HealthResponse(
            status: status,
            latestRateDate: latest?.description,
            storedDays: storedDays,
            lastSync: lastFinished.map {
                .init(
                    trigger: $0.trigger.rawValue,
                    status: $0.status.rawValue,
                    startedAt: $0.startedAt,
                    finishedAt: $0.finishedAt,
                    datesAdded: $0.datesAdded,
                    error: $0.error
                )
            },
            syncInProgress: inProgress,
            nextSyncAt: nextSyncAt
        )
        return try JSONResponse.make(body, status: status == .notReady ? .serviceUnavailable : .ok, cache: .noStore)
    }
}
