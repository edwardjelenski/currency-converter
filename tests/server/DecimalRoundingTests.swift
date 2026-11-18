import Foundation
import Testing
@testable import App

struct DecimalRoundingTests {
    @Test(arguments: [
        ("159.41830780452224", "159.418"),
        ("0.000123456789", "0.000123457"),
        ("0.75939096", "0.759391"),
        ("12345678", "12345700"),
        ("1.0968", "1.0968"),
        ("-2.5555555", "-2.55556"),
        ("0", "0"),
    ])
    func roundsToSixSignificantDigits(input: String, expected: String) {
        #expect(Decimal(rateText: input)!.rounded(significantDigits: 6).description == expected)
    }

    @Test func parsesRateTextIndependentOfLocale() {
        #expect(Decimal(rateText: "174.85") == Decimal(string: "174.85"))
        #expect(Decimal(rateText: "abc") == nil)
    }
}
