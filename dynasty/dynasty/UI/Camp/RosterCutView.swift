import SwiftUI
import SwiftData

// MARK: - Roster Cut View
//
// The three-stage cutdown — 87 → 75 → 65 → 53 — on the wave-3 standard:
// `DSSlatBand` for the ladder, `DSActionBar` for the commit, `DSResultSheet` for
// the ending (UI_REDESIGN_VISION §2.1 / §2.5 / §2.6).
//
// **The three rungs now fall due in three different phases** (#205a §1): camp
// breaks at 75, the preseason slate ends at 65, cutdown day sets the 53. The
// screen is therefore reachable from `.trainingCamp`, `.preseason` and
// `.rosterCuts`, and the one thing it had to learn is that the ladder counts
// down only as far as the calendar has reached — see `stage`. `CutDay.duePhase`
// is the single authority for that mapping; the left-menu rows
// (`TaskGenerator.rosterLadderTask`) and the advance gate read the same enum.
//
// **What was actually wrong here was the ending, not the list.** The screen
// committed a set of releases and then advanced its own `@State stage` — the
// in-place body swap §2.6 bans by name. The header re-titled itself, the target
// changed and the list shortened, all silently, and the user was never told how
// many men he had released, how much room it had freed, or how much dead money
// it had left behind. Every one of those numbers already existed: the engine
// returns them and the screen threw them away.
//
// Two structural changes follow from fixing that:
//
//   1. **The stage is derived, not stored.** The roster count is the truth, so
//      a stored stage was a second copy of a fact that could disagree with the
//      list underneath it (it did: the stage always opened at 90 → 75 no matter
//      what the roster actually held, so a club resuming a half-done cutdown
//      was shown the wrong target). Deriving only works if the count is live:
//      the `roster` parameter the shell passes in is a one-shot fetch that
//      never refreshes, so this screen owns `liveRoster` and re-fetches it
//      after every commit. Without that the derived stage freezes at the value
//      it opened with and the cutdown can never be finished.
//   2. **The commit confirms.** A release is irreversible and career-affecting,
//      which is exactly the class §0 counted committing on first tap.
//
// **And the confirm had nothing to confirm about football** (#208a). The dialog
// priced the release in cap dollars and said nothing about the shape of what was
// leaving, so all three quarterbacks — the starter among them — could go on one
// sheet and the only warning was a number of millions. `RosterCutEvaluator` has
// carried the depth guard since it was written, but it governed the
// RECOMMENDATION only and was never asked about the commit. It is now:
// `releaseBlockReason` closes a row the moment ticking it would take a room
// under its floor, and `positionImpacts` puts the rooms the plan touches in the
// confirm dialog beside the money.

struct RosterCutView: View {

    let career: Career
    /// The shell's opening snapshot. Used only until the first fetch lands —
    /// see `activeRoster`.
    let roster: [Player]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The club as it stands **now**. `nil` before the first fetch, so the very
    /// first render still has the shell's snapshot to draw rather than an empty
    /// list. Refreshed on appear and after every commit.
    @State private var liveRoster: [Player]?
    /// The club, loaded with the ledger (#208 G1). The positional guard is the
    /// engine's, and the engine's spelling of it takes the `Team` — so the row
    /// guard needs the same club object the commit books against instead of
    /// fetching one per row.
    @State private var loadedTeam: Team?

    @State private var positionGroup: CutPositionGroup = .all
    @State private var selectedIDs: Set<UUID> = []
    /// Player IDs that the user has flagged as practice-squad-eligible.
    @State private var practiceSquadIDs: Set<UUID> = []
    /// Detailed deals for this club, so the release split prices a real
    /// `Contract` where one exists instead of always using the proxy.
    @State private var contractsByPlayer: [UUID: Contract] = [:]
    /// Cut priority, worst first, as a rank per player. Held rather than
    /// derived per render: `keepScore` reads a dozen properties per man and the
    /// list re-renders on every tap. Refreshed with the roster it ranks.
    @State private var cutOrder: [UUID: Int] = [:]
    /// Releases already booked this cutdown, keyed by the stage that booked
    /// them — what each finished slat reports (§2.1's `done` row).
    @State private var releasesByStage: [CutDay: Int] = [:]
    /// The commit is irreversible, so it asks first.
    @State private var showCutConfirm = false
    /// **The one modal slot.** One `.sheet(item:)`, per the house rule.
    @State private var result: CutResult?

