import Charts
import SwiftUI

/// Line chart of a rate with drag-to-select: a rule and a bubble with the value on that day.
struct RateHistoryChart: View {
    let history: RateHistory
    let period: HistoryPeriod
    let formatRate: (Decimal) -> String

    @State private var selectedDate: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Big text (or long month names, e.g. Russian "нояб.") needs fewer, wider-spaced labels.
    private var isLargeText: Bool { dynamicTypeSize >= .xxLarge }

    init(history: RateHistory, period: HistoryPeriod, formatRate: @escaping (Decimal) -> String, selectedDate: Date? = nil) {
        self.history = history
        self.period = period
        self.formatRate = formatRate
        _selectedDate = State(initialValue: selectedDate)
    }

    private var selectedPoint: RatePoint? {
        selectedDate.flatMap { history.point(nearest: $0) }
    }

    var body: some View {
        let yDomain = yDomain
        Chart {
            ForEach(history.points) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    yStart: .value("Rate", yDomain.lowerBound),
                    yEnd: .value("Rate", point.plotValue)
                )
                .foregroundStyle(areaGradient)
                .interpolationMethod(.monotone)
                // Decoration: VoiceOver reads each day once, from the line.
                .accessibilityHidden(true)

                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Rate", point.plotValue)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                // A week has only ~5 publication days: mark them, so the smooth line
                // over the weekend isn't mistaken for data.
                .symbol(.circle)
                .symbolSize(period == .week ? 36 : 0)
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(formatRate(point.rate))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionBubble(value: formatRate(selectedPoint.rate), date: selectedPoint.date)
                    }
                    .accessibilityHidden(true)

                PointMark(
                    x: .value("Date", selectedPoint.date, unit: .day),
                    y: .value("Rate", selectedPoint.plotValue)
                )
                .symbolSize(70)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            }
        }
        // Audio Graph and the chart summary in the VoiceOver rotor.
        .accessibilityChartDescriptor(RateChartDescriptor(history: history, yDomain: yDomain))
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: yDomain)
        // Room at both ends so the first and last x-axis labels stay inside the chart.
        .chartXScale(range: .plotDimension(padding: isLargeText ? 32 : 20))
        .chartXAxis {
            // .aligned keeps the first and last labels inside the plot instead of truncating them.
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: isLargeText ? 3 : (period == .week ? 5 : 4))) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(rate, format: .number.precision(.significantDigits(2...5)))
                    }
                }
            }
        }
        // Room above the line for the selection bubble.
        .padding(.top, 44)
        .sensoryFeedback(.selection, trigger: selectedPoint?.id)
    }

    /// Min…max with some headroom, so a calm period doesn't look flat or clipped.
    private var yDomain: ClosedRange<Double> {
        let values = history.points.map(\.plotValue)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, abs(high) * 0.001)
        return (low - padding)...(high + padding)
    }

    private var xAxisFormat: Date.FormatStyle {
        switch period {
        case .week: .dateTime.weekday(.abbreviated)
        case .month, .quarter: .dateTime.day().month(.abbreviated)
        case .year: .dateTime.month(.abbreviated)
        }
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Describes the chart for VoiceOver's Audio Graph: the dates on x, the rate on y.
private struct RateChartDescriptor: AXChartDescriptorRepresentable {
    let history: RateHistory
    let yDomain: ClosedRange<Double>

    func makeChartDescriptor() -> AXChartDescriptor {
        let times = history.points.map { $0.date.timeIntervalSince1970 }
        let xRange = (times.min() ?? 0)...(times.max() ?? 1)
        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Date"),
            range: xRange,
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Rate"),
            range: yDomain,
            gridlinePositions: []
        ) { Decimal($0).formatted(.number.precision(.significantDigits(1...6))) }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "Rate"),
            isContinuous: true,
            dataPoints: history.points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.plotValue) }
        )
        return AXChartDescriptor(
            title: String(localized: "Rate history"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

private struct SelectionBubble: View {
    let value: String
    let date: Date

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(date, format: .dateTime.day().month(.abbreviated).year())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
