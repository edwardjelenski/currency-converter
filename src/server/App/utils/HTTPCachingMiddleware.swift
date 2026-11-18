import Crypto
import Foundation
import Vapor

/// Adds a strong `ETag` to successful GET responses and answers `304 Not Modified`
/// when the client's `If-None-Match` already has it.
///
/// The ETag is the first 16 bytes of the SHA-256 of the body, so it is always
/// correct without any manual versioning: same bytes, same tag.
/// `Cache-Control` is set by each route; responses marked `no-store` get no ETag.
struct HTTPCachingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        guard request.method == .GET || request.method == .HEAD,
              response.status == .ok,
              !(response.headers.first(name: .cacheControl)?.contains("no-store") ?? false),
              let body = response.body.data
        else { return response }

        let etag = Self.etag(for: body)
        response.headers.replaceOrAdd(name: .eTag, value: etag)

        guard Self.ifNoneMatch(request.headers[.ifNoneMatch], matches: etag) else { return response }
        let notModified = Response(status: .notModified)
        notModified.headers.replaceOrAdd(name: .eTag, value: etag)
        if let cacheControl = response.headers.first(name: .cacheControl) {
            notModified.headers.replaceOrAdd(name: .cacheControl, value: cacheControl)
        }
        return notModified
    }

    static func etag(for body: Data) -> String {
        let digest = SHA256.hash(data: body)
        return "\"" + digest.prefix(16).map { String(format: "%02x", $0) }.joined() + "\""
    }

    /// `If-None-Match` may list several tags, use weak `W/` tags, or `*`.
    static func ifNoneMatch(_ headerValues: [String], matches etag: String) -> Bool {
        let weakETag = "W/" + etag
        for value in headerValues {
            for part in value.split(separator: ",") {
                let tag = part.trimmingCharacters(in: .whitespaces)
                if tag == "*" || tag == etag || tag == weakETag { return true }
            }
        }
        return false
    }
}
