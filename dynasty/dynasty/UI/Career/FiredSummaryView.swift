import SwiftUI
import SwiftData

// MARK: - FiredSummaryView (R31)

/// The end of the road: the owner has fired the coach. Shows a career
/// summary (record, playoffs, championships, reputation, legacy) and
/// returns to the main menu. The career is marked `isGameOver` so
/// reopening the save lands back on this screen.
struct FiredSummaryView: View {

    let career: Career
    let teamName: String
    let ownerName: String
    /// The owner's parting words from the season review, when available.
    let reviewSummary: String?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    ownerStatement

                    careerStatsCard

                    legacyCard

                    Button {
                        returnToMainMenu()
                    } label: {
                        Text("Return to Main Menu")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.danger)

            Text("Relieved of Duties")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(Color.textPrimary)

            Text("\(ownerName) has decided to move on from you as the leader of the \(teamName).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
    }

    // MARK: - Owner Statement

    @ViewBuilder
    private var ownerStatement: some View {
        if let reviewSummary {
            VStack(alignment: .leading, spacing: 10) {
                Text("THE OWNER'S STATEMENT")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.danger)

                Text("\u{201C}\(reviewSummary)\u{201D}")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\u{2014} \(ownerName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.danger.opacity(0.4), lineWidth: 1.5)
                    )
            )
        }
    }

    // MARK: - Career Stats

    private var careerStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CAREER SUMMARY \u{2014} \(career.playerName.uppercased())")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                statColumn(
                    label: "Career Record",
                    value: "\(career.totalWins)-\(career.totalLosses)",
                    color: career.totalWins >= career.totalLosses ? .success : .danger
                )
                statColumn(
                    label: "Win %",
                    value: String(format: "%.1f%%", career.winPercentage * 100),
                    color: .textPrimary
                )
                statColumn(
                    label: "Seasons",
                    value: "\(max(1, (career.totalWins + career.totalLosses) / 17))",
                    color: .textPrimary
                )
            }

            HStack(spacing: 0) {
                statColumn(
                    label: "Playoff Trips",
                    value: "\(career.playoffAppearances)",
                    color: career.playoffAppearances > 0 ? .success : .textSecondary
                )
                statColumn(
                    label: "Championships",
                    value: "\(career.championships)",
                    color: career.championships > 0 ? .accentGold : .textSecondary
                )
                statColumn(
                    label: "Reputation",
                    value: "\(career.reputation)",
                    color: .accentBlue
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Legacy

    private var legacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Legacy")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(career.legacy.totalPoints) pts")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }

            Text(legacyText)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var legacyText: String {
        if career.championships > 0 {
            return "A champion's résumé speaks for itself. Getting fired stings, but a ring is forever — the league will remember this tenure."
        } else if career.playoffAppearances > 0 {
            return "You brought playoff football to the \(teamName). It wasn't enough for \(ownerName), but other front offices took notes."
        } else if career.totalWins >= career.totalLosses {
            return "A winning record without the postseason breakthrough. The next chapter of your coaching story is still unwritten."
        } else {
            return "A tough tenure comes to an end. Every great coach has been fired at least once — the comeback starts now."
        }
    }

    // MARK: - Exit

    private func returnToMainMenu() {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.rootViewController = UIHostingController(rootView:
                ContentView()
                    .modelContainer(DataContainer.create())
            )
        }
    }
}

// MARK: - Preview

#Preview {
    FiredSummaryView(
        career: Career(playerName: "Alex Reid", role: .gm, capMode: .simple),
        teamName: "Chicago Bears",
        ownerName: "Marlene Vance",
        reviewSummary: "You hit 0 of 4 goals with a 3-14 finish. I've made a decision — this organization needs a new direction."
    )
    .modelContainer(for: Career.self, inMemory: true)
}
