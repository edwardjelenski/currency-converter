import SwiftUI

/// History of one currency pair: period picker, chart with drag selection, low/high/change.
struct RateHistoryView: View {
    @Bindable var model: RateHistoryViewModel
    /// Preselected chart point (previews only).
    var previewSelection: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Picker("Period", selection: $model.period) {
                    ForEach(HistoryPeriod.allCases) { period in
                        Text(period.rawValue)
                            .accessibilityLabel(period.accessibilityName)
                            .tag(period)
                    }
                }
                .pickerStyle(.segmented)

                if let staleNotice = model.staleNotice {
                    OfflineBanner(message: staleNotice, savedAt: model.loadedAt)
                }

                chartArea
                    .frame(height: 280)

                if let history = model.history {
                    HistoryStatsView(history: history, model: model)
                }

                Text("ECB reference rates. Published on working days only, so weekends and holidays have no points.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Swap currencies", systemImage: "arrow.left.arrow.right") {
                    withAnimation(.snappy) { model.swapPair() }
                }
            }
        }
        .refreshable { await model.load() }
        .task(id: model.requestID) { await model.load() }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("1 \(model.base) =")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let last = model.history?.last {
                Text("\(model.format(rate: last.rate)) \(model.target)")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    if let ratio = model.history?.changeRatio {
                        Text(model.format(change: ratio))
                            .foregroundStyle(ChangeTint(ratio).color)
                            .fontWeight(.semibold)
                    }
                    Text("over \(model.period.accessibilityName) · \(last.date.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.monospacedDigit())
            } else {
                Text("— \(model.target)")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(" ")
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: model.history?.last)
    }

    // MARK: Chart area

    @ViewBuilder
    private var chartArea: some View {
        switch model.content {
        case .loading:
            ProgressView("Loading history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .chart(history):
            RateHistoryChart(history: history, period: model.period, formatRate: model.format(rate:), selectedDate: previewSelection)
                .id(model.requestID)

        case let .empty(message):
            ContentUnavailableView {
                Label("No data for this period", systemImage: "chart.line.downtrend.xyaxis")
            } description: {
                Text(message)
            }

        case let .failed(failure):
            ContentUnavailableView {
                Label(failure.title, systemImage: failure.isOffline ? "wifi.slash" : "exclamationmark.triangle")
            } description: {
                Text(failure.message)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Owns the view model for a pushed history screen, so it survives parent re-renders.
struct RateHistoryScreen: View {
    @State private var model: RateHistoryViewModel

    init(route: HistoryRoute, repository: RateHistoryRepository) {
        _model = State(initialValue: RateHistoryViewModel(base: route.base, target: route.target, repository: repository))
    }

    var body: some View {
        RateHistoryView(model: model)
    }
}

/// Navigation value for opening the history of a pair.
struct HistoryRoute: Hashable {
    let base: String
    let target: String
}

#if DEBUG
#Preview("Month") {
    NavigationStack {
        RateHistoryView(model: .preview(.chart(.sample(period: .month))))
    }
}

#Preview("Year, dragging") {
    let history = RateHistory.sample(period: .year)
    NavigationStack {
        RateHistoryView(
            model: .preview(.chart(history), period: .year),
            previewSelection: history.points[history.points.count * 2 / 3].date
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        RateHistoryView(model: .preview(
            .empty("There are no EUR → BGN rates for 1 month. The currency may not have been published by the ECB in this period."),
            base: "EUR", target: "BGN"
        ))
    }
}

#Preview("Offline") {
    NavigationStack {
        RateHistoryView(model: .preview(.failed(RateHistoryViewModel.failure(for: URLError(.cannotConnectToHost))), api: OfflineRatesAPI()))
    }
}

#Preview("Loading") {
    NavigationStack {
        RateHistoryView(model: .preview(.loading))
    }
}

extension RateHistoryViewModel {
    /// A model already in `content`, so the preview renders before `.task` runs.
    /// The API answers the same way, so the task's reload doesn't change the picture.
    static func preview(
        _ content: Content,
        period: HistoryPeriod = .month,
        base: String = "USD",
        target: String = "EUR",
        api: any RatesAPI = PreviewRatesAPI()
    ) -> RateHistoryViewModel {
        RateHistoryViewModel(base: base, target: target, period: period, repository: .preview(api: api), initialContent: content)
    }
}
#endif
