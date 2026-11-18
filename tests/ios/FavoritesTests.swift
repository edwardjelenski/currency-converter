import Foundation
import SwiftUI
import Testing
@testable import CurrencyConverter

@MainActor
struct FavoritesTests {
    private func makeModel(defaults: UserDefaults = makeIsolatedDefaults()) -> ConverterViewModel {
        ConverterViewModel(
            repository: RatesRepository(api: MockRatesAPI(), cache: makeTemporaryCache()),
            defaults: defaults,
            locale: Locale(identifier: "en_US"),
            initialSnapshot: .fixture()
        )
    }

    // MARK: Favorites

    @Test func firstLaunchHasDefaultFavorites() {
        #expect(makeModel().favorites == ["EUR", "GBP", "JPY", "CHF"])
    }

    @Test func favoritesShowTheSameAmountConverted() {
        let model = makeModel()
        model.amountText = "10" // USD; fixture: 1 EUR = 2 USD = 1 GBP = 200 JPY

        let rows = model.favoriteConversions
        #expect(rows.map(\.currency.code) == ["EUR", "GBP", "JPY", "CHF"])
        #expect(rows.map(\.amount) == [5, 5, 1000, nil]) // CHF isn't in the fixture → no rate
    }

    @Test func favoriteAmountsFollowTheSourceCurrency() {
        let model = makeModel()
        model.amountText = "10"
        model.selectSource("GBP")
        #expect(model.favoriteConversions.first { $0.id == "EUR" }?.amount == 10)
    }

    @Test func toggleAddsAtTheEndAndRemoves() {
        let model = makeModel()
        model.toggleFavorite("USD")
        #expect(model.favorites == ["EUR", "GBP", "JPY", "CHF", "USD"])
        model.toggleFavorite("GBP")
        #expect(model.favorites == ["EUR", "JPY", "CHF", "USD"])
    }

    @Test func swipeToDeleteRemovesRows() {
        let model = makeModel()
        model.removeFavorites(at: [0, 2])
        #expect(model.favorites == ["GBP", "CHF"])
    }

    @Test(arguments: [
        // SwiftUI onMove semantics: destination is an index in the list before the move.
        ([0], 4, ["GBP", "JPY", "CHF", "EUR"]),
        ([3], 0, ["CHF", "EUR", "GBP", "JPY"]),
        ([1], 3, ["EUR", "JPY", "GBP", "CHF"]),
        ([2], 1, ["EUR", "JPY", "GBP", "CHF"]),
        ([0, 1], 3, ["JPY", "EUR", "GBP", "CHF"]),
    ] as [([Int], Int, [String])])
    func dragToReorder(offsets: [Int], destination: Int, expected: [String]) {
        let model = makeModel()
        model.moveFavorites(from: IndexSet(offsets), to: destination)
        #expect(model.favorites == expected)
    }

    @Test func moveMatchesSwiftUIArrayMove() {
        // Cross-check against the reference implementation for every single-row move.
        for from in 0..<4 {
            for to in 0...4 {
                let model = makeModel()
                var reference = model.favorites
                reference.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                model.moveFavorites(from: IndexSet(integer: from), to: to)
                #expect(model.favorites == reference, "move \(from) → \(to)")
            }
        }
    }

    @Test func emptiedFavoritesStayEmpty() {
        let defaults = makeIsolatedDefaults()
        let model = makeModel(defaults: defaults)
        model.removeFavorites(at: IndexSet(0..<4))

        #expect(makeModel(defaults: defaults).favorites.isEmpty, "Not refilled with defaults on relaunch")
    }

    // MARK: Recents

    @Test func recentsAreMostRecentFirstWithoutDuplicates() {
        let model = makeModel()
        model.selectTarget("GBP")
        model.selectSource("JPY")
        model.selectTarget("GBP")
        #expect(model.recents == ["GBP", "JPY"])
    }

    @Test func recentsKeepFive() {
        let model = makeModel()
        for code in ["A1A", "B2B", "C3C", "D4D", "E5E", "F6F"] {
            model.selectTarget(code)
        }
        #expect(model.recents == ["F6F", "E5E", "D4D", "C3C", "B2B"])
    }

    @Test func addingAFavoriteCountsAsRecentButRemovingDoesNot() {
        let model = makeModel()
        model.toggleFavorite("USD")
        model.toggleFavorite("GBP") // removes
        #expect(model.recents == ["USD"])
    }

    @Test func pickerRecentsOnlyListCurrenciesWithRates() {
        let model = makeModel()
        model.selectTarget("XAU")
        model.selectTarget("GBP")
        #expect(model.recentCurrencies.map(\.code) == ["GBP"])
    }

    // MARK: Persistence across launches

    @Test func everythingIsRestoredOnRelaunch() {
        let defaults = makeIsolatedDefaults()
        let first = makeModel(defaults: defaults)
        first.amountText = "250,5"
        first.selectSource("GBP")
        first.selectTarget("JPY")
        first.toggleFavorite("USD")
        first.moveFavorites(from: [4], to: 0)
        first.removeFavorites(at: [1])

        let relaunched = makeModel(defaults: defaults)
        #expect(relaunched.amountText == "250,5")
        #expect(relaunched.sourceCode == "GBP")
        #expect(relaunched.targetCode == "JPY")
        #expect(relaunched.favorites == ["USD", "GBP", "JPY", "CHF"])
        #expect(relaunched.recents == ["USD", "JPY", "GBP"])
    }

    @Test func swapIsRestoredOnRelaunch() {
        let defaults = makeIsolatedDefaults()
        let first = makeModel(defaults: defaults)
        first.swapCurrencies()

        let relaunched = makeModel(defaults: defaults)
        #expect(relaunched.sourceCode == "EUR")
        #expect(relaunched.targetCode == "USD")
    }

    // MARK: With the rates API

    @Test func favoritesFollowNewRatesAfterRefresh() async {
        let api = MockRatesAPI(.ok(.fixture, etag: "\"v1\"", maxAge: 3600))
        let model = ConverterViewModel(
            repository: RatesRepository(api: api, cache: makeTemporaryCache()),
            defaults: makeIsolatedDefaults(),
            locale: Locale(identifier: "en_US")
        )
        await model.load()
        model.amountText = "10"
        #expect(model.favoriteConversions.first { $0.id == "EUR" }?.amount == 5) // 1 EUR = 2 USD

        await api.setReply(.ok(.nextDay, etag: "\"v2\"", maxAge: 3600))           // 1 EUR = 2.5 USD
        await model.refresh()

        #expect(model.favoriteConversions.first { $0.id == "EUR" }?.amount == 4)
        #expect(model.favoriteConversions.first { $0.id == "JPY" }?.amount == 800)
    }

    @Test func unparsableAmountGivesNoFavoriteAmounts() {
        let model = makeModel()
        model.amountText = "12abc"
        #expect(model.favoriteConversions.allSatisfy { $0.amount == nil })
        #expect(model.favoriteConversions.count == 4)
    }

    @Test func noRatesYetGivesNoFavoriteAmounts() async {
        let model = ConverterViewModel(
            repository: RatesRepository(api: MockRatesAPI(.failure(URLError(.cannotConnectToHost))), cache: makeTemporaryCache()),
            defaults: makeIsolatedDefaults(),
            locale: Locale(identifier: "en_US")
        )
        await model.load()
        #expect(model.favoriteConversions.map(\.id) == ["EUR", "GBP", "JPY", "CHF"])
        #expect(model.favoriteConversions.allSatisfy { $0.amount == nil })
    }
}
