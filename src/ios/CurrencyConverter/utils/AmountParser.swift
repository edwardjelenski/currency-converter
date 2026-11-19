import Foundation

/// Parses an amount typed by the user, tolerating both `.` and `,` as the
/// decimal separator, grouping separators, and spaces.
///
/// Rules:
/// - Whitespace (including the non-breaking space used for grouping in many locales) is ignored.
/// - If both `.` and `,` appear, the one that appears last is the decimal separator.
/// - If only one of them appears, it is a grouping separator only when it is the
///   locale's grouping separator and every occurrence is followed by exactly three
///   digits (`1.234` in German, `1,234,567` in English). Otherwise it is the decimal separator.
enum AmountParser {
    static func parse(_ text: String, locale: Locale) -> Decimal? {
        // Spaces and apostrophes only ever group digits (1 234, 1'234, 1’234), and so does a
        // locale's own grouping separator when it isn't "." or ",".
        let extraGrouping = locale.groupingSeparator.flatMap { $0 == "." || $0 == "," ? nil : $0 } ?? ""
        let text = text.filter { !$0.isWhitespace && !"'’".contains($0) && !extraGrouping.contains($0) }
        guard !text.isEmpty else { return nil }

        let lastDot = text.lastIndex(of: ".")
        let lastComma = text.lastIndex(of: ",")

        let decimalSeparator: Character?
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            decimalSeparator = dot > comma ? "." : ","
        case (_?, nil):
            decimalSeparator = isGrouping(".", in: text, locale: locale) ? nil : "."
        case (nil, _?):
            decimalSeparator = isGrouping(",", in: text, locale: locale) ? nil : ","
        case (nil, nil):
            decimalSeparator = nil
        }

        var normalized = ""
        var hasDecimalPoint = false
        for character in text {
            switch character {
            case "0"..."9":
                normalized.append(character)
            case "." where character == decimalSeparator, "," where character == decimalSeparator:
                guard !hasDecimalPoint else { return nil }
                hasDecimalPoint = true
                normalized.append(".")
            case ".", ",":
                continue // grouping separator
            default:
                return nil
            }
        }

        guard normalized.contains(where: \.isNumber) else { return nil }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasSuffix(".") { normalized.removeLast() }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isGrouping(_ separator: Character, in text: String, locale: Locale) -> Bool {
        guard locale.groupingSeparator == String(separator) else { return false }
        let groups = text.split(separator: separator, omittingEmptySubsequences: false)
        // "0.125" is a fraction, not a thousands group: a grouped number never starts with 0.
        guard let first = groups.first, !first.isEmpty, first.count <= 3, first.first != "0" else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }
}
