import SwiftUI
import SwiftData

struct FACompleteView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var recentSignings: [Player] = []

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.success)

                        Text("FREE AGENCY COMPLETE")
                            .font(.title2.weight(.black))
                            .foregroundStyle(Color.accentGold)

                        Text("All free agency rounds are finished. Your roster has been updated.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)

                    // Cap summary
                    if let team {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundStyle(Color.accentGold)
                                Text("Final Cap Situation")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentGold)
                                Spacer()
                            }

                            HStack(spacing: 0) {
                                capStat(label: "Cap", value: formatMillions(team.salaryCap), color: .accentGold)
                                capStat(label: "Used", value: formatMillions(team.currentCapUsage), color: .textPrimary)
                                capStat(label: "Available", value: formatMillions(team.availableCap), color: team.availableCap >= 0 ? .success : .danger)
                            }
                        }
                        .padding(16)
                        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
                    }

                    // Recent signings
                    if !recentSignings.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.badge.plus")
                                    .foregroundStyle(Color.accentGold)
                                Text("Your FA Signings")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentGold)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                            Divider().overlay(Color.surfaceBorder)

                            ForEach(recentSignings, id: \.id) { player in
                                HStack(spacing: 10) {
                                    Text(player.position.rawValue)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.textPrimary)
                                        .frame(width: 30)
                                        .padding(.vertical, 3)
                                        .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))
                                    Text(player.fullName)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(player.overall) OVR")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(Color.forRating(player.overall))
                                    Text(formatMillions(player.annualSalary) + "/yr")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
                    }

                    // Advance button (not actually advancing phase — that's handled by the shell)
                    Text("Use the Advance button in the sidebar to proceed to the next phase.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("FA Complete")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Helpers

    private func capStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        // Show recently signed players (short contracts = likely FA signings)
        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        let allPlayers = (try? modelContext.fetch(playerDesc)) ?? []
        // Approximate: players with short contracts (1-3 years) likely signed in FA
        recentSignings = allPlayers.filter { $0.contractYearsRemaining <= 3 && $0.contractYearsRemaining > 0 }
            .sorted { $0.overall > $1.overall }
            .prefix(10)
            .map { $0 }
    }
}
