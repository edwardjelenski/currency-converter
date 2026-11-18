import Foundation
import Testing
@testable import CurrencyConverter

struct RateHistoryAPITests {
    let api = { (http: MockHTTPClient) in ServerRatesAPI(baseURL: URL(string: "http://127.0.0.1:8080")!, http: http) }

    @Test func requestsOnePairForTheRange() async throws {
        let http = MockHTTPClient(status: 200, body: #"{"base":"USD","start":"2026-10-18","end":"2026-11-18","rates":{}}"#)
        _ = try await api(http).history(
            base: "USD", target: "EUR",
            start: RateDay.date(from: "2026-10-18")!, end: RateDay.date(from: "2026-11-18")!
        )
        #expect(http.lastRequest?.url?.absoluteString
            == "http://127.0.0.1:8080/timeseries?base=USD&symbols=EUR&start=2026-10-18&end=2026-11-18")
    }

    @Test func pointsAreSortedExactAndSkipDaysWithoutTheTarget() async throws {
        let body = #"""
        {"base":"USD","start":"2026-11-12","end":"2026-11-18","rates":{
          "2026-11-18":{"EUR":"0.911743"},
          "2026-11-12":{"EUR":"0.902446"},
          "2026-11-13":{"GBP":"0.756053"}
        }}
        """#
        let history = try await api(MockHTTPClient(status: 200, body: body))
            .history(base: "USD", target: "EUR", start: .now, end: .now)

        #expect(history.points.map(\.day) == ["2026-11-12", "2026-11-18"])
        #expect(history.points.last?.rate == Decimal(string: "0.911743"))
        #expect(history.base == "USD")
        #expect(history.target == "EUR")
    }

    @Test func noDataIsATypedServerError() async {
        let http = MockHTTPClient(status: 404, body: #"{"error":{"code":"no_data","message":"No rates for EUR between 2020-01-01 and 2020-02-01."}}"#)
        await #expect(throws: RatesAPIError.server(status: 404, code: "no_data", message: "No rates for EUR between 2020-01-01 and 2020-02-01.")) {
            try await api(http).history(base: "USD", target: "EUR", start: .now, end: .now)
        }
    }

    @Test func invalidRateIsRejected() async {
        let http = MockHTTPClient(status: 200, body: #"{"base":"USD","rates":{"2026-11-18":{"EUR":"-1"}}}"#)
        await #expect(throws: RatesAPIError.invalidRate(currency: "EUR", value: "-1")) {
            try await api(http).history(base: "USD", target: "EUR", start: .now, end: .now)
        }
    }
}
