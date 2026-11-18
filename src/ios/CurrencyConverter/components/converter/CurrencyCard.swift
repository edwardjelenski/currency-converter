import SwiftUI

struct CurrencyCard<Value: View>: View {
    let title: LocalizedStringKey
    let currency: Currency
    let pick: () -> Void
    @ViewBuilder let value: () -> Value

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side normally; at accessibility text sizes the amount gets its own line,
    /// otherwise a large number and the currency chip don't fit next to each other.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            layout {
                Button(action: pick) {
                    HStack(spacing: 8) {
                        Text(currency.flag).font(.title2)
                        Text(currency.code).font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.chip, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(currency.name()), change currency"))

                value()
            }
            Text(currency.name())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
