import SwiftUI

// MARK: - The one owner briefing (#105 Wave 5a)
//
// UI_REDESIGN_VISION §3 row 12b and §4 Wave 5: *"Merge the two press-conference
// views and the two owner screens, then restyle the survivors."* §3 names the
// pair by file — `News/OwnerMeetingView` vs `IntroSequenceView.OwnerMeetingStep`
// — and §5 states the target: *"one owner screen"*.
//
// The two screens described the same man twice and disagreed while doing it:
//
//   * `OwnerMeetingStep` (intro) had the **explainers** — what "Win Now" means
//     for your free agency, what patience 3 costs you, what the budget buys
//     against the league average, what meddling 70 does to your personnel
//     control — plus the owner's personal quote and the consequences line.
//   * `OwnerMeetingView` (hub) had the **live state** — satisfaction, job
//     security, the whim, the goal tracker, the budget envelope, the last
//     season review — with no explainers at all, so a hub reader saw
//     "Involvement: Frequently Involved" and was told nothing about what that
//     did to him.
//
// So this file is neither screen: it is the vocabulary both are now written in.
// One card per subject, each a plain value-in / view-out component, following
// the same shape `NegotiationChat` established for the negotiation merge in
// Wave 3. Both screens compose the cards they need and own nothing else:
//
//   OwnerBriefingHeader      who is across the table, and how happy he is
//   OwnerPrioritiesCard      philosophy · patience · budget · involvement,
//                            each with the implication line under it
//   OwnerPatienceCard        the clock, in seasons
//   OwnerBudgetCard          the three staff pots + the facilities verdict
//   OwnerGoalsCard           the season goals, as a checklist
//   OwnerQuoteCard           what he actually said, and what failure costs
//   OwnerSatisfactionCard    the meter and the job-security readout
//   OwnerLastReviewCard      last season's verdict
//   OwnerWarningCard         the specific reasons he is unhappy
//
// **No engine logic moved here.** `OwnerPersonaEngine`, `OwnerGoalsEngine` and
// `FacilityEngine` keep every threshold and every verdict; these cards are handed
// an `Owner`, a `Career` and pre-evaluated goals, and they draw them. The copy
// tables (implications, quotes, warnings) are the strings the two screens
// already shipped, deduplicated — they are presentation, and they were the thing
// that existed twice.
//
// **Navigation stays with the caller.** The goal and budget cards take an
// optional ``OwnerBriefingLink``; the hub passes one (it lives in a
// `NavigationStack`), the intro passes nil (it does not, and a dead chevron is
// worse than no chevron).

// MARK: - Values

/// One season goal as the briefing draws it.
///
/// Deliberately not `SeasonGoal`: the hub evaluates live `SeasonGoal`s through
/// `OwnerGoalsEngine`, while the intro has a freshly generated `SeasonGoals`
/// (primary/secondary strings and nothing else). Unifying *those* is a model
/// change; this is the view's own value type, and each screen maps into it.
struct OwnerBriefingGoal: Identifiable {
    let id: String
    let title: String
    /// "PRIMARY" / "SECONDARY" / "BONUS".
    let priorityLabel: String
    let isPrimary: Bool
    /// `progress / target`, when the goal counts something.
    let progress: (done: Int, target: Int)?
    let isAchieved: Bool

    init(
        id: String,
        title: String,
        priorityLabel: String,
        isPrimary: Bool,
        progress: (done: Int, target: Int)? = nil,
        isAchieved: Bool = false
    ) {
        self.id = id
        self.title = title
        self.priorityLabel = priorityLabel
        self.isPrimary = isPrimary
        self.progress = progress
        self.isAchieved = isAchieved
    }
}

/// A "there is more of this elsewhere" row at the foot of a card. Only a screen
/// inside a `NavigationStack` may pass one.
struct OwnerBriefingLink {
    let title: String
    let destination: AnyView

    init<Destination: View>(title: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.destination = AnyView(destination())
    }
}

// MARK: - Shared copy and palette
//
// The strings the two screens had two copies of. Static, because a card, a
// warning list and a header all read the same table.

enum OwnerBriefingCopy {

    // MARK: Bands

    static func spendingLabel(_ value: Int) -> (text: String, color: Color) {
        if value < 25 { return ("Budget Conscious", Color.dangerText) }
        if value < 50 { return ("Moderate Spender", Color.warning) }
        if value < 75 { return ("Willing to Spend", Color.accentBlue) }
        return ("Opens the Checkbook", Color.success)
    }

