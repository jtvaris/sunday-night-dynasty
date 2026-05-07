import SwiftUI

// MARK: - Waiver Claims Banner
//
// Top-edge banner shown on the Roster screen for ~8 seconds after one
// (or more) of the GM's recent cuts has been claimed off waivers by
// another team. Auto-dismisses; tap to keep visible / open detail.

struct WaiverClaimsBanner: View {

    /// One row per claimed cut.
    struct Claim: Identifiable, Equatable {
        let id: UUID
        let playerName: String
        let claimingTeamAbbrev: String
    }

    let claims: [Claim]
    /// Called when the banner should be dismissed (timeout or manual).
    let onDismiss: () -> Void

    @State private var visible: Bool = false
    @State private var dwellTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(Color.danger)
                    .font(.subheadline)
                Text(headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    dismissNow()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if !claims.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(claims.prefix(4)) { claim in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(Color.warning)
                                .font(.caption)
                            Text("\(claim.playerName) → \(claim.claimingTeamAbbrev)")
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                    }
                    if claims.count > 4 {
                        Text("…and \(claims.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(Color.danger.opacity(0.6), lineWidth: 1)
        )
        .padding(.horizontal, DSSpacing.md)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -20)
        .onAppear { startDwell() }
        .onDisappear { dwellTask?.cancel() }
    }

    // MARK: - Helpers

    private var headline: String {
        let n = claims.count
        if n == 0 { return "Waiver claim activity" }
        return "🚨 \(n) of your cut\(n == 1 ? "" : "s") \(n == 1 ? "was" : "were") claimed by other teams"
    }

    private func startDwell() {
        withAnimation(.easeOut(duration: 0.25)) { visible = true }
        dwellTask?.cancel()
        dwellTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run { dismissNow() }
        }
    }

    private func dismissNow() {
        dwellTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { visible = false }
        // Allow the fade-out to play before removing.
        Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            await MainActor.run { onDismiss() }
        }
    }
}
