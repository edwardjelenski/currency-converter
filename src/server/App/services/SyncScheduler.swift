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

    func stop() {
        task?.cancel()
        task = nil
        nextRunAt = nil
    }

    /// Startup sync, then scheduled syncs until `sleep` throws (cancellation).
    func runLoop() async {
        // Backfill on the first start, catch up missed days on later ones.
        await syncLoggingErrors(trigger: .startup)

        while !Task.isCancelled {
            let now = service.now()
            let hasToday = (try? await service.hasRatesForToday()) ?? false
            let next = schedule.nextAttempt(after: now, hasRatesForToday: hasToday)
            nextRunAt = next
            logger.info("Next sync at \(Self.format(next, in: schedule.timeZone))")
            do {
                try await sleep(next, now)
            } catch {
                return // cancelled on shutdown
            }
            await syncLoggingErrors(trigger: .scheduled)
        }
    }

    private func syncLoggingErrors(trigger: SyncRun.Trigger) async {
        do {
            try await service.sync(trigger: trigger)
        } catch {
            // Already logged and recorded in sync_runs; the next attempt follows the schedule.
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
        await scheduler.start()
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
