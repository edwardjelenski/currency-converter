import Foundation
import Observation

@MainActor
@Observable
final class RateHistoryViewModel {
    enum Content: Equatable {
        case loading
        case chart(RateHistory)
        /// Nothing to draw for this pair and period; the text says why.
        case empty(String)
        case failed(Failure)
    }

    struct Failure: Equatable {
        let title: String
        let message: String
        let isOffline: Bool
    }

    private(set) var base: String
    private(set) var target: String
    var period: HistoryPeriod
    private(set) var content: Content
    /// Older data is on screen but the latest reload failed.
    private(set) var staleNotice: String?
    /// When the data on screen was loaded from the server.
    private(set) var loadedAt: Date?

    @ObservationIgnored private let repository: RateHistoryRepository
    @ObservationIgnored let locale: Locale
    /// The request whose result is on screen, so reloading it (pull to refresh) keeps the
    /// chart instead of flashing a spinner.
    @ObservationIgnored private var shownKey: RateHistoryRepository.Key?

    init(
        base: String,
        target: String,
        period: HistoryPeriod = .month,
        repository: RateHistoryRepository,
        locale: Locale = .current,
        initialContent: Content = .loading
    ) {
        self.base = base
        self.target = target
        self.period = period
        self.repository = repository
        self.locale = locale
        self.content = initialContent
        if case .chart = initialContent {
            shownKey = repository.key(base: base, target: target, period: period)
        }
    }

    var title: String { "\(base) → \(target)" }

    /// Changes whenever a different request is needed; drives `.task(id:)`.
    var requestID: String { "\(base)-\(target)-\(period.rawValue)" }

    var history: RateHistory? {
        if case let .chart(history) = content { history } else { nil }
    }

    /// Shows what's in memory for this period right away, then asks the server.
    func load() async {
        let key = repository.key(base: base, target: target, period: period)
        if let cached = await repository.cached(key) {
            // The user may have switched period or pair during the await.
            guard isCurrent(key) else { return }
            show(cached.history, for: key)
            loadedAt = cached.loadedAt
        } else if shownKey != key {
            content = .loading
        }
        staleNotice = nil

        do {
            let history = try await repository.load(key)
            guard isCurrent(key) else { return }
            show(history, for: key)
            loadedAt = .now
        } catch is CancellationError {
            // Period switched or the screen closed.
        } catch let error as URLError where error.code == .cancelled {
            // Same, surfaced by URLSession.
        } catch {
            guard isCurrent(key) else { return }
            handle(error)
        }
    }

    func swapPair() {
        (base, target) = (target, base)
    }

    // MARK: Formatting

    nonisolated func format(rate: Decimal) -> String {
        rate.formatted(.number.precision(.significantDigits(3...6)).locale(locale))
    }

    nonisolated func format(change ratio: Decimal) -> String {
        ratio.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()).locale(locale))
    }

    nonisolated func format(signedRate value: Decimal) -> String {
        value.formatted(.number.precision(.significantDigits(1...4)).sign(strategy: .always()).locale(locale))
    }

    // MARK: Private

    private func isCurrent(_ key: RateHistoryRepository.Key) -> Bool {
        !Task.isCancelled && key.base == base && key.target == target && key.period == period
    }

    private func show(_ history: RateHistory, for key: RateHistoryRepository.Key) {
        shownKey = key
        if history.isChartable {
            content = .chart(history)
        } else {
            content = .empty(String(
                localized: "Not enough data to draw \(title) for \(period.displayName). The ECB publishes rates on working days only.",
                comment: "History empty state: fewer than two days of rates. First argument is a pair like 'USD → EUR', second a period like '1 week'"
            ))
        }
    }

    private func handle(_ error: any Error) {
        if case let .server(_, code, _) = error as? RatesAPIError, code == "no_data" {
            content = .empty(String(
                localized: "There are no \(title) rates for \(period.displayName). The currency may not have been published by the ECB in this period.",
                comment: "History empty state: no rates at all. First argument is a pair like 'USD → EUR', second a period like '1 month'"
            ))
            shownKey = nil
            return
        }
        let failure = Self.failure(for: error)
        if case .chart = content {
            // Keep the chart from memory, say it couldn't be refreshed.
            staleNotice = failure.message
        } else {
            content = .failed(failure)
            shownKey = nil
        }
    }

    static func failure(for error: any Error) -> Failure {
        let offline = UserFacingError.isOffline(error)
        return Failure(
            title: offline ? String(localized: "No connection") : String(localized: "Couldn't load history"),
            message: UserFacingError.message(for: error),
            isOffline: offline
        )
    }
}
