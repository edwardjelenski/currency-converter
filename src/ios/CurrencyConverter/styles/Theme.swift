import SwiftUI

/// Shared colors and metrics so screens stay visually consistent.
/// The accent color lives in `resources/Assets.xcassets/AccentColor`.
enum Theme {
    /// Screen background behind cards.
    static let background = Color(.systemGroupedBackground)
    /// Card and list surface on top of `background`.
    static let surface = Color(.secondarySystemGroupedBackground)
    /// Pill behind the currency selector.
    static let chip = Color(.tertiarySystemFill)

    /// Rate went up / down. System green and red are too light on a white card
    /// (≈2:1); the light-mode shades reach ≥4.5:1, dark mode keeps the system colors.
    static let positive = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGreen : UIColor(red: 0.0, green: 0.5, blue: 0.2, alpha: 1)
    })
    static let negative = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemRed : UIColor(red: 0.78, green: 0.1, blue: 0.1, alpha: 1)
    })

    static let warning = Color.orange
    static let warningBackground = Color.orange.opacity(0.12)

    static let cardCornerRadius: CGFloat = 20
    static let listCornerRadius: CGFloat = 16

    /// The amount you send and the result: large, and with monospaced digits so the
    /// number doesn't jiggle sideways while typing or when the rate updates.
    static let amountFont = Font.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit()
}
