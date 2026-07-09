import Foundation

/// R31 — Owner & Economy 2.0.
///
/// Derives a personality archetype from the owner's existing persisted traits
/// (no schema change needed), scores job security, rolls Meddler "whims"
/// during the season, and runs the end-of-season owner review that hands out
/// bonus budgets, warnings — or the pink slip.
///
/// Pure logic + inbox message builders. WeekAdvancer and the Owner UI call in.
enum OwnerPersonaEngine {

    // MARK: - Archetype

    /// A deterministic personality read of the owner. Computed from persisted
    /// traits so the same owner always resolves to the same archetype.
    enum OwnerArchetype: String, Codable, CaseIterable {
        case winNowTycoon
        case patientBuilder
        case pennyPincher
        case meddler

        /// Deterministic derivation — order matters (meddling dominates,
        /// then the wallet, then the win-now itch).
        static func from(_ owner: Owner) -> OwnerArchetype {
            if owner.meddling >= 65 { return .meddler }
            if owner.spendingWillingness <= 35 { return .pennyPincher }
            if owner.prefersWinNow && owner.spendingWillingness >= 55 { return .winNowTycoon }
            return .patientBuilder
        }

        var displayName: String {
            switch self {
            case .winNowTycoon:  return "Win-Now Tycoon"
            case .patientBuilder: return "Patient Builder"
            case .pennyPincher:  return "Penny Pincher"
            case .meddler:       return "Meddler"
            }
        }

        var icon: String {
            switch self {
            case .winNowTycoon:  return "flame.fill"
            case .patientBuilder: return "leaf.fill"
            case .pennyPincher:  return "banknote"
            case .meddler:       return "person.badge.key.fill"
            }
        }

        var blurb: String {
            switch self {
            case .winNowTycoon:
                return "Spends big and expects trophies. The checkbook is open, but so is the trapdoor under your seat."
            case .patientBuilder:
                return "Believes in the process. Gives you time to build — as long as the arrow keeps pointing up."
            case .pennyPincher:
                return "Watches every dollar. Budgets run lean and overspending is a personal insult."
            case .meddler:
                return "Can't resist getting involved. Expect phone calls, suggestions, and opinions on your roster."
            }
        }

        /// Multiplier applied on top of the base staff-budget formula.
        var budgetMultiplier: Double {
            switch self {
            case .winNowTycoon:  return 1.10
            case .pennyPincher:  return 0.85
            case .patientBuilder, .meddler: return 1.0
            }
        }

        /// Extra scaling for negative satisfaction swings — how fast the seat
        /// heats up under this owner.
        var negativeSwingMultiplier: Double {
            switch self {
            case .winNowTycoon:  return 1.2
            case .meddler:       return 1.1
            case .pennyPincher:  return 1.0
            case .patientBuilder: return 0.85
            }
        }

        /// Adjustment applied to numeric win targets in the season goals —
        /// tycoons demand more, patient builders accept less.
        var winTargetAdjustment: Int {
            switch self {
            case .winNowTycoon:  return 1
            case .patientBuilder: return -1
            case .pennyPincher, .meddler: return 0
            }
        }
    }

    // MARK: - Job Security

    enum JobSecurityLevel: String {
        case secure, stable, pressure, hotSeat, critical

        var label: String {
            switch self {
            case .secure:   return "Secure"
            case .stable:   return "Stable"
            case .pressure: return "Pressure"
            case .hotSeat:  return "Hot Seat"
            case .critical: return "Critical"
            }
        }
    }

    /// Scores the coach's job security 0-100 from owner satisfaction,
    /// patience, and archetype. Higher = safer.
    static func jobSecurity(owner: Owner, career: Career) -> (score: Int, level: JobSecurityLevel) {
        var score = owner.satisfaction + (owner.patience - 5) * 3
        switch OwnerArchetype.from(owner) {
        case .winNowTycoon:  score -= 5
        case .patientBuilder: score += 5
        case .pennyPincher, .meddler: break
        }
        score = min(100, max(0, score))

        let level: JobSecurityLevel
        switch score {
        case 75...: level = .secure
        case 55..<75: level = .stable
        case 40..<55: level = .pressure
        case 25..<40: level = .hotSeat
        default: level = .critical
        }
        return (score, level)
    }

    // MARK: - Whims (Meddler owners)

