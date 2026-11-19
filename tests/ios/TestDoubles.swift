import Foundation
@testable import CurrencyConverter

/// `RatesAPI` that answers from a script and records what it was asked.
actor MockRatesAPI: RatesAPI {
    enum Reply: Sendable {
        case ok(ExchangeRates, etag: String, maxAge: TimeInterval?)
        case notModified(maxAge: TimeInterval?)
        case failure(URLError)
    }

    struct HistoryRequest: Sendable, Equatable {
        let base: String
        let target: String
        let start: Date
        let end: Date
    }

    private var reply: Reply
    private(set) var receivedETags: [String?] = []
    private var historyReply: Result<RateHistory, any Error> = .failure(URLError(.badServerResponse))
    private(set) var historyRequests: [HistoryRequest] = []

    init(_ reply: Reply = .ok(.fixture, etag: "\"v1\"", maxAge: 3600)) {
        self.reply = reply
    }

    func setReply(_ reply: Reply) { self.reply = reply }
    func setHistory(_ result: Result<RateHistory, any Error>) { historyReply = result }

    var requestCount: Int { receivedETags.count }

    func latestRates(base: String, ifNoneMatch etag: String?) async throws -> Conditional<ExchangeRates> {
        receivedETags.append(etag)
        switch reply {
        case let .ok(rates, newETag, maxAge): return .modified(rates, etag: newETag, maxAge: maxAge)
        case let .notModified(maxAge): return .notModified(maxAge: maxAge)
        case let .failure(error): throw error
        }
    }

    func history(base: String, target: String, start: Date, end: Date) async throws -> RateHistory {
        historyRequests.append(HistoryRequest(base: base, target: target, start: start, end: end))
        return try historyReply.get()
    }
}

/// `HTTPClient` that returns one canned response and keeps the request.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    let status: Int
    let headers: [String: String]
    let body: String
    /// Thrown instead of answering, like a connection failure.
    let failure: URLError?

    init(status: Int, headers: [String: String] = [:], body: String = "", failure: URLError? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.failure = failure
    }

    var lastRequest: URLRequest? { lock.withLock { requests.last } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        if let failure { throw failure }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

/// A clock the repository reads through a `@Sendable` closure.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_795_000_000)) { current = date }
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
}

extension ExchangeRates {
    /// Simple, exact numbers so assertions don't depend on floating point.
    static let fixture = ExchangeRates(
        base: "EUR",
        date: "2026-11-18",
        rates: ["USD": 2, "GBP": 1, "JPY": 200]
    )

    static let nextDay = ExchangeRates(
        base: "EUR",
        date: "2026-11-19",
        rates: ["USD": 2.5, "GBP": 1, "JPY": 200]
    )
}

extension CachedRates {
    static func fixture(etag: String? = "\"v1\"", at date: Date = .now, maxAge: TimeInterval = 3600) -> CachedRates {
        CachedRates(rates: .fixture, etag: etag, fetchedAt: date, validatedAt: date, expiresAt: date.addingTimeInterval(maxAge))
    }
}

func makeTemporaryCache() -> RatesCache {
    RatesCache(fileURL: URL.temporaryDirectory.appending(path: "rates-\(UUID().uuidString).json"))
}

func makeIsolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
}

/// Builds a history from `yyyy-MM-dd: rate` pairs.
func makeHistory(base: String = "USD", target: String = "EUR", _ points: [(String, String)]) -> RateHistory {
    RateHistory(base: base, target: target, points: points.map { day, rate in
        RatePoint(day: day, date: RateDay.date(from: day)!, rate: Decimal(string: rate)!)
    })
}

/// Holds every `latestRates` call until the test releases it, to make overlapping
/// refreshes deterministic.
actor GatedRatesAPI: RatesAPI {
    private(set) var callCount = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func latestRates(base: String, ifNoneMatch etag: String?) async throws -> Conditional<ExchangeRates> {
        callCount += 1
        await withCheckedContinuation { waiting.append($0) }
        return .modified(.fixture, etag: "\"v1\"", maxAge: 3600)
    }

    func history(base: String, target: String, start: Date, end: Date) async throws -> RateHistory {
        throw URLError(.badServerResponse)
    }

    func releaseWaiting() {
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// Yields until `condition` holds (or gives up after a while, letting the expectation fail).
@MainActor
func waitUntil(_ condition: () async -> Bool) async {
    var attempts = 0
    while attempts < 10_000, await !condition() {
        attempts += 1
        await Task.yield()
    }
}