    static func meddlingLabel(_ value: Int) -> (text: String, color: Color) {
        if value < 25 { return ("Hands Off", Color.success) }
        if value < 50 { return ("Occasionally Involved", Color.accentBlue) }
        if value < 75 { return ("Frequently Involved", Color.warning) }
        return ("Highly Controlling", Color.dangerText)
    }

    // MARK: Implications (#15, from the intro screen)

    static func visionImplication(_ owner: Owner) -> String {
        owner.prefersWinNow
            ? "Prioritizes free agency spending and expects playoff contention. Veterans are favored over draft-and-develop."
            : "Supports a long-term plan. Draft picks and player development are valued over quick fixes."
    }

    static func patienceImplication(_ owner: Owner) -> String {
        let leagueAvg = 5
        let comparison: String
        if owner.patience < leagueAvg - 1 {
            comparison = "Less patient than most owners"
        } else if owner.patience > leagueAvg + 1 {
            comparison = "More patient than most owners"
        } else {
            comparison = "About average patience"
        }
        let tail: String
        switch owner.patience {
        case ...3:    tail = "Win fast or face consequences."
        case 4...6:   tail = "Steady progress expected each year."
        default:      tail = "Time to build through the draft."
        }
        return "League avg: \(leagueAvg) seasons \u{2014} \(comparison). \(tail)"
    }

    static func budgetImplication(_ owner: Owner) -> String {
        let budgetM = money(owner.coachingBudget)
        let leagueAvgM = "$38.0M"
        let tail: String
        switch owner.spendingWillingness {
        case ...30:   tail = "Build through the draft \u{2014} free agency will be tight."
        case 31...60: tail = "Modest spending \u{2014} be strategic with signings."
        case 61...80: tail = "Significant resources for roster upgrades."
        default:      tail = "Money is no object \u{2014} the owner backs any move."
        }
        return "Budget: \(budgetM) (league avg: \(leagueAvgM)). \(tail)"
    }

    static func meddlingImplication(_ owner: Owner) -> String {
        switch owner.meddling {
        case ...30:   return "Full autonomy on roster decisions. The owner trusts your football judgment completely."
        case 31...60: return "The owner may weigh in on major decisions but generally stays out of the way."
        case 61...80: return "Expect the owner to have opinions on key signings and draft picks."
        default:      return "The owner will frequently override your decisions. Pick your battles carefully."
        }
    }

    // MARK: The personal quote (#16, from the intro screen)

    static func personalQuote(_ owner: Owner) -> String {
        let name = owner.name.components(separatedBy: " ").first ?? owner.name
        if owner.prefersWinNow && owner.patience <= 3 {
            return "\u{201C}I didn't buy this team to lose. I want a championship, and I want it now.\u{201D} \u{2014} \(name)"
        } else if owner.prefersWinNow && owner.meddling > 60 {
            return "\u{201C}I'll be watching every move you make. My fans deserve winners.\u{201D} \u{2014} \(name)"
        } else if owner.prefersWinNow {
            return "\u{201C}I believe in winning. Show me results and you'll have everything you need.\u{201D} \u{2014} \(name)"
        } else if owner.patience >= 7 {
            return "\u{201C}Take your time and build this the right way. I'm not going anywhere.\u{201D} \u{2014} \(name)"
        } else if owner.meddling > 60 {
            return "\u{201C}I trust you, but I like to stay close to the operation. Don't shut me out.\u{201D} \u{2014} \(name)"
        } else if owner.spendingWillingness < 30 {
            return "\u{201C}Be smart with the money. Every dollar has to count around here.\u{201D} \u{2014} \(name)"
        } else {
            return "\u{201C}Just give me a team the city can be proud of. That's all I ask.\u{201D} \u{2014} \(name)"
        }
    }

    // MARK: Satisfaction

    static func satisfactionTitle(_ value: Int) -> String {
        if value > 75 { return "Owner is thrilled" }
        if value > 60 { return "Owner is satisfied" }
        if value > 45 { return "Owner has concerns" }
        if value > 35 { return "Owner is frustrated" }
        return "Owner is furious"
    }

