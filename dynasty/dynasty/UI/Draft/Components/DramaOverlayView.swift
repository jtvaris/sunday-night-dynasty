import SwiftUI

/// Top-level drama overlay that listens to `coordinator.pendingDrama` and
/// renders one event at a time with the appropriate broadcast treatment
/// (steal banner, gem flash, round curtain, "your pick is coming up" pulse,
/// Mr. Irrelevant moment).
struct DramaOverlayView: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    @State private var visible: Bool = false
    @State private var presentedIndex: Int = -1

    var body: some View {
        ZStack {
            if let event = coordinator.pendingDrama.first {
                content(for: event)
                    .task(id: dramaKey(event)) {
                        await runLifecycle(for: event)
                    }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Lifecycle

    private func runLifecycle(for event: DraftDramaEngine.DramaEvent) async {
        visible = false
        try? await Task.sleep(nanoseconds: 30_000_000)
        withAnimation(.easeOut(duration: DraftAnimation.bannerIn)) {
            visible = true
        }

        let dwellNanos = UInt64(dwellSeconds(for: event) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: dwellNanos)

        withAnimation(.easeIn(duration: DraftAnimation.bannerOut)) {
            visible = false
        }

        let outNanos = UInt64(DraftAnimation.bannerOut * 1_000_000_000) + 60_000_000
        try? await Task.sleep(nanoseconds: outNanos)

        coordinator.consumeOldestDrama()
    }

    private func dwellSeconds(for event: DraftDramaEngine.DramaEvent) -> Double {
        switch event {
        case .stealOfTheDraft:      return 2.5
        case .roundTransition:      return 1.5
        case .gemMoment:            return 1.2
        case .userPickIncoming:     return 1.0
        case .finalPick:            return 2.0
        }
    }

    private func dramaKey(_ event: DraftDramaEngine.DramaEvent) -> String {
        switch event {
        case .stealOfTheDraft(let p, let t, let v):
            return "steal:\(t):\(p):\(v)"
        case .roundTransition(let r):
            return "round:\(r)"
        case .gemMoment(let p, let t):
            return "gem:\(t):\(p)"
        case .userPickIncoming(let n):
            return "incoming:\(n)"
        case .finalPick:
            return "final"
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private func content(for event: DraftDramaEngine.DramaEvent) -> some View {
        switch event {
        case .stealOfTheDraft(let playerName, let teamAbbrev, let valueDelta):
            stealBanner(playerName: playerName, teamAbbrev: teamAbbrev, valueDelta: valueDelta)
        case .roundTransition(let roundNumber):
            roundCurtain(roundNumber: roundNumber)
        case .gemMoment(let playerName, let teamAbbrev):
            gemFlash(playerName: playerName, teamAbbrev: teamAbbrev)
        case .userPickIncoming(let picksAway):
            incomingBanner(picksAway: picksAway)
        case .finalPick:
            finalPickOverlay()
        }
    }

    // MARK: - Steal of the draft (top ticker)

    private func stealBanner(playerName: String, teamAbbrev: String, valueDelta: Int) -> some View {
        VStack {
            HStack(spacing: DSSpacing.sm) {
                Text("⚡ STEAL OF THE DRAFT")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(1.2)
                Text("— \(teamAbbrev) snags \(playerName) (+\(valueDelta) value)")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .background(
                LinearGradient(
                    colors: [
                        Color.draftReachRed,
                        Color.draftStealGold
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.card))
            .shadow(color: Color.draftStealGold.opacity(0.6), radius: 12, x: 0, y: 4)
            .opacity(visible ? 1 : 0)
            .offset(x: visible ? 0 : -400)
            .padding(.top, DSSpacing.md)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Round transition (full-screen fade)

    private func roundCurtain(roundNumber: Int) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.backgroundPrimary,
                    Color.draftStealGold.opacity(0.45),
                    Color.backgroundPrimary
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .opacity(visible ? 0.92 : 0)

            VStack(spacing: DSSpacing.sm) {
                Text("ROUND")
                    .font(.title.weight(.heavy))
                    .tracking(8)
                    .foregroundStyle(Color.textPrimary.opacity(0.85))
                Text("\(roundNumber)")
                    .font(.system(size: 140, weight: .black, design: .rounded))
                    .foregroundStyle(Color.draftStealGold)
                    .shadow(color: Color.draftStealGold.opacity(0.6), radius: 20)
                Text("BEGINS")
                    .font(.title2.weight(.bold))
                    .tracking(6)
                    .foregroundStyle(Color.textPrimary)
            }
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1.0 : 0.9)
        }
    }

    // MARK: - Gem flash

    private func gemFlash(playerName: String, teamAbbrev: String) -> some View {
        ZStack {
            Color.black.opacity(visible ? 0.35 : 0)
                .ignoresSafeArea()

            VStack(spacing: DSSpacing.sm) {
                Text("💎")
                    .font(.system(size: 60))
                Text("\(teamAbbrev) LANDS THEIR GUY")
                    .font(.headline.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(Color.draftStealGold)
                Text(playerName)
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(DSSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(Color.draftStealGold, lineWidth: 3)
                    )
            )
            .shadow(color: Color.draftStealGold.opacity(0.7), radius: 24, x: 0, y: 0)
            .scaleEffect(visible ? 1.0 : 0.6)
            .opacity(visible ? 1 : 0)
        }
    }

    // MARK: - User pick incoming (top pulse banner)

    private func incomingBanner(picksAway: Int) -> some View {
        VStack {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.draftClockUrgent)
                Text("YOUR PICK IN \(picksAway) \(picksAway == 1 ? "PICK" : "PICKS")")
                    .font(.headline.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.draftClockUrgent.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(Color.draftStealGold, lineWidth: 2)
                    )
            )
            .scaleEffect(visible ? 1.06 : 1.0)
            .opacity(visible ? 1 : 0)
            .padding(.top, DSSpacing.md)
            .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: visible)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Final pick

    private func finalPickOverlay() -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.backgroundPrimary,
                    Color.draftStealGold.opacity(0.5),
                    Color.backgroundPrimary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(visible ? 0.95 : 0)

            VStack(spacing: DSSpacing.md) {
                Text("🎉")
                    .font(.system(size: 80))
                Text("MR. IRRELEVANT")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(Color.draftStealGold)
                    .shadow(color: Color.draftStealGold.opacity(0.6), radius: 16)
                Text("DRAFT COMPLETE")
                    .font(.title.weight(.bold))
                    .tracking(4)
                    .foregroundStyle(Color.textPrimary)
            }
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1.0 : 0.85)
        }
    }
}
