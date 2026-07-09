import SwiftUI

// MARK: - OwnerSeasonReviewSheet (R31)

/// End-of-season owner meeting: the verdict on this year's goals and the
/// consequences that follow (bonus budget, praise, warning). Firing verdicts
/// are handled by `FiredSummaryView` instead.
struct OwnerSeasonReviewSheet: View {

    let review: OwnerPersonaEngine.OwnerSeasonReview
    let ownerName: String
    let teamName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    verdictBadge

                    statsRow

                    // Owner's words
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FROM THE OWNER'S OFFICE")
                            .font(.system(size: 11, weight: .black))
                            .tracking(1.5)
                            .foregroundStyle(Color.accentGold)

                        Text("\u{201C}\(review.summary)\u{201D}")
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
                    .cardBackground()

                    consequencesCard

                    Button {
                        dismiss()
                    } label: {
                        Text("Understood")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentGold)
            Text("Season \(String(review.seasonYear)) Review")
                .font(.title2.weight(.black))
                .foregroundStyle(Color.textPrimary)
            Text(teamName)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Verdict

    private var verdictBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: verdictIcon)
                .font(.system(size: 18, weight: .bold))
            Text(review.verdict.label.uppercased())
                .font(.headline.weight(.black))
                .tracking(1.0)
        }
        .foregroundStyle(verdictColor)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(verdictColor.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(verdictColor.opacity(0.5), lineWidth: 1.5))
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(
                label: "Final Record",
                value: review.finalRecord,
                color: .textPrimary
            )
            statColumn(
                label: "Goals Met",
                value: "\(review.goalsAchieved)/\(max(review.goalsTotal, 1))",
                color: review.goalsAchieved >= max(review.goalsTotal, 1) ? .accentGold : .textPrimary
            )
            statColumn(
                label: "Primary Goal",
                value: review.primaryGoalAchieved ? "Met" : "Missed",
                color: review.primaryGoalAchieved ? .success : .danger
            )
        }
        .padding(.vertical, 16)
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
    }

    // MARK: - Consequences

    private var consequencesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONSEQUENCES")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            ForEach(consequenceLines, id: \.text) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: line.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(line.color)
                        .frame(width: 20)
                        .padding(.top, 1)
                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var consequenceLines: [(icon: String, color: Color, text: String)] {
        var lines: [(String, Color, String)] = []

        if review.budgetBonusPct > 0 {
            let pct = Int((review.budgetBonusPct * 100).rounded())
            lines.append((
                "dollarsign.circle.fill", Color.success,
                "Next season's staff budget envelope grows by \(pct)% as a reward."
            ))
        }
        if review.reputationBonus > 0 {
            lines.append((
                "star.circle.fill", Color.accentGold,
                "Standing your ground against the owner's suggestions — and delivering — earned you +\(review.reputationBonus) reputation."
            ))
        }
        switch review.verdict {
        case .warning:
            lines.append((
                "exclamationmark.triangle.fill", Color.warning,
                "This is a formal warning. Miss the mark again next season and your job is on the line."
            ))
        case .neutral:
            lines.append((
                "minus.circle.fill", Color.textSecondary,
                "No changes — but the owner expects a clear step forward next season."
            ))
        case .bonus, .praise:
            lines.append((
                "checkmark.circle.fill", Color.success,
                "The owner's confidence in your leadership has grown."
            ))
        case .fired:
            break
        }

        if lines.isEmpty {
            lines.append((
                "info.circle", Color.textSecondary,
                "The owner will be watching how you follow up."
            ))
        }
        return lines
    }

    // MARK: - Verdict Style

    private var verdictColor: Color {
        switch review.verdict {
        case .bonus:   return .accentGold
        case .praise:  return .success
        case .neutral: return .textSecondary
        case .warning: return .warning
        case .fired:   return .danger
        }
    }

    private var verdictIcon: String {
        switch review.verdict {
        case .bonus:   return "trophy.fill"
        case .praise:  return "hand.thumbsup.fill"
        case .neutral: return "equal.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fired:   return "xmark.octagon.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    OwnerSeasonReviewSheet(
        review: OwnerPersonaEngine.OwnerSeasonReview(
            seasonYear: 2027,
            verdict: .warning,
            finalRecord: "6-11",
            goalsAchieved: 1,
            goalsTotal: 4,
            primaryGoalTitle: "Make the Playoffs",
            primaryGoalAchieved: false,
            budgetBonusPct: 0,
            reputationBonus: 0,
            summary: "I'm disappointed. You hit 1 of 4 goals with a 6-11 finish. Consider this a formal warning.",
            acknowledged: false
        ),
        ownerName: "Marlene Vance",
        teamName: "Chicago Bears"
    )
}