    static func satisfactionBody(_ owner: Owner) -> String {
        let value = owner.satisfaction
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

    static func patienceDescription(_ value: Int) -> String {
        if value >= 8 { return "This owner is very patient and will give you time to build a winner through any strategy." }
        if value >= 6 { return "The owner is moderately patient but expects steady improvement each season." }
        if value >= 4 { return "The owner wants results sooner rather than later. Missing the playoffs repeatedly will cost you." }
        return "This owner has a short fuse. You need wins now or your tenure will be brief."
    }

    static func warnings(owner: Owner, career: Career) -> [String] {
        var messages: [String] = []
        if owner.satisfaction < 35 {
            messages.append("The owner is actively considering a coaching change.")
        }
        if owner.prefersWinNow && career.totalWins < 5 {
            messages.append("This owner prioritizes winning immediately \u{2014} results are expected now.")
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

    // MARK: Palette

    /// Owner satisfaction is a 0–100 percentage, so it takes the shared ladder
    /// (P7). A bespoke copy is exactly how the hub tile and the meeting screen
    /// ended up disagreeing about the same owner.
    static func satisfactionColor(_ value: Int) -> Color {
        Color.forRating(value, scale: .percent)
    }

    static func patienceColor(_ value: Int) -> Color {
        if value >= 7 { return Color.success }
        if value >= 4 { return Color.warning }
        return Color.dangerText
    }

    static func jobSecurityColor(_ level: OwnerPersonaEngine.JobSecurityLevel) -> Color {
        switch level {
        case .secure:   return .success
        case .stable:   return .accentBlue
        case .pressure: return .warning
        case .hotSeat:  return .warning
        case .critical: return .dangerText
        }
    }

    static func money(_ thousands: Int) -> String {
        String(format: "$%.1fM", Double(thousands) / 1_000.0)
    }
}

// MARK: - Card chrome
//
// One head, one surface, one radius. §2.9: section heads are `textSecondary` and
// tracked, not gold — gold has three jobs and "every heading on the screen" is
// not one of them.

private struct OwnerCard<Content: View>: View {
    let icon: String
    let title: String
    let trailing: AnyView?
    /// A card that is itself a warning takes the warning hue for its head, its
    /// glyph and its border. Everything else keeps the neutral head §2.9 asks
    /// for — gold has three jobs and "every heading" is not one of them.
    let accent: Color?
    let content: Content

    /// Written out rather than synthesized: the memberwise initializer of a
    /// generic view with a builder-attributed stored property is a subtle thing
    /// to depend on, and this component is called from two files.
    init(
        icon: String,
        title: String,
        trailing: AnyView? = nil,
        accent: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.trailing = trailing
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent ?? Color.accentGold)
                Text(title.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(accent ?? Color.textSecondary)
                Spacer(minLength: DSSpacing.xs)
                if let trailing { trailing }
            }

            Divider().overlay(Color.surfaceBorder)

            content
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(accent?.opacity(0.45) ?? Color.surfaceBorder, lineWidth: 1)
                )
        )
    }
}

/// The card-foot navigation row. One shape, so "View Full Goal Tracker" and
/// "Reallocate Budget" cannot be two different affordances.
private struct OwnerCardLinkRow: View {
    let link: OwnerBriefingLink

    var body: some View {
        NavigationLink {
            link.destination
        } label: {
            HStack {
                Text(link.title)
                    .font(DSType.text(14, .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.accentGold)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A label / value line inside a card.
private struct OwnerFactRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .textPrimary

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentGold)
                .frame(width: 22)
            Text(label)
                .font(DSType.text(14, .regular))
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: DSSpacing.xs)
            Text(value)
                .font(DSType.text(14, .semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The explainer under a fact (#15). This is the line the hub screen never had.
private struct OwnerImplicationRow: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentGold.opacity(0.6))
                Text(text)
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, DSSpacing.lg)
        }
    }
}

// MARK: - Header

/// Both sides of the meeting, facing each other: the owner's photograph and the
/// player's own portrait. Each screen used to draw one participant only — the
/// hub drew the pair, the intro drew the pair differently.
struct OwnerBriefingHeader: View {

    let career: Career
    let owner: Owner
    let teamName: String
    /// The intro presents this as a scene and wants the big plate; the hub wants
    /// a row it can stack cards under.
    var isHero: Bool = false

