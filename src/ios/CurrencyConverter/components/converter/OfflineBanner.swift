import SwiftUI

struct OfflineBanner: View {
    let message: String
    let fetchedAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't update rates").font(.subheadline.weight(.semibold))
                if let fetchedAt {
                    Text("Showing rates saved \(fetchedAt.formatted(.relative(presentation: .named))).")
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
