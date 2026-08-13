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
                    continueTitle: continueTitle(after: recap.gameIndex),
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
            .frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Planning — the game card and the coach decision

    @ViewBuilder
    private var planningContent: some View {
        gameCard
        policyPicker
        rosterStanding
    }

    private var gameCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Game \(currentGame) of \(PreseasonFlowBand.gameCount)".uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.accentGold)

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
                badge: DSRowBadge(
                    text: isSelected ? "\u{2022}" : " ",
                    tint: isSelected ? Color.accentGold : Color.backgroundTertiary,
                    accessibilityLabel: isSelected ? "Selected" : "Not selected"
                ),
                portraitWidth: 0,
                affordance: .none
            ) {
                EmptyView()
            } identity: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: policy.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)
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
                VStack(alignment: .trailing, spacing: 3) {
                    DSStatusPill(label: policy.familiarityNote, tone: .info, showsDot: false)
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
            Text("Game \(recap.gameIndex) \u{00B7} \(recap.policy.displayTitle)".uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.accentGold)

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

        if let lastIndex = playedIndices.last, let built = recapsByGame[lastIndex] {
            moversCard(built)
            PreseasonBubbleTable(recap: built, cohort: $cohort)
        }

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
            DSStatusPill(label: "Hurt", tone: .bad, value: "\(recap.hurtCount)", showsDot: false)
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
                    title: "What this costs",
                    message: planExplainer
                ),
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
    /// The sim runs on the main actor, synchronously, because SwiftData models
    /// are main-actor bound and every other commit in this app (an FA round, a
    /// week advance) does the same. One preseason game is one `GameSimulator`
    /// run — the same cost as a regular-season game the user coaches.
    private func playGame(_ index: Int) {
        guard !isSimulating, let current = flow else { return }
        guard let matchup = current.matchup(at: index) else { return }
        isSimulating = true
        defer { isSimulating = false }

        guard let result = PreseasonEngine.simulateGame(
            career: career,
            matchup: matchup,
            policy: selectedPolicy,
            modelContext: modelContext
        ) else { return }

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
