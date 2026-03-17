import SwiftUI
import SwiftData

// MARK: - OwnerMeetingView

struct OwnerMeetingView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var owner: Owner?
    @State private var team: Team?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if let owner {
                    ScrollView {
                        VStack(spacing: 20) {
                            ownerProfileCard(owner)
                            satisfactionCard(owner)
                            patienceCard(owner)
                            preferencesCard(owner)
                            if owner.satisfaction < 60 {
                                warningCard(owner)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    noOwnerState
                }
            }
        }
        .navigationTitle("Owner Relations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadOwner() }
    }

    // MARK: - Owner Profile Card

    private func ownerProfileCard(_ owner: Owner) -> some View {
        HStack(spacing: 16) {
            // Avatar
            OwnerAvatarImageView(avatarID: owner.avatarID, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(owner.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(team?.fullName ?? "Owner")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Text("Season \(career.currentSeason)")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Satisfaction badge
            satisfactionBadge(owner.satisfaction)
        }
        .padding(20)
        .cardBackground()
    }

    private func satisfactionBadge(_ value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)%")
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(satisfactionColor(value))
            Text("Satisfied")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: 60)
    }

    // MARK: - Satisfaction Card

    private func satisfactionCard(_ owner: Owner) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Owner Satisfaction")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(owner.satisfaction) / 100")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(satisfactionColor(owner.satisfaction))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(satisfactionGradient(owner.satisfaction))
                        .frame(width: geo.size.width * CGFloat(owner.satisfaction) / 100.0, height: 14)
                        .animation(.easeOut(duration: 0.6), value: owner.satisfaction)
                }
            }
            .frame(height: 14)

            // Zone labels
            HStack {
                Label("Danger", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.danger)
                Spacer()
                Label("Caution", systemImage: "minus.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.warning)
                Spacer()
                Label("Good", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.success)
            }
            .padding(.top, 2)

            Divider().overlay(Color.surfaceBorder)

            // Status text
            VStack(alignment: .leading, spacing: 6) {
                Text(satisfactionStatusTitle(owner.satisfaction))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(satisfactionColor(owner.satisfaction))
                Text(satisfactionStatusBody(owner.satisfaction, owner: owner))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Patience Card

    private func patienceCard(_ owner: Owner) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color.accentGold)
                Text("Owner Patience")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                patienceStatColumn(
                    label: "Patience",
                    value: "\(owner.patience)/10",
                    color: patienceColor(owner.patience)
                )
                patienceStatColumn(
                    label: "Seasons Before Review",
                    value: seasonsBeforeFiring(owner),
                    color: Color.textPrimary
                )
                patienceStatColumn(
                    label: "Current Season",
                    value: "\(career.currentSeason)",
                    color: Color.textSecondary
                )
            }

            Text(patienceDescription(owner.patience))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundTertiary)
                )
        }
        .padding(20)
        .cardBackground()
    }

    private func patienceStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Preferences Card

    private func preferencesCard(_ owner: Owner) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.accentGold)
                Text("Owner Priorities")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            // Win Now vs Rebuild
            preferenceRow(
                icon: owner.prefersWinNow ? "trophy.fill" : "building.2.fill",
                label: "Philosophy",
                value: owner.prefersWinNow ? "Win Now" : "Willing to Rebuild",
                valueColor: owner.prefersWinNow ? Color.accentGold : Color.accentBlue
            )

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Meddling level
            let meddleLabel = meddlingLabel(owner.meddling)
            preferenceRow(
                icon: "person.badge.key.fill",
                label: "Involvement",
                value: meddleLabel.text,
                valueColor: meddleLabel.color
            )

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Spending willingness
            let spendLabel = spendingLabel(owner.spendingWillingness)
            preferenceRow(
                icon: "dollarsign.circle.fill",
                label: "Spending",
                value: spendLabel.text,
                valueColor: spendLabel.color
            )
        }
        .padding(20)
        .cardBackground()
    }

    private func preferenceRow(icon: String, label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentGold)
                .frame(width: 22)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Warning Card

    private func warningCard(_ owner: Owner) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.danger)
                    .font(.system(size: 18))
                Text(owner.satisfaction < 35 ? "Your Job Is In Danger" : "Owner Is Concerned")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(owner.satisfaction < 35 ? Color.danger : Color.warning)
            }

            Divider().overlay(Color.surfaceBorder)

            ForEach(warningMessages(owner), id: \.self) { message in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(owner.satisfaction < 35 ? Color.danger : Color.warning)
                        .padding(.top, 2)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            owner.satisfaction < 35 ? Color.danger.opacity(0.5) : Color.warning.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
        )
    }

    // MARK: - No Owner State

    private var noOwnerState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Owner Data")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text("Owner information will be available once a team is selected.")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func satisfactionColor(_ value: Int) -> Color {
        if value > 60  { return Color.success }
        if value >= 35 { return Color.warning }
        return Color.danger
    }

    private func satisfactionGradient(_ value: Int) -> LinearGradient {
        let color = satisfactionColor(value)
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func satisfactionStatusTitle(_ value: Int) -> String {
        if value > 75 { return "Owner is thrilled" }
        if value > 60 { return "Owner is satisfied" }
        if value > 45 { return "Owner has concerns" }
        if value > 35 { return "Owner is frustrated" }
        return "Owner is furious"
    }

    private func satisfactionStatusBody(_ value: Int, owner: Owner) -> String {
        if value > 75 {
            return "\(owner.name) is very pleased with the direction of the franchise and has full confidence in your leadership."
        } else if value > 60 {
            return "\(owner.name) is generally happy but expects continued improvement heading into the next stretch."
        } else if value > 45 {
            return "\(owner.name) has started to question some decisions. Winning games will ease the tension."
        } else if value > 35 {
            return "\(owner.name) is openly frustrated. A losing streak or another controversy could put your job at risk."
        } else {
            return "\(owner.name) is furious. Significant improvement is needed immediately or you will be fired."
        }
    }

    private func patienceColor(_ value: Int) -> Color {
        if value >= 7 { return Color.success }
        if value >= 4 { return Color.warning }
        return Color.danger
    }

    private func patienceDescription(_ value: Int) -> String {
        if value >= 8 { return "This owner is very patient and will give you time to build a winner through any strategy." }
        if value >= 6 { return "The owner is moderately patient but expects steady improvement each season." }
        if value >= 4 { return "The owner wants results sooner rather than later. Missing the playoffs repeatedly will cost you." }
        return "This owner has a short fuse. You need wins now or your tenure will be brief."
    }

    private func seasonsBeforeFiring(_ owner: Owner) -> String {
        let remaining = max(0, owner.patience - career.yearsFired)
        return remaining == 0 ? "This Season" : "\(remaining)"
    }

    private func meddlingLabel(_ value: Int) -> (text: String, color: Color) {
        if value < 25 { return ("Hands Off", Color.success) }
        if value < 50 { return ("Occasionally Involved", Color.accentBlue) }
        if value < 75 { return ("Frequently Involved", Color.warning) }
        return ("Highly Controlling", Color.danger)
    }

    private func spendingLabel(_ value: Int) -> (text: String, color: Color) {
        if value < 25 { return ("Budget Conscious", Color.danger) }
        if value < 50 { return ("Moderate Spender", Color.warning) }
        if value < 75 { return ("Willing to Spend", Color.accentBlue) }
        return ("Opens the Checkbook", Color.success) }

    private func warningMessages(_ owner: Owner) -> [String] {
        var messages: [String] = []
        if owner.satisfaction < 35 {
            messages.append("The owner is actively considering a coaching change.")
        }
        if owner.prefersWinNow && career.totalWins < 5 {
            messages.append("This owner prioritizes winning immediately — results are expected now.")
        }
        if owner.meddling > 60 {
            messages.append("The owner may start overriding your personnel decisions.")
        }
        if owner.patience <= 3 {
            messages.append("The owner's patience is extremely limited. One more poor season may end your tenure.")
        }
        if messages.isEmpty {
            messages.append("Improve your win percentage and avoid off-field controversies to raise satisfaction.")
        }
        return messages
    }

    // MARK: - Data

    private func loadOwner() {
        guard let teamID = career.teamID else { return }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first
        owner = team?.owner
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Alex Reid", role: .gm, capMode: .simple)
    NavigationStack {
        OwnerMeetingView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Owner.self], inMemory: true)
}
