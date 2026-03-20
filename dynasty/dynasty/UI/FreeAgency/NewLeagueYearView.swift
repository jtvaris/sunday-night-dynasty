import SwiftUI
import SwiftData

struct NewLeagueYearView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var summary: FreeAgencyEngine.LeagueYearSummary?
    @State private var hasExecuted = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let summary {
                ScrollView {
                    VStack(spacing: 24) {
                        transitionHeader(summary: summary)
                        capSummaryCard(summary: summary)
                        notableFACard(summary: summary)
                        continueButton
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Color.accentGold)
                    Text("Advancing contracts...")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .navigationTitle("New League Year")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { executeTransition() }
    }

    // MARK: - Transition Header

    private func transitionHeader(summary: FreeAgencyEngine.LeagueYearSummary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentGold)

            Text("NEW LEAGUE YEAR")
                .font(.title2.weight(.black))
                .foregroundStyle(Color.accentGold)

            Text("\(summary.totalFreeAgentCount) players hit free agency")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Cap Summary

    private func capSummaryCard(summary: FreeAgencyEngine.LeagueYearSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text("Your Cap Situation")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            VStack(spacing: 12) {
                capRow(label: "Previous cap usage", value: formatMillions(summary.playerTeamCapBefore), color: .textSecondary)
                capRow(label: "Cap freed from expirations", value: "+\(formatMillions(summary.capFreed))", color: .success)
                capRow(label: "New cap usage", value: formatMillions(summary.playerTeamCapAfter), color: .textPrimary)
            }
            .padding(16)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func capRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: - Notable Free Agents

    private func notableFACard(summary: FreeAgencyEngine.LeagueYearSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text("Notable New Free Agents")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            VStack(spacing: 0) {
                ForEach(Array(summary.notableFreeAgents.enumerated()), id: \.offset) { index, fa in
                    HStack(spacing: 10) {
                        Text(fa.position)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 34)
                            .padding(.vertical, 3)
                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))

                        Text(fa.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(fa.overall) OVR")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(fa.overall))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if index < summary.notableFreeAgents.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            career.freeAgencyStep = FreeAgencyStep.capReview.rawValue
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title3)
                Text("Continue to Cap Review")
                    .font(.headline)
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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

    private func executeTransition() {
        guard !hasExecuted else { return }
        hasExecuted = true

        guard let teamID = career.teamID else { return }
        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []

        summary = FreeAgencyEngine.executeNewLeagueYear(
            allPlayers: allPlayers,
            allTeams: allTeams,
            playerTeamID: teamID,
            modelContext: modelContext
        )
    }
}
