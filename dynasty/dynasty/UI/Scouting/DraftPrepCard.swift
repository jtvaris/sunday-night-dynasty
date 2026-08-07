import SwiftUI

// MARK: - Prep chips

/// The three facts that decide whether a name on the board is a scouting
/// decision or a scouting hole: tape filed, room taken, numbers measured.
///
/// Rendered as three fixed slots rather than as "show what exists", because the
/// question the user is asking down a board is *who have I not done the work
/// on* — and an absent icon answers that far worse than a dimmed one.
struct ProspectPrepChips: View {
    let prospect: CollegeProspect
    /// Drops the report count digit for very tight rows.
    var compact: Bool = false

    private var status: DraftIntel.PrepStatus { DraftIntel.prepStatus(for: prospect) }

    var body: some View {
        let prep = status
        HStack(spacing: 3) {
            chip(
                icon: "doc.text.fill",
                filled: prep.reportCount > 0,
                tint: prep.reportCount >= 2 ? Color.success : Color.accentBlue,
                badge: (compact || prep.reportCount == 0) ? nil : "\(prep.reportCount)"
            )
            chip(
                icon: "bubble.left.and.bubble.right.fill",
                filled: prep.isInterviewed,
                tint: Color.accentBlue,
                badge: nil
            )
            chip(
                icon: "stopwatch.fill",
                filled: prep.hasMeasurables,
                tint: Color.accentGold,
                badge: nil
            )
            if prep.hasProDay {
                chip(icon: "figure.run", filled: true, tint: Color.success, badge: nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(prep))
    }

    @ViewBuilder
    private func chip(icon: String, filled: Bool, tint: Color, badge: String?) -> some View {
        HStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro))
            if let badge {
                Text(badge)
                    .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
            }
        }
        .foregroundStyle(filled ? tint : Color.textTertiary.opacity(0.35))
    }

    private func accessibilityText(_ prep: DraftIntel.PrepStatus) -> String {
        if prep.isUntouched { return "No scouting work done on this prospect" }
        var parts: [String] = []
        parts.append(prep.reportCount == 0
                     ? "no reports"
                     : "\(prep.reportCount) report\(prep.reportCount == 1 ? "" : "s")")
        parts.append(prep.isInterviewed ? "interviewed" : "not interviewed")
        parts.append(prep.hasMeasurables ? "measured" : "no measurables")
        if prep.hasProDay { parts.append("pro day attended") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Draft prep card

/// "Am I ready for this draft?" — one collapsible card at the top of the
/// Scouting hub.
///
/// Every number below is read off stored state (filed reports, the interview
/// counter on `Career`, the combine trip flag, scout pro-day tallies, the
/// owner's scouting pot). Nothing here is a phase-derived guess at progress:
/// if the card says 41 % of the top 100 is scouted, forty-one of those hundred
/// men carry a `ScoutingReport`.
struct DraftPrepCard: View {
    let career: Career
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    let scouts: [Scout]
    let scoutsSentToCombine: Bool
    /// Thousands left in the owner's scouting pot after salaries, the combine
    /// trip and this cycle's per-prospect evaluations.
    let scoutingBudgetRemaining: Int
    /// Per-prospect scout evaluations spent this cycle (`ScoutEvaluationBudget`).
    var evaluationsUsed: Int = 0
    /// Jumps the hub to a tab (used by the position-coverage rows).
    var onSelectTab: ((ScoutingTab) -> Void)? = nil
    /// Applies a position filter to the hub's shared chips.
    var onFilterPosition: ((ProspectPositionFilter) -> Void)? = nil

    /// Collapsed by default.
    ///
    /// The card used to default to expanded and it alone ate ~180 pt at the top
    /// of a screen whose job is a scrolling list. Collapsed it is one line of
    /// stage progress, which is what the user actually needs at a glance; the
    /// detail is one tap away and the preference sticks.
    ///
    /// A NEW key on purpose: `draftPrepCardExpanded` is already `true` in every
    /// existing save's defaults, and `@AppStorage`'s default only applies to an
    /// absent key — flipping the literal would have changed nothing for anybody
    /// who has ever opened this screen.
    @AppStorage("draftPrepCardExpandedV2") private var isExpanded: Bool = false
    /// Observed so starring a prospect on another tab re-derives the
    /// "on your board, never interviewed" rows instead of going stale.
    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared

    /// The cycle rations live on ``DraftPrepProgress`` now. Four screens each
    /// carried a private `let maxInterviews = 60`, which is how the prep card,
    /// the stage banner and the required task could each print a different
    /// denominator for the same sixty slots.
    private var maxInterviews: Int { DraftPrepProgress.interviewSlots }
    private let topSliceSize = 100

    // MARK: - Derived state

    private var interviewsRemaining: Int {
        max(0, maxInterviews - career.interviewsUsed)
    }

    /// Focus slots **reserved** — `scout.proDayColleges`, the ledger the tour
    /// screen fills and the stage banner counts. Not `proDaysAttended`, which
    /// only moves once `attendProDay` has run and therefore printed "0 of 11
    /// focus slots used" on a card sitting next to a screen showing five
    /// schools booked.
    private var proDayReservations: Int {
        scouts.reduce(0) { $0 + $1.proDayColleges.count }
    }

    /// Schools the department has actually been to this cycle.
    private var proDayVisits: Int {
        scouts.reduce(0) { $0 + $1.proDaysAttended }
    }

    private var proDayCapacity: Int {
        scouts.reduce(0) { $0 + $1.maxProDays }
    }

    /// Interview slots only mean something while the window is open.
    private var interviewWindowOpen: Bool {
        career.currentPhase == .combine || career.currentPhase == .proDays
    }

    private var evaluationsRemaining: Int {
        max(0, ScoutEvaluationBudget.slotsPerCycle - evaluationsUsed)
    }

    private var evaluationWindowOpen: Bool {
        ScoutEvaluationBudget.isWindowOpen(career.currentPhase)
    }

    // MARK: - Phase copy

    private var phaseHeadline: String {
        switch career.currentPhase {
        case .coachingChanges, .reviewRoster:
            return "Pre-combine"
        case .combine:
            return "Combine week"
        case .freeAgency:
            return "Free agency"
        case .proDays:
            return "Pro days"
        case .draft:
            return "Draft week"
        case .regularSeason, .tradeDeadline, .playoffs:
            return "Autumn tape"
        default:
            return "Draft prep"
        }
    }

    private var phaseSubtitle: String {
        switch career.currentPhase {
        case .coachingChanges, .reviewRoster:
            // Film study is calendar-locked until the combine window opens
            // (prepCalendarRank == 0 here), so this must read as waiting, not
            // as an invitation to file reports the board will refuse.
            return "The combine is next on the calendar. Film, interviews and the department trip all open in Indianapolis."
        case .combine:
            return "Indianapolis. Interviews and the department trip are both one-window offers."
        case .freeAgency:
            return "The class keeps. Pro days and Top-30 visits are still ahead of you."
        case .proDays:
            return "Last hands-on look: pro days, private workouts, Top-30 visits."
        case .draft:
            return "Anything unscouted now goes on the clock unscouted."
        case .regularSeason, .tradeDeadline, .playoffs:
            return "The class is on the board but the chequebook is shut. Reports open at the combine."
        default:
            return "The board keeps between cycles \u{2014} coverage carries into draft week."
        }
    }

    // MARK: - Needs attention

    /// One actionable gap. Either a specific man (tap → his card) or a position
    /// group (tap → the board, filtered to it).
    struct AttentionItem: Identifiable {
        enum Target {
            case prospect(CollegeProspect)
            case position(ProspectPositionFilter)
        }
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        let target: Target
    }

    /// Everything the card renders, derived once.
    ///
    /// A draft class is ~350 rows and each of `consensusTop`, `boardCoverage`
    /// and `needCoverage` sorts or re-walks it; computing them as bare
    /// properties meant five full passes per body evaluation, on a card that
    /// sits above a scrolling list. One pass, one struct.
    private struct Snapshot {
        let coverage: DraftIntel.BoardCoverage
        let attention: [AttentionItem]
        /// The stage ledger, built once here so the card's collapsed line and
        /// the hub's process bar print the same counter for the same stage.
        let progress: DraftPrepProgress
    }

    private func makeSnapshot() -> Snapshot {
        let topSlice = DraftIntel.consensusTop(prospects, count: topSliceSize)
        let coverage = DraftIntel.BoardCoverage(
            sampleSize: topSlice.count,
            // Own reports only — the inherited "Previous Staff" freebie covers
            // the whole top slice on a fresh save, and the hub header three
            // inches up already counts hasOwnReport (#124).
            scouted: topSlice.filter { ProspectFog.hasOwnReport($0) }.count,
            interviewed: topSlice.filter(\.interviewCompleted).count
        )
        let progress = DraftPrepProgress(career: career, prospects: prospects, scouts: scouts)
        return Snapshot(
            coverage: coverage,
            attention: attentionItems(topSlice: topSlice, progress: progress),
            progress: progress
        )
    }

    private func attentionItems(
        topSlice: [CollegeProspect],
        progress: DraftPrepProgress
    ) -> [AttentionItem] {
        var items: [AttentionItem] = []

        // Report gaps are only actionable while a report can actually be
        // ordered. Pre-combine the board holds film study shut, so "no report
        // filed — 1 to fix" over a waiting screen was the #107 contradiction
        // in card form: a nag with no button behind it.
        let filmWindowOpen = progress.canAct(.filmStudy)

        // 1. The best men nobody has filed a word on. Worst gap there is, so it
        //    goes first and gets the most slots.
        if filmWindowOpen {
            let unscoutedElite = topSlice.prefix(32).filter { !ProspectFog.hasOwnReport($0) }
            for prospect in unscoutedElite.prefix(3) {
                items.append(AttentionItem(
                    id: "unscouted-\(prospect.id.uuidString)",
                    icon: "doc.badge.ellipsis",
                    tint: .danger,
                    title: "\(prospect.fullName) \u{00B7} \(prospect.position.rawValue)",
                    detail: "Top-32 consensus, no report filed",
                    target: .prospect(prospect)
                ))
            }
        }

        // 2. Men the user has flagged for himself but never met. Only while the
        //    room is actually open — nagging about an interview in October is
        //    noise, not a task.
        if interviewWindowOpen && interviewsRemaining > 0 {
            // ONE mark system: Elite and Target are the two tiers that mean "I
            // want this man". This used to read `prospectFlag` OR the star
            // store — two of the four parallel opinions — so a prospect marked
            // on the third or fourth never produced a nag at all.
            let markedUnmet = prospects.filter { prospect in
                guard !prospect.interviewCompleted else { return false }
                return prospect.userMark.isBoardPositive
            }
            .sorted { lhs, rhs in
                // Elite first, then by where the media has him.
                if lhs.userMark.sortRank != rhs.userMark.sortRank {
                    return lhs.userMark.sortRank < rhs.userMark.sortRank
                }
                return (lhs.draftProjection ?? 9) < (rhs.draftProjection ?? 9)
            }
            for prospect in markedUnmet.prefix(2) {
                items.append(AttentionItem(
                    id: "unmet-\(prospect.id.uuidString)",
                    icon: "bubble.left.and.bubble.right",
                    tint: .accentGold,
                    title: "\(prospect.fullName) \u{00B7} \(prospect.position.rawValue)",
                    detail: "Marked \(prospect.userMark.label), never interviewed",
                    target: .prospect(prospect)
                ))
            }
        }

        // 3. Need groups you are walking into the draft blind on. Same gate as
        //    the report gaps above: thin coverage is only fixable when a
        //    report can be ordered.
        if filmWindowOpen {
            let thinNeeds = DraftIntel.needCoverage(
                prospects: prospects,
                roster: teamRoster,
                topCount: topSliceSize
            ).filter(\.isThin)
            for need in thinNeeds.prefix(2) {
                items.append(AttentionItem(
                    id: "need-\(need.position.rawValue)",
                    icon: "exclamationmark.triangle.fill",
                    tint: .warning,
                    title: "\(need.position.rawValue) is a need \u{2014} thin coverage",
                    detail: "\(need.scouted) of \(need.onBoard) top-100 \(need.position.rawValue)s scouted",
                    target: .position(Self.filter(for: need.position))
                ))
            }
        }

        return Array(items.prefix(5))
    }

    private static func filter(for position: Position) -> ProspectPositionFilter {
        ProspectPositionFilter.allCases.first { $0 != .all && $0.matches(position) } ?? .all
    }

    // MARK: - Body

    var body: some View {
        if prospects.isEmpty {
            EmptyView()
        } else {
            let snapshot = makeSnapshot()
            VStack(alignment: .leading, spacing: 0) {
                header(snapshot)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        coverageRow(snapshot.coverage)
                        attentionSection(snapshot)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.surfaceBorder.opacity(0.7), lineWidth: 1)
            )
        }
    }

    private func header(_ snapshot: Snapshot) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Draft Prep")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.textPrimary)
                        Text(phaseHeadline.uppercased())
                            .font(.system(size: DSType.Size.micro, weight: .heavy))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                    }
                    if isExpanded {
                        Text(phaseSubtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    } else {
                        Text(collapsedSummary(snapshot))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !snapshot.attention.isEmpty {
                    Text("\(snapshot.attention.count)")
                        .font(.system(size: 9, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color.warning))
                        .accessibilityLabel("\(snapshot.attention.count) items need attention")
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse draft prep" : "Expand draft prep")
    }

    /// Collapsed, the card names the room the club is standing in and how much
    /// of it is done: "Pro Day Focus · 3/11 focus slots".
    ///
    /// **It no longer counts the stages.** It used to open with "Stage 4 of 9"
    /// and close with "3 of 9 stages done" — two of the three places the hub
    /// printed its position, over a gold capsule meter that was a fifth progress
    /// metaphor on one screen. The band head states the count once and the band
    /// itself IS the progress; this line says what the count cannot, which is
    /// the room's own currency (#105 wave 0).
    private func collapsedSummary(_ snapshot: Snapshot) -> String {
        let progress = snapshot.progress
        let step = progress.current
        var parts = [step.displayName]
        // `DraftPrepProgress`'s own counter string — but only when it IS a
        // count. For the read-only stages it is the word "Done", and a third
        // "Done" on a screen whose band already ticks the slat is the duplicate
        // #105 wave 0 exists to remove.
        if progress[step].isCounted { parts.append(progress[step].counter) }
        if !snapshot.attention.isEmpty {
            parts.append("\(snapshot.attention.count) to fix")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Coverage

    private func coverageRow(_ cover: DraftIntel.BoardCoverage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                stat(
                    icon: "doc.text.magnifyingglass",
                    value: "\(cover.scoutedPercent)%",
                    label: "Top \(cover.sampleSize) scouted",
                    tint: cover.scoutedPercent >= 60 ? .success
                        : cover.scoutedPercent >= 25 ? .accentGold : .danger,
                    detail: "\(cover.scouted)/\(cover.sampleSize)"
                )
                stat(
                    icon: "bubble.left.and.bubble.right.fill",
                    value: "\(career.interviewsUsed)/\(maxInterviews)",
                    label: interviewWindowOpen ? "Interviews used" : "Interviews (window shut)",
                    tint: interviewWindowOpen
                        ? (interviewsRemaining == 0 ? .textSecondary : .accentBlue)
                        : .textTertiary,
                    detail: "\(cover.interviewedPercent)% of top \(cover.sampleSize)"
                )
                stat(
                    icon: scoutsSentToCombine ? "binoculars.fill" : "tv",
                    value: scoutsSentToCombine ? "On site" : "TV",
                    label: "Combine",
                    tint: scoutsSentToCombine ? .success : .textTertiary,
                    detail: scoutsSentToCombine ? "Exact numbers" : "Rounded numbers"
                )
                stat(
                    icon: "figure.run",
                    value: "\(proDayReservations)/\(max(proDayCapacity, proDayReservations))",
                    label: proDayVisits > 0 ? "Pro day slots (sent)" : "Pro day slots",
                    tint: proDayReservations > 0 ? .accentBlue : .textTertiary,
                    detail: "\(career.top30VisitsUsed)/\(DraftPrepProgress.top30Slots) Top-30"
                )
                stat(
                    icon: "magnifyingglass",
                    value: "\(evaluationsUsed)/\(ScoutEvaluationBudget.slotsPerCycle)",
                    label: evaluationWindowOpen ? "Evaluations used" : "Evaluations (window shut)",
                    tint: evaluationWindowOpen
                        ? (evaluationsRemaining == 0 ? .warning : .accentGold)
                        : .textTertiary,
                    detail: evaluationsRemaining == 0
                        ? "None left this cycle"
                        : "\(evaluationsRemaining) left"
                )
                stat(
                    icon: "dollarsign.circle",
                    value: "$\(scoutingBudgetRemaining)K",
                    label: "Scouting budget",
                    tint: scoutingBudgetRemaining <= 0 ? .danger
                        : scoutingBudgetRemaining < 500 ? .warning : .success,
                    detail: "\(scouts.count) on staff"
                )
            }
        }
    }

    private func stat(icon: String, value: String, label: String, tint: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 12, weight: .heavy).monospacedDigit())
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minWidth: 104, alignment: .leading)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value), \(detail)")
    }

    // MARK: - Needs attention

    @ViewBuilder
    private func attentionSection(_ snapshot: Snapshot) -> some View {
        let items = snapshot.attention
        VStack(alignment: .leading, spacing: 4) {
            Text(items.isEmpty ? "NOTHING OUTSTANDING" : "NEEDS ATTENTION")
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .foregroundStyle(Color.textTertiary)

            if items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.success)
                    Text(emptyAttentionCopy(snapshot.coverage))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 3)
            } else {
                ForEach(items) { item in
                    attentionRow(item)
                }
            }
        }
    }

    private func emptyAttentionCopy(_ cover: DraftIntel.BoardCoverage) -> String {
        if cover.scouted == 0 {
            return "No draft class intel yet \u{2014} hire scouts and file your first reports."
        }
        return "Every top-32 name has a report and your board is covered."
    }

    @ViewBuilder
    private func attentionRow(_ item: AttentionItem) -> some View {
        switch item.target {
        case .prospect(let prospect):
            NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                attentionRowLabel(item, prospect: prospect)
            }
            .buttonStyle(.plain)
        case .position(let filter):
            Button {
                onFilterPosition?(filter)
                onSelectTab?(.board)
            } label: {
                attentionRowLabel(item, prospect: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func attentionRowLabel(_ item: AttentionItem, prospect: CollegeProspect?) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.icon)
                .font(.system(size: 10))
                .foregroundStyle(item.tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let prospect {
                ProspectPrepChips(prospect: prospect, compact: true)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundTertiary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
