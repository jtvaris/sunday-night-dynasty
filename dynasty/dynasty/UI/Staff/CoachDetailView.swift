import SwiftUI
import SwiftData

/// The coach card, on the shared study-density layout (UI_REDESIGN_VISION §4
/// wave 4).
///
/// This screen was the app's worst stock form: nine `Section("String")` heads,
/// eighteen `LabeledContent` rows and four full-width centred `Button`s stacked
/// in a "Management" section at the bottom of an `.insetGrouped` `List` — i.e.
/// the default iOS Settings look, on the screen where a GM decides whether to
/// fire a man. It shared no component with `PlayerDetailView` and no component
/// with `ProspectDetailView`, and the three of them are the same screen.
///
/// It now mounts the same `DSDetailPage` / `DSDetailHero` / `DSDetailCard` /
/// `DSActionBar` set as the other two. What changed beyond the chrome:
///
///   * **The four management buttons moved onto the action bar** (P5). Fire is
///     the destructive slot behind its rule, and the bar's explainer names the
///     salary and the severance the commit will cost before it is pressed.
///   * **Development and Projected Impact gained explainers** — which coach
///     this is, what he is working on, and what the number under it actually
///     does to the roster (§4 wave 4).
///   * The promote flow's `DispatchQueue.main.asyncAfter(0.3)` hand-off from
///     sheet to alert is gone; the confirmation is raised from the sheet's own
///     `onDismiss`, which is what the delay was approximating.
struct CoachDetailView: View {

    let coach: Coach
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCoachesUnscoped: [Coach]
    @Query private var allCareers: [Career]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here. Without it the
    // screen mixes two careers' populations into one list.
    private var allCoaches: [Coach] { allCoachesUnscoped.filter { $0.careerID == coach.careerID } }

    @State private var showFireConfirmation = false
    @State private var showExtendAlert = false
    @State private var showDemoteAlert = false
    @State private var selectedPromotionRole: CoachRole?
    @State private var showPromoteConfirmation = false

    /// **The one sheet slot on this screen** — an enum, not a `Bool`.
    ///
    /// Repeat bug class: several screens in this app shipped two or more
    /// `.sheet(isPresented:)` modifiers on the same node, SwiftUI honoured only
    /// the last one written, and the others dismissed silently. There is one
    /// sheet here today; it is `item:`-driven anyway so a second can never be
    /// added as a second modifier.
    private enum CoachSheet: String, Identifiable {
        case promoteRolePicker
        var id: String { rawValue }
    }

    @State private var activeSheet: CoachSheet?

    /// Available promotion targets, filtered by career role constraints.
    private var availablePromotionTargets: [CoachRole] {
        var targets = coach.role.promotionTargets
        // If promoting to HC, only allow if career role is .gm (not .gmAndHeadCoach)
        if let career = career, career.role == .gmAndHeadCoach {
            targets = targets.filter { $0 != .headCoach }
        }
        return targets
    }

    /// Coach overall rating (average of 12 attributes).
    private var coachOverallRating: Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// The head coach on the same team (nil if this coach IS the HC or no team).
    private var headCoach: Coach? {
        guard coach.role != .headCoach,
              let teamID = coach.teamID else { return nil }
        return allCoaches.first { $0.role == .headCoach && $0.teamID == teamID }
    }

    /// The save this coach belongs to — the row names it, so `allCareers.first`
    /// (which could pick the wrong save once two exist) is no longer consulted.
    private var career: Career? {
        allCareers.first { $0.id == coach.careerID }
    }

    /// Seasons he has been on this staff, minimum 1. Both the fuzzy potential
    /// read and the tenure row are denominated in it, so it is computed once.
    private var seasonsOnStaff: Int {
        guard let currentSeason = career?.currentSeason, coach.hireSeasonYear > 0 else { return 1 }
        return max(1, currentSeason - coach.hireSeasonYear + 1)
    }

