import SwiftUI

/// Main screen: the pair converter, its rate (→ history) and the favorites list.
///
/// A `List` rather than a `ScrollView`: favorites need the system's swipe to delete
/// and drag to reorder, which only `List` provides.
struct ConverterView: View {
    @Bindable var model: ConverterViewModel
    let history: RateHistoryRepository

    @State private var picking: PickerTarget?
    @State private var path: [HistoryRoute] = []
    @State private var editMode: EditMode = .inactive
    /// Bumped on every swap; drives the haptic.
    @State private var swapCount = 0
    @FocusState private var amountFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `.snappy`, or no animation with Reduce Motion on.
    private var motion: Animation? { reduceMotion ? nil : .snappy }

    private enum PickerTarget: String, Identifiable {
        case source, target, favorites
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.hasRates {
                    content
                } else if model.isRefreshing || !model.hasAttemptedLoad {
                    // Before the first attempt finishes there is nothing to report yet:
                    // a spinner, not a flash of "No rates yet / Try Again".
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
                picker(for: target)
            }
        }
        .task { await model.load() }
        .onChange(of: model.errorMessage) { _, message in
            // The banner appears silently otherwise; VoiceOver users hear why rates are stale.
            if let message {
                AccessibilityNotification.Announcement(String(localized: "Couldn't update rates. \(message)")).post()
            }
        }
        .onChange(of: model.favorites.isEmpty) { _, isEmpty in
            // Nothing left to edit: leave Edit mode, otherwise it comes back "stuck" on the next add.
            if isEmpty { editMode = .inactive }
        }
    }

    // MARK: Content

    private var content: some View {
        List {
            if let errorMessage = model.errorMessage {
                OfflineBanner(message: errorMessage, savedAt: model.snapshot?.validatedAt)
                    .plainListRow()
            }
            converterCards
                .plainListRow()
            rateInfo
                .plainListRow()
            favoritesSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.editMode, $editMode)
        .refreshable { await model.refresh() }
    }

    private var converterCards: some View {
        // The swap button sits between the cards and overlaps both; laid out in the stack
        // (not as an overlay) so it stays between them when the cards grow with Dynamic Type.
        VStack(spacing: -18) {
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

            swapButton
                .zIndex(1)

            CurrencyCard(title: "They get", currency: model.target) {
                picking = .target
            } value: {
                // Full size whenever it fits; shrink only a really long number. A plain
                // lineLimit(1) + minimumScaleFactor shrinks needlessly inside a List row
                // (the row is measured with a narrower width first).
                ViewThatFits(in: .horizontal) {
                    resultText
                        .fixedSize(horizontal: true, vertical: false)
                    resultText
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .animation(motion, value: model.formattedResult)
    }

    private var resultText: some View {
        Text(model.formattedResult)
            .font(Theme.amountFont)
            .foregroundStyle(.tint)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .textSelection(.enabled)
            .accessibilityLabel("Converted amount")
            .accessibilityValue(model.convertedAmount == nil ? String(localized: "No amount") : model.formattedResult)
    }

    private var swapButton: some View {
        Button {
            swapCount += 1
            withAnimation(motion) { model.swapCurrencies() }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.headline)
                // The circle has a fixed size, so the glyph can't follow huge text sizes;
                // VoiceOver users get the label, everyone else the Large Content Viewer.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .frame(width: 44, height: 44)
                .background(.tint, in: .circle)
                .foregroundStyle(.white)
                .overlay(Circle().stroke(Theme.background, lineWidth: 4))
        }
        // In a List row a default-styled button makes the whole row its tap area.
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: swapCount)
        .accessibilityLabel("Swap currencies")
        .accessibilityShowsLargeContentViewer()
    }

    /// The pair's rate; tapping it opens the rate history. This is where people look at
    /// "how much is it", so it is the natural door to "how has it changed".
    @ViewBuilder
    private var rateInfo: some View {
        if let rateDescription = model.rateDescription {
            Button {
                path.append(HistoryRoute(base: model.sourceCode, target: model.targetCode))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.body.weight(.semibold))
                        // Fixed circle: keep the glyph inside it at huge text sizes.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
                    // At accessibility sizes the rate needs the room; the chevron still says "opens".
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("History")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
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

    // MARK: Favorites

    private var favoritesSection: some View {
        Section {
            ForEach(model.favoriteConversions) { favorite in
                let isSource = favorite.currency.code == model.sourceCode
                Button {
                    withAnimation(motion) { model.selectFavorite(favorite.currency.code) }
                } label: {
                    ConversionRow(currency: favorite.currency, amount: amountText(for: favorite))
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
                .contextMenu {
                    // EUR → EUR has no history.
                    if !isSource {
                        Button("Rate history", systemImage: "chart.xyaxis.line") {
                            path.append(HistoryRoute(base: model.sourceCode, target: favorite.currency.code))
                        }
                    }
                    Button("Reorder", systemImage: "arrow.up.arrow.down") {
                        withAnimation(motion) { editMode = .active }
                    }
                    Button("Remove from Favorites", systemImage: "star.slash", role: .destructive) {
                        withAnimation(motion) { model.toggleFavorite(favorite.currency.code) }
                    }
                }
                .accessibilityHint(isSource ? "Swaps the currencies" : "Makes it the currency you get")
            }
            .onDelete { offsets in
                withAnimation(motion) { model.removeFavorites(at: offsets) }
            }
            .onMove { offsets, destination in
                model.moveFavorites(from: offsets, to: destination)
            }

            if model.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No favorites yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Add currencies to see the same amount in each of them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Add Currencies", systemImage: "plus") { picking = .favorites }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
                .padding(.vertical, 6)
                .listRowBackground(Theme.surface)
            }
        } header: {
            favoritesHeader
        }
    }

    /// Title with Edit and +; at accessibility sizes the title gets its own line,
    /// otherwise "Favorites" and "Edit" break mid-word (especially in Russian).
    private var favoritesHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return layout {
            Text("Favorites")
                .font(.headline)
                .foregroundStyle(.primary)
            HStack {
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                if !model.favorites.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation(motion) { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                }
                if dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Add to Favorites", systemImage: "plus.circle.fill") {
                    picking = .favorites
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            }
        }
        .textCase(nil)
        .padding(.horizontal, -4)
    }

    /// "No rate" when the currency isn't published; "—" (read as "No amount") when the field is empty.
    private func amountText(for favorite: ConverterViewModel.FavoriteConversion) -> ConversionRow.Amount {
        if !favorite.hasRate { return .text(String(localized: "No rate")) }
        guard let amount = favorite.amount else { return .none }
        return .text(model.format(amount, currency: favorite.currency.code))
    }

    // MARK: Picker

    @ViewBuilder
    private func picker(for target: PickerTarget) -> some View {
        switch target {
        case .source:
            CurrencyPickerView(
                title: "You send",
                currencies: model.currencies,
                recents: model.recentCurrencies,
                selected: [model.sourceCode],
                allowsMultipleSelection: false,
                onSelect: { model.selectSource($0) }
            )
        case .target:
            CurrencyPickerView(
                title: "They get",
                currencies: model.currencies,
                recents: model.recentCurrencies,
                selected: [model.targetCode],
                allowsMultipleSelection: false,
                onSelect: { model.selectTarget($0) }
            )
        case .favorites:
            CurrencyPickerView(
                title: "Favorites",
                currencies: model.currencies,
                recents: model.recentCurrencies,
                selected: Set(model.favorites),
                allowsMultipleSelection: true,
                onSelect: { code in withAnimation(motion) { model.toggleFavorite(code) } }
            )
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("No rates yet", systemImage: "wifi.exclamationmark")
        } description: {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
            } else {
                Text("Exchange rates couldn't be loaded.")
            }
        } actions: {
            Button("Try Again") { Task { await model.refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

private extension View {
    /// A list row without the system background, insets or separators — for the cards.
    func plainListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

#if DEBUG
#Preview("Converter") {
    ConverterView(model: .preview(), history: .preview())
}

#Preview("Long result") {
    ConverterView(model: .preview(amount: "250", target: "GBP"), history: .preview())
}

#Preview("Huge result") {
    ConverterView(model: .preview(amount: "2500000", target: "IDR"), history: .preview())
}

#Preview("No favorites") {
    ConverterView(model: .preview(favorites: []), history: .preview())
}

#Preview("Offline, no cache") {
    ConverterView(model: .preview(api: OfflineRatesAPI(), snapshot: nil), history: .preview(api: OfflineRatesAPI()))
}
#endif
