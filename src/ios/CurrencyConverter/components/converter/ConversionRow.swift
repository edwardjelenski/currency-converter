import SwiftUI

struct ConversionRow: View {
    enum Amount: Equatable {
        /// No amount typed: shown as "—", read as "No amount".
        case none
        case text(String)

        var display: String {
            if case let .text(text) = self { text } else { "—" }
        }

        var spoken: String {
            if case let .text(text) = self { text } else { String(localized: "No amount") }
        }
    }

    let currency: Currency
    let amount: Amount

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content
            // One VoiceOver element: "Japanese Yen, JPY, ¥23,456" — no flag emoji read aloud.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(currency.name()), \(currency.code)"))
            .accessibilityValue(amount.spoken)
    }

    @ViewBuilder
    private var content: some View {
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
                Text(amount.display)
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
            Text(amount.display)
                .font(.body.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