    var body: some View {
        ZStack {
            // Subtle plate behind the page — it is what stops a wall of cards
            // reading as a spreadsheet. The locker-room photograph that used to
            // do this carried Nike/adidas/Puma logos (#167), so the plate is now
            // token-only: the same 8%-strength lift, made of palette steps.
            Color.backgroundPrimary.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.backgroundSecondary,
                    Color.backgroundPrimary,
                    Color.backgroundPlate
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // `surface: .clear` — the page must not paint over the plate above.
            DSDetailPage(surface: .clear) {
                coachHero
            } cards: {
                DSDetailColumns {
                    // LEAD — the job, the money, the deal.
                    overviewCard
                    projectedImpactCard
                } middle: {
                    // MIDDLE — what he is becoming.
                    developmentCard
                    personalityCard
                    schemeCard
                } trail: {
                    // TRAIL — what he is made of, and how he sits beside the HC.
                    attributesCard
                    schemeFitCard
                }
            }
        }
        .safeAreaInset(edge: .bottom) { coachActionBar }
        .navigationTitle(coach.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
        .alert("Fire \(coach.fullName)?", isPresented: $showFireConfirmation) {
            Button("Fire Coach", role: .destructive) {
                fireCoach()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(fireConfirmationMessage)
        }
        // Fix #53: Extend contract alert
        .alert("Extend \(coach.fullName)'s Contract?", isPresented: $showExtendAlert) {
            Button("Extend 2 Years") {
                extendContract()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will offer \(coach.firstName) a 2-year contract extension at their current salary of \(coachSalaryText(coach.salary)). Contract will go from \(coach.contractYearsRemaining) to \(coach.contractYearsRemaining + 2) years.")
        }
        // ONE sheet modifier, `item:`-driven. The role picker hands off to the
        // confirmation alert from `onDismiss` — the previous version slept
        // 300 ms on the main queue and hoped the sheet had finished animating,
        // which is exactly the timing hack §4 wave 3 retires elsewhere.
        .sheet(item: $activeSheet, onDismiss: {
            if selectedPromotionRole != nil {
                showPromoteConfirmation = true
            }
        }) { sheet in
            switch sheet {
            case .promoteRolePicker:
                promoteRolePickerSheet
            }
        }
        // Promote: confirmation alert after role selection
        .alert("Promote \(coach.fullName)?", isPresented: $showPromoteConfirmation) {
            if let targetRole = selectedPromotionRole {
                Button("Promote to \(targetRole.displayName)") {
                    promoteCoach(to: targetRole)
                }
            }
            Button("Cancel", role: .cancel) {
                selectedPromotionRole = nil
            }
        } message: {
            if let targetRole = selectedPromotionRole {
                let newSalary = Int(Double(coach.salary) * 1.2)
                Text("This will promote \(coach.firstName) from \(coach.role.displayName) to \(targetRole.displayName). Salary will increase to \(coachSalaryText(newSalary)).")
            }
        }
        // Demote: confirmation alert
        .alert("Demote \(coach.fullName)?", isPresented: $showDemoteAlert) {
            Button("Demote", role: .destructive) {
                demoteCoach()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Demoting will reduce morale and reputation by 10. Continue?")
        }
    }

    // MARK: - Hero

    /// Portrait, role, and the screen's one hero numeral — his overall.
    ///
    /// The old avatar section was a centred portrait and a gold role caption on
    /// a `Color.clear` list row: no rating anywhere above the fold, on a card
    /// whose entire purpose is judging a man. His overall was computed
    /// (`coachOverallRating`) and used only to derive a trajectory string.
    private var coachHero: some View {
        DSDetailHero {
            HStack(spacing: DSSpacing.md) {
                PersonFaceView(coach: coach, size: .large, ringColor: .accentGold)

                VStack(spacing: DSSpacing.xxs) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.forRating(coachOverallRating), lineWidth: 3)
                            .frame(width: 76, height: 76)
                        VStack(spacing: 0) {
                            Text("\(coachOverallRating)")
                                .font(.system(size: DSType.Size.title1, weight: .heavy).monospacedDigit())
                                .foregroundStyle(Color.forRating(coachOverallRating))
                            Text("OVR")
                                .font(.system(size: DSType.Size.micro, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Color.textTertiaryReadable)
                        }
                    }
                    Text("CEILING \(coach.attributeCeiling)")
                        .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                        .tracking(0.5)
                        .foregroundStyle(Color.textTertiaryReadable)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Overall \(coachOverallRating), ceiling \(coach.attributeCeiling)")

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(coach.role.displayName.uppercased())
                        .font(.system(size: DSType.Size.caption, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Color.accentGold)

                    Text(coach.fullName)
                        .font(.system(size: DSType.Size.title2, weight: .bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: DSSpacing.sm) {
                        Label("Age \(coach.age)", systemImage: "calendar")
                        Label(experienceLabel, systemImage: "clock.arrow.circlepath")
                        Label(
                            seasonsOnStaff == 1 ? "1st season here" : "\(seasonsOnStaff) seasons here",
                            systemImage: "building.2"
                        )
                    }
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)

                    if coach.isInAdjustmentPeriod {
                        Label("Adjusting to the role — bonuses reduced ~25% this season", systemImage: "hourglass")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.warning)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Overview

    private var overviewCard: some View {
        DSDetailCard(
            "Overview",
            icon: "person.text.rectangle",
            explainer: "The job he holds, what it costs, and how long you have him for."
        ) {
            DSDetailRow("Role", coach.role.displayName)
            DSDetailRow("Age", "\(coach.age)")
            DSDetailRow("Experience", experienceLabel, tint: .textSecondary, weight: .regular)
            DSDetailRow("Salary", coachSalaryText(coach.salary), tint: .accentGold)
            DSDetailRow(
                "Contract",
                coach.contractYearsRemaining <= 1
                    ? "\(max(1, coach.contractYearsRemaining)) yr remaining"
                    : "\(coach.contractYearsRemaining) yrs remaining",
                tint: coach.contractYearsRemaining <= 1 ? .warning : .textPrimary
            )
            if career?.currentSeason != nil, coach.hireSeasonYear > 0 {
                DSDetailRow(
                    "Tenure",
                    seasonsOnStaff == 1 ? "1st season" : "\(seasonsOnStaff) seasons",
                    tint: .textSecondary,
                    weight: .regular
                )
            }
            if !coach.background.isEmpty {
                Divider().overlay(Color.surfaceBorder)
                Text(coach.background)
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Development

    /// What this man is becoming, and — the part wave 4 asks for — **what the
    /// two headline reads on it actually are**.
    ///
    /// The old section printed "Developer Reputation · Elite · 82",
    /// "Potential · High Ceiling" and "Trajectory · Improving" as three bare
    /// `LabeledContent` rows with no statement anywhere of what the numbers
    /// were measuring or how they were arrived at.
    private var developmentCard: some View {
        DSDetailCard(
            "Development",
            icon: "chart.line.uptrend.xyaxis",
            explainer: "Two different reads. **Developer reputation** is what the young players on his watch actually gained. **Potential** is your own staff's guess at his ceiling, and it sharpens the longer he is in the building — this is season \(seasonsOnStaff)."
        ) {
            developerReputationBlock

            // Fuzzy potential label — accuracy improves with tenure
            let label = coach.potentialLabel(seasonsOnTeam: seasonsOnStaff)
            DSDetailRow(label: "Potential") {
                Text(label)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(potentialLabelColor(label))
            }

            DSDetailRow(label: "Trajectory") {
                let trajectory = coachTrajectory
                Text(trajectory.label)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(trajectory.color)
            }
            DSDetailNote(text: coachTrajectory.reason, icon: "arrow.up.right")

            DSDetailRow(label: "Attribute Ceiling") {
                Text("\(coach.attributeCeiling)")
                    .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.forRating(coach.attributeCeiling))
            }
            DSDetailNote(
                text: "His attributes can still grow to \(coach.attributeCeiling); he averages \(coachOverallRating) today.",
                icon: "arrow.up.to.line"
            )

            // Mentorship origin
            if coach.mentorCoachID != nil, let origin = coach.mentorshipOrigin {
                Divider().overlay(Color.surfaceBorder)
                DSDetailNote(text: origin, icon: "person.2.badge.gearshape")
            }
        }
    }

    /// TODO §5.7 — the chip that puts a coach's development record on his card.
    ///
    /// The detail line is deliberately explicit about which of the two states
    /// the number is in: "Projected" while the score is still an attribute
    /// read, the measured tally once completed seasons exist. A player looking
    /// at a hire needs to know whether he is reading a promise or a result.
    private var developerReputationBlock: some View {
        let record = CoachDevelopmentEngine.developerRecord(
            coach: coach,
            currentSeason: career?.currentSeason
        )
        return VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            DSDetailRow(label: "Developer Reputation") {
                HStack(spacing: DSSpacing.xxs) {
                    Text(record.tier)
                        .font(.system(size: DSType.Size.body, weight: .semibold))
                        .foregroundStyle(developerScoreColor(record.score))
                    Text("\(record.score)")
                        .font(.system(size: DSType.Size.footnote, weight: .heavy).monospacedDigit())
                        .foregroundStyle(developerScoreColor(record.score))
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(developerScoreColor(record.score).opacity(0.15))
                        )
                }
            }
            DSDetailNote(text: record.detail, icon: "text.magnifyingglass")
        }
    }

    /// Unified onto `Color.forRating`. The bespoke six-band ladder reached
    /// outside the palette entirely — `.green`, `.orange` and `.red` are stock
    /// SwiftUI system colours, not the app's `success` / `warning` / `danger`,
    /// so a coach card was the one place in the app painting iOS-blue-era hues.
    private func developerScoreColor(_ score: Int) -> Color {
        Color.forRating(score)
    }

    /// Color for the fuzzy potential label. Off the app palette, not the stock
    /// SwiftUI hues the previous version used (`.green` / `.orange` / `.red`).
    private func potentialLabelColor(_ label: String) -> Color {
        switch label {
        case "Elite Ceiling":   return Color.accentGold
        case "High Ceiling":    return Color.success
        case "Solid Ceiling":   return Color.accentBlue
        case "Limited Upside":  return Color.warning
        case "Low Ceiling":     return Color.danger
        default:                return Color.textSecondary
        }
    }

    /// Trajectory based on age and rating vs ceiling — and, new in wave 4, the
    /// one sentence saying why, because "Plateaued" on its own is a verdict
    /// with no evidence attached.
    private var coachTrajectory: (label: String, color: Color, reason: String) {
        if coach.age >= 55 {
            return (
                "Declining",
                Color.danger,
                "Past 55 — the attributes drift down from here regardless of the ceiling."
            )
        } else if coach.age < 50 && coachOverallRating < coach.attributeCeiling - 5 {
            return (
                "Improving",
                Color.success,
                "Under 50 and \(coach.attributeCeiling - coachOverallRating) points short of his ceiling — he still has room to grow into."
            )
        } else {
            return (
                "Plateaued",
                Color.warning,
                "He is at or near his ceiling. What you see is what this staff gets."
            )
        }
    }

    // MARK: - Promote Role Picker Sheet

    private var promoteRolePickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DSSpacing.xs) {
                        ForEach(availablePromotionTargets, id: \.self) { targetRole in
                            Button {
                                selectedPromotionRole = targetRole
                                // The confirmation is raised in `onDismiss`.
                                activeSheet = nil
                            } label: {
                                promotionTargetRow(targetRole)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DSSpacing.md)
                }
            }
            .navigationTitle("Promote \(coach.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
            }
        }
    }

    private func promotionTargetRow(_ targetRole: CoachRole) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(targetRole.abbreviation)
                .font(.system(size: DSType.Size.footnote, weight: .black))
                .foregroundStyle(Color.backgroundPlate)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

            VStack(alignment: .leading, spacing: 2) {
                Text(targetRole.displayName)
                    .font(.system(size: DSType.Size.body, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                let newSalary = Int(Double(coach.salary) * 1.2)
                Text("Salary: \(coachSalaryText(coach.salary)) → \(coachSalaryText(newSalary))")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: DSType.Size.title3))
                .foregroundStyle(Color.accentBlue)
        }
        .padding(DSSpacing.sm)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Promote to \(targetRole.displayName)")
    }

    // MARK: - Attributes

    private var attributesCard: some View {
        DSDetailCard(
            "Coaching Attributes",
            icon: "slider.horizontal.3",
            explainer: "All twelve on the same 0–99 ladder every rating in the game uses."
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: DSSpacing.xs) {
                attributeCell(name: "Play Calling",        value: coach.playCalling)
                attributeCell(name: "Player Development",  value: coach.playerDevelopment)
                attributeCell(name: "Reputation",          value: coach.reputation)
                attributeCell(name: "Adaptability",        value: coach.adaptability)
                attributeCell(name: "Game Planning",       value: coach.gamePlanning)
                attributeCell(name: "Scouting Ability",    value: coach.scoutingAbility)
                attributeCell(name: "Recruiting",          value: coach.recruiting)
                attributeCell(name: "Motivation",          value: coach.motivation)
                attributeCell(name: "Discipline",          value: coach.discipline)
                attributeCell(name: "Media Handling",      value: coach.mediaHandling)
                attributeCell(name: "Contract Negotiation", value: coach.contractNegotiation)
                attributeCell(name: "Morale Influence",    value: coach.moraleInfluence)
            }
        }
    }

    /// A single attribute cell: the same colour-bar + value + tier grammar the
    /// player card's attribute grid uses, so the two screens read as one.
    private func attributeCell(name: String, value: Int) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                .fill(attributeColor(value))
                .frame(width: 3, height: 16)
            Text(name)
                .font(.system(size: DSType.Size.footnote))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            Spacer(minLength: 2)
            Text("\(value)")
                .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                .foregroundStyle(attributeColor(value))
            Text(attributeTierLabel(value))
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(attributeColor(value))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(value), \(attributeTierLabel(value))")
    }

    // MARK: - Personality

    private var personalityCard: some View {
        DSDetailCard(
            "Personality",
            icon: "person.crop.circle",
            explainer: "How he handles a locker room, a press conference and a losing streak."
        ) {
            DSDetailRow("Archetype", coach.personality.displayName)
        }
    }

    // MARK: - Scheme

    @ViewBuilder
    private var schemeCard: some View {
        let hasScheme = coach.offensiveScheme != nil || coach.defensiveScheme != nil
        if hasScheme {
            DSDetailCard(
                "Scheme",
                icon: "square.grid.3x3",
                explainer: "What he installs. Players on his side of the ball gain familiarity with it faster than with anything else."
            ) {
                if let offScheme = coach.offensiveScheme {
                    DSDetailRow("Offensive Scheme", offScheme.displayName, tint: .accentBlue)
                }
                if let defScheme = coach.defensiveScheme {
                    DSDetailRow("Defensive Scheme", defScheme.displayName, tint: .danger)
                }
            }
        }
    }

    // MARK: - Scheme Fit / HC Compatibility

    @ViewBuilder
    private var schemeFitCard: some View {
        // Only meaningful for non-HC coaches, who answer to somebody.
        if coach.role != .headCoach {
            DSDetailCard(
                "Fit With The Head Coach",
                icon: "person.2",
                explainer: "Attribute-by-attribute against your HC: where he covers a gap, where he duplicates a strength you already have, and where the two of them are weak together."
            ) {
                if let hc = headCoach {
                    let analysis = analyzeCompatibility(with: hc)

                    DSDetailRow(label: "HC Compatibility") {
                        Text(analysis.overallLabel)
                            .font(.system(size: DSType.Size.body, weight: .semibold))
                            .foregroundStyle(analysis.overallColor)
                    }

                    if let style = career?.coachingStyle {
                        DSDetailRow("HC Style", style.displayName, tint: .textSecondary, weight: .regular)
                    }

                    if !analysis.complements.isEmpty {
                        compatibilityBlock(
                            title: "Covers a gap",
                            tint: .success,
                            items: analysis.complements,
                            note: "He is strong here and the head coach is not."
                        )
                    }

                    if !analysis.redundancies.isEmpty {
                        compatibilityBlock(
                            title: "Duplicates the HC",
                            tint: .accentGold,
                            items: analysis.redundancies,
                            note: "Both are strong here — you are paying twice for the same edge."
                        )
                    }

                    if !analysis.weaknesses.isEmpty {
                        compatibilityBlock(
                            title: "Weak together",
                            tint: .warning,
                            items: analysis.weaknesses,
                            note: "Neither of them covers this. Nobody on the sideline does."
                        )
                    }
                } else {
                    Text("No head coach on staff to compare against.")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textTertiaryReadable)
                }
            }
        }
    }

