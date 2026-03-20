import SwiftUI

struct FARoundSummaryView: View {

    let results: RoundResults
    let roundLabel: String
    let nextRoundLabel: String
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("\(roundLabel) RESULTS")
                                .font(.title2.weight(.black))
                                .foregroundStyle(Color.accentGold)
                        }
                        .padding(.vertical, 20)

                        // Your signings
                        if !results.yourSignings.isEmpty {
                            summarySection(
                                title: "Your Signings",
                                icon: "checkmark.circle.fill",
                                color: .success
                            ) {
                                ForEach(Array(results.yourSignings.enumerated()), id: \.offset) { _, signing in
                                    HStack(spacing: 8) {
                                        Text(signing.position)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 30)
                                            .padding(.vertical, 2)
                                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))
                                        Text(signing.playerName)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(formatMillions(signing.salary))/yr \u{00B7} \(signing.years)yr")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // Your rejections
                        if !results.yourRejections.isEmpty {
                            summarySection(
                                title: "Rejections",
                                icon: "xmark.circle.fill",
                                color: .danger
                            ) {
                                ForEach(Array(results.yourRejections.enumerated()), id: \.offset) { _, rejection in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(rejection.position)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.textPrimary)
                                                .frame(width: 30)
                                                .padding(.vertical, 2)
                                                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))
                                            Text(rejection.playerName)
                                                .font(.subheadline)
                                                .foregroundStyle(Color.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            if let chosenTeam = rejection.chosenTeam {
                                                Text("\u{2192} \(chosenTeam)")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                        }
                                        Text("\"\(rejection.reason)\"")
                                            .font(.caption)
                                            .foregroundStyle(Color.textTertiary)
                                            .italic()
                                            .padding(.leading, 38)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // AI signings
                        if !results.aiSignings.isEmpty {
                            summarySection(
                                title: "Around the League",
                                icon: "newspaper.fill",
                                color: .accentBlue
                            ) {
                                ForEach(Array(results.aiSignings.prefix(8).enumerated()), id: \.offset) { _, signing in
                                    HStack(spacing: 8) {
                                        Text(signing.position)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 30)
                                            .padding(.vertical, 2)
                                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))
                                        Text(signing.playerName)
                                            .font(.caption)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\u{2192} \(signing.team)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textSecondary)
                                        Text(formatMillions(signing.salary))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        // Media headlines
                        if !results.headlines.isEmpty {
                            summarySection(
                                title: "Headlines",
                                icon: "newspaper.fill",
                                color: .accentGold
                            ) {
                                ForEach(Array(results.headlines.enumerated()), id: \.offset) { _, headline in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\u{201C}")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(Color.accentGold)
                                        Text(headline)
                                            .font(.caption)
                                            .foregroundStyle(Color.textPrimary)
                                            .italic()
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        // Market update
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text("\(results.playersRemaining)")
                                    .font(.title2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Color.textPrimary)
                                Text("Players Left")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            VStack(spacing: 2) {
                                Text(formatMillions(results.capRemaining))
                                    .font(.title2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(results.capRemaining > 0 ? Color.success : Color.danger)
                                Text("Your Cap Space")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(.vertical, 12)

                        // Continue button
                        Button {
                            onContinue()
                        } label: {
                            Text("Continue to \(nextRoundLabel)")
                                .font(.headline)
                                .foregroundStyle(Color.backgroundPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Round Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Section

    private func summarySection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 14))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().overlay(Color.surfaceBorder)

            content()

            Spacer().frame(height: 8)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Helpers

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }
}
