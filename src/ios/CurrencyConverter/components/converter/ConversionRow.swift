import SwiftUI

struct ConversionRow: View {
    let currency: Currency
    let amount: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Name and amount don't fit on one line at accessibility sizes: stack them.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(currency.flag).font(.title2)
                    Text(currency.code).font(.body.weight(.medium))
                }
                Text(currency.name())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(amount)
                    .font(.body.monospacedDigit())
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Text(currency.flag)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(currency.code).font(.body.weight(.medium))
                Text(currency.name())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.body.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
