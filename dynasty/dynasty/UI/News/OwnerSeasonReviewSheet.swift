import SwiftUI

// MARK: - OwnerSeasonReviewSheet (R31 / #39)

/// End-of-season owner meeting, surfaced right after the Super Bowl and BEFORE
/// the coaching-changes (Black Monday) phase. Covers the full arc the owner
/// walks the coach through:
///   1. Season recap from the owner's chair (record + playoff result).
///   2. The goals scorecard — every goal, met or missed.
///   3. How the season played around the league (power ranking, media read,
///      job-security temperature).
///   4. The verdict and its consequences (bonus budget, warning, praise).
///   5. If the coach keeps the job: next season's mandate — the goals the
///      owner will be watching for — and the coach's acknowledgement.
///
/// Firing verdicts are handled by `FiredSummaryView` instead (this sheet only
/// ever shows for non-firing verdicts).
struct OwnerSeasonReviewSheet: View {

    let review: OwnerPersonaEngine.OwnerSeasonReview
    let ownerName: String
    let teamName: String
    /// Enriched, presentation-only context built at the call site from the
    /// live career/team state (see `Context.build`). Defaults to `.empty` so
    /// the preview and any legacy call site still compile.
    var context: Context = .empty

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    verdictBadge

                    if let playoff = context.playoffResult {
                        playoffPill(playoff)
                    }

                    statsRow

                    if !context.goals.isEmpty {
                        goalsScorecard
                    }

                    if let media = context.media {
                        aroundTheLeagueCard(media)
                    }

                    ownerWordsCard

                    consequencesCard

