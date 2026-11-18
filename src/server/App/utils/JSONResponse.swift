import Foundation
import Vapor

/// How long clients and proxies may reuse a response (docs/architecture.md, section 4).
enum CachePolicy: Sendable {
    /// Latest data: a new publication can arrive any working day.
    case short
    /// Rarely changing reference data (currency list).
    case day
    /// Past dates: ECB rates for a published day never change.
    case immutable
    /// Errors and health.
    case noStore

    var headerValue: String {
        switch self {
        case .short: "public, max-age=3600"
        case .day: "public, max-age=86400"
        case .immutable: "public, max-age=31536000, immutable"
        case .noStore: "no-store"
        }
    }
}

enum JSONResponse {
    /// Sorted keys make the body byte-for-byte stable, which the ETag relies on.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func make(_ value: some Encodable, status: HTTPResponseStatus = .ok, cache: CachePolicy) throws -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .json
        headers.replaceOrAdd(name: .cacheControl, value: cache.headerValue)
        return Response(status: status, headers: headers, body: .init(data: try encoder().encode(value)))
    }
}
