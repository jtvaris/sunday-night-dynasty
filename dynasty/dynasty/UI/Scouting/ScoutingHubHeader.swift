import SwiftUI

// MARK: - Stage gate

/// Everything the hub needs to know about the stage the club is standing in:
/// what finishes it, what advancing costs, and who owns the button.
///
/// The prep is a staged pipeline (``DraftPrepStep``) with forced transitions,
/// and the transition is the ONE place a stage's batch action runs — that is
/// what makes the pro-day tour a single execution path instead of a button that
/// prints a receipt for work that already happened. Some stages advance from
/// the header (a review, a decision the hub can verify); the rest advance from
/// the screen that owns their action, and for those the header only opens the
/// tab.
struct ScoutingStageGate {

    /// Who owns the forward transition out of this stage.
    enum Action: Equatable {
        /// The header advances directly — nothing has to run first.
        case advance(next: DraftPrepStep)
        /// The stage's own screen owns the advance, because the advance also
        /// runs the stage's batch action (the pro-day tour, a workout, a visit).
        case open(tab: ScoutingTab, next: DraftPrepStep)
        /// End of the pipeline.
        case none
    }

    let step: DraftPrepStep
    let action: Action
    /// Whether the stage's completion predicate is satisfied.
    let isComplete: Bool
    /// What the user still has to do, in one sentence.
    let requirement: String
    /// What walking past this stage costs him, in one sentence. Every stage is
    /// skippable; none of them is silently skippable.
    let skipCost: String
    /// `true` when the next stage belongs to a phase the calendar has not
    /// reached. The stage machine never runs ahead of the season.
    let isPhaseBlocked: Bool
    let phaseBlockedReason: String

    var next: DraftPrepStep? {
        switch action {
        case let .advance(next):    return next
        case let .open(_, next):    return next
        case .none:                 return nil
        }
    }

    /// Whether the **header** may offer a Skip button for this stage.
    ///
    /// Only for `.advance` stages — the ones the hub can transition on its own.
    /// A `.open` stage's transition belongs to its screen, and for the pro-day
    /// tour that transition is *destructive*: `.proDayFocus` holds focus-slot
    /// reservations in `scout.proDayColleges` and `ProDayTourView` guards the
    /// skip behind an "Go in on tape?" alert. A 10 pt unconfirmed "Skip" in the
    /// header — drawn directly above that screen — threw the reservations away
    /// with one stray tap, and since `advancePrepStep` never lowers a step the
    /// tour could then never run and the required task could never complete.
    var offersHeaderSkip: Bool {
        if case .advance = action { return !isPhaseBlocked }
        return false
    }

    /// Builds the gate for the stage the club is standing in.
    ///
    /// **`isComplete` is no longer computed here.** It is
    /// `DraftPrepProgress.Stage.isSatisfied`, the one predicate the required
    /// task in the left bar, the process bar's tick and this button all read.
    /// The shipped build had this function holding one copy of those tests and
    /// `CareerShellView`'s completion switch holding another, keyed off
    /// different state — which is exactly how "Send Scouts to Combine —
    /// Required" stayed red forever while the department was in Indianapolis.
    /// What is left here is what belongs to the *view*: the requirement
    /// sentence, the price of skipping, and who owns the transition.
    static func make(progress: DraftPrepProgress, career: Career) -> ScoutingStageGate {
        let step = progress.current
        let next = step.next
        let row = progress[step]

        // A stage whose successor belongs to a later phase cannot be advanced
        // out of: the pro days are not open in combine week, and free agency
        // freezes the prep entirely (the market has its own step machine).
        let blocked: Bool = {
            guard let next else { return false }
            return next.phase.prepCalendarRank > career.currentPhase.prepCalendarRank
        }()
        let blockedReason: String = {
            guard let next else { return "" }
            switch next.phase {
            case .proDays: return "The pro-day circuit does not open until the pro-day window."
            case .draft:
                // `.mockTwo` is the last stop of the spring and it ends in a
                // wait, not in a button: the Final Mock is printed with the
                // draft order, which is a league event on a fixed date.
                return step == .mockTwo
                    ? "The final mock is printed with the draft order \u{2014} the room opens in draft week."
                    : "The draft room opens in draft week."
            default:       return "Not yet on the calendar."
            }
        }()

        let action: Action = {
            guard let next else { return .none }
            switch step {
            case .combineReview, .interviews, .filmStudy:
                return .advance(next: next)
            case .proDayFocus:  return .open(tab: .proDays, next: next)
            case .workouts:     return .open(tab: .workouts, next: next)
            case .mockOne:      return .open(tab: .mockDraft, next: next)
            case .top30Visits:  return .open(tab: .top30, next: next)
            case .mockTwo:      return .open(tab: .mockDraft, next: next)
            case .ready:        return .none
            }
        }()

        let requirement: String
        let skipCost: String

        switch step {
        case .combineReview:
            requirement = row.isSatisfied
                ? "Numbers read. The spring is yours."
                : "Open the Combine tab and read the numbers."
            skipCost = "You go into the spring on the broadcast's rounded times."
        case .interviews:
            requirement = row.isSatisfied
                ? "\(row.counter) used. Advance when you are done in the room."
                : "Put at least one prospect in a room \u{2014} \(row.counter)."
            skipCost = "Nobody in the building has met this class \u{2014} the MEET column stays empty."
        case .filmStudy:
            requirement = "Order film study on \(DraftPrepProgress.filmStudyThreshold) men \u{2014} \(row.counter)."
            skipCost = "Your board stays the media's board: no reports, no bands of your own."
        case .proDayFocus:
            // RESERVATIONS, not executions. `scout.proDayColleges` is the ledger
            // the tour screen fills and the advance button spends;
            // `proDaysAttended` is written by `attendProDay`, i.e. only *after*
            // the tour has run — by which point the stage has already closed.
            requirement = row.isSatisfied
                ? "\(row.counter) reserved \u{2014} send the department out from the Pro Days tab."
                : "Reserve at least one school for the department."
            skipCost = "Every pro-day number you get is the broadcast's \u{2014} no decimals, no reports."
        case .workouts:
            requirement = row.isSatisfied
                ? "\(row.counter) run."
                : "Work at least one prospect out privately \u{2014} \(row.counter)."
            skipCost = "The highest-fidelity look in the game goes unspent."
        case .mockOne:
            requirement = "Read where the league has your board."
            skipCost = "You will not see the consensus move before the visits."
        case .top30Visits:
            requirement = row.isSatisfied
                ? "\(row.counter) hosted."
                : "Host at least one prospect at the facility \u{2014} \(row.counter)."
            skipCost = "Medical and character files stay half-open on men you never brought in."
        case .mockTwo:
            // The only stage whose forward transition the calendar owns: `.ready`
            // is draft week. Reading it is still a real act, so it is recorded —
            // otherwise the last stage of the spring was a button that visibly
            // did nothing, forever, with no chip and no acknowledgement.
            requirement = row.isSatisfied
                ? "Read. The room opens on the clock."
                : "Read the last mock the league has printed."
            skipCost = "You walk into the room without the last read on the market."
        case .ready:
            requirement = "The board is closed. Draft."
            skipCost = ""
        }

        return ScoutingStageGate(
            step: step,
            action: action,
            isComplete: row.isSatisfied,
            requirement: requirement,
            skipCost: skipCost,
            isPhaseBlocked: blocked,
            phaseBlockedReason: blockedReason
        )
    }
}

