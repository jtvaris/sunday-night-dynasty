import SwiftUI

/// Bottom-edge toast that surfaces a single FA storyline event (revenge tour,
/// hometown discount, holdout, etc). Auto-dismisses after ~4s with a slide+fade.
struct FAStorylineToast: View {
    let event: FAStorylineEvent?
    let onDismiss: () -> Void

    @State private var visible: Bool = false

    var body: some View {
        if let evt = event {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: FAStorylineIcons.icon(for: evt.type))
                        .foregroundStyle(FAStorylineIcons.tint(for: evt.type))
                    Text(evt.headline)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { visible = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text(evt.body)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }
            .padding(DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(FAStorylineIcons.tint(for: evt.type), lineWidth: 2)
                    )
            )
            .frame(maxWidth: 420)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 50)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3)) { visible = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    withAnimation(.easeInOut(duration: 0.25)) { visible = false }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    onDismiss()
                }
            }
        }
    }
}

/// Shared icon + tint mapping used by both the toast and inbox views.
enum FAStorylineIcons {
    static func icon(for type: FAStorylineEventType) -> String {
        switch type {
        case .revengeTour:     return "flame.fill"
        case .loyaltyDiscount: return "shield.fill"
        case .coachReunion:    return "person.2.fill"
        case .hometown:        return "house.fill"
        case .mentorPair:      return "person.fill"
        case .holdout:         return "exclamationmark.octagon.fill"
        case .milestone:       return "trophy.fill"
        case .community:       return "heart.fill"
        }
    }

    static func tint(for type: FAStorylineEventType) -> Color {
        switch type {
        case .revengeTour:     return .draftReachRed
        case .loyaltyDiscount: return .draftStealGold
        case .coachReunion:    return .accentGold
        case .hometown:        return .accentBlue
        case .mentorPair:      return .accentBlue
        case .holdout:         return .danger
        case .milestone:       return .draftStealGold
        case .community:       return .success
        }
    }
}
