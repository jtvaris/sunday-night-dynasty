import SwiftUI

struct FAOfferSheet: View {

    let player: Player
    let career: Career
    let team: Team
    let marketValue: Int
    let onSubmit: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var offerSalary: Int = 5000
    @State private var offerYears: Int = 2

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        playerInfoCard
                        offerTermsCard
                        capImpactCard
                        submitButton
                    }
                    .padding(24)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Make Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onAppear {
                offerSalary = marketValue
                offerYears = 2
            }
        }
    }

    // MARK: - Player Info

    private var playerInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(player.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 34)
                    .padding(.vertical, 4)
                    .background(positionSideColor, in: RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 8) {
                        Text("\(player.overall) OVR")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                        Text("Age \(player.age)")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 12) {
                statPill(label: "Asking", value: formatMillions(marketValue) + "/yr")
                statPill(label: "Motivation", value: player.personality.motivation.rawValue)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Offer Terms

    private var offerTermsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contract Terms")
                .font(.headline)
                .foregroundStyle(Color.accentGold)

            // Years
            HStack {
                Text("Years:")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Stepper("\(offerYears)", value: $offerYears, in: 1...5)
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }

            // Salary
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Annual Salary:")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(formatMillions(offerSalary) + "/yr")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
                Slider(
                    value: Binding(
                        get: { Double(offerSalary) },
                        set: { offerSalary = Int(($0 / 500).rounded()) * 500 }
                    ),
                    in: 500...75000,
                    step: 500
                )
                .tint(Color.accentGold)
            }

            // Total value
            HStack {
                Text("Total Value:")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(formatMillions(offerSalary * offerYears))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }

            // vs market
            let diff = offerSalary - marketValue
            HStack {
                Text("vs. Asking Price:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(diff >= 0 ? "+\(formatMillions(diff))" : formatMillions(diff))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(diff >= 0 ? Color.success : Color.danger)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Cap Impact

    private var capImpactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cap Impact")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            HStack {
                Text("Current Available:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(formatMillions(team.availableCap))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
            HStack {
                Text("After Signing:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                let remaining = team.availableCap - offerSalary
                Text(formatMillions(remaining))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? Color.success : Color.danger)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            onSubmit(offerSalary, offerYears)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "signature")
                Text("Submit Offer")
                    .font(.headline)
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }
}
