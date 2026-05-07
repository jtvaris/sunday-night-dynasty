import SwiftUI

// MARK: - Hard Knocks Toast
//
// Bottom-edge slide+fade toast (4s dwell) that surfaces a single
// `HardKnocksEvent`. Tap to expand the full storyline as a modal
// sheet. Type-icon at the leading edge, headline + 2-line body.

struct HardKnocksToast: View {

    let event: HardKnocksEvent
    /// Called after the dwell elapses or the user dismisses.
    let onDismiss: () -> Void

    @State private var visible: Bool = false
    @State private var showFullStory: Bool = false
    @State private var dwellTask: Task<Void, Never>?

    var body: some View {
        toastBody
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.sm)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 60)
            .onAppear { startDwell() }
            .onDisappear { dwellTask?.cancel() }
            .onTapGesture { showFullStory = true }
            .sheet(isPresented: $showFullStory, onDismiss: { dismissNow() }) {
                fullStorySheet
            }
    }

    // MARK: - Toast body

    private var toastBody: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Text(emoji(for: event.type))
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(event.body)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.up.circle")
                .foregroundStyle(Color.textTertiary)
                .font(.title3)
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(tint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - Full story sheet

    private var fullStorySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack(spacing: DSSpacing.sm) {
                        Text(emoji(for: event.type))
                            .font(.system(size: 48))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(typeLabel(for: event.type))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(tint)
                                .textCase(.uppercase)
                                .tracking(1.2)
                            Text(event.headline)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(event.body)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(DSSpacing.md)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Hard Knocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFullStory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func emoji(for type: HardKnocksEventType) -> String {
        switch type {
        case .rookieBreakout:    return "🌟"
        case .vetOnBubble:       return "⚠️"
        case .surpriseStarter:   return "🚀"
        case .depthChartShakeup: return "📊"
        case .campInjury:        return "🚑"
        case .tradeRumor:        return "💬"
        }
    }

    private func typeLabel(for type: HardKnocksEventType) -> String {
        switch type {
        case .rookieBreakout:    return "Rookie Breakout"
        case .vetOnBubble:       return "Vet on the Bubble"
        case .surpriseStarter:   return "Surprise Starter"
        case .depthChartShakeup: return "Depth Chart Shakeup"
        case .campInjury:        return "Camp Injury"
        case .tradeRumor:        return "Trade Rumor"
        }
    }

    private var tint: Color {
        switch event.type {
        case .rookieBreakout:    return Color.accentGold
        case .vetOnBubble:       return Color.warning
        case .surpriseStarter:   return Color.accentBlue
        case .depthChartShakeup: return Color.accentBlue
        case .campInjury:        return Color.danger
        case .tradeRumor:        return Color.success
        }
    }

    private func startDwell() {
        withAnimation(.easeOut(duration: 0.30)) { visible = true }
        dwellTask?.cancel()
        dwellTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !showFullStory { dismissNow() }
            }
        }
    }

    private func dismissNow() {
        dwellTask?.cancel()
        withAnimation(.easeIn(duration: 0.25)) { visible = false }
        Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            await MainActor.run { onDismiss() }
        }
    }
}
