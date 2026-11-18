import Foundation

/// Display helpers for an ISO 4217 currency code.
struct Currency: Identifiable, Hashable, Sendable {
    let code: String

    var id: String { code }

    func name(locale: Locale = .current) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }

    /// Flag emoji of the issuing region, derived from the first two letters of the code.
    var flag: String {
        switch code {
        case "EUR": return "🇪🇺"
        case "XAU", "XAG", "XDR": return "🏳️"
        default:
            let scalars = code.prefix(2).unicodeScalars.compactMap {
                Unicode.Scalar(127_397 + $0.value)
            }
            return String(String.UnicodeScalarView(scalars))
        }
    }

    func matches(_ query: String, locale: Locale = .current) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return code.localizedCaseInsensitiveContains(query)
            || name(locale: locale).localizedCaseInsensitiveContains(query)
    }
}
