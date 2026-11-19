import Foundation
import Vapor

/// Runs `RatesSyncService` on startup and then on the `SyncSchedule`.
///
/// A plain `Task` loop instead of Vapor Queues: scheduled jobs in Queues need a
/// queue backend (Redis), which would be an extra service for one job a day.
actor SyncScheduler {
    /// Waits until `target`; `now` is the service clock's current time. Throws when cancelled.
    typealias Sleep = @Sendable (_ target: Date, _ now: Date) async throws -> Void

    private let service: RatesSyncService
    private let schedule: SyncSchedule
    private let logger: Logger
    private let sleep: Sleep
    private var task: Task<Void, Never>?

    /// When the next scheduled run will happen; shown in `/health`.
    private(set) var nextRunAt: Date?

    /// `sleep` is replaced in tests with a fake clock that jumps straight to `target`.
    init(service: RatesSyncService, schedule: SyncSchedule, logger: Logger, sleep: @escaping Sleep = SyncScheduler.realSleep) {
        self.service = service
        self.schedule = schedule
        self.logger = logger
        self.sleep = sleep
    }

    static let realSleep: Sleep = { target, now in
        try await Task.sleep(for: .seconds(max(0, target.timeIntervalSince(now))))
    }

    func start() {
        guard task == nil else { return }
        task = Task { await self.runLoop() }
    }

    /// Cancels the loop and waits for it, so a sync in flight finishes (as `interrupted`)
    /// before Vapor shuts down the database and HTTP client under it.
    func stop() async {
        guard let task else { return }
        self.task = nil
        task.cancel()
        await task.value
        nextRunAt = nil
    }

    /// Startup sync, then scheduled syncs until `sleep` throws (cancellation).
    ///
    /// After a failed sync the next try comes after a growing pause (`failureRetryDelays`),
    /// or at the next scheduled attempt if that is sooner, so a short upstream outage
    /// at startup doesn't leave the database empty until the next publication window.
    func runLoop() async {
        // Backfill on the first start, catch up missed days on later ones.
        var consecutiveFailures = await sync(trigger: .startup) ? 0 : 1

        while !Task.isCancelled {
            let now = service.now()
            let hasToday = (try? await service.hasRatesForToday()) ?? false
            var next = schedule.nextAttempt(after: now, hasRatesForToday: hasToday)
            if consecutiveFailures > 0 {
                next = min(next, now.addingTimeInterval(schedule.retryDelay(afterFailures: consecutiveFailures)))
            }
            nextRunAt = next
            logger.info("Next sync at \(Self.format(next, in: schedule.timeZone))")
            do {
                try await sleep(next, now)
            } catch {
                return // cancelled on shutdown
            }
            nextRunAt = nil
            consecutiveFailures = await sync(trigger: .scheduled) ? 0 : consecutiveFailures + 1
        }
    }

    /// `true` when the sync finished (with or without new data).
    private func sync(trigger: SyncRun.Trigger) async -> Bool {
        do {
            try await service.sync(trigger: trigger)
            return true
        } catch {
            // Already logged and recorded in sync_runs.
            return false
        }
    }

    private static func format(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits) \(timeZone: .identifier(.long))",
                timeZone: timeZone,
                calendar: Calendar(identifier: .gregorian)
            )
        )
    }
}

/// Starts the scheduler once the server has booted and stops it on shutdown.
struct SyncSchedulerLifecycle: LifecycleHandler {
    let scheduler: SyncScheduler

    func didBootAsync(_ application: Application) async throws {
        // Lifecycle handlers run for every command; only the server should sync,
        // not `App routes` or `App migrate`.
        guard Self.isServeCommand(application.environment.arguments) else { return }
        await scheduler.start()
    }

    /// `serve` is also Vapor's default command when none is given.
    static func isServeCommand(_ arguments: [String]) -> Bool {
        guard let command = arguments.dropFirst().first, !command.hasPrefix("-") else { return true }
        return command == "serve"
    }

    func shutdownAsync(_ application: Application) async {
        await scheduler.stop()
    }
}

extension Application {
    private struct SyncSchedulerKey: StorageKey {
        typealias Value = SyncScheduler
    }

    /// The running scheduler, if sync is enabled.
    var syncScheduler: SyncScheduler? {
        get { storage[SyncSchedulerKey.self] }
        set { storage[SyncSchedulerKey.self] = newValue }
    }
}
