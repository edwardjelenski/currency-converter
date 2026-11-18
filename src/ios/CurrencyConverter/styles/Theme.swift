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

    static let warning = Color.orange
    static let warningBackground = Color.orange.opacity(0.12)

    static let cardCornerRadius: CGFloat = 20
    static let listCornerRadius: CGFloat = 16

    static let amountFont = Font.system(.title, design: .rounded, weight: .semibold)
}
