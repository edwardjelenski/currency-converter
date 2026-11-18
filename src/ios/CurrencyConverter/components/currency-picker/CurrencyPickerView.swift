import SwiftUI

/// Searchable currency list with recently picked currencies on top.
///
/// Single selection (the pair) picks and closes; multiple selection (favorites)
/// toggles checkmarks and stays open until Done.
struct CurrencyPickerView: View {
    let title: LocalizedStringKey
    let currencies: [Currency]
    let allowsMultipleSelection: Bool
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    /// Checkmarks are local state: a closure reading the model from inside `List` rows
    /// isn't observed, so toggled rows wouldn't redraw.
    @State private var selection: Set<String>
    /// Most recent first, as of opening the picker; shown as its own section while not
    /// searching. Frozen so that picking a currency doesn't shift the rows under the finger.
    @State private var recents: [Currency]

    init(
        title: LocalizedStringKey,
        currencies: [Currency],
        recents: [Currency],
        selected: Set<String>,
        allowsMultipleSelection: Bool,
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.currencies = currencies
        _recents = State(initialValue: recents)
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onSelect = onSelect
        _selection = State(initialValue: selected)
    }

    private var filtered: [Currency] {
        currencies
            .filter { $0.matches(query) }
            .sorted { $0.name().localizedStandardCompare($1.name()) == .orderedAscending }
    }

    private var showsRecents: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && !recents.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if showsRecents {
                    Section("Recent") {
                        ForEach(recents) { row(for: $0) }
                    }
                    Section("All Currencies") {
                        ForEach(filtered) { row(for: $0) }
                    }
                } else {
                    ForEach(filtered) { row(for: $0) }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Currency or code")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsMultipleSelection {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private func row(for currency: Currency) -> some View {
        let selected = selection.contains(currency.code)
        return Button {
            if allowsMultipleSelection {
                if selected { selection.remove(currency.code) } else { selection.insert(currency.code) }
            }
            onSelect(currency.code)
            if !allowsMultipleSelection { dismiss() }
        } label: {
            HStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    // Flag next to the code, so the name gets the full width and doesn't
                    // break mid-word.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currency.name())
                        Text(verbatim: "\(currency.flag) \(currency.code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(currency.flag).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currency.name())
                        Text(currency.code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if allowsMultipleSelection {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                } else if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Pick one") {
    CurrencyPickerView(
        title: "They get",
        currencies: ExchangeRates.sample.currencyCodes.map(Currency.init(code:)),
        recents: ["GBP", "JPY", "CHF"].map(Currency.init(code:)),
        selected: ["EUR"],
        allowsMultipleSelection: false
    ) { _ in }
}

#Preview("Favorites") {
    CurrencyPickerView(
        title: "Favorites",
        currencies: ExchangeRates.sample.currencyCodes.map(Currency.init(code:)),
        recents: ["GBP", "JPY"].map(Currency.init(code:)),
        selected: ["EUR", "GBP", "JPY", "CHF"],
        allowsMultipleSelection: true
    ) { _ in }
}
#endif
