import SwiftUI

struct OfflineBanner: View {
    let message: String
    /// When the server last confirmed the shown rates.
    let savedAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't update rates").font(.subheadline.weight(.semibold))
                if let savedAt {
                    Text("Showing rates last updated \(savedAt.formatted(.relative(presentation: .named))).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Theme.warningBackground, in: .rect(cornerRadius: Theme.listCornerRadius))
    }
}
