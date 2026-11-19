import Foundation
import Testing
@testable import CurrencyConverter

struct AmountParserTests {
    @Test(arguments: [
        // Plain numbers
        ("en_US", "100", "100"),
        ("en_US", "0", "0"),
        ("en_US", "  42 ", "42"),
        // Locale decimal separator
        ("en_US", "12.5", "12.5"),
        ("ru_RU", "12,5", "12.5"),
        ("de_DE", "12,5", "12.5"),
        // The other separator still works as decimal when it can't be grouping
        ("ru_RU", "0.25", "0.25"),
        ("en_US", "0,25", "0.25"),
        ("de_DE", "1.5", "1.5"),
        // Grouping separators
        ("en_US", "1,234", "1234"),
        ("en_US", "1,234,567.89", "1234567.89"),
        ("de_DE", "1.234", "1234"),
        ("de_DE", "1.234,5", "1234.5"),
        ("ru_RU", "1\u{00A0}234,5", "1234.5"),
        ("ru_RU", "1 234 567", "1234567"),
        // Review I11: a group never starts with 0, so these are fractions
        ("de_DE", "0.125", "0.125"),
        ("en_US", "0,125", "0.125"),
        // Apostrophes group digits (Swiss style), whatever the locale
        ("de_CH", "1’234.5", "1234.5"),
        ("de_CH", "1'234.5", "1234.5"),
        ("en_US", "1'234", "1234"),
        // Trailing / leading separator while typing
        ("en_US", "12.", "12"),
        ("ru_RU", ",5", "0.5"),
    ])
    func parses(localeID: String, text: String, expected: String) {
        let result = AmountParser.parse(text, locale: Locale(identifier: localeID))
        #expect(result == Decimal(string: expected))
    }

    @Test(arguments: ["", " ", "abc", "1.2.3", "12a", "-", ".", "1,2,3,4"])
    func rejects(text: String) {
        #expect(AmountParser.parse(text, locale: Locale(identifier: "en_US")) == nil)
    }
}
