import SwiftUI
import SwiftData

// MARK: - PreseasonView — three games, one decision each
//
// `docs/OFFSEASON_ROSTER_PLAN.md` §4 and §5 (#205b). Three sim-only games run
// as three **steps inside a single `.preseason` phase**, exactly the way free
// agency runs a six-day market inside `.freeAgency`. Nothing here touches
// `SeasonPhase`, `phase(after:)`, `TaskProgressStore` or `career.currentWeek`:
// the step machine lives in `PreseasonState.step` on the career blob, and this
// screen advances it the same way `FAWeeklyView` advances `freeAgencyStep`.
//
// **Invariant (1), stated where someone would break it.** Preseason ticks NO
// contracts. Three games look like three weeks and the temptation to age the
// deals here is exactly the #89 week-18 double-tick bug. The only place a
// contract clock moves is the week-18 tick and `executeNewLeagueYear`. This
// screen writes one thing to the career: the preseason blob.
//
// **The screen is a decision, not a button.** §4.2: the coach picks who dresses,
// and the pick is a real bet — scheme familiarity banked against injury
// exposure, three times, with the 75 → 65 → 53 ladder waiting at the end. The
// recap is the evidence that bet produced (`PreseasonRecapSheet`), and the
// bubble table behind it is what the 65 is written from.
//
// House rules honoured: `DSSlatBand` for the spine, `DSActionBar` as the only
// commit, `DSResultSheet` as the only ending, **one** `.sheet(item:)` slot,
// English-only copy on `DSType` tokens.
//
// MARK: The engine contract this screen is written against
//
// The engine half landed alongside this screen, and the surface it actually
// ships is the one this file now speaks to — `Domain/Models/Camp/PreseasonState.swift`
// (`PreseasonState`, `PreseasonStep`, `PreseasonMatchup`, `PreseasonResult`) and
// `Engine/Simulation/PreseasonEngine.swift`
// (`openPreseasonIfNeeded`, `simulateGame(career:matchup:policy:modelContext:)`,
// `recordResult`, `acknowledgeRecap`). The UI touches it in exactly four places:
// `seedFlowIfNeeded`, `playGame`, `advance` and `PreseasonRecap.init(result:…)`.
//
// Two shapes are worth stating here because they differ from the plan's sketch:
// the step machine is a `kind` + `gameIndex` STRUCT (stable persisted JSON, not
// an enum with associated values), and the policy the user chose rides on
// `PreseasonResult.policy` rather than in a parallel `policies` array — one
// authority, so the state and the recap can never disagree.
//
// The blob is persisted on `Career.preseasonData` and read through
// `Career.preseasonState`.
//
// `RosterStatus.campBody` (wave 0) is read once, in `PreseasonRecap`'s tier
// derivation.

struct PreseasonView: View {

    let career: Career
    /// The shell's opening snapshot, used until the first fetch lands — the
    /// same contract `RosterCutView` documents. A sim changes the roster
    /// (injuries), so the count on this screen has to be live or the 65 gate
    /// reads a stale number.
    let roster: [Player]
    /// Pushes the shell to the cut screen. The shell owns `navigationPath`, so
    /// the route is handed in rather than reached for — that keeps
    /// `CareerShellView`'s change to one line and this view previewable.
    var onOpenRosterCuts: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    @State private var liveRoster: [Player]?
    @State private var teamsByID: [UUID: Team] = [:]
    /// The persisted flow. Seeded on first appearance if the phase opened
    /// without one, and re-seeded if the blob is stamped for a previous season.
    @State private var flow: PreseasonState?
    /// The policy the user is about to commit for the game he is planning.
    @State private var selectedPolicy: PreseasonPolicy = .starterSeries
    @State private var isSimulating = false
    /// Why the last attempt to play produced nothing, if it did — surfaced in
    /// the action bar's explainer as a warning rather than swallowed.
    @State private var playFailure: String?
    /// `false` until the first fetch lands — see the `body`'s first branch.
    @State private var didLoad = false
    @State private var cohort: PreseasonBubbleTable.Cohort = .bubble
    /// The opponent for the game being planned. Cached — see `refreshFixture`.
    @State private var upcomingFixture: PreseasonMatchup?
    /// Built recaps, keyed by game index.
    ///
    /// Cached rather than derived in `body`: a recap sorts every stat line and
    /// resolves a starting lineup, and `body` reads them three times over (the
    /// band's outcomes, the band's tints, the table). It is rebuilt exactly
    /// when its inputs move — a game is played, the step advances, the roster
    /// is refetched.
    @State private var recapsByGame: [Int: PreseasonRecap] = [:]
    /// **The one modal slot** (house rule). Four stacked `.sheet` modifiers is
    /// the bug class that has bitten this codebase repeatedly: the later ones
    /// win and the earlier ones dismiss silently.
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case recap(PreseasonRecap)

