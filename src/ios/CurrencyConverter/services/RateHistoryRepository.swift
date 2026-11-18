import Foundation

/// Rate history from `/timeseries`, remembered in memory for this app session.
///
/// History isn't kept on disk (docs/architecture.md, section 6): the converter must work
/// offline, the chart is a nice-to-have. Within a session, a period opened before is shown
/// instantly and refreshed in the background.
struct RateHistoryRepository: Sendable {
    struct Key: Hashable, Sendable {
        let base: String
        let target: String
        let period: HistoryPeriod
        /// Part of the key so that yesterday's "last month" isn't shown as today's.
        let endDay: String
    }

    struct Entry: Sendable {
        let history: RateHistory
        let loadedAt: Date
    }

    let api: any RatesAPI
    private let memory = MemoryCache()
    var now: @Sendable () -> Date = { .now }

    init(api: any RatesAPI, now: @escaping @Sendable () -> Date = { .now }) {
        self.api = api
        self.now = now
    }

    func key(base: String, target: String, period: HistoryPeriod) -> Key {
        Key(base: base, target: target, period: period, endDay: RateDay.string(from: now()))
    }

    func cached(_ key: Key) async -> Entry? {
        await memory.entry(for: key)
    }

    func load(_ key: Key) async throws -> RateHistory {
        let end = now()
        let history = try await api.history(
            base: key.base,
            target: key.target,
            start: key.period.start(endingOn: end),
            end: end
        )
        await memory.store(Entry(history: history, loadedAt: now()), for: key)
        return history
    }

    private actor MemoryCache {
        private var entries: [Key: Entry] = [:]
        func entry(for key: Key) -> Entry? { entries[key] }
        func store(_ entry: Entry, for key: Key) { entries[key] = entry }
    }
}
