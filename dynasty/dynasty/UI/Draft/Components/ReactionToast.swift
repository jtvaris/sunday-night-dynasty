import SwiftUI

/// Bottom-edge overlay that surfaces ONE pending `ReactionsEngine.Reaction` at
/// a time, FIFO order. Each toast animates in (`toastIn`), dwells
/// (`toastDwell`), and animates out before consuming the head of the queue and
/// optionally showing the next.
struct ReactionToast: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    @State private var visible: Bool = false
    @State private var pulse: Bool = false
    @State private var presentedKey: String? = nil

    var body: some View {
        ZStack {
            if let reaction = coordinator.pendingReactions.first {
                let key = reactionKey(for: reaction)
                toast(for: reaction)
                    .opacity(visible ? 1 : 0)
                    .offset(y: visible ? 0 : 24)
                    .scaleEffect(pulseScale(for: reaction))
                    .animation(.easeOut(duration: DraftAnimation.toastIn), value: visible)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                    .task(id: key) {
                        await runLifecycle(reactionKey: key, sentiment: reaction.sentiment)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Lifecycle

    private func runLifecycle(reactionKey: String, sentiment: ReactionsEngine.Sentiment) async {
        // Reset state for the new reaction.
        presentedKey = reactionKey
        visible = false
        pulse = false

        // Brief delay before animating in so SwiftUI can settle.
        try? await Task.sleep(nanoseconds: 30_000_000)
        withAnimation(.easeOut(duration: DraftAnimation.toastIn)) {
            visible = true
        }
        if sentiment == .critical {
            pulse = true
        }

        // Dwell while visible.
        let dwellNanos = UInt64(DraftAnimation.toastDwell * 1_000_000_000)
        try? await Task.sleep(nanoseconds: dwellNanos)

        // If the queue head changed mid-dwell (e.g. rapid picks), abort.
        guard presentedKey == reactionKey else { return }

        withAnimation(.easeIn(duration: DraftAnimation.bannerOut)) {
            visible = false
            pulse = false
        }

        let outNanos = UInt64(DraftAnimation.bannerOut * 1_000_000_000) + 50_000_000
        try? await Task.sleep(nanoseconds: outNanos)

        // Only consume if we are still the displayed reaction.
        guard presentedKey == reactionKey else { return }
        coordinator.consumeOldestReaction()
    }

    private func reactionKey(for reaction: ReactionsEngine.Reaction) -> String {
        "\(reaction.actor.rawValue):\(reaction.message):\(reaction.mechanicalDelta):\(coordinator.pendingReactions.count)"
    }

    private func pulseScale(for reaction: ReactionsEngine.Reaction) -> CGFloat {
        guard reaction.sentiment == .critical, pulse else { return 1.0 }
        return 1.03
    }

    // MARK: - View

    @ViewBuilder
    private func toast(for reaction: ReactionsEngine.Reaction) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(actorIcon(for: reaction.actor))
                        .font(.title3)
                    Text(actorName(for: reaction.actor))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)
                        .tracking(0.8)
                }
                Text(reaction.message)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary.opacity(0.94))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if reaction.mechanicalDelta != 0 {
                Text(formattedDelta(reaction.mechanicalDelta))
                    .font(.callout.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(deltaBackground(for: reaction.sentiment))
                    .foregroundStyle(deltaForeground(for: reaction.sentiment))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(DSSpacing.md)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(backgroundTint(for: reaction.sentiment))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(borderColor(for: reaction.sentiment),
                                      lineWidth: reaction.sentiment == .critical ? 2 : 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
    }

    // MARK: - Styling

    private func actorIcon(for actor: ReactionsEngine.Actor) -> String {
        switch actor {
        case .owner:      return "👔"
        case .media:      return "📰"
        case .lockerRoom: return "🏈"
        case .fans:       return "📣"
        }
    }

    private func actorName(for actor: ReactionsEngine.Actor) -> String {
        switch actor {
        case .owner:      return "OWNER"
        case .media:      return "MEDIA"
        case .lockerRoom: return "LOCKER ROOM"
        case .fans:       return "FANS"
        }
    }

    private func backgroundTint(for sentiment: ReactionsEngine.Sentiment) -> Color {
        switch sentiment {
        case .positive: return Color.draftStealGold.opacity(0.32)
        case .mixed:    return Color.draftSolidNeutral.opacity(0.42)
        case .negative: return Color.draftReachRed.opacity(0.38)
        case .critical: return Color.draftReachRed.opacity(0.55)
        }
    }

    private func borderColor(for sentiment: ReactionsEngine.Sentiment) -> Color {
        switch sentiment {
        case .positive: return Color.draftStealGold.opacity(0.6)
        case .mixed:    return Color.surfaceBorder
        case .negative: return Color.draftReachRed.opacity(0.5)
        case .critical: return Color.draftReachRed
        }
    }

    private func deltaBackground(for sentiment: ReactionsEngine.Sentiment) -> Color {
        switch sentiment {
        case .positive: return Color.success.opacity(0.85)
        case .mixed:    return Color.draftSolidNeutral
        case .negative: return Color.danger.opacity(0.85)
        case .critical: return Color.danger
        }
    }

    private func deltaForeground(for sentiment: ReactionsEngine.Sentiment) -> Color {
        Color.textPrimary
    }

    private func formattedDelta(_ delta: Int) -> String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }
}
