import Foundation
import Testing
@testable import CurrencyConverter

struct ServerRatesAPITests {
    let baseURL = URL(string: "http://127.0.0.1:8080")!
    let ratesBody = #"{"base":"EUR","date":"2026-11-18","rates":{"GBP":"0.8329","JPY":"174.85","USD":"1.0968"}}"#

    @Test func requestsRatesWithBaseAndConditionalHeader() async throws {
        let http = MockHTTPClient(status: 304, headers: ["Cache-Control": "public, max-age=3600"])
        let api = ServerRatesAPI(baseURL: baseURL, http: http)

        _ = try await api.latestRates(base: "EUR", ifNoneMatch: "\"abc\"")

        let request = try #require(http.lastRequest)
        #expect(request.url?.absoluteString == "http://127.0.0.1:8080/rates?base=EUR")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
    }

    @Test func firstRequestHasNoConditionalHeader() async throws {
        let http = MockHTTPClient(status: 200, body: ratesBody)
        _ = try await ServerRatesAPI(baseURL: baseURL, http: http).latestRates(base: "EUR", ifNoneMatch: nil)
        #expect(http.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func okDecodesStringRatesExactlyWithETagAndMaxAge() async throws {
        let http = MockHTTPClient(
            status: 200,
            headers: ["ETag": "\"8cbb9eb2\"", "Cache-Control": "public, max-age=3600"],
            body: ratesBody
        )

        let result = try await ServerRatesAPI(baseURL: baseURL, http: http).latestRates(base: "EUR", ifNoneMatch: nil)

        guard case let .modified(rates, etag, maxAge) = result else {
            Issue.record("Expected .modified, got \(result)")
            return
        }
        #expect(rates.date == "2026-11-18")
        #expect(rates.rates["USD"] == Decimal(string: "1.0968"))
        #expect(rates.rates["JPY"]?.description == "174.85")
        #expect(etag == "\"8cbb9eb2\"")
        #expect(maxAge == 3600)
    }

    @Test func notModifiedKeepsMaxAge() async throws {
        let http = MockHTTPClient(status: 304, headers: ["Cache-Control": "public, max-age=3600"])
        let result = try await ServerRatesAPI(baseURL: baseURL, http: http).latestRates(base: "EUR", ifNoneMatch: "\"x\"")
        guard case let .notModified(maxAge) = result else {
            Issue.record("Expected .notModified, got \(result)")
            return
        }
        #expect(maxAge == 3600)
    }

    @Test func serverErrorFormatBecomesTypedError() async {
        let http = MockHTTPClient(status: 503, body: #"{"error":{"code":"not_ready","message":"Rates are still being loaded. Try again shortly."}}"#)
        await #expect(throws: RatesAPIError.server(status: 503, code: "not_ready", message: "Rates are still being loaded. Try again shortly.")) {
            try await ServerRatesAPI(baseURL: baseURL, http: http).latestRates(base: "EUR", ifNoneMatch: nil)
        }
    }

    @Test func otherStatusWithoutErrorBody() async {
        let http = MockHTTPClient(status: 502, body: "<html>Bad Gateway</html>")
        await #expect(throws: RatesAPIError.unexpectedStatus(502)) {
            try await ServerRatesAPI(baseURL: baseURL, http: http).latestRates(base: "EUR", ifNoneMatch: nil)
        }
    }

    @Test(arguments: ["abc", "-1.2", "0"])
    func invalidRateIsRejected(value: String) async {
        let http = MockHTTPClient(status: 200, body: #"{"base":"EUR","date":"2026-11-18","rates":{"USD":"\#(value)"}}"#)
        await #expect(throws: RatesAPIError.invalidRate(currency: "USD", value: value)) {
            try await ServerRatesAPI(baseURL: baseURL, http: http).latestRates(base: "EUR", ifNoneMatch: nil)
        }
    }

    @Test func notModifiedWithoutETagIsAnError() async {
        let http = MockHTTPClient(status: 304)
        await #expect(throws: RatesAPIError.unexpectedNotModified) {
            try await ServerRatesAPI(baseURL: baseURL, http: http).latestRates(base: "EUR", ifNoneMatch: nil)
        }
    }

    @Test(arguments: [
        ("public, max-age=3600", 3600.0),
        ("max-age=60", 60),
        ("public, max-age=31536000, immutable", 31_536_000),
        ("no-store", 0),
        ("NO-CACHE", 0),
    ] as [(String, TimeInterval)])
    func parsesMaxAge(header: String, expected: TimeInterval) {
        #expect(ServerRatesAPI.maxAge(fromCacheControl: header) == expected)
    }

    @Test func missingOrUnknownCacheControlHasNoMaxAge() {
        #expect(ServerRatesAPI.maxAge(fromCacheControl: nil) == nil)
        #expect(ServerRatesAPI.maxAge(fromCacheControl: "public") == nil)
    }
}