        var id: Int {
            switch self {
            case let .recap(recap): return recap.gameIndex
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !didLoad {
                // The first render happens before `.task` runs. Without this
                // the screen flashes "Preseason is not open" for a frame on
                // every entry, which reads as a bug rather than as a load.
                Color.clear
            } else if flow != nil {
                PreseasonFlowBandView(
                    currentGame: currentGame,
                    stance: stance,
                    outcomes: bandOutcomes,
                    tints: bandTints,
                    gamesPlayed: recapsByGame.count
                )
                content
                actionBar
            } else {
                notInPreseason
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Preseason")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sheet(item: $activeSheet) { slot in
            switch slot {
            case let .recap(recap):
                PreseasonRecapSheet(
                    recap: recap,
                    // NOT `continueTitle(after:)`. This button dismisses and
                    // nothing else — the step only moves on the action bar
                    // behind it, which is §2.5's one commit — so printing the
                    // bar's words on it put two identical gold "Plan game 2"
                    // buttons on the screen at once, and the one the user
                    // reaches first does not plan game 2. It says what it does:
                    // it leaves the modal into the evidence.
                    continueTitle: "Read the tape",
                    onContinue: { activeSheet = nil }
                )
                // The sheet is the ending, and the evidence is behind it. It
                // must not be dismissable by drag: §2.6's rule is that a
                // process ends through its one commit.
                .interactiveDismissDisabled(true)
            }
        }
    }

    // MARK: - Derived flow position
    //
    // ONE place maps the persisted step onto what the band and the screen show.
    // Everything downstream reads these two, so a change to the engine's step
    // shape lands here and nowhere else.

    private var currentGame: Int {
        guard let flow else { return 1 }
        switch flow.step.kind {
        case .plan, .recap: return flow.step.gameIndex
        case .complete:     return PreseasonFlowBand.gameCount
        }
    }

    private var stance: PreseasonFlowBand.Stance {
        guard let flow else { return .planning }
        switch flow.step.kind {
        case .plan:     return .planning
        case .recap:    return .reviewing
        case .complete: return .complete
        }
    }

    /// Game indices with a payload, in order.
    private var playedIndices: [Int] {
        recapsByGame.keys.sorted()
    }

    private var bandOutcomes: [Int: String] {
        recapsByGame.mapValues { "\($0.resultLetter) \($0.scoreText)" }
    }

    private var bandTints: [Int: Color] {
        recapsByGame.reduce(into: [:]) { out, entry in
            // A tie leaves the slat's neutral rule, so the key is simply not
            // written — `DSSlat.tint` is documented as nil-means-neutral.
            if entry.value.didWin {
                out[entry.key] = Color.success
            } else if entry.value.didLose {
                out[entry.key] = Color.dangerText
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                switch stance {
                case .planning:  planningContent
                case .reviewing: reviewContent
                case .complete:  slateContent
                }
            }
            .padding(DSSpacing.md)
            // `wideMeasure`, centred. The screen's body is the tape — a
            // six-column table of every man the cut reaches — which is exactly
            // what that token is for; `contentMeasure` is the reading column
            // for a stack of prose cards. And the leading pin dumped all the
            // slack on one side, so a third of a portrait iPad was flat
            // background down the right edge while the band above and the
            // action bar below ran full width.
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Planning — the game card and the coach decision

    @ViewBuilder
    private var planningContent: some View {
        gameCard
        policyPicker
        rosterStanding
        // Who to dress for game 2 is a question about what the men have already
        // done, so the tape so far belongs on the page the decision is made on
        // — three cards and half an empty screen was not the evidence.
        if !playedIndices.isEmpty {
            slateCaseTable(title: "Across the slate so far")
        }
    }

    private var gameCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // No "GAME n OF 3" eyebrow. §2.1 gives the count exactly one home
            // and `PreseasonFlowBand` is it; the eyebrow printed the slate's
            // position a third time on the same screen, in gold, i.e. at higher
            // emphasis than the authority. The opponent is the card's headline.
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text(upcomingFixtureLabel)
                    .font(DSType.display(DSType.Size.title2, .heavy))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let opponent = upcomingOpponent {
                    DSStatusPill(
                        label: opponent.abbreviation,
                        tone: .neutral,
                        showsDot: false,
                        spokenLabel: "\(opponent.city) \(opponent.name)"
                    )
                }
            }

            Text(
                "Preseason results do not go in the book. What the game leaves behind is a "
                + "stat line for every man on the bubble \u{2014} and that is what the cut to 65 gets written from."
            )
            .font(DSType.text(14, .regular, prose: true))
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var policyPicker: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Who dresses")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 0) {
                ForEach(Array(PreseasonPolicy.pickerOrder.enumerated()), id: \.offset) { index, policy in
                    policyRow(policy)
                    if index < PreseasonPolicy.pickerOrder.count - 1 {
                        Divider().overlay(Color.surfaceBorder)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .cardBackground()
        }
    }

    private func policyRow(_ policy: PreseasonPolicy) -> some View {
        let isSelected = policy == selectedPolicy
        return Button {
            selectedPolicy = policy
        } label: {
            DSListRow(
                density: .study,
                portraitWidth: DSListColumn.position,
                affordance: .none
            ) {
                // A real radio, in the badge slot's own width. This was a
                // `DSRowBadge` whose unselected text was a literal space, so an
                // unchosen row rendered as an empty dark rectangle and the only
                // thing saying what WAS chosen was a gold fill — a colour cue
                // with no shape behind it, in the one colour P5 reserves for the
                // commit and the band's current slat.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: DSType.Size.callout, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
                    .accessibilityLabel(isSelected ? "Selected" : "Not selected")
            } identity: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: policy.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
                        Text(policy.displayTitle)
                            .font(DSType.text(16, .semibold, prose: true))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                    Text(policy.displayDetail)
                        .font(DSType.text(13, .regular, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } columns: {
                Spacer(minLength: DSSpacing.sm)
                // #208 FIX C — the two trade-off pills are SENTENCES, not the
                // 3-4 letter idents `DSListColumn.state` (76 pt) is sized for.
                // `dsColumn` shrinks then CLIPS, and `DSStatusPill` pins its own
                // width with `fixedSize`, so the shrink step never ran: "NO
                // FIRST-TEAM INSTALL" was clipped to its middle and butted
                // straight against the clipped middle of "NO STARTER RISK",
                // rendering as one run of nonsense ("IRST-TEAM INSO STARTER RIS")
                // on the row the user makes his decision from.
                //
                // So they leave the fixed-column grid: the pair is stacked at
                // the trailing edge at its own natural width (`fixedSize`), and
                // the flexible identity block gives way instead — which is the
                // one column `DSListRow` documents as the one that yields. The
                // row is `.study` density, so the two lines cost no height.
                //
                // Both pills ramp. Flat blue on all three installs beside a
                // green → orange → red risk ramp said only the cost varied, and
                // pointed the eye at the one row carrying the screen's only
                // green chip.
                VStack(alignment: .trailing, spacing: 3) {
                    DSStatusPill(label: policy.familiarityNote, tone: policy.familiarityTone, showsDot: false)
                    DSStatusPill(label: policy.riskNote, tone: policy.riskTone, showsDot: false)
                }
                .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(policy.displayTitle). \(policy.displayDetail)")
        .accessibilityValue("\(policy.familiarityNote), \(policy.riskNote)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Where the club stands against the rung that is actually due. Not a
    /// second ladder — `RosterCutView` owns the ladder; this is the one number
    /// the preseason decision is taken against.
    private var rosterStanding: some View {
        let count = activeRoster.count
        let over = max(0, count - preseasonExitCeiling)
        return HStack(spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("On the roster")
                    .font(DSType.display(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiaryReadable)
                Text("\(count)")
                    .font(DSType.display(DSType.Size.title2, .heavy))
                    .foregroundStyle(over > 0 ? Color.alertOrange : Color.textPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Season opens at")
                    .font(DSType.display(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiaryReadable)
                Text("\(preseasonExitCeiling)")
                    .font(DSType.display(DSType.Size.title2, .heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer(minLength: 0)
            Text(
                over > 0
                    ? "\(over) still to release before the phase closes."
                    : "You are already legal for the next rung."
            )
            .font(DSType.text(13, .regular, prose: true))
            .foregroundStyle(over > 0 ? Color.alertOrange : Color.textSecondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: Review — the evidence

    @ViewBuilder
    private var reviewContent: some View {
        if let built = recapsByGame[currentGame] {
            reviewHeader(built)
            moversCard(built)
            PreseasonBubbleTable(recap: built, cohort: $cohort)
            // The band's earlier slats are not navigable, so without this the
            // last game's box score is the only tape reachable from here.
            if playedIndices.count > 1 {
                slateCaseTable(title: "Across the slate")
            }
        } else {
            // The step says a game was played and no payload exists for it.
            // Rather than render an empty table that looks like a quiet game,
            // the screen says what happened and offers the way forward — the
            // action bar's primary re-plans this game.
            DSEmptyState(
                icon: "exclamationmark.triangle",
                title: "That game has no tape",
                message: "The result for game \(currentGame) is missing. Play it again to produce one."
            )
        }
    }

    private func reviewHeader(_ recap: PreseasonRecap) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // The band above says which game this is (§2.1), so the eyebrow says
            // only what it was played under — and it says it in the section-head
            // colour, because gold is the commit fill and the band's current
            // slat, never a header (P5).
            Text(recap.policy.displayTitle.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text(recap.scoreText)
                    .font(DSType.display(DSType.Size.title1, .heavy))
                    .foregroundStyle(Color.textPrimary)
                Text(recap.opponentLabel)
                    .font(DSType.text(16, .semibold, prose: true))
                    .foregroundStyle(Color.textSecondary)
                DSStatusPill(
                    label: recap.resultLetter,
                    tone: recap.didWin ? .ok : (recap.didLose ? .bad : .neutral),
                    showsDot: false
                )
            }

            Text(reviewSummary(recap))
                .font(DSType.text(14, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// The header sentence, which has to survive the honest zero.
    ///
    /// It used to state two counts unconditionally, so a game in which nothing
    /// moved read "0 helped their case, 0 hurt theirs" — a sentence that tells
    /// the user nothing about why, and reads as a broken screen rather than as
    /// a policy that bought install instead of tape (#208 FIX C).
    private func reviewSummary(_ recap: PreseasonRecap) -> String {
        guard recap.helpedCount > 0 || recap.hurtCount > 0 else {
            return recap.policy == .fullTilt
                ? "Nobody on the bubble moved \u{2014} the ones took the afternoon, which is what "
                    + "full tilt buys. The cut to \(preseasonExitCeiling) still has to come out of this room."
                : "Nobody on the bubble moved. The tape below is still the sheet the cut to "
                    + "\(preseasonExitCeiling) gets written from."
        }
        var line = "\(recap.helpedCount) helped \(recap.helpedCount == 1 ? "his" : "their") case"
        if recap.hurtCount > 0 {
            line += ", \(recap.hurtCount) hurt \(recap.hurtCount == 1 ? "his" : "theirs")"
        }
        // Both counts are the cut cohort's, and `moversCard` under this sentence
        // lists starters too — so without this clause the card said "4 helped,
        // 1 hurt" over a list of six named men and the arithmetic on screen did
        // not close.
        if recap.starterMoverCount > 0 {
            line += " \u{2014} plus \(recap.starterMoverCount) starter"
                + (recap.starterMoverCount == 1 ? " who moved" : "s who moved")
        }
        return line + ". This is the sheet the cut to \(preseasonExitCeiling) gets written from."
    }

    // MARK: Who moved — the named evidence (#208 FIX C)

    /// The men whose case actually moved, with one line of reasoning each.
    ///
    /// The chips and the header print COUNTS, and a count is not evidence: the
    /// user cutting twelve men needs to know *which* fourth-string receiver
    /// played his way onto the 53 and what he did to get there. Starters are in
    /// the list too — a first-team quarterback throwing three picks is the most
    /// important thing that happened in an exhibition even though nobody is
    /// cutting him — and their tier pill says so.
    @ViewBuilder
    private func moversCard(_ recap: PreseasonRecap) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Who moved")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            if recap.movers.isEmpty {
                DSEmptyState(
                    icon: "equal.circle",
                    title: "Nobody moved today",
                    message: recap.policy == .fullTilt
                        ? "The first team played it out, so the bubble barely touched the ball. "
                            + "Rest the ones next time and the tape writes itself."
                        : "Every man who dressed did about what his spot asks. "
                            + "The full box score is below."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(recap.movers) { line in
                        moverRow(line)
                        if line.id != recap.movers.last?.id {
                            Divider().overlay(Color.surfaceBorder)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.sm)
                .cardBackground()
            }
        }
    }

    private func moverRow(_ line: PreseasonRecap.Line) -> some View {
        DSListRow(
            density: .study,
            badge: DSRowBadge(
                // The SAME position tint the bubble table under this card uses.
                // Colouring the badge by verdict instead would have two lists on
                // one screen meaning two different things by the same green.
                text: line.position.rawValue,
                tint: positionTint(line.position),
                accessibilityLabel: "\(line.position.rawValue), \(line.position.side.rawValue)"
            ),
            portraitWidth: 0,
            affordance: .none
        ) {
            EmptyView()
        } identity: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(line.name)
                        .font(DSType.text(16, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if line.injured {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.dangerText)
                            .accessibilityLabel("Left the game hurt")
                    }
                }
                // The one line of reasoning. Two lines of room, because the
                // sentence is the point of the row and truncating it would put
                // the screen back where the counts left it.
                Text(line.reason)
                    .font(DSType.text(13, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } columns: {
            Spacer(minLength: DSSpacing.sm)
            // Natural width, never a fixed column: "Bubble" and "Helped" are
            // short, but the same clipping trap the policy rows fell into is
            // one long word away.
            VStack(alignment: .trailing, spacing: 3) {
                DSStatusPill(label: line.verdict.pillLabel, tone: line.verdict.tone,
                             showsDot: false, spokenLabel: line.verdict.spoken)
                DSStatusPill(label: line.tier.pillLabel, tone: line.tier.tone, showsDot: false)
            }
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.name), \(line.position.rawValue), \(line.tier.pillLabel)")
        .accessibilityValue("\(line.verdict.spoken). \(line.reason)")
    }

    private func positionTint(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    // MARK: Across the slate — the sheet the cut is actually written from

    /// One man's whole preseason, on one row.
    ///
    /// Every other table on this screen is a single exhibition's box score, and
    /// the cut to 65 is not taken against one afternoon: the same receiver read
    /// HELPED in game 1 and HELD in game 2 with nothing anywhere adding the two
    /// together, and the `.complete` step showed the LAST game's table under
    /// copy calling it the cut sheet. This is the addition.
    private struct SlateCase: Identifiable {
        let id: UUID
        var name: String
        var position: Position
        /// Where he stands NOW: taken from the last game he dressed for, which
        /// is the lineup the club carries into the cut.
        var tier: PreseasonRecap.Tier
        var overall: Int
        /// Verdict per game index. A game he did not dress for has no entry,
        /// which is not the same statement as a quiet one.
        var verdicts: [Int: PreseasonCampCase.Verdict] = [:]
        /// Case points summed across the slate.
        var total: Double = 0
        /// The sentence from the game that carried his case, and which game it
        /// was — the evidence, kept in the man's own row rather than stranded
        /// in a recap that is three screens back.
        var reason = ""
        var reasonGame = 0
        /// True once any game produced a box score at all.
        ///
        /// `PreseasonEngine.CampCase.read` leaves `delta` at exactly zero when
        /// a man had no visible chances, so a run of quiet-and-zero is the
        /// engine saying the box score cannot see this position — a tackle, a
        /// guard — rather than saying he was poor. The row says that in words
        /// instead of grading him on an empty line.
        var hasTape = false
        var injured = false

        private var reasonWeight = -1.0

        init(_ line: PreseasonRecap.Line, game: Int) {
            id = line.id
            name = line.name
            position = line.position
            tier = line.tier
            overall = line.overall
            absorb(line, game: game)
        }

        mutating func absorb(_ line: PreseasonRecap.Line, game: Int) {
            tier = line.tier
            overall = line.overall
            verdicts[game] = line.verdict
            total += line.caseScore
            injured = injured || line.injured
            if line.verdict != .quiet || line.caseScore != 0 { hasTape = true }
            if abs(line.caseScore) > reasonWeight {
                reasonWeight = abs(line.caseScore)
                reason = line.reason
                reasonGame = game
            }
        }
    }

    /// The cut cohort, every played game folded in, best case first.
    private var slateCases: [SlateCase] {
        var order: [UUID] = []
        var built: [UUID: SlateCase] = [:]
        for index in playedIndices {
            guard let recap = recapsByGame[index] else { continue }
            for line in recap.lines {
                if var existing = built[line.id] {
                    existing.absorb(line, game: index)
                    built[line.id] = existing
                } else {
                    order.append(line.id)
                    built[line.id] = SlateCase(line, game: index)
                }
            }
        }
        return order.compactMap { built[$0] }
            .filter { $0.tier.isCutCohort }
            .sorted {
                // A man the box score cannot see is not evidence either way, so
                // he sits under everyone who left something on tape rather than
                // in the middle of the list on a zero.
                if $0.hasTape != $1.hasTape { return $0.hasTape }
                return $0.total > $1.total
            }
    }

    private var slateCaseCaption: String {
        playedIndices.count == 1
            ? "Every man the cut to \(preseasonExitCeiling) reaches, one game in."
            : "Every man the cut to \(preseasonExitCeiling) reaches, all \(playedIndices.count) games added up."
    }

    @ViewBuilder
    private func slateCaseTable(title: String) -> some View {
        let cases = slateCases
        if !cases.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(title)
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.textSecondary)

                Text(slateCaseCaption)
                .font(DSType.text(13, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                slateCaseHeader
                VStack(spacing: 0) {
                    ForEach(cases) { item in
                        slateCaseRow(item)
                        if item.id != cases.last?.id {
                            Divider().overlay(Color.surfaceBorder)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.sm)
                .cardBackground()
            }
        }
    }

    private var slateCaseHeader: some View {
        DSListHeaderRow(
            density: .scan,
            reservesBadge: true,
            portraitWidth: 0,
            identityLabel: "Player \u{00B7} the case he made"
        ) {
            DSColumnHeader("OVR", width: DSListColumn.ovr)
            // Derived from the count so the strip and the label over it cannot
            // disagree about how many exhibitions there are.
            DSColumnHeader(
                (1...PreseasonFlowBand.gameCount).map { "G\($0)" }.joined(separator: " "),
                width: DSListColumn.state
            )
            DSColumnHeader("Case", width: DSListColumn.value)
            DSColumnHeader("Standing", width: DSListColumn.label)
        }
        .padding(.horizontal, DSSpacing.sm)
    }

    private func slateCaseRow(_ item: SlateCase) -> some View {
        DSListRow(
            density: .scan,
            badge: DSRowBadge(
                text: item.position.rawValue,
                tint: positionTint(item.position),
                accessibilityLabel: "\(item.position.rawValue), \(item.position.side.rawValue)"
            ),
            portraitWidth: 0
        ) {
            EmptyView()
        } identity: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(item.name)
                        .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if item.injured {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.dangerText)
                            .accessibilityLabel("Left a game hurt")
                    }
                }
                Text(
                    item.hasTape
                        ? "G\(item.reasonGame) \u{00B7} \(item.reason)"
                        : "Nothing the box score can show \u{2014} judge him on camp and OVR."
                )
                .font(DSType.text(12, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            }
        } columns: {
            Text("\(item.overall)")
                .font(DSType.display(DSType.Size.body, .heavy))
                .foregroundStyle(Color.forRating(item.overall))
                .dsColumn(DSListColumn.ovr)

            verdictStrip(item)
                .dsColumn(DSListColumn.state)

            Text(item.hasTape ? String(format: "%+.1f", item.total) : "\u{2013}")
                .font(DSType.display(DSType.Size.footnote, .heavy))
                .foregroundStyle(slateCaseTint(item))
                .dsColumn(DSListColumn.value)

            DSStatusPill(label: item.tier.pillLabel, tone: item.tier.tone, showsDot: false)
                .dsColumn(DSListColumn.label)
        }
    }

    private func slateCaseTint(_ item: SlateCase) -> Color {
        guard item.hasTape, item.total != 0 else { return .textTertiaryReadable }
        return item.total > 0 ? .success : .dangerText
    }

    /// One cell per exhibition, in the verdict's own colour — the three games
    /// side by side, which is the whole reason this table exists.
    private func verdictStrip(_ item: SlateCase) -> some View {
        HStack(spacing: 3) {
            ForEach(1...PreseasonFlowBand.gameCount, id: \.self) { game in
                verdictCell(item.verdicts[game], game: game)
            }
        }
    }

    private func verdictCell(_ verdict: PreseasonCampCase.Verdict?, game: Int) -> some View {
        // An empty cell borrows `DSStatusPill`'s `.empty` treatment — dashed,
        // dimmed, no fill — because it means the same thing: the slot exists
        // and nothing filled it.
        let tint = verdict?.tone.tint ?? Color.textTertiary
        return RoundedRectangle(cornerRadius: DSCornerRadius.tight)
            .fill(verdict == nil ? Color.clear : tint.opacity(0.16))
            .overlay {
                if let verdict {
                    Image(systemName: verdictGlyph(verdict))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(tint)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .strokeBorder(
                        tint.opacity(verdict == nil ? 0.35 : 0.45),
                        style: StrokeStyle(lineWidth: 1, dash: verdict == nil ? [2, 2] : [])
                    )
            )
            .frame(width: 22, height: 18)
            .accessibilityElement()
            .accessibilityLabel("Game \(game)")
            .accessibilityValue(verdict?.spoken ?? "did not dress")
    }

    private func verdictGlyph(_ verdict: PreseasonCampCase.Verdict) -> String {
        switch verdict {
        case .helped: return "arrow.up"
        case .held:   return "equal"
        case .hurt:   return "arrow.down"
        case .quiet:  return "minus"
        }
    }

    // MARK: Complete — the slate, read back

    @ViewBuilder
    private var slateContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("The slate")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 0) {
                ForEach(playedIndices, id: \.self) { index in
                    if let built = recapsByGame[index] {
                        slateRow(built)
                        if index != playedIndices.last {
                            Divider().overlay(Color.surfaceBorder)
                        }
                    }
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .cardBackground()
        }

        // The slate is closed, so the last exhibition's box score is not the
        // cut sheet — the three games added together are. This step used to
        // mount `moversCard` and the bubble table for `playedIndices.last`
        // alone, under copy that called it the sheet the 65 is written from.
        slateCaseTable(title: "Across the slate")

        rosterStanding
    }

    private func slateRow(_ recap: PreseasonRecap) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text("G\(recap.gameIndex)")
                .font(DSType.display(11, .heavy))
                .foregroundStyle(Color.textTertiaryReadable)
                .dsColumn(DSListColumn.rank, alignment: .leading)
            DSStatusPill(
                label: recap.resultLetter,
                tone: recap.didWin ? .ok : (recap.didLose ? .bad : .neutral),
                showsDot: false
            )
            Text("\(recap.scoreText) \(recap.opponentLabel)")
                .font(DSType.text(14, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DSSpacing.xs)
            Text(recap.policy.displayTitle)
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            DSStatusPill(label: "Helped", tone: .ok, value: "\(recap.helpedCount)", showsDot: false)
            DSStatusPill(label: "Slipped", tone: .bad, value: "\(recap.hurtCount)", showsDot: false)
        }
        .frame(minHeight: 44)
    }

    // MARK: - The commit (§2.5)

    @ViewBuilder
    private var actionBar: some View {
        switch stance {
        case .planning:
            DSActionBar(
                explainer: .init(
                    title: playFailure == nil ? "What this costs" : "Could not play it",
                    message: playFailure ?? planExplainer,
                    isWarning: playFailure != nil
                ),
                // `rosterStanding` above states the obligation ("10 still to
                // release before the phase closes") and until this existed the
                // only route to it was the `.complete` bar's primary — so for
                // all three planning steps the screen named the job and offered
                // no way to do it.
                secondary: onOpenRosterCuts.map {
                    DSActionBar.Action(title: "Roster cuts", handler: $0)
                },
                primary: .init(
                    title: isSimulating ? "Playing\u{2026}" : "Play game \(currentGame)",
                    isEnabled: !isSimulating,
                    handler: { playGame(currentGame) }
                )
            )
        case .reviewing:
            DSActionBar(
                explainer: .init(
                    title: currentGame < PreseasonFlowBand.gameCount ? "Next" : "After this",
                    message: reviewExplainer
                ),
                primary: .init(
                    title: continueTitle(after: currentGame),
                    handler: { advance(from: currentGame) }
                )
            )
        case .complete:
            DSActionBar(
                explainer: .init(
                    title: "Before the season opens",
                    message: completeExplainer,
                    isWarning: activeRoster.count > preseasonExitCeiling
                ),
                primary: .init(
                    title: "Roster cuts",
                    isEnabled: onOpenRosterCuts != nil,
                    handler: { onOpenRosterCuts?() }
                )
            )
        }
    }

    private var planExplainer: String {
        switch selectedPolicy {
        case .startersRest:
            return "**No first-team snaps.** The bubble plays the whole game and the starters take no injury risk "
                + "\u{2014} but they bank no scheme familiarity either. Every stat line below belongs to a man "
                + "fighting for a spot."
        case .starterSeries:
            return "**A third of the ones open.** They rotate across the slate, so every starter gets one "
                + "exhibition and the other two thirds of the first-team spots belong to the bubble. "
                + "Part install, part risk, and most of the tape."
        case .fullTilt:
            return "**Everybody plays it out.** Full install for the starters, and full injury exposure with it "
                + "\u{2014} at the price of the bubble barely touching the ball."
        }
    }

    private var reviewExplainer: String {
        if currentGame < PreseasonFlowBand.gameCount {
            return "You can change who dresses for game \(currentGame + 1). Nothing here is locked until the slate is done."
        }
        let over = max(0, activeRoster.count - preseasonExitCeiling)
        return over > 0
            ? "The slate closes with **\(activeRoster.count)** on the roster \u{2014} **\(over)** over the \(preseasonExitCeiling) the phase exits at."
            : "The slate closes with **\(activeRoster.count)** on the roster, already inside the \(preseasonExitCeiling)."
    }

    private var completeExplainer: String {
        let over = max(0, activeRoster.count - preseasonExitCeiling)
        return over > 0
            ? "You are carrying **\(activeRoster.count)**. Release **\(over)** more to get to \(preseasonExitCeiling) \u{2014} the tape above is the case for each of them."
            : "You are at **\(activeRoster.count)**, inside the \(preseasonExitCeiling). Nothing is blocking the advance."
    }

    private func continueTitle(after game: Int) -> String {
        game < PreseasonFlowBand.gameCount ? "Plan game \(game + 1)" : "Close the slate"
    }

    // MARK: - Actions

    /// Plays one preseason game and banks it.
    ///
    /// **The only two calls this screen makes into `PreseasonEngine`** are here
    /// and in `refreshFixture`, so the engine's surface is wired in exactly two
    /// places and an integration fix lands in two lines.
    ///
    /// The sim runs on the main actor because SwiftData models are bound to it
    /// and every other commit in this app (an FA round, a week advance) does the
    /// same. One preseason game is one `GameSimulator` run — the same cost as a
    /// regular-season game the user coaches.
    private func playGame(_ index: Int) {
        guard !isSimulating, let current = flow else { return }
        // Both of these used to be a bare `else { return }`: the user pressed
        // the one commit on the screen and absolutely nothing happened — no
        // sheet, no message, no state change. A commit that cannot run says so.
        guard let matchup = current.matchup(at: index) else {
            playFailure = "Game \(index) has no opponent on the slate."
            return
        }
        isSimulating = true
        // The flag used to be cleared by a `defer` in this same synchronous
        // body, so SwiftUI never drew a frame between the two writes: the
        // disabled "Playing…" title the bar already declares was unreachable,
        // and a `GameSimulator` run held the main thread with the button still
        // reading "Play game 1". One turn of the loop before the sim is what
        // makes the state the bar declares the state it shows.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms — let the button paint
            play(index, matchup: matchup, into: current)
            isSimulating = false
        }
    }

    /// The commit itself, once the button has had its frame.
    private func play(_ index: Int, matchup: PreseasonMatchup, into current: PreseasonState) {
        guard let result = PreseasonEngine.simulateGame(
            career: career,
            matchup: matchup,
            policy: selectedPolicy,
            modelContext: modelContext
        ) else {
            playFailure = "The exhibition could not be played. Nothing was banked \u{2014} try it again."
            return
        }
        playFailure = nil

        // The engine owns the step machine: `recordResult` overwrites a replayed
        // game's own slot and moves the step to `.recap(index)`. The policy the
        // user chose rides on the result itself — one authority, so the recap
        // and the state can never disagree about what he called.
        let next = PreseasonEngine.recordResult(result, into: current)

        flow = next
        career.preseasonState = next
        try? modelContext.save()

        refreshRoster()
        rebuildRecaps()
        refreshFixture()
        cohort = .bubble
        // Read the freshly cached recap rather than building a second one, so
        // the sheet and the table behind it are literally the same object.
        if let built = recapsByGame[index] { activeSheet = .recap(built) }
    }

    /// Moves the step machine on from a played game.
    private func advance(from game: Int) {
        guard let current = flow else { return }
        playFailure = nil
        // The engine decides whether another exhibition is owed — it reads the
        // persisted slate, so the step machine has one authority.
        let next = PreseasonEngine.acknowledgeRecap(current)
        if next.step.kind == .plan {
            // The next game is a fresh decision, and defaulting it to the last
            // choice would quietly make the bet once instead of three times.
            selectedPolicy = .starterSeries
        }
        flow = next
        career.preseasonState = next
        try? modelContext.save()
        refreshRoster()
        rebuildRecaps()
        refreshFixture()
    }

    // MARK: - Loading

    private var activeRoster: [Player] { liveRoster ?? roster }

    private var playersByID: [UUID: Player] {
        Dictionary(activeRoster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The projected first team, from the same authority the weekly starter
    /// tally and the policy composition use — never a second lineup rule.
    ///
    /// Availability is filtered exactly as `PreseasonEngine.simulateGame` does
    /// it (an injured or holding-out man does not dress for an exhibition), so
    /// this projection cannot disagree with the lineup a game is played with.
    private var starterIDs: Set<UUID> {
        WeekAdvancer.startingLineupIDs(
            available: activeRoster.filter { !$0.isRetired && !$0.isInjured && !$0.isHoldingOut }
        )
    }

    /// The rung the phase exits at (§3.4). Read from `CutDay` so the ladder has
    /// one authority; this screen never states a target of its own.
    private var preseasonExitCeiling: Int { CutDay.cut75To65.target }

    /// Rebuilds every recap from the persisted results.
    ///
    /// Each game is labelled with the lineup IT was played with, banked on its
    /// own payload — a recap is a historical record, and applying one live
    /// projection retroactively to all three games mislabels every one of them
    /// the moment somebody is hurt. The live projection is computed once and
    /// handed down only as the fallback for a blob written before the payload
    /// carried its own set.
    private func rebuildRecaps() {
        let results = flow?.results ?? []
        guard !results.isEmpty else {
            recapsByGame = [:]
            return
        }
        let byID = playersByID
        let projected = starterIDs
        recapsByGame = results.reduce(into: [:]) { out, result in
            out[result.gameIndex] = PreseasonRecap(
                result: result,
                policy: result.policy,
                opponentLabel: label(opponentID: result.matchup.opponentTeamID, isUserHome: result.matchup.isHome),
                playersByID: byID,
                starterIDs: result.starterIDs(fallback: projected)
            )
        }
    }

    private func label(opponentID: UUID?, isUserHome: Bool) -> String {
        let venue = isUserHome ? "vs" : "at"
        guard let opponentID, let team = teamsByID[opponentID] else { return "\(venue) TBA" }
        return "\(venue) \(team.city)"
    }

    private var upcomingOpponent: Team? {
        guard let fixture = upcomingFixture else { return nil }
        return teamsByID[fixture.opponentTeamID]
    }

    private var upcomingFixtureLabel: String {
        guard let fixture = upcomingFixture else { return "Opponent to be announced" }
        return label(opponentID: fixture.opponentTeamID, isUserHome: fixture.isHome)
    }

    /// Refreshes the cached fixture for the game being planned.
    ///
    /// The slate is drawn once, when the phase opens, and persisted with the
    /// flow — so this is a read off the blob rather than a second draw, and the
    /// opponent is stable across a re-entered phase and a cold launch.
    private func refreshFixture() {
        guard let flow, stance == .planning else {
            upcomingFixture = nil
            return
        }
        upcomingFixture = flow.matchup(at: currentGame)
    }

    private func load() {
        refreshRoster()

        let careerID = career.id
        let teams = (try? modelContext.fetch(
            FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.careerID == careerID })
        )) ?? []
        teamsByID = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        seedFlowIfNeeded()
        rebuildRecaps()
        refreshFixture()
        didLoad = true
    }

    private func refreshRoster() {
        guard let teamID = career.teamID else { return }
        liveRoster = (try? modelContext.fetch(
            FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.teamID == teamID })
        )) ?? []
    }

    /// Seeds the blob if the phase opened without one, and re-seeds it when it
    /// is stamped for a previous season.
    ///
    /// The season stamp is the same idempotency shape `campFillSeason` and
    /// `lastRolloverSeason` use, and it is what stops last August's three games
    /// from being shown as this August's. A process global would not survive a
    /// cold launch, which is half of why the old `.otas` UDFA path was
    /// unreliable — so the stamp lives in the persisted state.
    private func seedFlowIfNeeded() {
        guard career.currentPhase == .preseason else {
            flow = nil
            return
        }
        let existing = career.preseasonState
        // The engine hands back a matching blob untouched and draws a fresh
        // slate otherwise — the stale-blob check (`matches(career:)`) and the
        // draw live in one place.
        let state = PreseasonEngine.openPreseasonIfNeeded(
            existing: existing,
            career: career,
            teams: Array(teamsByID.values)
        )
        flow = state
        // The last call the user made is the sensible default when he re-enters
        // a game he already planned once.
        if state.step.kind == .plan,
           let previous = state.result(at: state.step.gameIndex) {
            selectedPolicy = previous.policy
        }
        // Only a freshly drawn slate is written back; a matching blob is handed
        // straight through and must not be re-saved on every entry.
        if existing?.matches(career: career) != true {
            career.preseasonState = state
            try? modelContext.save()
        }
    }

    // MARK: - Off-phase

    private var notInPreseason: some View {
        DSEmptyState(
            icon: "calendar.badge.clock",
            title: "Preseason is not open",
            message: "The three-game slate runs after training camp and before final cuts."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
