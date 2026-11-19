import SwiftUI

/// Low, high and change over the period.
struct HistoryStatsView: View {
    let history: RateHistory
    let model: RateHistoryViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Three tiles in a row normally, one per line at accessibility text sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if let low = history.minPoint {
                tile(title: "Low", value: model.format(rate: low.rate), detail: low.date.formatted(.dateTime.day().month(.abbreviated)))
            }
            if let high = history.maxPoint {
                tile(title: "High", value: model.format(rate: high.rate), detail: high.date.formatted(.dateTime.day().month(.abbreviated)))
            }
            if let ratio = history.changeRatio, let change = history.change {
                tile(title: "Change", value: model.format(change: ratio), detail: model.format(signedRate: change), tint: ChangeTint(ratio).color)
            }
        }
    }

    private func tile(title: LocalizedStringKey, value: String, detail: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.listCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Green when the base currency got stronger, red when weaker, neutral when flat.
struct ChangeTint {
    let color: Color

    init(_ ratio: Decimal) {
        color = ratio > 0 ? Theme.positive : (ratio < 0 ? Theme.negative : .secondary)
    }
}