    var body: some View {
        if isHero {
            VStack(spacing: DSSpacing.sm) {
                HStack(spacing: -14) {
                    PersonFaceView(owner: owner, size: .large)
                    UserPortraitView(career: career, size: .medium)
                        .offset(y: 16)
                }
                Text("OWNER MEETING")
                    .font(DSType.display(DSType.Size.footnote, .black))
                    .tracking(4)
                    .foregroundStyle(Color.accentGold)
                Text(owner.name)
                    .font(DSType.display(DSType.Size.title2, .heavy))
                    .foregroundStyle(Color.textPrimary)
                Text("Owner, \(teamName)")
                    .font(DSType.text(14, .regular))
                    .foregroundStyle(Color.textSecondary)
                archetypeBadge
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: DSSpacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    PersonFaceView(owner: owner, size: .medium)
                    UserPortraitView(career: career, size: .small)
                        .offset(x: 10, y: 6)
                }
                .padding(.trailing, DSSpacing.xs)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(owner.name)
                        .font(DSType.display(DSType.Size.title3, .heavy))
                        .foregroundStyle(Color.textPrimary)
                    Text(teamName)
                        .font(DSType.text(14, .regular))
                        .foregroundStyle(Color.textSecondary)
                    archetypeBadge
                }

                Spacer(minLength: DSSpacing.xs)

                satisfactionBadge
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    private var archetypeBadge: some View {
        let archetype = OwnerPersonaEngine.OwnerArchetype.from(owner)
        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: archetype.icon)
                .font(.system(size: 10))
            Text(archetype.displayName.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.5)
        }
        .foregroundStyle(Color.accentGold)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 3)
        .background(Color.accentGold.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1))
    }

    private var satisfactionBadge: some View {
        VStack(spacing: DSSpacing.xxs) {
            Text("\(owner.satisfaction)%")
                .font(DSType.display(DSType.Size.title2, .heavy))
                .foregroundStyle(OwnerBriefingCopy.satisfactionColor(owner.satisfaction))
            Text("SATISFIED")
                .font(DSType.display(11, .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .frame(width: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Owner satisfaction \(owner.satisfaction) percent")
    }
}

// MARK: - Priorities (with the explainers)

struct OwnerPrioritiesCard: View {

    let owner: Owner

    /// Fact + explainer, as one unit. Kept as a block rather than as eleven
    /// loose children so the card reads as four subjects and not as a list of
    /// twenty-two lines.
    private struct Priority: Identifiable {
        let id: String
        let icon: String
        let label: String
        let value: String
        let valueColor: Color
        let implication: String
    }

    private var priorities: [Priority] {
        let spend = OwnerBriefingCopy.spendingLabel(owner.spendingWillingness)
        let meddle = OwnerBriefingCopy.meddlingLabel(owner.meddling)
        return [
            Priority(
                id: "philosophy",
                icon: owner.prefersWinNow ? "trophy.fill" : "building.2.fill",
                label: "Philosophy",
                value: owner.prefersWinNow ? "Win Now" : "Willing to Rebuild",
                valueColor: owner.prefersWinNow ? Color.accentGold : Color.accentBlue,
                implication: OwnerBriefingCopy.visionImplication(owner)
            ),
            Priority(
                id: "patience",
                icon: "clock.fill",
                label: "Patience",
                value: "Results within \(owner.patience) season\(owner.patience == 1 ? "" : "s")",
                valueColor: OwnerBriefingCopy.patienceColor(owner.patience),
                implication: OwnerBriefingCopy.patienceImplication(owner)
            ),
            Priority(
                id: "spending",
                icon: "dollarsign.circle.fill",
                label: "Spending",
                value: spend.text,
                valueColor: spend.color,
                implication: OwnerBriefingCopy.budgetImplication(owner)
            ),
            Priority(
                id: "involvement",
                icon: "person.badge.key.fill",
                label: "Involvement",
                value: meddle.text,
                valueColor: meddle.color,
                implication: OwnerBriefingCopy.meddlingImplication(owner)
            )
        ]
    }

    var body: some View {
        OwnerCard(icon: "slider.horizontal.3", title: "Owner Priorities") {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ForEach(Array(priorities.enumerated()), id: \.element.id) { index, priority in
                    if index > 0 {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                    }
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        OwnerFactRow(
                            icon: priority.icon,
                            label: priority.label,
                            value: priority.value,
                            valueColor: priority.valueColor
                        )
                        OwnerImplicationRow(text: priority.implication)
                    }
                }
            }
        }
    }
}

// MARK: - Patience

struct OwnerPatienceCard: View {

    let owner: Owner
    let career: Career

    private var seasonsBeforeReview: String {
        let remaining = max(0, owner.patience - career.yearsFired)
        return remaining == 0 ? "This Season" : "\(remaining)"
    }

    var body: some View {
        OwnerCard(icon: "hourglass", title: "Owner Patience") {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: 0) {
                    statColumn(
                        label: "Patience",
                        value: "\(owner.patience)/10",
                        color: OwnerBriefingCopy.patienceColor(owner.patience)
                    )
                    statColumn(
                        label: "Seasons before review",
                        value: seasonsBeforeReview,
                        color: Color.textPrimary
                    )
                    statColumn(
                        label: "Current season",
                        value: "\(career.currentSeason)",
                        color: Color.textSecondary
                    )
                }

                Text(OwnerBriefingCopy.patienceDescription(owner.patience))
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(DSSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .fill(Color.backgroundTertiary)
                    )
            }
        }
    }

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Text(value)
                .font(DSType.display(DSType.Size.title3, .heavy))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(DSType.display(11, .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.textTertiaryReadable)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Budget

struct OwnerBudgetCard: View {

    let owner: Owner
    /// The hub links to the reallocation screen; the intro cannot.
    var link: OwnerBriefingLink?

    private var total: Int {
        owner.coachingBudget + owner.scoutingBudget + owner.medicalBudget
    }

    var body: some View {
        OwnerCard(
            icon: "dollarsign.circle.fill",
            title: "Staff Budget Envelope",
            trailing: AnyView(
                Text(OwnerBriefingCopy.money(total))
                    .font(DSType.display(DSType.Size.callout, .heavy))
                    .foregroundStyle(Color.accentGold)
            )
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: 0) {
                    potColumn(label: "Coaching", value: owner.coachingBudget, color: .accentGold)
                    potColumn(label: "Scouting", value: owner.scoutingBudget, color: .accentBlue)
                    potColumn(label: "Medical", value: owner.medicalBudget, color: .success)
                }

                Divider().overlay(Color.surfaceBorder)

                // TODO §5.4: the facilities envelope is a separate pot from the
                // three above, and the owner meeting is where he says what he
                // thinks of the buildings he pays for.
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentGold)
                    Text(FacilityEngine.ownerMeetingLine(owner: owner))
                        .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                        .italic()
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let link {
                    OwnerCardLinkRow(link: link)
                }
            }
        }
    }

    private func potColumn(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Text(OwnerBriefingCopy.money(value))
                .font(DSType.display(DSType.Size.callout, .heavy))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(DSType.display(11, .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Season goals

struct OwnerGoalsCard: View {

    let goals: [OwnerBriefingGoal]
    var link: OwnerBriefingLink?

    private var met: Int { goals.filter(\.isAchieved).count }

    var body: some View {
        OwnerCard(
            icon: "target",
            title: "Season Goals",
            trailing: AnyView(
                Text("\(met)/\(goals.count) met")
                    .font(DSType.display(DSType.Size.footnote, .heavy))
                    .foregroundStyle(Color.textSecondary)
            )
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ForEach(goals) { goal in
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: goal.isAchieved ? "star.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(goal.isAchieved ? Color.accentGold : Color.textTertiary)
                        Text(goal.title)
                            .font(DSType.text(14, .regular, prose: true))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: DSSpacing.xs)
                        if let progress = goal.progress {
                            Text("\(progress.done)/\(progress.target)")
                                .font(DSType.display(DSType.Size.footnote, .heavy))
                                .foregroundStyle(goal.isAchieved ? Color.accentGold : Color.textSecondary)
                        }
                        Text(goal.priorityLabel.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.5)
                            .foregroundStyle(goal.isPrimary ? Color.accentGold : Color.textTertiaryReadable)
                    }
                    .frame(minHeight: 32)
                }

                if let link {
                    OwnerCardLinkRow(link: link)
                }
            }
        }
    }
}

