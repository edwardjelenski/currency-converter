import SwiftUI

struct ConversionRow: View {
    let currency: Currency
    let amount: String

    var body: some View {
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
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}