    private func compatibilityBlock(title: String, tint: Color, items: [String], note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(items.joined(separator: " \u{00B7} "))
                .font(.system(size: DSType.Size.footnote))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(note)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiaryReadable)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The commit surface (§2.5, P5)

    /// The four management actions, off the bottom of a scrolling form and onto
    /// the bar, in `DSActionBar`'s fixed order.
    ///
    /// Fire sits in the destructive slot behind its own rule — never adjacent
    /// to the primary — and the explainer prices the decision before it is
    /// taken rather than only inside the confirmation alert.
    private var coachActionBar: some View {
        DSActionBar(
            explainer: .init(
                title: "On staff",
                message: managementExplainer
            ),
            destructive: .init(
                title: "Fire Coach",
                caption: estimatedSeveranceK > 0 ? severanceDisplay : "no severance owed",
                handler: { showFireConfirmation = true }
            ),
            ghost: coach.role.demotionTargets.isEmpty
                ? nil
                : .init(title: "Demote", handler: { showDemoteAlert = true }),
            secondary: availablePromotionTargets.isEmpty ? nil : promoteAction,
            primary: .init(
                title: "Extend Contract",
                caption: "+2 years at \(coachSalaryText(coach.salary))",
                handler: { showExtendAlert = true }
            )
        )
    }

