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

    /// The one patience band table. The priorities row and the patience card
    /// sit on the same screen a few hundred points apart and used to band
    /// differently: patience 4 was "about average — steady progress" in the row
    /// and "wants results sooner rather than later" in the card. Every patience
    /// readout asks this instead.
    ///
    /// The breaks come from the league average the row already quotes: with an
    /// average of 5 seasons, 4–6 is the middle of the league, which is what
    /// makes 4 average rather than impatient.
    enum PatienceBand {
        case shortFuse
        case average
        case patient
    }

    static func patienceBand(_ value: Int) -> PatienceBand {
        if value <= 3 { return .shortFuse }
        if value <= 6 { return .average }
        return .patient
    }

    static func patienceImplication(_ owner: Owner) -> String {
        let leagueAvg = 5
        let comparison: String
        let tail: String
        switch patienceBand(owner.patience) {
        case .shortFuse:
            comparison = "Less patient than most owners"
            tail = "Win fast or face consequences."
        case .average:
            comparison = "About average patience"
            tail = "Steady progress expected each year."
        case .patient:
            comparison = "More patient than most owners"
            tail = "Time to build through the draft."
        }
        return "League avg: \(leagueAvg) seasons \u{2014} \(comparison). \(tail)"
    }

    static func budgetImplication(_ owner: Owner) -> String {
        let budgetM = money(owner.coachingBudget)
        let leagueAvgM = "$38.0M"
        // The 25 / 50 / 75 breaks are `spendingLabel`'s. Label and explainer are
        // printed as one row, and on their own breaks the 50–60 band was handed
        // the headline "Willing to Spend" over the tail "Modest spending".
        let tail: String
        switch owner.spendingWillingness {
        case ...24:   tail = "Build through the draft \u{2014} free agency will be tight."
        case 25...49: tail = "Modest spending \u{2014} be strategic with signings."
        case 50...74: tail = "Significant resources for roster upgrades."
        default:      tail = "Money is no object \u{2014} the owner backs any move."
        }
        // The figure is the COACHING pot and the tail is about players. Printed
        // as one sentence ("Budget: $47.0M … be strategic with signings") they
        // read as one pot, so the staff envelope looked like the money that buys
        // free agents — which is cap room, on the screen after this one.
        return "\(tail) Coaching staff budget: \(budgetM) (league avg: \(leagueAvgM)), separate from the cap."
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
        switch patienceBand(value) {
        case .patient:
            return "This owner is patient and will give you time to build a winner through any strategy."
        case .average:
            return "The owner expects steady improvement every season. Missing the playoffs repeatedly will cost you."
        case .shortFuse:
            return "This owner has a short fuse. You need wins now or your tenure will be brief."
        }
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
        switch patienceBand(value) {
        case .patient:   return Color.success
        case .average:   return Color.warning
        case .shortFuse: return Color.dangerText
        }
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
    ///
    /// #177: the head *glyph* used to fall back to gold even though the head
    /// *word* right beside it already fell back to `textSecondary`, which is
    /// the audit's own complaint verbatim — "all section header icons are the
    /// same yellow tint and same size — they compete for attention instead of
    /// guiding it". Glyph and word now share one fallback.
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
                    .foregroundStyle(accent ?? Color.textSecondary)
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
///
/// **Blue, not gold** (#177). P5 gives gold three jobs — commit fill,
/// current-step marker, live indicator — and a link to another screen is none
/// of them. The audit recorded this exact one: *"'View All' gold pill — same
/// gold as every other CTA; tone down for nav links."* Blue is
/// "informational / selected" (P7), which is what going somewhere to read more
/// is; the gold on this surface belongs to whatever the hosting screen commits
/// with, and there is exactly one of those.
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
            .foregroundStyle(Color.accentBlue)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A label / value line inside a card.
///
/// The leading glyph is a **bullet, not a highlight** (#177): it identifies the
/// subject and the VALUE carries whatever verdict there is. Painting all four
/// of them gold put a column of primaries down a card whose actual reading is
/// in the right-hand column.
private struct OwnerFactRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .textPrimary

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiaryReadable)
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
                    .foregroundStyle(Color.textTertiary)
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
                // The eyebrow names the scene; it is not the current step of a
                // band and not a live indicator, so it is a tracked
                // `textSecondary` ident like every other section head (§2.9).
                Text("OWNER MEETING")
                    .font(DSType.display(DSType.Size.footnote, .black))
                    .tracking(4)
                    .foregroundStyle(Color.textSecondary)
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

    /// Which kind of owner this is — a category with no verdict attached, so it
    /// takes the informational hue (P7) rather than the primary one (#177).
    private var archetypeBadge: some View {
        let archetype = OwnerPersonaEngine.OwnerArchetype.from(owner)
        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: archetype.icon)
                .font(.system(size: 10))
            Text(archetype.displayName.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.5)
        }
        .foregroundStyle(Color.accentBlue)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 3)
        .background(Color.accentBlue.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentBlue.opacity(0.4), lineWidth: 1))
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
                // Two categories, neither of them better than the other and
                // neither a threshold — so no ladder colour and no accent
                // (P7 rule 2). "Win Now" was gold, which read as the good one.
                valueColor: Color.textPrimary,
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

    var body: some View {
        OwnerCard(icon: "hourglass", title: "Owner Patience") {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: 0) {
                    statColumn(
                        label: "Patience",
                        value: "\(owner.patience)/10",
                        color: OwnerBriefingCopy.patienceColor(owner.patience)
                    )
                    // `OwnerPersonaEngine.evaluateSeason` runs once a year, in
                    // the `.superBowl` phase, for every owner — patience sets
                    // how harsh the verdict is, not how long until it comes.
                    // This column used to print `patience - yearsFired`, a
                    // countdown that could never move: `yearsFired` is
                    // incremented at the moment the coach is fired, and that
                    // same moment ends the career.
                    statColumn(
                        label: "Owner review",
                        value: "Every Season",
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

    /// The sum of what the three columns SHOW, not the exact sum rounded once.
    /// Each column rounds to a tenth of a million on its own, so a total
    /// rounded independently can print a figure the columns visibly contradict:
    /// $47.0M + $4.1M + $2.8M under a head that read $53.8M.
    private var shownTotal: String {
        let shown = [owner.coachingBudget, owner.scoutingBudget, owner.medicalBudget]
            .reduce(0.0) { $0 + (Double(String(format: "%.1f", Double($1) / 1_000.0)) ?? 0) }
        return String(format: "$%.1fM", shown)
    }

    var body: some View {
        OwnerCard(
            icon: "dollarsign.circle.fill",
            title: "Staff Budget Envelope",
            trailing: AnyView(
                Text(shownTotal)
                    .font(DSType.display(DSType.Size.callout, .heavy))
                    .foregroundStyle(Color.textPrimary)
            )
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // Three sums of money, none of them a verdict and none of them
                // on a 0–100 ladder — so no colour at all (P7 rule 2). They
                // shipped gold / blue / green, which said "coaching is the
                // primary one" and "medical is the good one" (#177).
                HStack(spacing: 0) {
                    potColumn(label: "Coaching", value: owner.coachingBudget)
                    potColumn(label: "Scouting", value: owner.scoutingBudget)
                    potColumn(label: "Medical", value: owner.medicalBudget)
                }

                Divider().overlay(Color.surfaceBorder)

                // TODO §5.4: the facilities envelope is a separate pot from the
                // three above, and the owner meeting is where he says what he
                // thinks of the buildings he pays for. The quote names a fourth
                // figure inside a card whose total excludes it, so the label
                // says so before he speaks.
                Text("FACILITIES \u{00B7} SEPARATE ENVELOPE")
                    .font(DSType.display(11, .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.textTertiaryReadable)

                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
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

    private func potColumn(label: String, value: Int) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Text(OwnerBriefingCopy.money(value))
                .font(DSType.display(DSType.Size.callout, .heavy))
                .foregroundStyle(Color.textPrimary)
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

    /// Whether the season has produced anything for the counter to count. The
    /// intro's briefing builds both goals unmet and untracked, so the first
    /// owner meeting of a career headed itself "0/2 met" — a zero score for a
    /// season nobody has played yet.
    private var hasReading: Bool {
        goals.contains { $0.isAchieved || $0.progress != nil }
    }

    var body: some View {
        OwnerCard(
            icon: "target",
            title: "Season Goals",
            trailing: AnyView(
                Text(hasReading
                     ? "\(met)/\(goals.count) met"
                     : "\(goals.count) goal\(goals.count == 1 ? "" : "s")")
                    .font(DSType.display(DSType.Size.footnote, .heavy))
                    .foregroundStyle(Color.textSecondary)
            )
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // A met goal is a **state**, so it is `success` green, and a
                // PRIMARY goal is a rank, so it is a weight difference and not
                // a hue (#177). Both were gold, which put two more golds on a
                // screen that is allowed one and made "met" and "primary"
                // indistinguishable at a glance.
                ForEach(goals) { goal in
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: goal.isAchieved ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(goal.isAchieved ? Color.success : Color.textTertiary)
                        Text(goal.title)
                            .font(DSType.text(14, .regular, prose: true))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: DSSpacing.xs)
                        if let progress = goal.progress {
                            Text("\(progress.done)/\(progress.target)")
                                .font(DSType.display(DSType.Size.footnote, .heavy))
                                .foregroundStyle(goal.isAchieved ? Color.success : Color.textSecondary)
                        }
                        Text(goal.priorityLabel.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.5)
                            .foregroundStyle(goal.isPrimary ? Color.textSecondary : Color.textTertiaryReadable)
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
                    .foregroundStyle(Color.textTertiary)
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
        // The same surface every other card on the briefing sits on. The gold
        // wash and gold hairline were the card saying "I am the important one"
        // in the primary-action hue (#177); the italic quote and the warning
        // line say it in words, which is the only claim this card can make
        // honestly.
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
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

    /// Status colour means state (P7). A bonus and a praise are both "the owner
    /// is happy", so both are `success` and the badge's own word carries the
    /// degree — gold on `.bonus` was the money, not the state (#177).
    private var verdictColor: Color {
        switch review.verdict {
        case .bonus:   return .success
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