// MARK: - The quote

/// What he actually said, and what failure costs (#16 / #129). The hub never had
/// this and it is the most human thing on either screen.
struct OwnerQuoteCard: View {

    let owner: Owner

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentGold.opacity(0.7))
                Text(OwnerBriefingCopy.personalQuote(owner))
                    .font(DSType.text(14, .regular, prose: true))
                    .italic()
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.warning)
                Text("Failure may result in budget cuts, forced trades, or termination.")
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.accentGold.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Satisfaction + job security

struct OwnerSatisfactionCard: View {

    let owner: Owner
    let career: Career

    var body: some View {
        OwnerCard(
            icon: "chart.bar.fill",
            title: "Owner Satisfaction",
            trailing: AnyView(
                Text("\(owner.satisfaction) / 100")
                    .font(DSType.display(DSType.Size.footnote, .heavy))
                    .foregroundStyle(OwnerBriefingCopy.satisfactionColor(owner.satisfaction))
            )
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                meter(
                    fraction: Double(owner.satisfaction) / 100.0,
                    color: OwnerBriefingCopy.satisfactionColor(owner.satisfaction),
                    height: 14
                )
                .animation(.easeOut(duration: 0.6), value: owner.satisfaction)

                HStack {
                    zoneLabel("Danger", "exclamationmark.triangle.fill", Color.dangerText)
                    Spacer()
                    zoneLabel("Caution", "minus.circle.fill", Color.warning)
                    Spacer()
                    zoneLabel("Good", "checkmark.circle.fill", Color.success)
                }

                Divider().overlay(Color.surfaceBorder)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(OwnerBriefingCopy.satisfactionTitle(owner.satisfaction))
                        .font(DSType.text(14, .semibold))
                        .foregroundStyle(OwnerBriefingCopy.satisfactionColor(owner.satisfaction))
                    Text(OwnerBriefingCopy.satisfactionBody(owner))
                        .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Color.surfaceBorder)

                let security = OwnerPersonaEngine.jobSecurity(owner: owner, career: career)
                HStack {
                    Label("Job Security", systemImage: "shield.lefthalf.filled")
                        .font(DSType.text(14, .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(security.level.label)
                        .font(DSType.text(14, .bold))
                        .foregroundStyle(OwnerBriefingCopy.jobSecurityColor(security.level))
                }
                meter(
                    fraction: Double(security.score) / 100.0,
                    color: OwnerBriefingCopy.jobSecurityColor(security.level),
                    height: 8
                )
            }
        }
    }

