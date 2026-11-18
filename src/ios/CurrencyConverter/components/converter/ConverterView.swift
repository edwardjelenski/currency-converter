import SwiftUI

struct ConverterView: View {
    @Bindable var model: ConverterViewModel

    @State private var picking: PickerTarget?
    @FocusState private var amountFocused: Bool

    private enum PickerTarget: String, Identifiable {
        case source, target
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
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

    @ViewBuilder
    private var rateInfo: some View {
        VStack(spacing: 4) {
            if let rateDescription = model.rateDescription {
                Text(rateDescription)
                    .font(.subheadline.monospacedDigit())
            }
            if let published = model.rates?.publishedAt {
                Text("ECB reference rate · \(published.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
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
    ConverterView(model: .preview())
}

#Preview("Offline, no cache") {
    ConverterView(model: .preview(api: OfflineRatesAPI(), snapshot: nil))
}
#endif