                    if !context.nextGoals.isEmpty {
                        nextSeasonCard
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text(context.nextGoals.isEmpty ? "Understood" : "Accept the Challenge")
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

    private func playoffPill(_ text: String) -> some View {
        let color = playoffColor(text)
        return HStack(spacing: 8) {
            Image(systemName: playoffIcon(text))
                .font(.system(size: 12, weight: .bold))
            Text(text.uppercased())
                .font(.caption.weight(.black))
                .tracking(1.0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: Capsule())
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

    // MARK: - Goals Scorecard

    private var goalsScorecard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOALS SCORECARD")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            ForEach(context.goals) { goal in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: goal.achieved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(goal.achieved ? Color.success : Color.danger)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(goal.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            priorityTag(goal.priority)
                        }
                        Text(goal.detail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Around the League

    private func aroundTheLeagueCard(_ media: Context.Media) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AROUND THE LEAGUE")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            HStack(spacing: 0) {
                if let rank = media.powerRank {
                    statColumn(
                        label: "Power Ranking",
                        value: "#\(rank) / \(media.leagueSize)",
                        color: rank <= 8 ? .accentGold : .textPrimary
                    )
                }
                statColumn(
                    label: "Job Security",
                    value: media.jobSecurityLabel,
                    color: jobSecurityColor(media.jobSecurityScore)
                )
            }

            Text(media.headline)
                .font(.subheadline)
                .italic()
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Owner's Words

    private var ownerWordsCard: some View {
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

    // MARK: - Next Season's Mandate

    private var nextSeasonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT SEASON'S MANDATE")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            Text("Here's what I'll be watching for next year:")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            ForEach(context.nextGoals) { goal in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentGold)
                        .padding(.top, 1)
                    HStack(spacing: 8) {
                        Text(goal.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        priorityTag(goal.priority)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Shared Bits

    private func priorityTag(_ priority: GoalPriority) -> some View {
        let (text, color): (String, Color)
        switch priority {
        case .primary:   (text, color) = ("PRIMARY", .accentGold)
        case .secondary: (text, color) = ("SECONDARY", .textSecondary)
        case .bonus:     (text, color) = ("BONUS", .success)
        }
        return Text(text)
            .font(.system(size: 9, weight: .black))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
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

    private func jobSecurityColor(_ score: Int) -> Color {
        switch score {
        case 75...:   return .success
        case 55..<75: return .textPrimary
        case 40..<55: return .warning
        default:      return .danger
        }
    }

    private func playoffColor(_ text: String) -> Color {
        if text.contains("Champions") { return .accentGold }
        if text.contains("Reached")   { return .success }
        return .textSecondary
    }

    private func playoffIcon(_ text: String) -> String {
        if text.contains("Champions") { return "trophy.fill" }
        if text.contains("Reached")   { return "checkmark.seal.fill" }
        return "xmark.seal.fill"
    }
}

// MARK: - Enriched Context

extension OwnerSeasonReviewSheet {

    /// Presentation-only enrichment for the season-review sheet, assembled from
    /// live career/team state at the moment the sheet is shown (before
    /// `startNewSeason` rolls the roster forward).
    struct Context {
        struct GoalOutcome: Identifiable {
            let id: UUID
            let title: String
            let priority: GoalPriority
            let achieved: Bool
            let detail: String
        }

        struct Media {
            let powerRank: Int?
            let leagueSize: Int
            let jobSecurityLabel: String
            let jobSecurityScore: Int
            let headline: String
        }

        struct NextGoal: Identifiable {
            let id: UUID
            let title: String
            let priority: GoalPriority
        }

        var goals: [GoalOutcome]
        var playoffResult: String?
        var media: Media?
        var nextGoals: [NextGoal]

        static let empty = Context(goals: [], playoffResult: nil, media: nil, nextGoals: [])

        /// Builds the full review context. `team` may be nil for the edge case
        /// where the user's team can't be resolved — the sheet degrades to the
        /// core verdict cards.
        static func build(
            review: OwnerPersonaEngine.OwnerSeasonReview,
            career: Career,
            team: Team?
        ) -> Context {
            // 1. Goals scorecard — the evaluated goals from THIS season are still
            //    on the career (startNewSeason hasn't regenerated them yet).
            let goals: [GoalOutcome] = career.ownerSeasonGoals.map { goal in
                GoalOutcome(
                    id: goal.id,
                    title: goal.title,
                    priority: goal.priority,
                    achieved: goal.isAchieved,
                    detail: goalDetail(goal)
                )
            }

            // 2. Playoff result from the season summary just recorded.
            let summary = career.seasonSummaries.first { $0.season == review.seasonYear }
            let playoffResult: String?
            if let summary {
                if summary.userWonChampionship {
                    playoffResult = "Super Bowl Champions"
                } else if summary.userMadePlayoffs {
                    playoffResult = "Reached the Playoffs"
                } else {
                    playoffResult = "Missed the Playoffs"
                }
            } else {
                playoffResult = nil
            }

            // 3. Around the league — power ranking + job-security read.
            var media: Media?
            if let team, let owner = team.owner {
                let rankings = career.leagueNarrative?.rankings ?? []
                let entry = rankings.first { $0.teamID == team.id }
                let security = OwnerPersonaEngine.jobSecurity(owner: owner, career: career)
                media = Media(
                    powerRank: entry?.rank,
                    leagueSize: rankings.isEmpty ? 32 : rankings.count,
                    jobSecurityLabel: security.level.label,
                    jobSecurityScore: security.score,
                    headline: mediaHeadline(rank: entry?.rank, verdict: review.verdict)
                )
            }

            // 4. Next season's mandate — only when the coach keeps the job.
            var nextGoals: [NextGoal] = []
            if review.verdict != .fired, let team, let owner = team.owner {
                nextGoals = OwnerGoalsEngine
                    .generateSeasonGoals(team: team, owner: owner, career: career)
                    .map { NextGoal(id: $0.id, title: $0.title, priority: $0.priority) }
            }

            return Context(
                goals: goals,
                playoffResult: playoffResult,
                media: media,
                nextGoals: nextGoals
            )
        }

        private static func goalDetail(_ goal: SeasonGoal) -> String {
            switch goal.type {
            case .wins:
                if let target = goal.target { return "\(goal.progress) / \(target) wins" }
                return "\(goal.progress) wins"
            case .playoffs:
                return goal.isAchieved ? "Clinched a berth" : "Fell short"
            case .divisionTitle:
                return goal.isAchieved ? "Won the division" : "No division crown"
            case .conference:
                return goal.isAchieved ? "Reached the Super Bowl" : "Fell short"
            case .superBowl:
                return goal.isAchieved ? "Lombardi secured" : "No title"
            case .developRookies:
                if let target = goal.target { return "\(goal.progress) / \(target) rookies developed" }
                return "\(goal.progress) rookies developed"
            case .reduceCapUsage:
                return goal.isAchieved ? "Cap-healthy" : "Over budget"
            case .winStreak:
                if let target = goal.target { return "Best surplus \(goal.progress) / \(target)" }
                return "\(goal.progress)"
            case .fanSatisfaction, .improveDraft, .tradeAcquisition:
                return goal.isAchieved ? "Met" : "Missed"
            }
        }

        private static func mediaHeadline(
            rank: Int?,
            verdict: OwnerPersonaEngine.OwnerSeasonReview.Verdict
        ) -> String {
            if let rank {
                switch rank {
                case ...4:
                    return "The national media has your team pegged as a genuine contender — the beat writers are all in."
                case ...12:
                    return "Around the league you're seen as a solid, well-run operation trending in the right direction."
                case ...22:
                    return "The talking heads are lukewarm — a middle-of-the-pack year in the league's eyes."
                default:
                    return "Pundits and fans spent the season questioning the direction of the franchise."
                }
            }
            switch verdict {
            case .bonus, .praise:
                return "The press liked what they saw from your team this year."
            case .neutral:
                return "The national narrative on your team was mixed at best."
            case .warning, .fired:
                return "The media spent the year questioning the direction of the franchise."
            }
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
        teamName: "Chicago Bears",
        context: OwnerSeasonReviewSheet.Context(
            goals: [
                .init(id: UUID(), title: "Make the Playoffs", priority: .primary, achieved: false, detail: "Fell short"),
                .init(id: UUID(), title: "Win 9+ Games", priority: .secondary, achieved: false, detail: "6 / 9 wins"),
                .init(id: UUID(), title: "Win the Division", priority: .bonus, achieved: false, detail: "No division crown")
            ],
            playoffResult: "Missed the Playoffs",
            media: .init(powerRank: 24, leagueSize: 32, jobSecurityLabel: "Hot Seat", jobSecurityScore: 34, headline: "Pundits and fans spent the season questioning the direction of the franchise."),
            nextGoals: [
                .init(id: UUID(), title: "Make the Playoffs", priority: .primary),
                .init(id: UUID(), title: "Win 9+ Games", priority: .secondary)
            ]
        )
    )
}
