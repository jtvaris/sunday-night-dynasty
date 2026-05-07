import SwiftUI

/// Modal sheet that lets the GM resolve a player's holdout situation.
/// Drives `HoldoutEngine.Resolution` selection (FA Drama brief, Phase 5 UI).
struct HoldoutDialog: View {
    let holdout: Holdout
    let playerName: String
    let position: String
    let currentSalary: Int           // thousands
    let marketValue: Int             // thousands
    let onResolve: (HoldoutEngine.Resolution) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedResolution: HoldoutEngine.Resolution = .mediation
    @State private var resolving: Bool = false
    @State private var result: Bool? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                headerCard

                Text("This player is unhappy. Their current $\(currentSalary/1000)M/yr is $\(holdout.subMarketDelta/1000)M below market value of $\(marketValue/1000)M/yr. Choose how to resolve:")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)

                VStack(spacing: DSSpacing.sm) {
                    resolutionOption(.extend, title: "Extend Contract",
                                     description: "Negotiate a multi-year extension at market rate. Costs cap room long-term.",
                                     icon: "doc.append.fill")
                    resolutionOption(.signingBonus, title: "Pay Signing Bonus",
                                     description: "Lump-sum bonus payment. Fast resolution but spreads cap hit.",
                                     icon: "dollarsign.circle.fill")
                    resolutionOption(.forceTrade, title: "Force Trade",
                                     description: "Move the unhappy player. Quick relief but lose the asset.",
                                     icon: "arrow.left.arrow.right.circle.fill")
                    resolutionOption(.mediation, title: "Mediate (75% chance)",
                                     description: "Have a 30-min meeting. Cheapest path but may fail.",
                                     icon: "person.2.wave.2.fill")
                }

                Spacer()

                if let result {
                    resultCard(success: result)
                }

                resolveButton
            }
            .padding(DSSpacing.lg)
            .background(Color.backgroundPrimary)
            .navigationTitle("Holdout Crisis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(resolving)
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(playerName)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                Text("\(position) · Holding out since \(holdout.startedAt, style: .date)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DSCornerRadius.card)
            .fill(Color.backgroundSecondary)
            .overlay(RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(Color.danger, lineWidth: 2)))
    }

    private func resolutionOption(_ res: HoldoutEngine.Resolution, title: String, description: String, icon: String) -> some View {
        let isSelected = selectedResolution == res
        return Button { selectedResolution = res } label: {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.draftStealGold : Color.textSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(isSelected ? Color.draftStealGold.opacity(0.15) : Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(isSelected ? Color.draftStealGold : Color.surfaceBorder, lineWidth: isSelected ? 2 : 1)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func resultCard(success: Bool) -> some View {
        HStack {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? Color.success : Color.danger)
            Text(success ? "Resolved successfully!" : "Mediation failed. Holdout continues.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(success ? Color.success : Color.danger)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DSCornerRadius.card)
            .fill((success ? Color.success : Color.danger).opacity(0.15)))
    }

    private var resolveButton: some View {
        Button {
            resolving = true
            // Simulate resolution
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                onResolve(selectedResolution)
                // Mediation has random outcome; others always succeed
                let didResolve = selectedResolution == .mediation ? Bool.random() : true
                await MainActor.run {
                    result = didResolve
                    resolving = false
                    if didResolve {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            dismiss()
                        }
                    }
                }
            }
        } label: {
            HStack {
                if resolving {
                    ProgressView()
                        .tint(Color.backgroundPrimary)
                }
                Text(resolving ? "Resolving..." : "Resolve")
                    .font(.headline)
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.draftStealGold, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        }
        .buttonStyle(.plain)
        .disabled(resolving || result == true)
    }
}