    /// A mid-season "suggestion" from a meddling owner. The user responds in
    /// Owner Relations; defying costs a little satisfaction now, but standing
    /// your ground AND delivering a successful season earns reputation.
    struct OwnerWhim: Codable, Identifiable, Equatable {
        enum Status: String, Codable {
            case pending, complied, defied
        }

        let id: UUID
        let title: String
        let request: String
        let seasonYear: Int
        let week: Int
        var status: Status

        init(
            id: UUID = UUID(),
            title: String,
            request: String,
            seasonYear: Int,
            week: Int,
            status: Status = .pending
        ) {
            self.id = id
            self.title = title
            self.request = request
            self.seasonYear = seasonYear
            self.week = week
            self.status = status
        }
    }

    private static let whimTemplates: [(title: String, request: String)] = [
        (
            "Draft Room Directive",
            "I've been reading the mock drafts. I want us taking a quarterback with our first pick next spring — the fans buy jerseys, not schemes. Tell me you're on board."
        ),
        (
            "Play the Local Kid",
            "The hometown boy on our bench sells more tickets than half our starters. I want to see him on the field on Sundays. Find him snaps."
        ),
        (
            "Make a Splash",
            "This roster needs star power. Go get a big name before the deadline — I'll take the back-page headline over a third-round pick any day."
        ),
        (
            "Play the Rookies",
            "If we're not winning it all, I at least want to see the future. Get our rookies real snaps down the stretch so I know what we drafted."
        ),
        (
            "Bench the Veteran",
            "I'm tired of watching our highest-paid veteran underperform. Sit him down for a week and light a fire. The locker room will survive."
        )
    ]

    /// Rolls a new whim for the user's team this week. Only Meddler owners
    /// whim; max 2 per season, one pending at a time, weeks 2-13 only.
    /// A week-10 backstop guarantees at least one whim most seasons.
    static func rollWhim(owner: Owner, career: Career, week: Int) -> OwnerWhim? {
        guard OwnerArchetype.from(owner) == .meddler else { return nil }
        guard (2...13).contains(week) else { return nil }

        let seasonWhims = career.ownerWhims.filter { $0.seasonYear == career.currentSeason }
        guard seasonWhims.count < 2 else { return nil }
        guard !seasonWhims.contains(where: { $0.status == .pending }) else { return nil }

        let chance = (week >= 10 && seasonWhims.isEmpty) ? 60 : 15
        guard Int.random(in: 1...100) <= chance else { return nil }

        let usedTitles = Set(seasonWhims.map(\.title))
        let available = whimTemplates.filter { !usedTitles.contains($0.title) }
        guard let template = available.randomElement() else { return nil }

        return OwnerWhim(
            title: template.title,
            request: template.request,
            seasonYear: career.currentSeason,
            week: week
        )
    }

    /// Applies the immediate effect of the user's response to a whim and
    /// returns the updated whim. Complying pleases the owner a little;
    /// pushing back stings — more so with an impatient owner.
    static func respond(to whim: OwnerWhim, comply: Bool, owner: Owner) -> OwnerWhim {
        var updated = whim
        if comply {
            updated.status = .complied
            owner.satisfaction = min(100, owner.satisfaction + 3)
        } else {
            updated.status = .defied
            let hit = owner.patience <= 3 ? 5 : 4
            owner.satisfaction = max(0, owner.satisfaction - hit)
        }
        return updated
    }

    /// Inbox message announcing a fresh whim.
    static func whimInboxMessage(whim: OwnerWhim, ownerName: String) -> InboxMessage {
        InboxMessage(
            sender: .owner(name: ownerName),
            subject: "A Suggestion: \(whim.title)",
            body: """
            Coach,

            \(whim.request)

            I'm not telling you how to do your job. I'm just telling you what the person who signs your checks would like to see. Head over to Owner Relations and let me know where you stand.

            \(ownerName)
            """,
            date: "Week \(whim.week), Season \(whim.seasonYear)",
            category: .ownerDirective,
            actionRequired: true,
            actionDestination: .ownerMeeting
        )
    }

    // MARK: - Season Review

    /// The owner's end-of-season evaluation: goals vs results, a verdict, and
    /// the consequences that follow (bonus budget, warning, or firing).
    struct OwnerSeasonReview: Codable, Equatable, Identifiable {
        enum Verdict: String, Codable {
            case bonus, praise, neutral, warning, fired

