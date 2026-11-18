import Foundation
import Testing
@testable import CurrencyConverter

struct CurrencyTests {
    @Test(arguments: [("USD", "🇺🇸"), ("JPY", "🇯🇵"), ("EUR", "🇪🇺"), ("GBP", "🇬🇧")])
    func flag(code: String, flag: String) {
        #expect(Currency(code: code).flag == flag)
    }

    @Test func searchMatchesCodeAndLocalizedName() {
        let locale = Locale(identifier: "en_US")
        let yen = Currency(code: "JPY")
        #expect(yen.matches("jp", locale: locale))
        #expect(yen.matches("japanese", locale: locale))
        #expect(yen.matches("  ", locale: locale))
        #expect(!yen.matches("dollar", locale: locale))
    }
}
