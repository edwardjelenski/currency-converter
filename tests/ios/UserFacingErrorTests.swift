import Foundation
import Testing
@testable import CurrencyConverter

/// Review I5: errors reach the UI as short localized messages, never as server texts or
/// protocol details.
struct UserFacingErrorTests {
    private let offline = String(localized: "Can't reach the rates server. Check your connection and try again.")
    private let notReady = String(localized: "The server is still loading rates. Try again in a minute.")
    private let unexpected = String(localized: "The rates server sent an unexpected response. Try again later.")

    @Test(arguments: [URLError.Code.notConnectedToInternet, .cannotConnectToHost, .timedOut, .networkConnectionLost])
    func connectionProblemsAreOffline(code: URLError.Code) {
        #expect(UserFacingError.isOffline(URLError(code)))
        #expect(UserFacingError.message(for: URLError(code)) == offline)
    }

    @Test func notReadyServerSaysToWait() {
        let error = RatesAPIError.server(status: 503, code: "not_ready", message: "Rates are still being loaded.")
        #expect(!UserFacingError.isOffline(error))
        #expect(UserFacingError.message(for: error) == notReady)
    }

    @Test func otherErrorsGetAGenericMessage() {
        let errors: [any Error] = [
            RatesAPIError.server(status: 500, code: "internal_error", message: "SQLITE_BUSY: database is locked"),
            URLError(.badServerResponse),
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad JSON")),
        ]
        for error in errors {
            #expect(UserFacingError.message(for: error) == unexpected)
        }
    }
}

/// Review I13: a bad `-APIBaseURL` is ignored instead of crashing or producing broken requests.
struct AppConfigurationTests {
    @Test(arguments: ["http://127.0.0.1:8080", "https://rates.example.com", "HTTP://localhost:8080/api"])
    func acceptsHTTPURLsWithAHost(text: String) {
        #expect(AppConfiguration.validURL(text) != nil)
    }

    @Test(arguments: ["", "localhost:8080", "127.0.0.1:8080", "ftp://example.com", "http://", "not a url"])
    func rejectsEverythingElse(text: String) {
        #expect(AppConfiguration.validURL(text) == nil)
    }
}