    /// The bar's one-liner. Quotes the same salary and the same remaining years
    /// the Overview card two columns away prints, so the two cannot disagree
    /// (§2.13, arithmetic gate).
    private var managementExplainer: String {
        let years = coach.contractYearsRemaining
        let yearsText = years <= 1 ? "**final year**" : "**\(years) years** left"
        return "\(coach.role.displayName) \u{00B7} \(yearsText) at **\(coachSalaryText(coach.salary))**."
    }

    private var promoteAction: DSActionBar.Action {
        .init(
            title: "Promote",
            caption: availablePromotionTargets.count == 1
                ? "to \(availablePromotionTargets[0].displayName)"
                : "\(availablePromotionTargets.count) roles open",
            handler: {
                if availablePromotionTargets.count == 1 {
                    // Single target: skip the picker, go straight to the
                    // confirmation the alert already writes in full.
                    selectedPromotionRole = availablePromotionTargets.first
                    showPromoteConfirmation = true
                } else {
                    activeSheet = .promoteRolePicker
                }
            }
        )
    }

    // MARK: - Projected Impact (concrete bonuses for the role)

    /// One line of the card: what the sim does differently because this man is
    /// in this seat.
    private struct ImpactRow: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let text: String
    }

    /// Signed percentage, one decimal — the house format for the figures below.
    private func pctText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(String(format: "%.1f", value))%"
    }

    /// Signed points, one decimal.
    private func ptsText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(String(format: "%.1f", value))"
    }

    /// One layer of `CoachingEngine.hierarchicalDevelopmentBonus`, as the
    /// percentage it adds to the development points of the players that layer
    /// covers. The weights are the engine's own — 0.08 (HC, off `motivation`),
    /// 0.04 (AHC), 0.10 (coordinator) and 0.15 (position coach) per 50 rating
    /// points above `developmentBonusPivot`.
    private func developmentPct(_ rating: Int, layer: Double) -> Double {
        (Double(rating) - CoachingEngine.developmentBonusPivot) / 50.0 * layer * 100.0
    }

    /// The other men in this coach's building. Two of the mechanics below are
    /// MAXIMA over the staff — `CoachingModifiers.ratings` takes the best game
    /// planner and the best morale influence on the payroll — so whether this
    /// man's number reaches the sim at all is a fact about the room and not
    /// about him.
    private var staffmates: [Coach] {
        guard let teamID = coach.teamID else { return [] }
        return allCoaches.filter { $0.teamID == teamID && $0.id != coach.id && !$0.isRetired }
    }

    /// Mech 2 — game planning onto completion probability, taken as a max over
    /// HC / AHC / OC / DC. A planner sitting behind a sharper colleague is
    /// worth exactly zero, which is worth saying plainly on the card that
    /// exists to justify his salary.
    private var gamePlanRow: ImpactRow {
        let best = staffmates
            .filter {
                $0.role == .headCoach || $0.role == .assistantHeadCoach
                    || $0.role == .offensiveCoordinator || $0.role == .defensiveCoordinator
            }
            .map(\.gamePlanning)
            .max()
        if let best, best > coach.gamePlanning {
            return ImpactRow(
                icon: "doc.text",
                color: .textTertiary,
                text: "Game planning \(coach.gamePlanning) sits behind the staff's best (\(best)), and the sim reads only the best"
            )
        }
        let edge = min(CoachingModifiers.planCompletionCap,
                       max(-CoachingModifiers.planCompletionCap,
                           (Double(coach.gamePlanning) - CoachingModifiers.planCenter)
                               * CoachingModifiers.planCompletionSlope)) * 100.0
        return ImpactRow(
            icon: "doc.text.fill",
            color: edge >= 0 ? .success : .danger,
            text: "Sets the week's game plan: \(ptsText(edge)) pts of completion probability"
        )
    }

    /// Mech 3 — morale influence onto the pre-game morale bump, the staff's
    /// other max. `nil` when a colleague's influence is higher, because then
    /// this man's contributes nothing at all. The head coach's motivation rides
    /// on top of it (Mech 5) and `CoachingModifiers.moraleBump` rounds the SUM
    /// of the two to a whole point, so what is quoted is his own term and not
    /// the applied bump.
    private var moraleInfluenceRow: ImpactRow? {
        if let best = staffmates.map(\.moraleInfluence).max(), best > coach.moraleInfluence {
            return nil
        }
        let term = (Double(coach.moraleInfluence) - CoachingModifiers.moraleCenter)
            * CoachingModifiers.moraleInfluenceSlope
        return ImpactRow(
            icon: "flame.fill",
            color: term >= 0 ? .accentGold : .danger,
            text: "Best morale influence on staff: \(ptsText(term)) pts into the pre-game morale bump"
        )
    }

    /// Mech 6 and development layer 3b — the coordinator's command of the
    /// system his unit actually installs, which the sim reads TWICE: a
    /// positive-only completion bonus above `CoachingModifiers.schemeCenter`,
    /// and a charge on his unit's development multiplier below it, reaching a
    /// full `CoachingEngine.coordinatorContinuityBonus` at expertise 20.
    ///
    /// This replaces "Players gain scheme familiarity faster", which named an
    /// effect the coordinator does not have: a roster's
    /// `activeSchemeFamiliarity` is its own install progress and does not read
    /// his expertise.
    ///
    /// `nil` for a coach carrying no `schemeExpertise` record at all (legacy
    /// rows written before the field existed) — layer 3b skips those, and
    /// `expertise(for:)`'s 20 fallback buys nothing under Mech 6 either.
    private func schemeRow(scheme: String, display: String) -> ImpactRow? {
        guard !coach.schemeExpertise.isEmpty else { return nil }
        let mastery = Double(coach.expertise(for: scheme))
        if mastery >= CoachingModifiers.schemeCenter {
            let bonus = min((mastery - CoachingModifiers.schemeCenter)
                                * CoachingModifiers.schemeCompletionSlope,
                            CoachingModifiers.schemeCompletionCap) * 100.0
            return ImpactRow(
                icon: "checkmark.seal.fill",
                color: .success,
                text: "Knows \(display) at \(Int(mastery)): \(ptsText(bonus)) pts of completion on top"
            )
        }
        let ignorance = min(1.0, max(0.0, (CoachingModifiers.schemeCenter - mastery) / 50.0))
        let charge = CoachingEngine.coordinatorContinuityBonus * ignorance * 100.0
        return ImpactRow(
            icon: "exclamationmark.triangle.fill",
            color: .warning,
            text: "Installing \(display) at expertise \(Int(mastery)), below par 70 — costs his unit \(String(format: "%.1f", charge))% development"
        )
    }

    /// Up to four projected-impact bullets for the coach in his current seat.
    ///
    /// ## Every line is an engine coefficient (#3046)
    ///
    /// This card used to quote "+12% offensive efficiency in games", "+12%
    /// defensive efficiency", "+5% staff chemistry", "+8% special teams
    /// performance", "-15% injury risk across the roster" off `discipline`,
    /// "-30% injury severity" and "+25% recovery speed" off `reputation`, each
    /// of them a hand-picked baseline run through a local `scaled(_:by:)`
    /// helper that multiplied it by `0.5 + attribute/99`.
    ///
    /// None of those quantities exists. Nothing in the sim has ever computed an
    /// "efficiency", a "staff chemistry" or a "special teams performance", and
    /// `reputation` and `discipline` do not appear ANYWHERE in `MedicalEngine`
    /// — the three medical seats are read for `playerDevelopment` and for
    /// nothing else. So the doctor's and the physio's headline numbers moved
    /// with an attribute no medical code reads, and the strength coach's injury
    /// line was driven by an attribute the engine uses for nothing of the kind.
    /// `HireCoachView`'s own projection card was corrected to the real
    /// coefficients; this card describes the same men two screens later and
    /// still answered in the invented units.
    ///
    /// Sources, one per line kind:
    ///
    /// * `CoachingModifiers` Mech 1 — coordinator grade, which is
    ///   `(playCalling + adaptability)/2` and not play-calling alone, onto
    ///   completion probability.
    /// * `CoachingModifiers` Mech 2 — game planning onto completion, a MAX over
    ///   HC/AHC/OC/DC (see ``gamePlanRow``).
    /// * `CoachingModifiers` Mech 3/5 — morale influence (a MAX over the whole
    ///   staff) and the head coach's motivation, onto pre-game morale.
    /// * `CoachingModifiers.disciplineScale` (Mech 4) — the head coach's
    ///   discipline scaling this club's own penalty AND fumble frequencies.
    /// * `CoachingModifiers` Mech 6 and `hierarchicalDevelopmentBonus` layer 3b
    ///   — coordinator scheme mastery (see ``schemeRow``).
    /// * `CoachingEngine.hierarchicalDevelopmentBonus` — its four layers (see
    ///   ``developmentPct``). The head coach's layer reads `motivation`; no
    ///   layer asks a head coach for `playerDevelopment`.
    /// * `PlayerDevelopmentEngine`'s `strengthBonus` and `resolvePositionCoach`,
    ///   and `WeekAdvancer.computeRecoveryRate`, for the strength coach.
    /// * `MedicalEngine.injuryCheck`, `.recoveryWeeks`, `.weeklyFatigueRecovery`
    ///   and `.processWeeklyRehab` for the three medical seats.
    ///
    /// Each line is what the SEAT is worth against it standing empty, which is
    /// the engine's own zero for every mechanic here — except the two maxima,
    /// which are stated against the rest of the staff, because that is the only
    /// way they are true.
    private var projectedImpacts: [ImpactRow] {
        var rows: [ImpactRow] = []

        switch coach.role {
        case .headCoach:
            // Mech 4 — his discipline scales this club's own penalty AND fumble
            // frequencies. Mirrors `CoachingModifiers.disciplineScale`, which is
            // private to that file.
            let scale = min(CoachingModifiers.disciplineScaleMax,
                            max(CoachingModifiers.disciplineScaleMin,
                                1.0 - (Double(coach.discipline) - CoachingModifiers.disciplineCenter)
                                    * CoachingModifiers.disciplineSlope))
            let penaltyPct = (scale - 1.0) * 100.0
            rows.append(.init(icon: "flag.fill", color: penaltyPct <= 0 ? .success : .danger,
                              text: "\(pctText(penaltyPct)) penalty and fumble frequency on your own snaps"))
            let devPct = developmentPct(coach.motivation, layer: 0.08)
            rows.append(.init(icon: "arrow.up.forward.circle.fill", color: devPct >= 0 ? .success : .danger,
                              text: "\(pctText(devPct)) roster-wide development per season, off his motivation"))
            // Mech 5 — motivation is the head coach's lever and nobody else's.
            let motivationTerm = (Double(coach.motivation) - CoachingModifiers.moraleCenter)
                * CoachingModifiers.motivationSlope
            rows.append(.init(icon: "trophy.fill", color: motivationTerm >= 0 ? .accentGold : .danger,
                              text: "\(ptsText(motivationTerm)) pts into the pre-game morale bump, off his motivation"))

        case .assistantHeadCoach:
            let devPct = developmentPct(coach.playerDevelopment, layer: 0.04)
            rows.append(.init(icon: "arrow.up.forward.circle.fill", color: devPct >= 0 ? .success : .danger,
                              text: "\(pctText(devPct)) roster-wide development per season"))
            rows.append(gamePlanRow)

        case .offensiveCoordinator, .defensiveCoordinator:
            // Mech 1 — the grade the sim reads is the average of play-calling
            // and adaptability. The OC pays it into his own offense's completion
            // probability; the DC takes the same magnitude out of the
            // opponent's.
            let grade = Double(coach.playCalling + coach.adaptability) / 2.0
            let shift = min(CoachingModifiers.coordCompletionCap,
                            max(-CoachingModifiers.coordCompletionCap,
                                (grade - CoachingModifiers.coordinatorCenter)
                                    * CoachingModifiers.coordCompletionSlope)) * 100.0
            let isOffense = coach.role == .offensiveCoordinator
            rows.append(.init(icon: isOffense ? "football.fill" : "shield.fill",
                              color: shift >= 0 ? .success : .danger,
                              text: isOffense
                                ? "\(ptsText(shift)) pts of completion probability for your offense"
                                : "\(ptsText(-shift)) pts of completion probability for the offenses he faces"))
            let devPct = developmentPct(coach.playerDevelopment, layer: 0.10)
            rows.append(.init(icon: "arrow.up.forward.circle.fill", color: devPct >= 0 ? .success : .danger,
                              text: "\(pctText(devPct)) development per season for his side of the ball"))
            if isOffense, let scheme = coach.offensiveScheme,
               let row = schemeRow(scheme: scheme.rawValue, display: scheme.displayName) {
                rows.append(row)
            } else if !isOffense, let scheme = coach.defensiveScheme,
                      let row = schemeRow(scheme: scheme.rawValue, display: scheme.displayName) {
                rows.append(row)
            }

        case .specialTeamsCoordinator:
            // He is the coordinator layer for a kicker or a punter and for
            // nobody else: `PlayerDevelopmentEngine` picks the coordinator by
            // the player's side of the ball. Neither Mech 1 nor Mech 2 reads him
            // at all — the planner list is HC/AHC/OC/DC.
            let devPct = developmentPct(coach.playerDevelopment, layer: 0.10)
            rows.append(.init(icon: "arrow.up.forward.circle.fill", color: devPct >= 0 ? .success : .danger,
                              text: "\(pctText(devPct)) development per season for kickers and punters"))

        case .qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach:
            let group = coach.role.displayName
                .replacingOccurrences(of: "Coach", with: "")
                .trimmingCharacters(in: .whitespaces)
            let devPct = developmentPct(coach.playerDevelopment, layer: 0.15)
            rows.append(.init(icon: "arrow.up.forward.circle.fill", color: devPct >= 0 ? .success : .danger,
                              text: "\(pctText(devPct)) \(group) development per season — the heaviest of the four layers"))

        case .strengthCoach:
            // `PlayerDevelopmentEngine` adds `strengthBonus` onto EVERY player's
            // physical development points each offseason. Quoted in points
            // because that is the unit the engine adds it in.
            let strengthBonus = 0.5 + Double(coach.playerDevelopment) / 99.0 * 0.5
            rows.append(.init(icon: "figure.strengthtraining.traditional", color: .success,
                              text: "+\(String(format: "%.2f", strengthBonus)) physical development points per player per season"))
            // `WeekAdvancer.computeRecoveryRate` maps his `playerDevelopment`
            // onto a camp recovery rate of 0.40...0.75. A club with neither a
            // strength coach nor a physio sits at 0.55.
            let rating = Double(max(1, min(99, coach.playerDevelopment)))
            let rate = 0.40 + (rating - 1.0) / 98.0 * 0.35
            let campPct = (rate / 0.55 - 1.0) * 100.0
            rows.append(.init(icon: "bed.double.fill", color: campPct >= 0 ? .success : .danger,
                              text: "\(pctText(campPct)) camp recovery against a club with no strength coach"))
            // `resolvePositionCoach` falls back to him for the positions no
            // specialist role covers, which `CoachingEngine.positionRoleMatch`
            // makes exactly K and P.
            let kpPct = developmentPct(coach.playerDevelopment, layer: 0.15)
            rows.append(.init(icon: "arrow.up.forward.circle.fill", color: kpPct >= 0 ? .success : .danger,
                              text: "\(pctText(kpPct)) K and P development — no specialist covers them, so he is their position coach"))

        case .teamDoctor:
            // `MedicalEngine.injuryCheck` scales risk by 1 - pd/330, and
            // `recoveryWeeks` takes pd/660 off the prognosis.
            rows.append(.init(icon: "cross.case.fill", color: .success,
                              text: "\(pctText(-Double(coach.playerDevelopment) / 330.0 * 100.0)) injury risk on every snap"))
            rows.append(.init(icon: "bandage.fill", color: .success,
                              text: "\(pctText(-Double(coach.playerDevelopment) / 660.0 * 100.0)) weeks on the injury report"))

        case .physio:
            // `MedicalEngine.recoveryWeeks` takes pd/400 off the prognosis, and
            // `weeklyFatigueRecovery` adds pd/10 to the base 15 points a week.
            rows.append(.init(icon: "bandage.fill", color: .success,
                              text: "\(pctText(-Double(coach.playerDevelopment) / 400.0 * 100.0)) weeks on the injury report"))
            let fatigue = Int(Double(coach.playerDevelopment) / 10.0)
            rows.append(.init(icon: "bolt.heart.fill", color: fatigue > 0 ? .success : .textTertiary,
                              text: "+\(fatigue) fatigue recovered per week on top of the base 15"))

        case .headTrainer:
            // `MedicalEngine.processWeeklyRehab` rolls a setback at
            // max(0.02, 0.10 - pd * 0.0006), against the 10 % a club with no
            // trainer rolls.
            let setback = max(0.02, 0.10 - Double(coach.playerDevelopment) * 0.0006)
            rows.append(.init(icon: "arrow.triangle.2.circlepath", color: .success,
                              text: "\(pctText((setback / 0.10 - 1.0) * 100.0)) rehab setbacks — \(String(format: "%.1f", setback * 100.0))% a week against a bare 10%"))
        }

        if let moraleRow = moraleInfluenceRow {
            rows.append(moraleRow)
        }

        // `isInAdjustmentPeriod` is read in exactly three places — layers 1 and
        // 3 of `hierarchicalDevelopmentBonus`, and the continuity gate in
        // `WeekAdvancer` — and for nobody outside those seats. The row here used
        // to read "bonuses reduced ~25% this season" for every man on the
        // payroll, a figure no engine produces for anyone.
        if coach.isInAdjustmentPeriod {
            switch coach.role {
            case .headCoach:
                rows.append(.init(icon: "hourglass", color: .warning,
                                  text: "First season in the building: 0.05 off the roster's development multiplier"))
            case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
                rows.append(.init(icon: "hourglass", color: .warning,
                                  text: "First season in the building: 0.03 off his unit's development multiplier, and no continuity bonus"))
            default:
                break
            }
        }

        // What a coach's reputation actually does: `CoachingEngine` builds each
        // club's head-coaching candidate pool from it — 0-99 maps to a 0.00-0.40
        // poach chance, plus 0.15 for a coordinator — and excludes head coaches,
        // assistant head coaches and the medical seats. It is a risk to the GM,
        // not the recruiting perk the old row advertised; nothing on the player
        // market reads a coach's reputation at all.
        if coach.reputation >= 75,
           coach.role != .headCoach,
           coach.role != .assistantHeadCoach,
           coach.role.family != .medical {
            rows.append(.init(icon: "person.3.fill", color: .warning,
                              text: "Reputation \(coach.reputation) — rival clubs pull men like him into head-coaching searches"))
        }

        return Array(rows.prefix(4))
    }

    /// **The screen's subject** (§2.11) — the one bordered, lifted insert.
    ///
    /// This card is why the coach exists on the payroll: what employing him
    /// does to the roster this season. Everything else on the page is evidence
    /// for or against it.
    @ViewBuilder
    private var projectedImpactCard: some View {
        let rows = projectedImpacts
        if !rows.isEmpty {
            DSDetailCard(
                "What He Is Doing For You",
                icon: "bolt.fill",
                explainer: "Derived from his role and his attributes — this is what the engine actually applies, not a description of the job.",
                isSubject: true
            ) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: DSSpacing.xs) {
                        Image(systemName: row.icon)
                            .font(.system(size: DSType.Size.footnote, weight: .semibold))
                            .foregroundStyle(row.color)
                            .frame(width: 18)
                        Text(row.text)
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Severance Preview (fire flow polish)

    /// Severance owed if the coach is fired now (in $K).
    ///
    /// F-64: this used to be an *estimate* in the strict sense — the alert
    /// quoted a number and `fireCoach()` charged nothing at all. It now reads
    /// the same `BudgetEngine` function the charge books, so the preview and
    /// the outcome cannot disagree.
    private var estimatedSeveranceK: Int {
        BudgetEngine.coachSeverance(
            salary: coach.salary,
            contractYearsRemaining: coach.contractYearsRemaining
        )
    }

    /// Formatted severance string for display.
    private var severanceDisplay: String {
        let amountK = estimatedSeveranceK
        if amountK <= 0 {
            return "no severance owed"
        }
        let millions = Double(amountK) / 1_000.0
        if millions >= 1.0 {
            return "approx $\(String(format: "%.1f", millions))M severance"
        }
        return "approx $\(amountK)K severance"
    }

    /// Full message for the fire confirmation alert with severance preview.
    ///
    /// F-64: the branch on years used to say "Contract expires after this
    /// season" for a man with one year left, which read as "this is free" — and
    /// was, because nothing was charged. It is now charged, so the copy names
    /// the bill whenever there is one and says so plainly when there is not.
    private var fireConfirmationMessage: String {
        let years = coach.contractYearsRemaining
        let yearsText: String
        if years <= 0 {
            yearsText = "His deal is already up — no severance owed."
        } else {
            let termText = years == 1 ? "1 year remains" : "\(years) years remain"
            yearsText = "\(termText) on contract — \(severanceDisplay), charged to your coaching budget."
        }
        return "This will remove \(coach.firstName) from your coaching staff. \(yearsText) This action cannot be undone."
    }

    // MARK: - Helpers

    private var experienceLabel: String {
        switch coach.yearsExperience {
        case 0:      return "No experience"
        case 1:      return "1 year"
        default:     return "\(coach.yearsExperience) years"
        }
    }

    /// Fix #64: Color-codes attribute values like Player Detail (green 80+, gold 70+, orange 60+, red below).
    private func attributeColor(_ value: Int) -> Color {
        Color.forRating(value)
    }

    /// Human-readable tier label for an attribute value.
    private func attributeTierLabel(_ value: Int) -> String {
        if value >= 90 { return "Elite" }
        if value >= 80 { return "Great" }
        if value >= 70 { return "Good" }
        if value >= 60 { return "Average" }
        if value >= 50 { return "Below Avg" }
        return "Poor"
    }

    // MARK: - Compatibility Analysis

    private struct CompatibilityAnalysis {
        var complements: [String]
        var redundancies: [String]
        var weaknesses: [String]
        var overallLabel: String
        var overallColor: Color
    }

    /// Named attribute pair for comparison.
    private struct AttributePair {
        let name: String
        let coachValue: Int
        let hcValue: Int
    }

    /// Compares this coach's attributes against the HC to find complements, redundancies, and weaknesses.
    private func analyzeCompatibility(with hc: Coach) -> CompatibilityAnalysis {
        let pairs: [AttributePair] = [
            .init(name: "Play Calling",        coachValue: coach.playCalling,        hcValue: hc.playCalling),
            .init(name: "Player Dev",          coachValue: coach.playerDevelopment,  hcValue: hc.playerDevelopment),
            .init(name: "Game Planning",       coachValue: coach.gamePlanning,       hcValue: hc.gamePlanning),
            .init(name: "Scouting",            coachValue: coach.scoutingAbility,    hcValue: hc.scoutingAbility),
            .init(name: "Recruiting",          coachValue: coach.recruiting,         hcValue: hc.recruiting),
            .init(name: "Motivation",          coachValue: coach.motivation,         hcValue: hc.motivation),
            .init(name: "Discipline",          coachValue: coach.discipline,         hcValue: hc.discipline),
            .init(name: "Adaptability",        coachValue: coach.adaptability,       hcValue: hc.adaptability),
            .init(name: "Morale Influence",    coachValue: coach.moraleInfluence,    hcValue: hc.moraleInfluence),
        ]

        var complements: [String] = []
        var redundancies: [String] = []
        var weaknesses: [String] = []

        for pair in pairs {
            let coachStrong = pair.coachValue >= 75
            let hcWeak = pair.hcValue < 60
            let hcStrong = pair.hcValue >= 75
            let bothWeak = pair.coachValue < 60 && pair.hcValue < 60

            if coachStrong && hcWeak {
                // Coach is strong where HC is weak -> complements
                complements.append(pair.name)
            } else if coachStrong && hcStrong {
                // Both are strong -> redundant
                redundancies.append(pair.name)
            } else if bothWeak {
                // Both are weak -> shared weakness
                weaknesses.append(pair.name)
            }
        }

        // Determine overall label. Off the app palette — the previous version
        // used the stock SwiftUI `.green` / `.orange`, which is the same hue
        // problem `developerScoreColor` was fixed for.
        let overallLabel: String
        let overallColor: Color
        if complements.count >= 3 && weaknesses.isEmpty {
            overallLabel = "Excellent Fit"
            overallColor = Color.success
        } else if complements.count > redundancies.count && weaknesses.count <= 1 {
            overallLabel = "Good Fit"
            overallColor = Color.success
        } else if redundancies.count > complements.count {
            overallLabel = "Redundant"
            overallColor = Color.accentGold
        } else if weaknesses.count >= 2 {
            overallLabel = "Poor Fit"
            overallColor = Color.warning
        } else {
            overallLabel = "Neutral"
            overallColor = Color.textSecondary
        }

        return CompatibilityAnalysis(
            complements: complements,
            redundancies: redundancies,
            weaknesses: weaknesses,
            overallLabel: overallLabel,
            overallColor: overallColor
        )
    }

    /// F-64 — firing a man under contract costs the owner's coaching pot.
    ///
    /// The severance is charged against `Owner.coachingBudget` and not against
    /// the salary cap, because coaching money never touches the cap in this game
    /// or in the real one. It is charged for the current league year only: the
    /// pot is recomputed every offseason (`BudgetEngine.calculateBudget` at
    /// `startNewSeason`), so the bill lands on the season the decision was made
    /// in and is not carried forward — the coaching equivalent of a one-year
    /// dead-money hit, and the reason a January purge of four assistants now
    /// costs you the man you wanted to replace them with.
    ///
    /// AI firings are deliberately NOT charged here: the Black Monday carousel
    /// is on the DO NOT TOUCH list, its 0.145 firings per club per season is the
    /// best-calibrated league-wide number in the audit, and pricing it would
    /// change how well-staffed 3-6 clubs are every January for a lever nobody
    /// exploits. The underpricing this fix is about is the user's.
    private func fireCoach() {
        let severance = estimatedSeveranceK
        if severance > 0,
           let teamID = coach.teamID,
           let owner = fetchOwner(teamID: teamID) {
            owner.coachingBudget = max(0, owner.coachingBudget - severance)
        }
        coach.teamID = nil
        coach.contractYearsRemaining = 0
        try? modelContext.save()
        dismiss()
    }

    /// The owner whose pot pays the severance.
    private func fetchOwner(teamID: UUID) -> Owner? {
        let descriptor = FetchDescriptor<Team>(
            predicate: #Predicate<Team> { $0.id == teamID }
        )
        return (try? modelContext.fetch(descriptor))?.first?.owner
    }

    /// Extend the coach's contract by 2 years.
    private func extendContract() {
        coach.contractYearsRemaining += 2
        try? modelContext.save()
    }

    /// Promote the coach to the selected target role.
    private func promoteCoach(to targetRole: CoachRole) {
        coach.role = targetRole
        // Salary bump for promotion (~20%)
        coach.salary = Int(Double(coach.salary) * 1.2)
        // Mark as promoted this season (triggers adjustment period)
        coach.promotedInSeason = career?.currentSeason ?? 1
        try? modelContext.save()
        selectedPromotionRole = nil
    }

    /// Demote the coach to the first available demotion target.
    private func demoteCoach() {
        guard let targetRole = coach.role.demotionTargets.first else { return }
        coach.role = targetRole
        // Reduce reputation by 10
        coach.reputation = max(1, coach.reputation - 10)
        try? modelContext.save()
    }
}


// MARK: - Preview

#Preview {
    NavigationStack {
        CoachDetailView(coach: Coach(
            firstName: "Bill",
            lastName: "Parcells",
            age: 62,
            role: .headCoach,
            offensiveScheme: .proPassing,
            defensiveScheme: .base43,
            playCalling: 91,
            playerDevelopment: 78,
            reputation: 88,
            adaptability: 72,
            personality: .fieryCompetitor,
            yearsExperience: 20
        ))
    }
    .modelContainer(for: Coach.self, inMemory: true)
}
