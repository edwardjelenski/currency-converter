import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite(.serialized)
struct HTTPCachingTests {
    @Test(arguments: [
        ("rates", "public, max-age=3600"),
        ("rates?date=2026-11-15", "public, max-age=31536000, immutable"),
        ("rates?date=2026-11-18", "public, max-age=31536000, immutable"),
        ("rates?date=2026-11-25", "public, max-age=3600"),
        ("currencies", "public, max-age=86400"),
        ("timeseries?start=2026-11-12&end=2026-11-18", "public, max-age=31536000, immutable"),
        ("timeseries?start=2026-11-12&end=2026-11-30", "public, max-age=3600"),
    ])
    func cacheControlDependsOnWhetherDataCanStillChange(path: String, cacheControl: String) async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, path) { res async throws in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: .cacheControl) == cacheControl)
            }
        }
    }

    @Test func etagIsStableSha256OfBody() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            var tags: [String] = []
            for _ in 0..<2 {
                try await app.testing().test(.GET, "rates?base=USD") { res async throws in
                    let tag = try #require(res.headers.first(name: .eTag))
                    #expect(tag.wholeMatch(of: /"[0-9a-f]{32}"/) != nil)
                    #expect(tag == HTTPCachingMiddleware.etag(for: Data(buffer: res.body)))
                    tags.append(tag)
                }
            }
            #expect(tags[0] == tags[1])
        }
    }

    @Test(arguments: ["{etag}", "W/{etag}", "\"other\", {etag}", "*"])
    func matchingIfNoneMatchGets304(ifNoneMatch: String) async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            let etag = try await Self.etag(app, "rates")
            let headers: HTTPHeaders = ["If-None-Match": ifNoneMatch.replacingOccurrences(of: "{etag}", with: etag)]
            try await app.testing().test(.GET, "rates", headers: headers) { res async throws in
                #expect(res.status == .notModified)
                #expect(res.body.readableBytes == 0)
                #expect(res.headers.first(name: .eTag) == etag)
                #expect(res.headers.first(name: .cacheControl) == "public, max-age=3600")
            }
        }
    }

    @Test func staleETagGetsFullResponse() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            try await app.testing().test(.GET, "rates", headers: ["If-None-Match": "\"0123456789abcdef0123456789abcdef\""]) { res async throws in
                #expect(res.status == .ok)
                #expect(res.body.readableBytes > 0)
            }
        }
    }

    @Test func newPublicationChangesETag() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            let before = try await Self.etag(app, "rates")

            try await RatesStore(database: app.db).upsert(days: [
                DailyRates(date: date("2026-11-19"), rates: ["USD": 1.1, "GBP": 0.83, "JPY": 175]),
            ])

            try await app.testing().test(.GET, "rates", headers: ["If-None-Match": before]) { res async throws in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: .eTag) != before)
                #expect(try res.content.decode(RatesResponse.self).date == "2026-11-19")
            }
        }
    }

    @Test func differentQueriesHaveDifferentETags() async throws {
        try await withApp(configure: configureForTests) { app in
            try await seedRates(app)
            let eur = try await Self.etag(app, "rates")
            let usd = try await Self.etag(app, "rates?base=USD")
            #expect(eur != usd)
        }
    }

    private static func etag(_ app: Application, _ path: String) async throws -> String {
        var tag: String?
        try await app.testing().test(.GET, path) { res async throws in
            tag = res.headers.first(name: .eTag)
        }
        return try #require(tag)
    }
}
