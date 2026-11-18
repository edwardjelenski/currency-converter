# Currency Converter

iOS currency converter built with SwiftUI.

- iOS 17+
- Swift 6 language mode with complete strict concurrency checking
- Project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- No third-party dependencies

## Features

- Convert between ~30 currencies using European Central Bank reference rates
- Swap currencies, search the currency list by name or ISO code
- See the amount converted into every other currency at once; tap one to make it the target
- Works offline with the last downloaded rates; pull to refresh
- Remembers the last amount and currency pair
- Locale-aware amount input (`1 234,5`, `1,234.5`, `1.234,5`)

## Getting started

```bash
brew install xcodegen
xcodegen generate
open CurrencyConverter.xcodeproj
```

The `.xcodeproj` is not committed — regenerate it after pulling changes to `project.yml`
or adding/removing files.

Run the tests from Xcode (⌘U) or:

```bash
xcodebuild test -project CurrencyConverter.xcodeproj -scheme CurrencyConverter \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Architecture

```
CurrencyConverter/
├── App/                  App entry point
├── Models/               ExchangeRates (cross-rate math), Currency, AmountParser
├── Services/             FrankfurterClient, RatesCache (actor), RatesRepository
├── Features/
│   ├── Converter/        ConverterView + @MainActor @Observable ConverterViewModel
│   └── CurrencyPicker/   Searchable currency sheet
└── Preview/              Debug-only sample data for #Preview
```

Rates come from the free [Frankfurter API](https://frankfurter.dev) (no API key).
The app fetches one EUR-based snapshot and computes every pair locally as a cross rate,
so a single request covers all conversions. ECB publishes new rates once per working day.
