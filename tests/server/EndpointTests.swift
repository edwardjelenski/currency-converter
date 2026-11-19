import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite(.serialized)
struct EndpointTests {
    // MARK: /currencies

    @Test func currenciesListsLatestDayPlusEuro() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "currencies") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(CurrenciesResponse.self)
                // BGN has rates only in 2025, so it is not offered.
                #expect(body.currencies.map(\.code) == ["EUR", "GBP", "JPY", "USD"])
                #expect(body.currencies.first { $0.code == "USD" }?.name == "United States Dollar")
                #expect(body.currencies.first { $0.code == "EUR" }?.name == "Euro")
            }
        }
    }

    // MARK: /rates

    @Test func ratesDefaultToLatestEuroRatesExactly() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "rates") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(RatesResponse.self)
                #expect(body == RatesResponse(base: "EUR", date: "2026-11-18", rates: ["GBP": "0.8329", "JPY": "174.85", "USD": "1.0968"]))
            }
        }
    }

    @Test func ratesForOtherBaseAreCrossRatesWithSixSignificantDigits() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "rates?base=usd") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(RatesResponse.self)
                #expect(body.base == "USD")
                // Expected values computed with Python's decimal module.
                #expect(body.rates == ["EUR": "0.911743", "GBP": "0.759391", "JPY": "159.418"])
            }
        }
    }

    @Test func dateWithoutPublicationFallsBackToPreviousDay() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "rates?date=2026-11-15") { res async throws in // Sunday
                #expect(res.status == .ok)
                #expect(try res.content.decode(RatesResponse.self).date == "2026-11-13")
            }
        }
    }

    @Test func currencyThatStoppedBeingPublishedWorksForPastDates() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing()
                .test(.GET, "rates?base=BGN") { res async throws in
                    #expect(res.status == .notFound)
                    #expect(res.errorBody?.code == "no_data")
                }
                .test(.GET, "rates?base=BGN&date=2025-12-31") { res async throws in
                    #expect(res.status == .ok)
                    #expect(try res.content.decode(RatesResponse.self).rates["EUR"] == "0.5113") // 1 / 1.9558, computed with Python decimal
                }
        }
    }

    // MARK: /timeseries

    @Test func timeseriesReturnsOnlyRequestedSymbolsPerPublicationDay() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "timeseries?base=USD&symbols=GBP&start=2026-11-12&end=2026-11-18") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(TimeseriesResponse.self)
                #expect(body.base == "USD")
                #expect(body.rates.keys.sorted() == ["2026-11-12", "2026-11-13", "2026-11-16", "2026-11-17", "2026-11-18"])
                #expect(body.rates["2026-11-17"] == ["GBP": "0.759038"])
                #expect(body.rates["2026-11-18"] == ["GBP": "0.759391"])
            }
        }
    }

    @Test func timeseriesSkipsDaysWithoutTheBaseCurrency() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "timeseries?base=BGN&start=2025-12-01&end=2026-11-18") { res async throws in
                #expect(res.status == .ok)
                #expect(try res.content.decode(TimeseriesResponse.self).rates.keys.sorted() == ["2025-12-31"])
            }
        }
    }

    // MARK: Errors

    @Test(arguments: [
        ("rates?base=US", "invalid_parameter"),
        ("rates?base=12A", "invalid_parameter"),
        ("rates?base=XYZ", "unknown_currency"),
        ("rates?date=2026-13-01", "invalid_parameter"),
        ("rates?date=yesterday", "invalid_parameter"),
        ("timeseries?end=2026-11-18", "invalid_parameter"),
        ("timeseries?start=2026-11-12", "invalid_parameter"),
        ("timeseries?start=2026-11-18&end=2026-11-12", "invalid_parameter"),
        ("timeseries?start=2020-01-01&end=2026-11-18", "invalid_parameter"),
        ("timeseries?start=2026-11-12&end=2026-11-18&symbols=USD,,GBP", "invalid_parameter"),
        ("timeseries?start=2026-11-12&end=2026-11-18&symbols=GBP,XYZ", "unknown_currency"),
        ("timeseries?base=USD&symbols=USD&start=2026-11-12&end=2026-11-18", "invalid_parameter"),
        ("rates?date=2026-+1-05", "invalid_parameter"),
    ])
    func badParametersAre400InTheErrorFormat(path: String, code: String) async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, path) { res async throws in
                #expect(res.status == .badRequest)
                let error = try #require(res.errorBody)
                #expect(error.code == code)
                #expect(!error.message.isEmpty)
                #expect(res.headers.first(name: .cacheControl) == "no-store")
                #expect(res.headers.first(name: .eTag) == nil)
            }
        }
    }

    @Test(arguments: [
        ("rates?date=2020-01-01", HTTPStatus.notFound, "no_data"),
        ("timeseries?start=2020-01-01&end=2020-02-01", .notFound, "no_data"),
        ("does-not-exist", .notFound, "not_found"),
    ])
    func notFoundUsesTheErrorFormat(path: String, status: HTTPStatus, code: String) async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, path) { res async throws in
                #expect(res.status == status)
                #expect(res.errorBody?.code == code)
            }
        }
    }

    @Test(arguments: ["currencies", "rates", "timeseries?start=2026-11-12&end=2026-11-18"])
    func emptyDatabaseIsNotReady(path: String) async throws {
        try await withApp(configure: configureForTests) { app in
            try await app.testing().test(.GET, path) { res async throws in
                #expect(res.status == .serviceUnavailable)
                #expect(res.errorBody?.code == "not_ready")
            }
        }
    }

    // MARK: /health

    @Test func healthReportsLatestDateAndLastSync() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(HealthResponse.self, using: Self.isoDecoder)
                #expect(body.status == .ok)
                #expect(body.latestRateDate == "2026-11-18")
                #expect(body.storedDays == 6)
                #expect(body.lastSync?.status == "success")
                #expect(body.lastSync?.trigger == "startup")
                #expect(body.lastSync?.datesAdded == 6)
                #expect(body.syncInProgress == false)
                #expect(res.headers.first(name: .cacheControl) == "no-store")
                #expect(res.headers.first(name: .eTag) == nil)
            }
        }
    }

    @Test func healthIsDegradedWhenLastSyncFailed() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            let failed = SyncRun(trigger: .scheduled, startedAt: .now, range: nil)
            failed.status = .failed
            failed.error = "Frankfurter latest responded 522"
            failed.finishedAt = .now
            try await failed.create(on: app.db)

            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .ok, "Stored rates are still served, so the container stays healthy")
                let body = try res.content.decode(HealthResponse.self, using: Self.isoDecoder)
                #expect(body.status == .degraded)
                #expect(body.lastSync?.error == "Frankfurter latest responded 522")
                #expect(body.latestRateDate == "2026-11-18")
            }
        }
    }

    @Test func healthIsNotReadyWithoutRates() async throws {
        try await withApp(configure: configureForTests) { app in
            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .serviceUnavailable)
                let body = try res.content.decode(HealthResponse.self, using: Self.isoDecoder)
                #expect(body.status == .notReady)
                #expect(body.storedDays == 0)
                #expect(body.latestRateDate == nil)
            }
        }
    }

    static let isoDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
