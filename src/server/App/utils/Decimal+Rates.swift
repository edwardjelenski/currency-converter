import Foundation

extension Decimal {
    /// Parses a plain decimal string such as `"174.85"` exactly, regardless of locale.
    init?(rateText text: String) {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self = value
    }

    /// Rounds half-up to `digits` significant digits: `159.4183…` → `159.418`, `0.0001234567` → `0.000123457`.
    func rounded(significantDigits digits: Int) -> Decimal {
        guard self != 0 else { return 0 }
        let text = magnitude.description
        // Digits before the decimal point, or minus the leading zeros after it for values below 1.
        let integerDigits: Int
        if magnitude >= 1 {
            integerDigits = text.prefix { $0 != "." }.count
        } else {
            let fraction = text.split(separator: ".").last ?? ""
            integerDigits = -fraction.prefix { $0 == "0" }.count
        }
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, digits - integerDigits, .plain)
        return result
    }
}
