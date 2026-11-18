import Vapor

/// Reading and validating query parameters into `APIError.invalidParameter`.
extension Request {
    /// A non-empty query parameter, or `nil` when absent or empty.
    func queryValue(_ name: String) -> String? {
        guard let value = try? query.get(String.self, at: name) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    func requiredQueryValue(_ name: String) throws -> String {
        guard let value = queryValue(name) else { throw APIError.invalidParameter("'\(name)' is required.") }
        return value
    }

    func dateParameter(_ name: String) throws -> RateDate? {
        guard let value = queryValue(name) else { return nil }
        guard let date = RateDate(value) else {
            throw APIError.invalidParameter("'\(name)' must be a date in YYYY-MM-DD format, got '\(value)'.")
        }
        return date
    }

    func requiredDateParameter(_ name: String) throws -> RateDate {
        guard let date = try dateParameter(name) else { throw APIError.invalidParameter("'\(name)' is required.") }
        return date
    }

    /// An ISO 4217 code, case-insensitive. Doesn't check that we have rates for it.
    func currencyParameter(_ name: String) throws -> String? {
        try queryValue(name).map { try Self.currencyCode($0, parameter: name, inList: false) }
    }

    /// Comma-separated ISO 4217 codes.
    func currencyListParameter(_ name: String) throws -> [String]? {
        guard let value = queryValue(name) else { return nil }
        let codes = try value.split(separator: ",", omittingEmptySubsequences: false).map {
            try Self.currencyCode(String($0), parameter: name, inList: true)
        }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    static func currencyCode(_ raw: String, parameter: String, inList: Bool) throws -> String {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            let expectation = inList ? "a comma-separated list of 3-letter ISO 4217 codes" : "a 3-letter ISO 4217 code"
            throw APIError.invalidParameter("'\(parameter)' must be \(expectation), got '\(raw)'.")
        }
        return code
    }
}
