import Foundation
import OSLog

enum AppConfiguration {
    /// Our server. Comes from the `API_BASE_URL` build setting via Info.plist and can be
    /// overridden at launch with `-APIBaseURL http://…` (launch argument → UserDefaults).
    /// An invalid override is ignored; an invalid Info.plist value is a build error.
    static var apiBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "APIBaseURL") {
            if let url = validURL(override) { return url }
            Logger(subsystem: "com.eduardyelenskiy.currencyconverter", category: "config")
                .error("Ignoring invalid -APIBaseURL \(override, privacy: .public)")
        }
        let value = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        guard let value, let url = validURL(value) else {
            preconditionFailure("APIBaseURL in Info.plist must be an http(s) URL with a host, got \(String(describing: value))")
        }
        return url
    }

    /// `http` or `https` with a host, e.g. `http://127.0.0.1:8080`.
    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
}
