import SwiftUI

struct ConverterView: View {
    @Bindable var model: ConverterViewModel
    let history: RateHistoryRepository

    @State private var picking: PickerTarget?
    @State private var path: [HistoryRoute] = []
    @FocusState private var amountFocused: Bool

    private enum PickerTarget: String, Identifiable {
        case source, target
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.hasRates {
                    content
                } else if model.isRefreshing {
                    ProgressView("Loading rates…")
                } else {
                    unavailable
                }
            }
            .navigationTitle("Converter")
            .background(Theme.background)
            .navigationDestination(for: HistoryRoute.self) { route in
                RateHistoryScreen(route: route, repository: history)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
            .sheet(item: $picking) { target in
                CurrencyPickerView(
                    currencies: model.currencies,
                    selection: target == .source ? model.sourceCode : model.targetCode
                ) { code in
                    switch target {
                    case .source: model.sourceCode = code
                    case .target: model.targetCode = code
                    }
                }
            }
        }
        .task { await model.load() }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let errorMessage = model.errorMessage {
                    OfflineBanner(message: errorMessage, savedAt: model.snapshot?.validatedAt)
                }
                converterCards
                rateInfo
                otherCurrencies
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refresh() }
    }

    private var converterCards: some View {
        VStack(spacing: 8) {
            CurrencyCard(title: "You send", currency: model.source) {
                picking = .source
            } value: {
                TextField("0", text: $model.amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.amountFont)
                    .accessibilityLabel("Amount in \(model.source.code)")
            }

            CurrencyCard(title: "They get", currency: model.target) {
                picking = .target
            } value: {
                Text(model.formattedResult)
                    .font(Theme.amountFont)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .overlay {
            Button {
                withAnimation(.snappy) { model.swapCurrencies() }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.tint, in: .circle)
                    .foregroundStyle(.white)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 4))
            }
            .accessibilityLabel("Swap currencies")
        }
        .animation(.snappy, value: model.formattedResult)
    }

    /// The pair's rate; tapping it opens the rate history. This is where people look at
    /// "how much is it", so it is the natural door to "how has it changed".
    @ViewBuilder
    private var rateInfo: some View {
        if let rateDescription = model.rateDescription {
            NavigationLink(value: HistoryRoute(base: model.sourceCode, target: model.targetCode)) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(.tint.opacity(0.12), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rateDescription)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        if let published = model.rates?.publishedAt {
                            Text("ECB reference rate · \(published.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("History")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.listCornerRadius))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.sourceCode == model.targetCode)
            .accessibilityHint("Shows how the rate changed over time")
        }
    }

    @ViewBuilder
    private var otherCurrencies: some View {
        let conversions = model.otherConversions
        if !conversions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Other currencies")
                    .font(.headline)
                    .padding(.horizontal, 4)

                LazyVStack(spacing: 0) {
                    ForEach(conversions) { conversion in
                        Button {
                            withAnimation(.snappy) { model.targetCode = conversion.currency.code }
                        } label: {
                            ConversionRow(
                                currency: conversion.currency,
                                amount: model.format(conversion.amount, currency: conversion.currency.code)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rate history", systemImage: "chart.xyaxis.line") {
                                path.append(HistoryRoute(base: model.sourceCode, target: conversion.currency.code))
                            }
                        }

                        if conversion.id != conversions.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Theme.surface, in: .rect(cornerRadius: Theme.listCornerRadius))
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("No rates yet", systemImage: "wifi.exclamationmark")
        } description: {
            Text(model.errorMessage ?? "Exchange rates couldn't be loaded.")
        } actions: {
            Button("Try Again") { Task { await model.refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

#if DEBUG
#Preview("Converter") {
    ConverterView(model: .preview(), history: .preview())
}

#Preview("Offline, no cache") {
    ConverterView(model: .preview(api: OfflineRatesAPI(), snapshot: nil), history: .preview(api: OfflineRatesAPI()))
}
#endif