    private func zoneLabel(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(DSType.display(11, .semibold))
            .foregroundStyle(color)
    }

    private func meter(fraction: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(Color.backgroundTertiary)
                    .frame(height: height)
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(max(fraction, 0), 1), height: height)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Last season review

struct OwnerLastReviewCard: View {

    let review: OwnerPersonaEngine.OwnerSeasonReview

    var body: some View {
        OwnerCard(
            icon: "doc.text.magnifyingglass",
            title: "Last Season Review (\(String(review.seasonYear)))",
            trailing: AnyView(
                Text(review.verdict.label.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.5)
                    .foregroundStyle(verdictColor)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, 3)
                    .background(verdictColor.opacity(0.15), in: Capsule())
            )
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("\(review.finalRecord) \u{2022} \(review.goalsAchieved)/\(max(review.goalsTotal, 1)) goals met")
                    .font(DSType.text(14, .semibold))
                    .foregroundStyle(Color.textSecondary)

                Text("\u{201C}\(review.summary)\u{201D}")
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .italic()
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var verdictColor: Color {
        switch review.verdict {
        case .bonus:   return .accentGold
        case .praise:  return .success
        case .neutral: return .textSecondary
        case .warning: return .warning
        case .fired:   return .dangerText
        }
    }
}

// MARK: - Warning

struct OwnerWarningCard: View {

    let owner: Owner
    let career: Career

    private var isCritical: Bool { owner.satisfaction < 35 }
    private var accent: Color { isCritical ? Color.dangerText : Color.warning }

    var body: some View {
        OwnerCard(
            icon: "exclamationmark.triangle.fill",
            title: isCritical ? "Your Job Is In Danger" : "Owner Is Concerned",
            accent: accent
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(OwnerBriefingCopy.warnings(owner: owner, career: career), id: \.self) { message in
                    HStack(alignment: .top, spacing: DSSpacing.xs) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accent)
                            .padding(.top, 2)
                        Text(message)
                            .font(DSType.text(14, .regular, prose: true))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
