import SwiftUI

struct CurrencyPickerView: View {
    let currencies: [Currency]
    let selection: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Currency] {
        currencies
            .filter { $0.matches(query) }
            .sorted { $0.name().localizedStandardCompare($1.name()) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { currency in
                Button {
                    onSelect(currency.code)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(currency.flag).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currency.name())
                            Text(currency.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if currency.code == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(currency.code == selection ? .isSelected : [])
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Currency or code")
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    CurrencyPickerView(
        currencies: ExchangeRates.sample.currencyCodes.map(Currency.init(code:)),
        selection: "USD"
    ) { _ in }
}
#endif