            var label: String {
                switch self {
                case .bonus:   return "Outstanding"
                case .praise:  return "Satisfied"
                case .neutral: return "Mixed"
                case .warning: return "Warning"
                case .fired:   return "Fired"
                }
            }
        }

        var id: Int { seasonYear }

        let seasonYear: Int
        let verdict: Verdict
        let finalRecord: String
        let goalsAchieved: Int
        let goalsTotal: Int
        let primaryGoalTitle: String
        let primaryGoalAchieved: Bool
        /// Applied on top of next season's fresh budget calculation.
        let budgetBonusPct: Double
        /// Reputation earned by defying whims and still delivering.
        let reputationBonus: Int
        let summary: String
        var acknowledged: Bool
    }

    /// Runs the end-of-season evaluation. Mutates owner satisfaction and
    /// career reputation as a side effect; the caller persists the returned
    /// review and surfaces the inbox message.
    ///
    /// Call once per season while the final records are still intact
    /// (the `.superBowl` phase processing in WeekAdvancer).
    static func evaluateSeason(
        owner: Owner,
        team: Team,
        career: Career,
        goals: [SeasonGoal]
    ) -> OwnerSeasonReview {
        let archetype = OwnerArchetype.from(owner)
        let totalGames = team.wins + team.losses
        let winPct = totalGames > 0 ? Double(team.wins) / Double(totalGames) : 0

        let achieved = goals.filter(\.isAchieved).count
        let total = max(goals.count, 1)
        let primary = goals.first { $0.priority == .primary }
        let primaryAchieved = primary?.isAchieved ?? (winPct >= 0.5)

        let seasonSuccessful = primaryAchieved || winPct >= 0.55 || achieved >= max(2, total - 1)

        // Defied whims pay off in reputation when the season lands.
        let defiedWhims = career.ownerWhims.filter {
            $0.seasonYear == career.currentSeason && $0.status == .defied
        }
        var reputationBonus = 0
        if seasonSuccessful && !defiedWhims.isEmpty {
            reputationBonus = min(4, defiedWhims.count * 2)
            career.reputation = min(99, career.reputation + reputationBonus)
        }

        // --- Verdict ---
        let criticalThreshold = max(10, 20 - owner.patience)
        let dangerThreshold = max(20, 35 - owner.patience)
        // First completed season gets grace — no firing straight out of the gate.
        let isFirstCompletedSeason = (career.totalWins + career.totalLosses) <= 18

        var verdict: OwnerSeasonReview.Verdict
        if owner.satisfaction < criticalThreshold && !isFirstCompletedSeason {
            verdict = .fired
        } else if owner.satisfaction < dangerThreshold
                    && !seasonSuccessful
                    && winPct < 0.45
                    && !isFirstCompletedSeason
                    && Int.random(in: 1...100) <= 50 {
            verdict = .fired
        } else if primaryAchieved && achieved >= total - 1 {
            verdict = .bonus
        } else if primaryAchieved {
            verdict = .praise
        } else if achieved * 2 >= total || winPct >= 0.5 {
            verdict = .neutral
        } else {
            verdict = .warning
        }

        // --- Consequences ---
        var budgetBonusPct = 0.0
        switch verdict {
        case .bonus:
            budgetBonusPct = archetype == .pennyPincher ? 0.06 : 0.10
            owner.satisfaction = min(100, owner.satisfaction + 8)
        case .praise:
            budgetBonusPct = archetype == .pennyPincher ? 0.03 : 0.05
            owner.satisfaction = min(100, owner.satisfaction + 5)
        case .neutral:
            break
        case .warning:
            owner.satisfaction = max(0, owner.satisfaction - 5)
        case .fired:
            break
        }

        let summary = reviewSummary(
            verdict: verdict,
            ownerName: owner.name,
            archetype: archetype,
            record: team.record,
            achieved: achieved,
            total: total,
            primaryTitle: primary?.title,
            reputationBonus: reputationBonus
        )

        return OwnerSeasonReview(
            seasonYear: career.currentSeason,
            verdict: verdict,
            finalRecord: team.record,
            goalsAchieved: achieved,
            goalsTotal: goals.count,
            primaryGoalTitle: primary?.title ?? "Winning record",
            primaryGoalAchieved: primaryAchieved,
            budgetBonusPct: budgetBonusPct,
            reputationBonus: reputationBonus,
            summary: summary,
            acknowledged: false
        )
    }