// MARK: - Hub header

/// The scroll-away header of the scouting hub.
///
/// It is passed BY CLOSURE into each list surface and rendered as that
/// surface's **first section** — it never wraps a surface. That is the whole
/// trick behind the full-page scroll: the hub used to be a `VStack` of metrics
/// strip → prep card → combine CTA → tab picker → chips → `Divider` → list, and
/// everything above the list was outside the scroll view permanently, so a
/// landscape iPad showed three prospect rows. A `ScrollView` around the hub is
/// illegal (`BigBoardView` and the combine table own `List`s, and a `List`
/// inside a `ScrollView` collapses), and flattening a 3000-line `List` into a
/// `LazyVStack` would destroy `.onMove`, which is the board's whole reordering
/// interaction. Moving the header inside the list keeps one scroll owner per
/// surface, one gesture, and every interaction intact.
///
/// Nothing in here may read an uncached computed property: it is a `Section` of
/// one row inside a list that re-evaluates on every `@State` touch.
struct ScoutingHubHeader: View {
    let career: Career
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    let scouts: [Scout]
    let scoutsSentToCombine: Bool
    let scoutingBudgetRemaining: Int
    let evaluationsUsed: Int
    /// Share of the class this club has filed a report on, computed by the hub.
    let scoutedPercent: Int
    let phaseLabel: String
    var onSelectTab: (ScoutingTab) -> Void
    var onFilterPosition: (ProspectPositionFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metricsStrip
            DraftPrepCard(
                career: career,
                prospects: prospects,
                teamRoster: teamRoster,
                scouts: scouts,
                scoutsSentToCombine: scoutsSentToCombine,
                scoutingBudgetRemaining: scoutingBudgetRemaining,
                evaluationsUsed: evaluationsUsed,
                onSelectTab: onSelectTab,
                onFilterPosition: onFilterPosition
            )
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - Metrics strip
    //
    // Four tiles became two. "Scouts 3/8" duplicated the Scout Team tab and the
    // prep card's budget tile, and "Top: Smith (B+)" named a man the board's
    // first row already names. What is left is the one number that says whether
    // the spring is going well and the one word that says what week it is.

    private var metricsStrip: some View {
        HStack(spacing: 10) {
            metricItem(
                icon: "doc.text.magnifyingglass",
                label: "\(scoutedPercent)% scouted",
                color: scoutedPercent >= 40 ? .success : scoutedPercent >= 15 ? .accentGold : .textSecondary
            )
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(width: 1, height: 14)
            metricItem(icon: "calendar", label: phaseLabel, color: .textSecondary)
            Spacer(minLength: 0)
            Text("\(career.prepStep.order + 1)/\(DraftPrepStep.allCases.count)")
                .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.textTertiaryReadable)
                .accessibilityLabel("Stage \(career.prepStep.order + 1) of \(DraftPrepStep.allCases.count)")
        }
        .frame(height: 28)
        .padding(.horizontal, 12)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricItem(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Stage banner (deleted)
    //
    // The banner — stage name, requirement, Advance, Skip — lived here, i.e.
    // inside the FIRST SECTION of a 350-row list. Everything it said is now in
    // the hub's pinned chrome: the process bar draws the stage and its state,
    // the explainer card draws what the stage buys, and `DraftPrepAdvanceBar`
    // draws the transition where a transition belongs. Four copies of the same
    // pipeline (banner, compact strip, prep-card summary, tab picker) collapsed
    // into one.
}
