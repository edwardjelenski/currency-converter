import Foundation

enum AppConfiguration {
    /// Our server. Comes from the `API_BASE_URL` build setting via Info.plist and can be
    /// overridden at launch with `-APIBaseURL http://…` (launch argument → UserDefaults).
    static var apiBaseURL: URL {
        let value = UserDefaults.standard.string(forKey: "APIBaseURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        guard let value, let url = URL(string: value), url.scheme != nil else {
            preconditionFailure("APIBaseURL is missing or invalid in Info.plist: \(String(describing: value))")
        }
        return url
    }
}
