import Foundation
import OSLog

/// Turns any error into a short, localized message for the UI. The details (server
/// texts, status codes, decoding errors) go to the log, never on screen.
enum UserFacingError {
    private static let logger = Logger(subsystem: "com.eduardyelenskiy.currencyconverter", category: "errors")

    static func isOffline(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return offlineCodes.contains(error.code)
    }

    static func message(for error: any Error) -> String {
        logger.error("\(String(reflecting: error), privacy: .public)")
        if isOffline(error) {
            return String(localized: "Can't reach the rates server. Check your connection and try again.")
        }
        if case let .server(_, code, _) = error as? RatesAPIError, code == "not_ready" {
            return String(localized: "The server is still loading rates. Try again in a minute.")
        }
        return String(localized: "The rates server sent an unexpected response. Try again later.")
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut,
        .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed,
    ]
}
