import SwiftUI

/// Broadcast beat for a trade that just landed — the "WE HAVE A TRADE" cut-in.
///
/// Kept separate from `DramaOverlayView` on purpose: that view queues
/// `DraftDramaEngine.DramaEvent`s, which are all pick-grade derived (steal,
/// gem, Mr. Irrelevant). A trade is not a pick and needs none of that
/// machinery — it needs a headline, a line of why, and to get out of the way.
struct TradeBeatBanner: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    @State private var shown: DraftDayCoordinator.TradeBeat?
    @State private var visible = false

    var body: some View {
        VStack {
            if let beat = shown {
                content(beat)
                    .opacity(visible ? 1 : 0)
                    .offset(y: visible ? 0 : -24)
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .onChange(of: coordinator.pendingTradeBeats.count) { _, _ in
            showNextIfIdle()
        }
        .onAppear { showNextIfIdle() }
    }

    private func content(_ beat: DraftDayCoordinator.TradeBeat) -> some View {
        VStack(spacing: 2) {
            Text(beat.title)
                .font(.headline.weight(.heavy))
                .tracking(1.6)
                .foregroundStyle(Color.backgroundPrimary)
            Text(beat.subtitle)
                .font(.caption)
                .foregroundStyle(Color.backgroundPrimary.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.draftStealGold)
        )
        .shadow(color: Color.draftStealGold.opacity(0.55), radius: 14, x: 0, y: 6)
        .padding(.top, DSSpacing.sm)
    }

    /// One beat at a time, ~2.6 s each. The coordinator's queue is drained by
    /// this view so a fast-forward that produced four trades still shows all of
    /// them, in order, instead of only the last.
    private func showNextIfIdle() {
        guard shown == nil, let next = coordinator.pendingTradeBeats.first else { return }
        shown = next
        withAnimation(.easeOut(duration: DraftAnimation.bannerIn)) { visible = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeIn(duration: 0.25)) { visible = false }
            try? await Task.sleep(nanoseconds: 260_000_000)
            shown = nil
            coordinator.consumeOldestTradeBeat()
            showNextIfIdle()
        }
    }
}
