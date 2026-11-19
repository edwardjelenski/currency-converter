import Foundation
import Testing
@testable import CurrencyConverter

@MainActor
struct RateHistoryViewModelTests {
    let month = makeHistory([("2026-10-20", "0.90"), ("2026-11-18", "0.9117")])

    private func makeModel(_ api: MockRatesAPI, period: HistoryPeriod = .month) -> RateHistoryViewModel {
        RateHistoryViewModel(
            base: "USD", target: "EUR", period: period,
            repository: RateHistoryRepository(api: api),
            locale: Locale(identifier: "en_US")
        )
    }

    @Test func loadsChart() async {
        let api = MockRatesAPI()
        await api.setHistory(.success(month))
        let model = makeModel(api)

        await model.load()

        #expect(model.content == .chart(month))
        #expect(model.staleNotice == nil)
        #expect(model.loadedAt != nil)
    }

    @Test func noDataIsEmptyState() async {
        let api = MockRatesAPI()
        await api.setHistory(.failure(RatesAPIError.server(status: 404, code: "no_data", message: "No rates")))
        let model = makeModel(api)

        await model.load()

        guard case .empty = model.content else {
            Issue.record("Expected empty, got \(model.content)")
            return
        }
    }

    @Test func singleDayIsEmptyState() async {
        let api = MockRatesAPI()
        await api.setHistory(.success(makeHistory([("2026-11-18", "0.91")])))
        let model = makeModel(api, period: .week)

        await model.load()

        guard case let .empty(message) = model.content else {
            Issue.record("Expected empty, got \(model.content)")
            return
        }
        // Language-independent: the simulator may run in Russian.
        #expect(message == String(localized: "Not enough data to draw \("USD → EUR") for \(HistoryPeriod.week.displayName). The ECB publishes rates on working days only."))
    }

    @Test(arguments: [URLError.Code.cannotConnectToHost, .notConnectedToInternet, .timedOut])
    func offlineWithoutDataIsOfflineError(code: URLError.Code) async {
        let api = MockRatesAPI()
        await api.setHistory(.failure(URLError(code)))
        let model = makeModel(api)

        await model.load()

        guard case let .failed(failure) = model.content else {
            Issue.record("Expected failure, got \(model.content)")
            return
        }
        #expect(failure.isOffline)
        #expect(failure.title == String(localized: "No connection"))
    }

    @Test func notReadyServerIsExplainedInTheUsersLanguage() async {
        let api = MockRatesAPI()
        await api.setHistory(.failure(RatesAPIError.server(status: 503, code: "not_ready", message: "Rates are still being loaded. Try again shortly.")))
        let model = makeModel(api)

        await model.load()

        // Review I5: the server's English text is not shown as is.
        #expect(model.content == .failed(.init(
            title: String(localized: "Couldn't load history"),
            message: String(localized: "The server is still loading rates. Try again in a minute."),
            isOffline: false
        )))
    }

    @Test func offlineReloadKeepsChartFromMemoryWithNotice() async {
        let api = MockRatesAPI()
        await api.setHistory(.success(month))
        let model = makeModel(api)
        await model.load()

        await api.setHistory(.failure(URLError(.cannotConnectToHost)))
        await model.load()

        #expect(model.content == .chart(month))
        #expect(model.staleNotice == String(localized: "Can't reach the rates server. Check your connection and try again."))
    }

    @Test func periodSelectsTheRequestedRange() async {
        let api = MockRatesAPI()
        await api.setHistory(.success(month))
        let model = makeModel(api)

        model.period = .year
        await model.load()

        let request = await api.historyRequests.last
        let days = request.map { Calendar.current.dateComponents([.day], from: $0.start, to: $0.end).day ?? 0 }
        #expect((365...366).contains(days ?? 0))
        #expect(request?.base == "USD")
        #expect(request?.target == "EUR")
    }

    @Test func swapReversesThePairAndTheRequest() async {
        let api = MockRatesAPI()
        await api.setHistory(.success(month))
        let model = makeModel(api)
        let before = model.requestID

        model.swapPair()
        await model.load()

        #expect(model.title == "EUR → USD")
        #expect(model.requestID != before)
        #expect(await api.historyRequests.last?.base == "EUR")
    }

    @Test func formatsChangeWithSign() {
        let model = makeModel(MockRatesAPI())
        #expect(model.format(change: Decimal(string: "0.0123")!) == "+1.23%")
        #expect(model.format(change: Decimal(string: "-0.004")!) == "-0.40%")
        #expect(model.format(rate: Decimal(string: "0.911743")!) == "0.911743")
        #expect(model.format(rate: Decimal(string: "159.418")!) == "159.418")
    }

    @Test func reopeningTheScreenOfflineShowsWhatWasLoaded() async {
        // One repository per app session, a new view model per opened screen.
        let api = MockRatesAPI()
        await api.setHistory(.success(month))
        let repository = RateHistoryRepository(api: api)
        let first = RateHistoryViewModel(base: "USD", target: "EUR", period: .month, repository: repository, locale: Locale(identifier: "en_US"))
        await first.load()

        await api.setHistory(.failure(URLError(.notConnectedToInternet)))
        let reopened = RateHistoryViewModel(base: "USD", target: "EUR", period: .month, repository: repository, locale: Locale(identifier: "en_US"))
        await reopened.load()

        #expect(reopened.content == .chart(month))
        #expect(reopened.staleNotice != nil)
        #expect(reopened.loadedAt != nil)
    }

    @Test func otherPeriodOfflineIsNotServedFromMemory() async {
        let api = MockRatesAPI()
        await api.setHistory(.success(month))
        let repository = RateHistoryRepository(api: api)
        let model = RateHistoryViewModel(base: "USD", target: "EUR", period: .month, repository: repository, locale: Locale(identifier: "en_US"))
        await model.load()

        await api.setHistory(.failure(URLError(.notConnectedToInternet)))
        model.period = .year
        await model.load()

        guard case let .failed(failure) = model.content else {
            Issue.record("Expected an offline error for a period never loaded, got \(model.content)")
            return
        }
        #expect(failure.isOffline)
    }
}