    private static func reviewSummary(
        verdict: OwnerSeasonReview.Verdict,
        ownerName: String,
        archetype: OwnerArchetype,
        record: String,
        achieved: Int,
        total: Int,
        primaryTitle: String?,
        reputationBonus: Int
    ) -> String {
        let goalLine = "You hit \(achieved) of \(total) goals with a \(record) finish."
        let defianceLine = reputationBonus > 0
            ? " I didn't love being told no this season — but the results speak for themselves. Respect earned."
            : ""

        switch verdict {
        case .bonus:
            return "Outstanding work. \(goalLine) Consider next season's budget my thank-you — I'm opening the wallet.\(defianceLine)"
        case .praise:
            return "That's what I wanted to see. \(goalLine) You delivered on the big one, and there will be a little extra in the budget for it.\(defianceLine)"
        case .neutral:
            return "A mixed year. \(goalLine) I can live with it — once. Let's aim higher next season.\(defianceLine)"
        case .warning:
            let primaryText = primaryTitle.map { " \"\($0)\" was the assignment, and it didn't happen." } ?? ""
            return "I'm disappointed. \(goalLine)\(primaryText) Consider this a formal warning: I need to see real progress next season, or we'll be having a very different conversation."
        case .fired:
            return "\(goalLine) I've made a decision — this organization needs a new direction, and it won't include you. Effective immediately, you're relieved of your duties. I wish you the best."
        }
    }

    /// Inbox message carrying the end-of-season review.
    static func reviewInboxMessage(review: OwnerSeasonReview, ownerName: String) -> InboxMessage {
        let subject: String
        switch review.verdict {
        case .bonus:   subject = "Season Review: Exceptional — Budget Increased"
        case .praise:  subject = "Season Review: Well Done"
        case .neutral: subject = "Season Review: Room to Grow"
        case .warning: subject = "Season Review: Official Warning"
        case .fired:   subject = "Season Review: A Change in Direction"
        }
        return InboxMessage(
            sender: .owner(name: ownerName),
            subject: subject,
            body: """
            Coach,

            \(review.summary)

            \(ownerName)
            """,
            date: "End of Season \(review.seasonYear)",
            category: .ownerDirective,
            actionRequired: review.verdict == .warning,
            actionDestination: .ownerMeeting
        )
    }

    // MARK: - Season Kickoff Meeting

    /// Inbox message for the season-opening owner meeting: this year's goals,
    /// the reasoning behind them, and the staff budget envelope.
    static func seasonKickoffMessage(
        owner: Owner,
        career: Career,
        goals: [SeasonGoal]
    ) -> InboxMessage {
        let archetype = OwnerArchetype.from(owner)

        let goalLines = goals.map { goal -> String in
            let tag: String
            switch goal.priority {
            case .primary:   tag = "PRIMARY"
            case .secondary: tag = "SECONDARY"
            case .bonus:     tag = "BONUS"
            }
            return "\u{2022} [\(tag)] \(goal.title)"
        }.joined(separator: "\n")

        let rationale: String
        switch archetype {
        case .winNowTycoon:
            rationale = "I didn't buy this team to finish second. The budget reflects my ambition — so do the goals. Deliver."
        case .patientBuilder:
            rationale = "I believe in what we're building. These goals are about steady progress — hit them and you'll have my patience and my support."
        case .pennyPincher:
            rationale = "The budget is what it is — I expect smart football, not expensive football. These goals are achievable without burning money."
        case .meddler:
            rationale = "I'll be watching closely this season — and don't be surprised if I share a thought or two along the way. These are the goals I care about."
        }

        let totalEnvelope = owner.coachingBudget + owner.scoutingBudget + owner.medicalBudget
        let fmt: (Int) -> String = { String(format: "$%.1fM", Double($0) / 1_000.0) }

        return InboxMessage(
            sender: .owner(name: owner.name),
            subject: "Season \(career.currentSeason): My Expectations",
            body: """
            Coach,

            Before we kick off, let's be clear about what I expect this season:

            \(goalLines)

            \(rationale)

            Your staff envelope for the year is \(fmt(totalEnvelope)) — \(fmt(owner.coachingBudget)) coaching, \(fmt(owner.scoutingBudget)) scouting, \(fmt(owner.medicalBudget)) medical. If you want it split differently, come see me in Owner Relations.

            \(owner.name)
            """,
            date: "Week 1, Season \(career.currentSeason)",
            category: .ownerDirective,
            actionRequired: true,
            actionDestination: .ownerMeeting
        )
    }
}
