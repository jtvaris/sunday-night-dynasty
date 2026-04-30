import SwiftUI

// MARK: - Empty State View
//
// Reusable empty-state component for lists, panels, and tabs that have no
// data yet. Provides a consistent illustration + headline + supporting copy
// + optional CTA, instead of bare "No data" strings.
//
// Usage:
//   EmptyStateView(
//       icon: "tray",
//       title: "No messages yet",
//       message: "Weekly recaps and league news will appear here.",
//       actionTitle: "Refresh",
//       action: { ... }
//   )

struct EmptyStateView: View {

    let icon: String
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            // Illustration: SF Symbol inside a soft circular halo
            ZStack {
                Circle()
                    .fill(Color.backgroundTertiary)
                    .frame(width: 88, height: 88)
                Circle()
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    .frame(width: 88, height: 88)
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentGold)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Compact Variant
//
// For inline / card-internal empty states where the full hero
// layout above would be too tall.

struct CompactEmptyStateView: View {

    let icon: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.textSecondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }
}

#Preview("Hero") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        EmptyStateView(
            icon: "tray",
            title: "No messages yet",
            message: "Weekly recaps and league news will appear here once the season starts.",
            actionTitle: "Open Inbox",
            action: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Compact") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        CompactEmptyStateView(
            icon: "person.crop.circle.badge.questionmark",
            message: "No prospects scouted yet — visit the combine to start."
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