    /// What a completed stage did, as `DSResultSheet` needs it.
    struct CutResult: Identifiable {
        let id = UUID()
        let released: Int
        let capFreed: Int
        let deadMoney: Int
        let practiceSquadFlagged: Int
        let rosterAfter: Int
        let stage: CutDay
        /// Men still over `stage.target` after this commit — what the club owes
        /// on THIS cut day before the calendar will move.
        let stillOwed: Int
        /// The rung after this one, if the ladder has one left. It is due in a
        /// later phase, so the sheet names that phase rather than presenting it
        /// as work in hand.
        let nextRung: CutDay?
        /// Starter slots this commit emptied and the chart re-filled on the
        /// spot. Named on the receipt, because a silently rewritten depth chart
        /// is exactly the thing the old blocking dialog was standing in for.
        let lineupRefilled: [DepthChartSlot]
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            tabBar
            listHeader
            list
            actionBar
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Roster Cuts")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadLedger() }
        // Confirmation only (§2.8) — never a result.
        .alert("Release \(selectedIDs.count) player\(selectedIDs.count == 1 ? "" : "s")?", isPresented: $showCutConfirm) {
            Button("Release", role: .destructive) { performCuts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .sheet(item: $result) { result in
            resultSheet(result)
        }
    }

    // MARK: - The ladder (§2.1)

    private var band: some View {
        DSSlatBand(
            slats: CutDay.allCases.enumerated().map { index, day in
                slat(for: day, position: index + 1)
            },
            headline: headline,
            meter: meter
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.backgroundPrimary)
    }

    private func slat(for day: CutDay, position: Int) -> DSSlat {
        let state: DSSlat.State
        if day.target > stage.target {
            // A larger target than the one the club is working to is behind it:
            // the ladder counts DOWN, so "done" is the higher number.
            state = .done
        } else if day == stage {
            // Banked, not finished: the rung the calendar asked for is met, but
            // the rungs below it are still ahead of the club.
            state = isDueStageComplete ? .done : .current
        } else {
            state = .future
        }
        let released = releasesByStage[day] ?? 0
        return DSSlat(
            id: day.rawValue,
            index: "\(position)",
            title: day.slatTitle,
            subcaption: state == .current ? currentSubcaption : nil,
            state: state,
            outcome: state == .done && released > 0 ? "\(released) released" : nil,
            accessibilityText: [
                "Cut stage \(position) of \(CutDay.allCases.count)",
                day.slatTitle,
                state == .done ? "complete" : (state == .current ? "current stage" : "not started"),
                state == .done && released > 0 ? "\(released) released" : nil,
                state == .current ? currentSubcaption : nil
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    /// **The one place the stage count is printed** (§2.1).
    private var headline: String {
        guard !isComplete, let index = CutDay.allCases.firstIndex(of: stage) else {
            return "Cutdown complete"
        }
        let label = "Cut day \(index + 1) of \(CutDay.allCases.count)"
        // Banked but not finished — say so, rather than leaving a "current"
        // headline over a ladder whose current slat has just gone green.
        return isDueStageComplete ? "\(label) \u{00B7} banked" : label
    }

    /// **What nothing else on the screen says.** The remainder had three
    /// phrasings in one viewport — the meter on the rule above ("0 spent · 12
    /// left"), this line ("12 more to release") and the action bar ("You are 12
    /// over the 53-man limit. Tap a player to mark him for release."). The bar
    /// is the one that says what to DO and the meter is the band's own grammar,
    /// so the remainder lives in those two and this line keeps the facts they
    /// cannot carry: how many men are on the roster, and how many are marked.
    private var currentSubcaption: String {
        guard requiredCuts > 0 else { return "At the limit \u{2014} bank it and move on" }
        guard !selectedIDs.isEmpty else {
            return "\(activeRoster.count) on the roster"
        }
        return "\(activeRoster.count) on the roster \u{00B7} \(selectedIDs.count) marked"
    }

    /// A filled pip is a spent cut — the meter's one meaning, everywhere.
    /// Suppressed when the stage asks for nothing, because a meter of zero pips
    /// is a rendering artefact rather than a reading.
    private var meter: DSResourceMeter? {
        guard requiredCuts > 0 else { return nil }
        return DSResourceMeter(
            spent: min(selectedIDs.count, requiredCuts),
            total: requiredCuts,
            unit: "cuts"
        )
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(CutPositionGroup.allCases) { group in
                    Button {
                        positionGroup = group
                    } label: {
                        // The room's size, on the chip. A bare "DL" makes you tap
                        // it to find out how deep the group is, and depth is the
                        // whole question this screen is asking.
                        HStack(spacing: DSSpacing.xxs) {
                            Text(group.label)
                            Text("\(count(in: group))")
                                .foregroundStyle(Color.textTertiaryReadable)
                        }
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(positionGroup == group ? Color.backgroundTertiary : Color.backgroundSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .strokeBorder(
                                    positionGroup == group ? Color.accentBlue : Color.surfaceBorder,
                                    lineWidth: positionGroup == group ? 2 : 1
                                )
                        )
                        .foregroundStyle(positionGroup == group ? Color.textPrimary : Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(positionGroup == group ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
        }
        .background(Color.backgroundPrimary)
    }

    /// **What order the rows are in, and what the marks are doing to the
    /// rooms.**
    ///
    /// The list shipped in whatever order SwiftData handed it back and said
    /// nothing about either, so the ranking was invisible and the position
    /// depth — the actual decision variable — was named for the first time
    /// inside the confirm alert, after all twelve men were already picked. Both
    /// read here now, off data the screen has held since it loaded.
    private var listHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                Text("Worst first \u{00B7} your staff's cut order".uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.textTertiaryReadable)
                ForEach(selectionImpacts) { impact in
                    Text(impact.line)
                        .font(DSType.display(11, .heavy))
                        .foregroundStyle(impact.isViolation ? Color.danger : Color.textSecondary)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.xxs)
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.xs) {
                ForEach(filteredRoster, id: \.id) { player in
                    row(for: player)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
    }

    private func row(for player: Player) -> some View {
        let isSelected = selectedIDs.contains(player.id)
        let isPS = practiceSquadIDs.contains(player.id)
        let blockReason = releaseBlockReason(for: player)
        let split = releaseSplit(for: player)
        return HStack(spacing: DSSpacing.sm) {
            // Avatar placeholder
            Circle()
                .fill(Color.backgroundTertiary)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(initials(for: player))
                        .font(DSType.display(DSType.Size.footnote, .bold))
                        .foregroundStyle(Color.textSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {  // ds-lint:allow(spacing) name-over-meta lockup inside one row
                HStack(spacing: DSSpacing.xxs) {
                    Text(player.position.rawValue)
                        .font(DSType.display(11, .heavy))
                        .padding(.horizontal, DSSpacing.xxs)
                        .padding(.vertical, 2)  // ds-lint:allow(spacing) position badge must not grow the row
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(Color.backgroundTertiary)
                        )
                        .foregroundStyle(Color.textSecondary)
                    Text(player.fullName)
                        .font(DSType.text(DSType.Size.body, .medium, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                // **The numbers outrank the name here.** The name was body
                // semibold over a meta line where OVR, the camp letter and the
                // age all sat at the 11 pt floor — so the eye landed first on
                // the one thing the user already knows and last on the two
                // gradings the cut is actually made on. The two verdicts move a
                // step up; the age, which decides nothing on its own, stays put.
                HStack(spacing: DSSpacing.xs) {
                    Text("OVR \(player.overall)")
                        .font(DSType.display(DSType.Size.footnote, .heavy))
                        .foregroundStyle(Color.forRating(player.overall))
                    if let grade = player.campGrade {
                        Text("Camp \(grade.displayLabel)")
                            .font(DSType.display(DSType.Size.footnote, .heavy))
                            .foregroundStyle(gradeColor(grade))
                    } else {
                        // A blank where every neighbouring row carries a letter
                        // reads as a data hole rather than as a fact. Men
                        // acquired after camp broke were never graded, and the
                        // absence is stated rather than left to be inferred.
                        Text("Camp \u{2014}")
                            .font(DSType.display(DSType.Size.footnote, .heavy))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .accessibilityLabel("No camp grade")
                    }
                    Text("Age \(player.age)")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                    // Years left on the deal — the third thing a cut is decided
                    // on, and the row had no room problem: it was 70 % empty.
                    Text("Yrs \(player.contractYearsRemaining)")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                }
                // §2.12 — a closed row says why it is closed, in the row. A
                // greyed line with no reason is the thing the guard exists to
                // stop being.
                if let blockReason {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "lock.fill")
                            .font(DSType.display(10, .bold))
                        Text(blockReason)
                            .font(DSType.text(DSType.Size.caption, .semibold, prose: true))
                            .lineLimit(2)
                    }
                    .foregroundStyle(Color.warning)
                }
            }

            Spacer()

            // **The money, with its sign and with its other half.**
            //
            // One unlabelled figure, always prefixed "+" and always painted
            // success green, is two lies on one row: `capSavings` is signed, so
            // a release that COSTS cap space rendered in the same green as one
            // that freed $25M; and a man on a minimum deal rounded to "+$0.0M",
            // which reads as "free to cut" rather than "saves nothing". The
            // dead cap the same release leaves behind — the number the confirm
            // dialog and the receipt both lead with — appeared nowhere on the
            // row where the decision is actually made.
            VStack(alignment: .trailing, spacing: 2) {  // ds-lint:allow(spacing) two-line money column inside one row
                Text(capSavingsLabel(split))
                    .font(DSType.display(DSType.Size.footnote, .heavy))
                    .foregroundStyle(capSavingsColor(split))
                Text(split.deadCap > 0 ? "\(money(split.deadCap)) dead" : "no dead cap")
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(split.deadCap > 0 ? Color.dangerText : Color.textTertiaryReadable)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(capSavingsAccessibilityLabel(split))

            // **The flag only means anything on a man who is leaving.** It is
            // stamped onto his release receipt and read back by the practice
            // squad's keeper pass; on a man you keep it was a toggle that lit
            // up, changed nothing, and was wiped on commit. So it appears when
            // he is marked and goes with him when he is un-marked — and it says
            // what it does, rather than two letters that are expanded nowhere
            // on the screen.
            if isSelected {
                Button {
                    togglePracticeSquad(player)
                } label: {
                    Text(isPS ? "On PS \u{2713}" : "Stash on PS")
                        .font(DSType.display(11, .heavy))
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 3)  // ds-lint:allow(spacing) inline toggle inside a fixed row height
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(isPS ? Color.accentBlue : Color.backgroundTertiary)
                        )
                        .foregroundStyle(isPS ? Color.textPrimary : Color.textSecondary)
                        // 44 pt of finger around a 19 pt pill: this control
                        // shares a hit area with the row's own tap, and that tap
                        // is the destructive one. A miss must not be a release.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isPS
                        ? "\(player.fullName) is flagged for the practice squad"
                        : "Flag \(player.fullName) for the practice squad"
                )
            }

            // The row carries four numbers and the tap on it is an irreversible
            // release, so the man himself was one thing the screen would not
            // show you. His card pushes onto the shell's own stack and pops
            // straight back onto the sheet, marks intact.
            NavigationLink(destination: PlayerDetailView(player: player)) {
                Image(systemName: "info.circle")
                    .font(DSType.display(DSType.Size.footnote, .semibold))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(player.fullName)'s player card")
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(isSelected ? Color.danger.opacity(0.18) : Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(
                    isSelected ? Color.danger : (blockReason != nil ? Color.warning.opacity(0.5) : Color.surfaceBorder),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        // Dimmed, not hidden: the man is still on the roster and his numbers
        // still read, he simply cannot be the one who goes.
        .opacity(blockReason == nil ? 1.0 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard blockReason == nil else { return }
            toggleSelection(player)
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(
            blockReason
                ?? (isSelected ? "Tap to keep him" : "Tap to mark him for release")
        )
    }

    /// The camp grade, on the same five-tier ladder as the OVR beside it.
    ///
    /// Every grade used to be one flat `accentGold`, so a Camp F and a Camp C
    /// were pixel-identical and the letter was the only thing carrying the
    /// reading — on the one number this phase actually generated. Gold is also
    /// the screen's primary button and its current slat, and a per-row badge in
    /// the call-to-action colour is the colour discipline §2.13 exists to keep.
    /// C sits on neutral rather than on a tier: it is the middle of the ladder,
    /// and neither a warning nor a recommendation.
    private func gradeColor(_ grade: CampGrade) -> Color {
        switch grade {
        case .aPlus: return .forRatingTier(.elite)
        case .a:     return .forRatingTier(.good)
        case .b:     return .forRatingTier(.solid)
        case .c:     return .textSecondary
        case .d:     return .forRatingTier(.average)
        case .f:     return .forRatingTier(.poor)
        }
    }

    /// Bodies a filter chip's room holds right now.
    private func count(in group: CutPositionGroup) -> Int {
        activeRoster.filter { group.includes($0.position) }.count
    }

    // MARK: - The commit surface (§2.5)

    /// **The bar is keyed on the selection first, the rung second.**
    ///
    /// It used to be keyed on `isDueStageComplete` alone, which replaced the
    /// whole primary with "Done" the moment the rung was met — and the rows
    /// underneath stayed fully selectable. In training camp at 74 the club is
    /// past the 75 rung, so a user marking three men for cap room watched the
    /// rows light up, watched the explainer price the release, and had no
    /// button that would commit it. Cutting under the rung in hand — which the
    /// copy here has always invited — was impossible from the one screen the
    /// camp task row deep-links to.
    ///
    /// So a live selection always owns the gold, and `Done` steps back into the
    /// secondary slot (the fixed order [ghost][secondary][PRIMARY] already puts
    /// it left of the commit). With nothing marked the bar is exactly what it
    /// was.
    private var actionBar: some View {
        let hasSelection = !selectedIDs.isEmpty
        // #208a: the rows cannot build an illegal sheet, but the roster can move
        // under one. The commit is gated on the same guard the rows are.
        let isLegal = selectionViolations.isEmpty
        return DSActionBar(
            explainer: explainer,
            ghost: suggestAction,
            secondary: isDueStageComplete && hasSelection ? doneAction : nil,
            primary: isDueStageComplete && !hasSelection
                ? doneAction
                : .init(
                    title: hasSelection
                        ? "Release \(selectedIDs.count) player\(selectedIDs.count == 1 ? "" : "s")"
                        : "Release players",
                    isEnabled: hasSelection && isLegal,
                    handler: { showCutConfirm = true }
                )
        )
    }

    /// **The staff's plan, offered before the user builds one by hand.**
    ///
    /// `RosterCutEvaluator.recommendCuts` has scored the whole roster since it
    /// was written and had no caller anywhere in the app: the bar said "tap a
    /// player to mark him for release" over 87 unranked rows, twelve times, and
    /// the answer sat one function away. This seeds the sheet with it — nothing
    /// is committed, every row stays editable, and the confirm still has to be
    /// tapped.
    ///
    /// Withdrawn as soon as anything is marked: it starts a selection, it never
    /// overwrites one.
    private var suggestAction: DSActionBar.Action? {
        guard selectedIDs.isEmpty, requiredCuts > 0, loadedTeam != nil else { return nil }
        return .init(
            title: "Suggest \(requiredCuts)",
            caption: "worst first \u{2014} yours to edit",
            handler: { suggestCuts() }
        )
    }

    /// Leaving the screen with the rung banked. Primary while nothing is
    /// marked; demoted to secondary the moment a release is priced, because a
    /// commit outranks an exit.
    private var doneAction: DSActionBar.Action {
        .init(
            title: isComplete
                ? "Done \u{2014} roster is set"
                : "Done \u{2014} back to \(TaskGenerator.phaseInfo(for: career.currentPhase).name)",
            handler: { dismiss() }
        )
    }

    /// What committing does and what it costs (P4) — or, when it is blocked,
    /// why (§2.12: a blocked commit swaps the rule to orange and says the
    /// reason rather than presenting a dead grey button with no explanation).
    ///
    /// **A live selection is priced whether or not the rung is banked.** The
    /// banked branch used to win outright, so a voluntary cut made under the
    /// limit was described by a bar still reading "Cut to 75 is banked" while
    /// the gold button beside it offered to release three men — the bar naming
    /// one action and pricing another.
    private var explainer: DSActionBar.Explainer {
        if selectedIDs.isEmpty, isDueStageComplete {
            // The rung in hand is met. Whether anything is still owed depends on
            // where the calendar is, so the copy names the next rung AND the
            // phase it falls due in — the screen is now reachable from three
            // phases and "next: cut to 65" with no date is the kind of half
            // sentence that reads as a demand for work due in six weeks.
            // No invitation to cut further on the last rung: 53 is the floor a
            // club has to field on Sunday, and "tap a player to go under it"
            // under a legal 53 is advice to play a man short. A release is
            // still possible — the row taps and the commit both stand — the
            // copy simply does not solicit one.
            guard let next = nextRung, !isComplete else {
                return .init(
                    title: "Cutdown complete",
                    message: "Your roster is at **\(activeRoster.count)**. Nothing more is owed here."
                )
            }
            return .init(
                title: "\(stage.slatTitle) is banked",
                message: "At **\(activeRoster.count)**. Next: **\(next.slatTitle)**\(dueClause(for: next)). "
                    + "Tap a player to go under it."
            )
        }
        if selectedIDs.isEmpty {
            // Reached only while the rung is still owed — the banked branch
            // above has already returned otherwise — so `remaining` is always
            // positive here and the bar is always the orange blocked state.
            return .init(
                title: "Nobody selected",
                message: "You are **\(remaining) over** the \(stage.target)-man limit. Tap a player to mark him for release.",
                isWarning: true
            )
        }
        // #208a — a sheet that would empty a position room is refused HERE, in
        // the orange state §2.12 reserves for a blocked commit, rather than by a
        // grey button with nothing to say.
        if let short = selectionViolations.first {
            return .init(
                title: "\(short.position.rawValue) room would be short",
                message: "This leaves **\(short.after)** at \(short.position.rawValue) against a "
                    + "**\(short.minimum)**-man minimum. Unmark someone in that room to release the rest.",
                isWarning: true
            )
        }
        let ps = practiceSquadIDs.intersection(selectedIDs).count
        let psLine = ps > 0 ? " **\(ps)** flagged for the practice squad." : ""
        return .init(
            title: "Release \(selectedIDs.count) \u{2014} \(activeRoster.count - selectedIDs.count) left on the roster",
            message: "Frees **\(money(selectionSavings))** and leaves **\(money(selectionDeadMoney))** of dead money.\(psLine)"
        )
    }

    // MARK: - The ending (§2.6)

    private func resultSheet(_ result: CutResult) -> some View {
        DSResultSheet(
            tone: result.deadMoney > result.capFreed ? .bad : .neutral,
            eyebrow: "Cutdown \u{00B7} \(result.stage.slatTitle)",
            headline: "\(result.released) player\(result.released == 1 ? "" : "s") released",
            message: resultMessage(result),
            chips: [
                .init(id: "roster", label: "Roster", value: "\(result.rosterAfter)", context: "\(result.released) released"),
                .init(
                    id: "freed",
                    label: "Cap freed",
                    value: money(result.capFreed),
                    context: "this year",
                    valueColor: .success
                ),
                .init(
                    id: "dead",
                    label: "Dead money",
                    value: money(result.deadMoney),
                    context: "stays on the books",
                    valueColor: result.deadMoney > 0 ? .dangerText : .textPrimary
                ),
                .init(
                    id: "ps",
                    label: "Practice squad",
                    value: "\(result.practiceSquadFlagged)",
                    context: "flagged"
                )
            ],
            cost: costLine(result),
            // **Not "Done".** The action bar underneath this sheet already
            // carries a gold "Done — back to <phase>" that leaves the screen,
            // and both were visible in the same frame: one word, one colour,
            // two destinations. This control only ever puts the list back, so
            // it says so.
            continueTitle: result.stillOwed > 0 ? "Keep cutting" : "Back to the list",
            onContinue: { self.result = nil }
        )
    }

    /// What the commit cost — and, **only when somebody was actually flagged**,
    /// what the flag risks.
    ///
    /// Both branches used to append the waiver clause unconditionally, so a
    /// sheet whose own chip read "practice squad · 0 flagged" warned in the next
    /// line that "a flagged man can still be claimed off waivers" — a risk the
    /// user had not taken, priced against a cut he had.
    private func costLine(_ result: CutResult) -> String {
        let dead = result.deadMoney > 0
            ? "**\(money(result.deadMoney))** of dead cap stays on this year's books."
            : "Nothing accelerated onto this year's cap."
        guard result.practiceSquadFlagged > 0 else { return dead }
        let claim = result.practiceSquadFlagged == 1
            ? "**1** flagged man can still be claimed off waivers before you sign him."
            : "**\(result.practiceSquadFlagged)** flagged men can still be claimed off waivers before you sign them."
        return "\(dead) \(claim)"
    }

    /// What the club owes after the commit, in the order it matters: this cut
    /// day first, then the next rung and the phase it falls due in, then the
    /// end of the arc.
    private func resultMessage(_ result: CutResult) -> String {
        var line: String
        if result.stillOwed > 0 {
            line = "Your roster is at **\(result.rosterAfter)**. "
                + "**\(result.stillOwed) more** to release to reach \(result.stage.target)."
        } else if let next = result.nextRung {
            line = "Your roster is at **\(result.rosterAfter)**. "
                + "\(result.stage.slatTitle) is banked \u{2014} next is **\(next.slatTitle)**\(dueClause(for: next))."
        } else {
            line = "Your roster is at **\(result.rosterAfter)**. The cutdown is done."
        }
        // A release that emptied a starter slot used to surface one screen
        // later as a blocking dialog. It is stated here instead, on the receipt
        // for the cut that caused it, and it names the rooms.
        if !result.lineupRefilled.isEmpty {
            let names = result.lineupRefilled.prefix(3).map(\.displayName).joined(separator: ", ")
            let extra = result.lineupRefilled.count > 3 ? " and \(result.lineupRefilled.count - 3) more" : ""
            line += result.lineupRefilled.count == 1
                ? " Your depth chart lost its **\(names)** starter \u{2014} the next man up has been promoted."
                : " Your depth chart lost **\(result.lineupRefilled.count)** starters (\(names)\(extra)) \u{2014} the next men up have been promoted."
        }
        return line
    }

    /// ", due when camp breaks" — but only while that is still in the future.
    ///
    /// A save can reach a phase with a roster the ladder did not expect (an old
    /// save landing in `.rosterCuts` at 80 walks the 75 rung there), and telling
    /// that user his next cut is due "when the preseason slate ends" points him
    /// at a phase he has already played.
    private func dueClause(for rung: CutDay) -> String {
        let here = TaskGenerator.phaseInfo(for: career.currentPhase).order
        let there = TaskGenerator.phaseInfo(for: rung.duePhase).order
        return there > here ? ", due \(rung.dueWhen)" : ""
    }

    // MARK: - Stage, derived

    /// **Every derivation below reads this, never `roster`.** The parameter is
    /// a frozen snapshot; this is the club after the releases already booked.
    private var activeRoster: [Player] { liveRoster ?? roster }

    /// The stage the club is working to, read off the roster **and the
    /// calendar** rather than stored.
    ///
    /// The count alone was enough while all three rungs fell due on the same
    /// day. Now they do not: a club that reaches 75 in training camp is done
    /// for that phase, but a purely count-derived stage rolls straight on to
    /// "Cut to 65" and starts demanding ten more releases weeks before the
    /// preseason is played — a red warning bar for work that is not owed yet.
    ///
    /// So the ladder counts down only as far as the calendar has reached: take
    /// the count's answer, but never past the rung `career.currentPhase` is due
    /// to deliver. The ladder counts DOWN, so "not past" is the LARGER target.
    /// Off the cut calendar entirely (the cap workspace can open this screen in
    /// any phase) there is no rung due, and the derivation falls back to
    /// exactly what it was before.
    private var stage: CutDay { dueStage(forRosterCount: activeRoster.count) }

    /// The derivation itself, so the result sheet can ask it about the roster
    /// the commit just produced without re-stating the rule.
    private func dueStage(forRosterCount count: Int) -> CutDay {
        let byCount = CutDay.stage(forRosterCount: count) ?? .cut65To53
        guard let due = CutDay.rung(dueIn: career.currentPhase) else { return byCount }
        return byCount.target > due.target ? byCount : due
    }

    /// The whole 80 → 53 arc is behind the club — the roster is legal for the
    /// season opener **and** the calendar has walked the ladder all the way
    /// down. Both halves are needed: a club that is already at 50 in training
    /// camp is legal, but the preseason and cutdown rungs have not happened
    /// yet, and claiming "cutdown complete" over a band whose last two slats
    /// are still drawn as future is the header lying about the body.
    private var isComplete: Bool {
        activeRoster.count <= CutDay.cut65To53.target && stage == .cut65To53
    }

    /// **This** cut day is banked — the roster is at or under the rung the
    /// calendar is currently asking for. The commit surface reads this, not
    /// `isComplete`: in training camp at 75 there is nothing more owed, even
    /// though two rungs of the ladder are still ahead.
    private var isDueStageComplete: Bool { activeRoster.count <= stage.target }

    /// The rung after the one in hand, if the ladder has one left.
    private var nextRung: CutDay? {
        guard let index = CutDay.allCases.firstIndex(of: stage),
              index + 1 < CutDay.allCases.count else { return nil }
        return CutDay.allCases[index + 1]
    }

    /// Men over this stage's limit before any selection.
    private var requiredCuts: Int { max(0, activeRoster.count - stage.target) }

    /// Men still to be marked after the current selection.
    private var remaining: Int { max(0, activeRoster.count - selectedIDs.count - stage.target) }

    /// The rows, worst first.
    ///
    /// The list used to come out in whatever order SwiftData handed back — not
    /// by rating, not by name, not by room — so finding the twelve worst men in
    /// 87 rows meant scanning all of them and holding the answer in your head,
    /// three times a cutdown. `cutOrder` is the evaluator's ranking, taken once
    /// per fetch; the name breaks a tie so two men on one score cannot swap
    /// places between renders.
    private var filteredRoster: [Player] {
        activeRoster
            .filter { positionGroup.includes($0.position) }
            .sorted { lhs, rhs in
                let left = cutOrder[lhs.id] ?? Int.max
                let right = cutOrder[rhs.id] ?? Int.max
                return left == right ? lhs.fullName < rhs.fullName : left < right
            }
    }

    // MARK: - Positional integrity (#208a)

    /// Why this row is closed, straight off the engine's guard. The view never
    /// re-states the rule — `RosterCutEvaluator` owns it, and the AI's trim
    /// reads the same table through `recommendCuts`.
    ///
    /// Asked through `CapManagementEngine` rather than the evaluator directly
    /// (#208 G1): the door `applyRelease` checks and the sentence this row shows
    /// have to be produced by the same call, or the sheet can offer a tick the
    /// commit then silently refuses. `team` is only in reach once the club has
    /// loaded; until then no row can be ticked anyway (`performCuts` needs it
    /// too), so an unguarded render is not a reachable commit.
    ///
    /// `given` is the live selection unless a caller is building one of its own
    /// — `suggestCuts` walks the evaluator's plan through the same door one man
    /// at a time, so the floors close on it exactly as they close on a row.
    private func releaseBlockReason(for player: Player, given selection: Set<UUID>? = nil) -> String? {
        guard let team = loadedTeam else { return nil }
        return CapManagementEngine.releaseBlockReason(
            player: player,
            team: team,
            roster: activeRoster,
            alreadySelected: selection ?? selectedIDs
        )
    }

    /// Rooms the live selection touches — the confirm dialog's football half.
    private var selectionImpacts: [RosterCutEvaluator.PositionImpact] {
        RosterCutEvaluator.positionImpacts(roster: activeRoster, releasing: selectedIDs)
    }

    /// Rooms the live selection would leave short.
    ///
    /// Belt and braces: the rows above cannot produce such a selection, but the
    /// roster underneath this screen is re-fetched after every commit and can
    /// move under a selection that was legal when it was made (a trade
    /// elsewhere, an injury). The commit checks again rather than trusting that
    /// the list it was drawn from is still the list.
    private var selectionViolations: [RosterCutEvaluator.PositionImpact] {
        selectionImpacts.filter(\.isViolation)
    }

    /// What the confirm dialog says: **who** is going, then the money, then the
    /// rooms — and the clause that cannot be taken back, alone on the last line.
    ///
    /// All of it used to run together as one paragraph whose seventh wrapped
    /// line ended "Releases cannot be undone.", and it never named a man: the
    /// only record of who was leaving was twelve red outlines behind the dimmed
    /// alert, most of them scrolled off. A system alert is the wrong shape for a
    /// table, but it holds a list and it holds paragraph breaks, and those are
    /// the two things the sentence was missing.
    private var confirmMessage: String {
        var lines: [String] = []
        let leaving = selectedIDs
            .compactMap { id in activeRoster.first(where: { $0.id == id }) }
            .sorted { lhs, rhs in
                lhs.position.rawValue == rhs.position.rawValue
                    ? lhs.fullName < rhs.fullName
                    : lhs.position.rawValue < rhs.position.rawValue
            }
        // Named in full up to a sheet the alert can still show whole; past that
        // the tail is counted rather than allowed to push the money off-screen.
        let named = leaving.prefix(15).map { "\($0.position.rawValue) \($0.fullName)" }
        if !named.isEmpty {
            let overflow = leaving.count - named.count
            lines.append(named.joined(separator: "\n") + (overflow > 0 ? "\n+ \(overflow) more" : ""))
        }
        lines.append(
            "Frees \(money(selectionSavings)) and leaves \(money(selectionDeadMoney)) of dead money on this year's books."
        )
        let impacts = selectionImpacts
        if !impacts.isEmpty {
            lines.append("Position groups after this: " + impacts.map(\.line).joined(separator: " \u{00B7} ") + ".")
        }
        if let short = selectionViolations.first {
            lines.append(
                "\(short.position.rawValue) would be left with \(short.after) \u{2014} "
                + "under the \(short.minimum)-man minimum. Unmark someone in that room first."
            )
        } else {
            lines.append("Releases cannot be undone.")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Selection

    private func toggleSelection(_ player: Player) {
        if selectedIDs.contains(player.id) {
            selectedIDs.remove(player.id)
            // The flag rides on the release, so taking the man off the sheet
            // takes his flag with him rather than leaving a tick nothing draws
            // and the next mark would silently restore.
            practiceSquadIDs.remove(player.id)
        } else {
            selectedIDs.insert(player.id)
        }
    }

    /// Fills the sheet from the evaluator's worst-first plan.
    ///
    /// The plan is re-checked man by man on the way in rather than trusted
    /// wholesale: `recommendCuts` guards a room down to one body, while the
    /// release door is stricter (two at QB, and never the last healthy man), so
    /// a plan taken at face value could seed a selection the commit would then
    /// refuse.
    private func suggestCuts() {
        var picked: Set<UUID> = []
        for player in RosterCutEvaluator.recommendCuts(
            roster: activeRoster,
            targetCount: stage.target,
            modelContext: modelContext
        ) {
            guard releaseBlockReason(for: player, given: picked) == nil else { continue }
            picked.insert(player.id)
        }
        selectedIDs = picked
    }

    private func togglePracticeSquad(_ player: Player) {
        if practiceSquadIDs.contains(player.id) {
            practiceSquadIDs.remove(player.id)
        } else {
            practiceSquadIDs.insert(player.id)
        }
    }

    private func initials(for player: Player) -> String {
        let f = player.firstName.first.map(String.init) ?? ""
        let l = player.lastName.first.map(String.init) ?? ""
        return "\(f)\(l)"
    }

    // MARK: - Money

    /// The share of the league year still unpaid, for the release split (#26).
    /// Cutdown day is an offseason phase, so this is 1.0 in the normal flow —
    /// it is read from the career anyway so a release made while the regular
    /// season is running prices the remaining game checks, not a full year.
    private var leagueYearRemaining: Double {
        CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase,
            week: career.currentWeek
        )
    }

    private func releaseSplit(for player: Player) -> CapManagementEngine.ReleaseCapSplit {
        CapManagementEngine.releaseCapSplit(
            player: player,
            contract: contractsByPlayer[player.id],
            capMode: career.capMode,
            leagueYearRemaining: leagueYearRemaining
        )
    }

    /// What the current selection frees, quoted from the same engine the cut
    /// itself books (#68), so the bar and the ledger cannot disagree.
    private var selectionSavings: Int {
        selectedIDs.reduce(0) { total, id in
            guard let player = activeRoster.first(where: { $0.id == id }) else { return total }
            return total + releaseSplit(for: player).capSavings
        }
    }

    /// What it leaves behind — the honest second number §2.4 asks every cost to
    /// carry.
    private var selectionDeadMoney: Int {
        selectedIDs.reduce(0) { total, id in
            guard let player = activeRoster.first(where: { $0.id == id }) else { return total }
            return total + releaseSplit(for: player).deadCap
        }
    }

    /// Net cap effect of releasing this man — relief minus the dead money that
    /// stays behind.
    ///
    /// `money` quotes tenths of a million, so anything under $50K collapsed to
    /// "$0.0M" on a third of the list. A floor is quoted instead: a saving too
    /// small to print is still a saving, and it is not the same reading as a
    /// release that frees exactly nothing.
    private func capSavingsLabel(_ split: CapManagementEngine.ReleaseCapSplit) -> String {
        let savings = split.capSavings
        guard savings != 0 else { return "$0.0M" }
        let sign = savings < 0 ? "\u{2212}" : "+"
        return abs(savings) < 50 ? "\(sign)<$0.1M" : sign + money(abs(savings))
    }

    /// Green frees room, red costs it, grey does neither.
    private func capSavingsColor(_ split: CapManagementEngine.ReleaseCapSplit) -> Color {
        if split.capSavings < 0 { return .dangerText }
        return split.capSavings == 0 ? .textTertiaryReadable : .success
    }

    /// The money column names what it is, for a reader who cannot see that the
    /// figure is green and sitting above a dead-cap line.
    private func capSavingsAccessibilityLabel(_ split: CapManagementEngine.ReleaseCapSplit) -> String {
        let cap = split.capSavings < 0
            ? "Releasing him costs \(money(abs(split.capSavings))) of cap space"
            : "Releasing him frees \(money(split.capSavings)) of cap space"
        let dead = split.deadCap > 0
            ? "and leaves \(money(split.deadCap)) of dead money"
            : "and leaves no dead money"
        return "\(cap) \(dead)"
    }

    private func money(_ thousands: Int) -> String {
        String(format: "$%.1fM", Double(thousands) / 1_000.0)
    }

    // MARK: - Data

    /// Detailed deals for this club, keyed by player. Most players have none —
    /// `Contract` rows are only minted for realistic-mode signings — and the
    /// engine falls back to the 15 %/yr proxy for the rest.
    ///
    /// The cut ledger is read in the same pass: a finished slat has to be able
    /// to report what it produced, and the `RosterCut` rows are where that lives
    /// across a relaunch.
    ///
    /// **And the roster itself**, because the whole ladder is derived from its
    /// count. This is the only hook that puts the released men back out of the
    /// list and moves the stage on.
    private func loadLedger() {
        guard let teamID = career.teamID else { return }
        let fetched = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        ))) ?? []
        liveRoster = fetched
        cutOrder = Dictionary(
            uniqueKeysWithValues: fetched
                .sorted { RosterCutEvaluator.keepScore(for: $0) < RosterCutEvaluator.keepScore(for: $1) }
                .enumerated()
                .map { ($0.element.id, $0.offset) }
        )
        // #208 G1 — the club the row guard measures against, fetched once here
        // rather than per row.
        loadedTeam = try? modelContext.fetch(
            FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.id == teamID })
        ).first

        let contractRows = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.teamID == teamID }
        ))) ?? []
        contractsByPlayer = Dictionary(
            contractRows.map { ($0.playerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let season = career.currentSeason
        let cutRows = (try? modelContext.fetch(FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> { $0.teamID == teamID && $0.seasonYear == season }
        ))) ?? []
        var byStage: [CutDay: Int] = [:]
        for cut in cutRows {
            guard let day = CutDay(rawValue: cut.cutDayRaw) else { continue }
            byStage[day, default: 0] += 1
        }
        releasesByStage = byStage
    }

    private func performCuts() {
        guard let teamID = career.teamID, !selectedIDs.isEmpty else { return }
        // #208a — the last gate before the releases are booked. The rows and the
        // action bar both refuse an illegal sheet already; this is the one that
        // holds when the roster moved between the tap and the confirm.
        guard selectionViolations.isEmpty else { return }
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.id == teamID })
        guard let team = try? modelContext.fetch(teamDescriptor).first else { return }

        let bankedStage = stage
        let now = Date()
        var released = 0
        var capFreed = 0
        var deadMoney = 0
        var psFlagged = 0

        for id in selectedIDs {
            guard let player = activeRoster.first(where: { $0.id == id }) else { continue }
            // A man already off the books cannot be released twice: without this
            // a stale tap would re-run `applyRelease` on a `teamID == nil`
            // player and book a second, $0 `RosterCut` row for him.
            guard player.teamID == teamID else { continue }
            // ONE authority for the money AND the roster move: this screen used
            // to write a receipt and nothing else — the player stayed on the 53
            // and not a cent of dead cap ever reached `currentCapUsage` (#68).
            let split = CapManagementEngine.applyRelease(
                player: player,
                team: team,
                // #208 G1 — the sheet's own roster, so the door does not re-fetch
                // one for each of the ~27 releases a cutdown books. Men already
                // released in this loop have a cleared `teamID` and drop out of
                // the room the engine counts, so the floors close one man at a
                // time exactly as the row guard promised they would.
                authority: .club(roster: activeRoster),
                contract: contractsByPlayer[player.id],
                capMode: career.capMode,
                leagueYearRemaining: leagueYearRemaining,
                careerID: career.id,
                reason: .campCut,
                seasonYear: career.currentSeason,
                modelContext: modelContext
            )
            // Refused at the door: nothing was booked, so nothing is stamped and
            // nothing is counted. Unreachable while the row guard and
            // `selectionViolations` agree with it — which is the point of
            // checking a third time.
            guard !split.isRefused else { continue }
            let isPS = practiceSquadIDs.contains(player.id)
            // ONE receipt per release (#188). The engine now files the row
            // itself, so this screen no longer writes a second one — two rows
            // for the same cut doubled the Cap screen's dead money and counted
            // the man twice on the cutdown ladder. What the screen still owns
            // is the camp CONTEXT the engine cannot know: which cut day the man
            // went on, and whether the user ticked him for the practice squad.
            // Both are stamped onto the engine's row here.
            //
            // `cutDayRaw` must end up a `CutDay`, not the reason: the waiver
            // sweep, the Hard Knocks burst and this screen's own ladder all
            // gate on `isCampCutdown`, and a row left saying "campCut" would
            // silently drop out of every one of them.
            stampCampContext(
                playerID: player.id,
                teamID: teamID,
                stage: bankedStage,
                practiceSquadEligible: isPS,
                split: split,
                occurredAt: now
            )

            released += 1
            capFreed += split.capSavings
            deadMoney += split.deadCap
            if isPS { psFlagged += 1 }
        }
        try? modelContext.save()

        selectedIDs.removeAll()
        practiceSquadIDs.removeAll()
        // Re-reads the roster as well as the ledger, so the ladder, the list and
        // the count below all move on together.
        loadLedger()
        let rosterAfter = activeRoster.count
        // Releasing a starter used to invalidate the depth chart silently: the
        // only feedback was the blocking "Lineup Incomplete" dialog one screen
        // later, on the next Advance — three rungs of the ladder, three blocks,
        // with nothing on THIS screen saying a marked man was somebody's
        // starter. The chart is reconciled against the surviving roster here,
        // where the hole is made, and the receipt below names the slots that
        // moved. `reconcile` only fills slots the release EMPTIED — a standing
        // starter is never re-ordered, so this cannot quietly undo the user's
        // own chart.
        let refilled = reconcileDepthChart()

        // Every man in the selection was already gone (a stale tap): nothing was
        // booked, so there is nothing to report. The refreshed list above is the
        // correction the user needs to see.
        guard released > 0 else { return }

        // §2.6 — the flow states what it did. It used to advance a `@State`
        // stage and say nothing at all.
        let after = dueStage(forRosterCount: rosterAfter)
        let nextIndex = (CutDay.allCases.firstIndex(of: bankedStage) ?? 0) + 1
        result = CutResult(
            released: released,
            capFreed: capFreed,
            deadMoney: deadMoney,
            practiceSquadFlagged: psFlagged,
            rosterAfter: rosterAfter,
            stage: bankedStage,
            // Measured against the rung that was actually worked, not against
            // whatever the count alone would roll on to: in training camp the
            // count rolls to "cut to 65" the moment the club touches 75, and
            // reporting ten men still owed there would invent work.
            stillOwed: max(0, rosterAfter - max(bankedStage.target, after.target)),
            nextRung: nextIndex < CutDay.allCases.count ? CutDay.allCases[nextIndex] : nil,
            lineupRefilled: refilled
        )
    }

    /// Prunes the released men out of the saved depth chart and re-fills the
    /// starter slots that leaves empty. Returns the slots it filled.
    ///
    /// No chart saved means nothing to reconcile: `depthChartData == nil` is the
    /// state the required "Set depth chart" task owns, and writing one here
    /// would silently complete somebody else's task.
    @discardableResult
    private func reconcileDepthChart() -> [DepthChartSlot] {
        let filled = DepthChart.reconcileSaved(career: career, roster: activeRoster)
        try? modelContext.save()
        return filled
    }

    /// Turns the engine's release receipt into a **camp cutdown** row.
    ///
    /// `CapManagementEngine.applyRelease` writes one `RosterCut` per release and
    /// stamps `cutDayRaw` with the reason it was given (`campCut` here). Only
    /// this screen knows the rest of the camp context — the ladder stage and the
    /// practice-squad tick — so it is applied to that same row rather than to a
    /// second one.
    ///
    /// The row is found among the context's PENDING inserts first: the receipt
    /// was created moments ago and `save()` has not run yet, so a plain fetch is
    /// not the dependable way to reach it. The persisted fetch is the fallback
    /// for a re-run inside the same league year, and the insert below that is
    /// the last resort — it only ever fires when no receipt exists at all, so it
    /// cannot bring the duplicate back.
    private func stampCampContext(
        playerID: UUID,
        teamID: UUID,
        stage: CutDay,
        practiceSquadEligible: Bool,
        split: CapManagementEngine.ReleaseCapSplit,
        occurredAt: Date
    ) {
        let season = career.currentSeason
        let reasonRaw = ReleaseReason.campCut.rawValue
        let matches: (RosterCut) -> Bool = { row in
            row.playerID == playerID
                && row.teamID == teamID
                && row.seasonYear == season
                && row.cutDayRaw == reasonRaw
        }

        let pending = modelContext.insertedModelsArray
            .compactMap { $0 as? RosterCut }
            .filter(matches)
        let receipt: RosterCut?
        if let first = pending.first {
            receipt = first
        } else {
            let descriptor = FetchDescriptor<RosterCut>(
                predicate: #Predicate<RosterCut> {
                    $0.playerID == playerID && $0.teamID == teamID && $0.seasonYear == season
                }
            )
            receipt = ((try? modelContext.fetch(descriptor)) ?? []).first(where: matches)
        }

        if let receipt {
            receipt.cutDayRaw = stage.rawValue
            receipt.practiceSquadEligible = practiceSquadEligible
            receipt.occurredAt = occurredAt
            receipt.careerID = career.id
            return
        }

        // No receipt reached storage (a release path that filed none): the
        // cutdown ladder, the waiver sweep and the keeper list all read this
        // row, so the screen books it rather than losing the cut.
        let cut = RosterCut(
            playerID: playerID,
            teamID: teamID,
            seasonYear: season,
            cutDayRaw: stage.rawValue,
            capSavings: split.capSavings,
            deadCap: split.deadCap,
            practiceSquadEligible: practiceSquadEligible,
            occurredAt: occurredAt
        )
        cut.releaseReasonRaw = reasonRaw
        cut.careerID = career.id
        modelContext.insert(cut)
    }
}

// MARK: - Cut stages, as the band draws them

extension CutDay {
    /// The roster size this stage is cutting **to**.
    var target: Int {
        switch self {
        case .cut90To75: return 75
        case .cut75To65: return 65
        case .cut65To53: return 53
        }
    }

    /// The slat label. Short on purpose: at three slats across an iPad the band
    /// has room, but the title is still held to the two-line box every other
    /// band lives in.
    var slatTitle: String {
        switch self {
        case .cut90To75: return "Cut to 75"
        case .cut75To65: return "Cut to 65"
        case .cut65To53: return "Cut to 53"
        }
    }

    /// The stage a club of this size is working to, or nil once it is legal.
    /// The same derivation `RosterCutView.stage` uses, exposed so the result
    /// sheet can name what comes next without duplicating the ladder.
    static func stage(forRosterCount count: Int) -> CutDay? {
        if count > CutDay.cut90To75.target { return .cut90To75 }
        if count > CutDay.cut75To65.target { return .cut75To65 }
        if count > CutDay.cut65To53.target { return .cut65To53 }
        return nil
    }

    // MARK: - The ladder on the calendar (#205a §1)

    /// **The phase this rung is due in — the ladder's one calendar authority.**
    ///
    /// All three rungs used to be emitted into `.rosterCuts`, where a club that
    /// had never carried more than 60 men found two of them already satisfied
    /// and the third the only one that meant anything. With camp filling to
    /// `CampRosterEngine.campRosterTarget` (87, ceiling 90) the rungs are real
    /// work, and each falls due at a different point on the
    /// calendar:
    ///
    /// * `.cut90To75` — camp breaks at 75.
    /// * `.cut75To65` — the preseason slate ends at 65.
    /// * `.cut65To53` — cutdown day, as before.
    ///
    /// Three readers derive from this and none of them re-states it:
    /// `TaskGenerator.rosterLadderTask` (the left-menu row),
    /// `WeekAdvancer`'s phase-keyed exit ceiling (the advance gate and the AI
    /// trim), and this screen's own `dueStage` (what it asks the user for).
    var duePhase: SeasonPhase {
        switch self {
        case .cut90To75: return .trainingCamp
        case .cut75To65: return .preseason
        case .cut65To53: return .rosterCuts
        }
    }

    /// The rung that falls due on the way out of `phase`, if any.
    ///
    /// `nil` everywhere else — and every reader treats `nil` as "the calendar
    /// is not asking for a cut here", which is what keeps the screen usable
    /// (and unchanged) when it is opened off-season from the cap workspace.
    static func rung(dueIn phase: SeasonPhase) -> CutDay? {
        allCases.first { $0.duePhase == phase }
    }

    /// When this rung falls due, as a clause that can be dropped into a
    /// sentence — "due **when camp breaks**". Derived copy for `duePhase`, kept
    /// beside it so the two cannot drift.
    var dueWhen: String {
        switch self {
        case .cut90To75: return "when camp breaks"
        case .cut75To65: return "when the preseason slate ends"
        case .cut65To53: return "on cutdown day"
        }
    }

    /// Why this rung falls where it does, in one sentence — the left-menu row's
    /// copy. Kept next to `duePhase` so the two can never say different things.
    var ladderDescription: String {
        switch self {
        case .cut90To75: return "Camp breaks with 75 men on the roster."
        case .cut75To65: return "The preseason slate ends with 65 men on the roster."
        case .cut65To53: return "Cutdown day \u{2014} set the 53-man active roster."
        }
    }
}

// MARK: - Position Groups

private enum CutPositionGroup: String, CaseIterable, Identifiable {
    case all
    case qb
    case backs
    case receivers
    case oline
    case dline
    case lb
    case db
    case st

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .qb:        return "QB"
        case .backs:     return "RB / FB"
        case .receivers: return "WR / TE"
        case .oline:     return "OL"
        case .dline:     return "DL"
        case .lb:        return "LB"
        case .db:        return "DB"
        case .st:        return "ST"
        }
    }

    func includes(_ position: Position) -> Bool {
        switch self {
        case .all:       return true
        case .qb:        return position == .QB
        case .backs:     return position == .RB || position == .FB
        case .receivers: return position == .WR || position == .TE
        case .oline:     return [.LT, .LG, .C, .RG, .RT].contains(position)
        case .dline:     return position == .DE || position == .DT
        case .lb:        return position == .OLB || position == .MLB
        case .db:        return [.CB, .FS, .SS].contains(position)
        case .st:        return position == .K || position == .P
        }
    }
}
