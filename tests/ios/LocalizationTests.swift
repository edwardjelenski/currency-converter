import Foundation
import Testing
@testable import CurrencyConverter

/// The String Catalog is compiled into the app with a Russian table.
struct LocalizationTests {
    private func bundle(_ language: String) throws -> Bundle {
        // Unit tests are hosted by the app, so the main bundle is the app.
        let app = Bundle.main
        let path = try #require(app.path(forResource: language, ofType: "lproj"), "\(language).lproj missing in the app bundle")
        return try #require(Bundle(path: path))
    }

    @Test(arguments: [
        ("No rate", "Нет курса"),
        ("Favorites", "Избранное"),
        ("1W", "1Н"),
        ("1Y", "1Г"),
        ("Swap currencies", "Поменять валюты местами"),
        ("over %@ · %@", "за %1$@ · %2$@"),
    ])
    func russianTranslations(key: String, expected: String) throws {
        let value = try bundle("ru").localizedString(forKey: key, value: "⚠️ missing", table: "Localizable")
        #expect(value == expected)
    }

    @Test func russianAppName() throws {
        #expect(try bundle("ru").localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist") == "Валюты")
    }

    @Test func formattedPhraseInRussian() throws {
        let format = try bundle("ru").localizedString(forKey: "over %@ · %@", value: nil, table: "Localizable")
        #expect(String(format: format, "1 месяц", "18 нояб. 2026 г.") == "за 1 месяц · 18 нояб. 2026 г.")
    }
}
