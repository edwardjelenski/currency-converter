import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// tests/fixtures/cross-rates.json — the same vectors run in tests/ios.
struct CrossRateFixture: Decodable, Sendable {
    struct CrossRate: Decodable, Sendable, CustomTestStringConvertible {
        let from: String
        let to: String
        /// nil: one of the currencies is unknown.
        let rate: String?
        var testDescription: String { "\(from)→\(to)" }
    }

    let date: String
    let rates: [String: String]
    let crossRates: [CrossRate]

    /// Read from the repository next to this file; SwiftPM can't bundle files outside the target.
    static let shared: CrossRateFixture = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // tests/server
            .deletingLastPathComponent()      // tests
            .appending(path: "fixtures/cross-rates.json")
        do {
            return try JSONDecoder().decode(CrossRateFixture.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Can't read \(url.path): \(error)")
        }
    }()

    func isKnown(_ code: String) -> Bool { code == "EUR" || rates[code] != nil }
}

@Suite(.serialized)
struct CrossRateVectorTests {
    static let fixture = CrossRateFixture.shared

    private func seed(_ app: Application) async throws {
        let store = RatesStore(database: app.db)
        try await store.upsert(currencies: Dictionary(uniqueKeysWithValues: Self.fixture.rates.keys.map { ($0, $0) }))
        try await store.upsert(days: [DailyRates(
            date: RateDate(Self.fixture.date)!,
            rates: Self.fixture.rates.mapValues { Decimal(rateText: $0)! }
        )])
    }

    @Test(arguments: fixture.crossRates)
    func ratesEndpointMatchesVector(_ vector: CrossRateFixture.CrossRate) async throws {
        try await withApp(configure: configureForTests) { app in
            try await seed(app)
            try await app.testing().test(.GET, "rates?base=\(vector.from)&date=\(Self.fixture.date)") { res async throws in
                guard Self.fixture.isKnown(vector.from) else {
                    #expect(res.status == .badRequest)
                    #expect(res.errorBody?.code == "unknown_currency")
                    #expect(vector.rate == nil)
                    return
                }
                #expect(res.status == .ok)
                let returned = try res.content.decode(RatesResponse.self).rates[vector.to]
                if vector.from == vector.to {
                    // The API leaves the base itself out of `rates`; the vector says 1.
                    #expect(returned == nil)
                    #expect(vector.rate == "1")
                } else {
                    #expect(returned.flatMap(Decimal.init(rateText:)) == vector.rate.flatMap(Decimal.init(rateText:)),
                            "API returned \(returned ?? "nil"), vector says \(vector.rate ?? "nil")")
                }
            }
        }
    }

    @Test(arguments: fixture.crossRates.filter {
        $0.rate != nil && $0.from != $0.to
    })
    func timeseriesUsesTheSameMath(_ vector: CrossRateFixture.CrossRate) async throws {
        let day = Self.fixture.date
        try await withApp(configure: configureForTests) { app in
            try await seed(app)
            try await app.testing().test(.GET, "timeseries?base=\(vector.from)&symbols=\(vector.to)&start=\(day)&end=\(day)") { res async throws in
                #expect(res.status == .ok)
                let returned = try res.content.decode(TimeseriesResponse.self).rates[day]?[vector.to]
                #expect(returned.flatMap(Decimal.init(rateText:)) == vector.rate.flatMap(Decimal.init(rateText:)))
            }
        }
    }
}
