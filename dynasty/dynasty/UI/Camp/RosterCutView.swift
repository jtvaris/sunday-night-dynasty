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
//
// **And then there was nothing to read on the row.** A name, four figures at
// the 11 pt floor and a money column, with ~770 pt of every line left blank —
// on the screen where a GM decides which twelve of eighty-seven men lose their
// jobs. Every fact the decision actually turns on was already in the save and
// none of it was on the row: what the exhibitions showed of the man, whether he
// has grown or fallen off since the season ended, where he sits on the club's
// own depth chart, and where the staff ranked him. So the rows are a table now,
// built on the shared list standard (§2.2 — `DSListRow` / `DSListHeaderRow`,
// the same components the preseason evidence table is drawn with), and five
// decisions hold it together:
//
//  1. **Every new column is a dictionary built once per fetch.** `REPS`/`CASE`
//     roll up the exhibition box scores the preseason already banked on
//     `Career.preseasonState`; `OVR±` is the man's swing since his last
//     `PlayerSeasonHistory` row closed; `DEPTH` is his slot on the saved chart;
//     and the cap split — which the row used to ask the engine for twice a
//     render, 87 times — is priced with the contracts it needs. The list
//     re-renders on every tap, so nothing here may be derived per row.
//  2. **The depth column is a CHART POSITION, not a room count.** A per-position
//     depth tally is the thing this screen must NOT print twice: the list header
//     above already prints selection-adjusted room sizes ("QB 3 → 2"), and a
//     second, un-adjusted count of the same room on every row would contradict
//     it the moment anything was ticked. A man's slot on the club's own depth
//     chart is a different fact, it does not move when a row is ticked, and it
//     is the one the cut is actually made on — a starter, a backup, or nobody's
//     answer at any position.
//  3. **A column with nothing to say for anybody is not drawn.** The cut to 75
//     falls due in training camp, before a single exhibition is played, so REPS
//     and CASE would be eighty-seven identical "no tape" cells there; the depth
//     column is the same when the club has no saved chart. Both are keyed off
//     the data's presence rather than shipped empty — the DS reserves its
//     `empty` tone for a hole the user should ACT on, not for a column that is
//     not this rung's business.
//  4. **The rank is drawn rather than implied.** `cutOrder` has ordered these
//     rows since the ranking shipped and the only thing that said so was a strip
//     of prose above the list. It is the leading column now, and the men inside
//     the rung's own cut count are tinted so the reader can see where the staff
//     would stop.
//  4b. **The money says what it is a share OF.** Every figure on this screen is
//     cap money and the screen never named the cap: two dollar columns, values
//     from +$0.7M to −$20.5M, and the only summary it printed was a headcount.
//     The club's cap position now sits on the strip above the list, the release
//     is priced into a cap-space-after figure on the bar, and the row carries
//     the `HIT` those two columns are the two halves of. Nothing here is a new
//     number: `Team` has held the cap since it was written and `applyRelease`
//     states the identity `HIT` is read from.
//  4c. **The 53 is inspected, not just counted.** `isDueStageComplete` is a pure
//     headcount and `selectionImpacts` dies the moment nothing is ticked, so a
//     roster of four linebackers and five kickers was stamped COMPLETE by a
//     screen that had never looked at its shape. `RoomShape` reads the standing
//     rooms against two tables the app already owns — the release door's floors
//     and the FA engine's per-room ideal — and the completion copy carries what
//     it finds.
//  5. **The header does not scroll.** It sits outside the `ScrollView` rather
//     than pinned inside it: this list is already a fixed band + tabs + strip
//     over a scroller, and one more always-visible row is both cheaper and
//     steadier than a pinned section. Its columns read the same `DSListColumn`
//     constants the cells do, and one gutter constant keeps the two on the same
//     x.
//  6. **A table the user can question.** Twelve comparable columns were laid out
//     as a table and behaved as a fixed list — "who costs the most", "who is
//     30+", "who lost ground since December" all meant scanning 87 rows by eye,
//     three times a cutdown. The numeric headers sort (`DSSortState`, the shared
//     rule: a fresh tap opens descending) and a name field reaches one man
//     directly. The staff's ranking stays the default and the strip above the
//     list is the way back to it, so the answer the screen came with is never
//     the thing a sort throws away.

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
    @State private var ledgerByStage: [CutDay: StageLedger] = [:]
    /// Practice-squad flags already banked on the rungs behind this one. The
    /// squad is a CEILING across the whole cutdown, so a rung that cannot see
    /// what the earlier rungs spent cannot tell the user when it is full.
    @State private var practiceSquadBanked = 0
    /// What releasing each man would do to the cap, priced once per fetch.
    ///
    /// `releaseCapSplit` re-reads the deal, the cap mode and the share of the
    /// league year still owed on every call, and the row asked it for a figure
    /// that cannot move until the next commit — 87 engine calls on every tap of
    /// every row. It is priced in the same pass that fetches the contracts it
    /// needs. `releaseSplit(for:)` still falls back to the engine for a man who
    /// is not in the map, so the opening render off the shell's snapshot is
    /// unchanged.
    @State private var releaseSplits: [UUID: CapManagementEngine.ReleaseCapSplit] = [:]
    /// The man's overall swing since his last finished season closed.
    @State private var ovrTrend: [UUID: OVRTrend] = [:]
    /// Where each man stands on the club's SAVED depth chart. Empty, and
    /// `hasDepthChart` false, when the club has not set one — see the file
    /// header, decision 3.
    @State private var depthByPlayer: [UUID: DepthSpot] = [:]
    @State private var hasDepthChart = false
    /// What the exhibitions showed of each man, rolled up across the slate.
    @State private var tapeByPlayer: [UUID: PreseasonTape] = [:]
    /// Exhibitions actually played, i.e. how much tape there is to have. Zero
    /// until the preseason has been simmed, which is what hides the two tape
    /// columns at the cut-to-75 rung.
    @State private var slateGamesPlayed = 0
    /// The commit is irreversible, so it asks first.
    @State private var showCutConfirm = false
    /// **The one modal slot.** One `.sheet(item:)`, per the house rule.
    @State private var result: CutResult?
    /// Which column the table is ordered by. Opens on the staff's own ranking,
    /// which is the answer the screen exists to offer; every other key is the
    /// user asking a question of his own.
    @State private var sort = DSSortState<CutSortKey>(key: .staff)
    /// A name filter over the list. Eighty-seven rows and a fourteen-column
    /// table had no way to reach one man.
    @State private var nameQuery = ""
    /// The column glossary — see `legendButton`.
    @State private var showsLegend = false

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

    // MARK: - What the new columns hold

    /// What one finished rung actually produced.
    ///
    /// The slats used to report a headcount and nothing else, while the
    /// `RosterCut` rows they are counted from carry the money per release. Two
    /// numbers were in hand and thrown away on the one screen where the club's
    /// cap position is otherwise never stated.
    struct StageLedger {
        var released = 0
        var capFreed = 0
        var deadMoney = 0
    }

    /// The columns the table can be ordered by. `staff` is the evaluator's own
    /// worst-first ranking — the order the list has always shipped in — and it
    /// is a case rather than an absence so the header can mark "no column
    /// active" and the caption can offer the way back to it.
    enum CutSortKey: Hashable {
        case staff, ovr, trend, age, years, hit, frees, dead

        var label: String {
            switch self {
            case .staff:  return "the staff's order"
            case .ovr:    return "OVR"
            case .trend:  return "OVR\u{00B1}"
            case .age:    return "age"
            case .years:  return "years left"
            case .hit:    return "cap hit"
            case .frees:  return "cap freed"
            case .dead:   return "dead money"
            }
        }
    }

    /// One man's overall swing across the offseason.
    ///
    /// `PlayerSeasonHistory.overallAtEndOfSeason` is snapshotted at week 18
    /// *before* any offseason development or age regression runs, so the
    /// difference against his live `overall` is exactly what the offseason and
    /// camp did to him — the one reading on this screen that is a direction
    /// rather than a level. A man with no finished season on record (a rookie,
    /// or an import with no backstory) has no trend at all, and the cell says
    /// so rather than printing a zero he did not earn.
    struct OVRTrend {
        let delta: Int
        /// The season the comparison is against, for the spoken label.
        let sinceSeason: Int
    }

    /// Where a man sits on the club's saved depth chart, display-ready.
    struct DepthSpot {
        /// The slot's own name for a starter ("QB", "WR2"), "Backup" for anyone
        /// behind one, the return job when that is all the chart says about him.
        let label: String
        let tone: DSStatusPill.Tone
        let spoken: String
    }

    /// What the exhibition slate showed of one man, rolled up.
    ///
    /// The **verdict is the engine's, once per game.** `PreseasonEngine.CampCase`
    /// measures a box score against what the position asks of a man with that
    /// many chances *on one afternoon*; handing it a three-game total would score
    /// a slate against a single game's bar. So each game is read on its own and
    /// this type counts the readings — which is arithmetic over the engine's
    /// answers, not a second opinion about football.
    struct PreseasonTape {
        /// Exhibitions he was in uniform for.
        let games: Int
        /// Chances the box score could see, summed — throws, touches, targets,
        /// credited defensive events, kicks. The sim keeps no snap counter
        /// (`PlayerGameStats` has no such column and `SeasonStatLine.snapsPlayed`
        /// is a regular-season figure), so this is the honest spelling of "how
        /// much of him did we actually get to see".
        let opportunities: Int
        let verdict: PreseasonCampCase.Verdict
        /// The slate's box score in the club's own shorthand, or `nil` when he
        /// dressed and never appeared in one.
        let line: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            tabBar
            listHeader
            columnHeader
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
        let ledger = ledgerByStage[day]
        let outcome = state == .done ? ledger.flatMap(outcomeLine) : nil
        return DSSlat(
            id: day.rawValue,
            index: "\(position)",
            title: day.slatTitle,
            subcaption: state == .current ? currentSubcaption : nil,
            state: state,
            outcome: outcome,
            accessibilityText: [
                "Cut stage \(position) of \(CutDay.allCases.count)",
                day.slatTitle,
                state == .done ? "complete" : (state == .current ? "current stage" : "not started"),
                state == .done ? ledger.flatMap(spokenOutcome) : nil,
                state == .current ? currentSubcaption : nil
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    /// **What the rung produced, not just how many men it took.**
    ///
    /// The receipts the ladder is counted from carry `capSavings` and `deadCap`
    /// per release, and the slat reduced them to a headcount — so thirty-four
    /// men could leave a roster across three phases and the screen could not say
    /// what any of it freed. The dead half is dropped when it is zero rather
    /// than printed as "$0.0M dead", which reads as a cost that was paid.
    private func outcomeLine(_ ledger: StageLedger) -> String? {
        guard ledger.released > 0 else { return nil }
        // A rung that moved no money says so by not mentioning any: the cut to
        // 75 is a rung of camp bodies whose minimums were never charged to the
        // cap in the first place, and "+$0.0M" there reads as a saving that
        // failed rather than as a rung with no money in it.
        guard ledger.capFreed != 0 || ledger.deadMoney != 0 else {
            return "\(ledger.released) released"
        }
        var line = "\(ledger.released) released \u{00B7} \(signedMoney(ledger.capFreed))"
        if ledger.deadMoney > 0 { line += " \u{00B7} \(money(ledger.deadMoney)) dead" }
        return line
    }

    private func spokenOutcome(_ ledger: StageLedger) -> String? {
        guard ledger.released > 0 else { return nil }
        let freed = ledger.capFreed < 0
            ? "cost \(money(-ledger.capFreed)) of cap space"
            : "freed \(money(ledger.capFreed)) of cap space"
        return "\(ledger.released) released, \(freed), left \(money(ledger.deadMoney)) of dead money"
    }

    /// **The one place the stage count is printed** (§2.1).
    ///
    /// On the finished ladder it prints the fact the action bar cannot carry
    /// instead of a second "Cutdown complete": the bar owns what to DO and says
    /// that phrase in gold 800 pt below, and the ladder's own three green slats
    /// have already asserted the state twice more. What nothing else says is how
    /// many men the whole cutdown took.
    private var headline: String {
        guard !isComplete, let index = CutDay.allCases.firstIndex(of: stage) else {
            let released = ledgerByStage.values.reduce(0) { $0 + $1.released }
            return released > 0
                ? "\(released) released \u{00B7} \(activeRoster.count) on the roster"
                : "\(activeRoster.count) on the roster"
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
        HStack(spacing: DSSpacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(CutPositionGroup.allCases) { group in
                        chip(for: group)
                    }
                }
                .padding(.leading, DSSpacing.md)
                // The chips claim their own 44 pt now, so the strip's own
                // padding comes down to keep the bar the height it was.
                .padding(.vertical, DSSpacing.xxs)
            }
            searchField
            // The glossary rides in the controls row rather than on the strip
            // below it: this row is already 44 pt tall, so the help gets a full
            // §2.12 target without a 28 pt compromise and without pushing the
            // list down the page.
            legendButton
                .padding(.trailing, DSSpacing.md)
        }
        .background(Color.backgroundPrimary)
    }

    /// One position filter.
    ///
    /// **Selection is carried by the fill and the label, not by a blue ring.**
    /// Blue already means three other things in this one viewport — an offensive
    /// position badge, the 70s OVR band, and a practice-squad flag — and the chip
    /// is the cheapest of the four to move, because it changes its fill as well
    /// (§2.13's colour discipline).
    private func chip(for group: CutPositionGroup) -> some View {
        let isSelected = positionGroup == group
        return Button {
            positionGroup = group
        } label: {
            // The room's size, on the chip. A bare "DL" makes you tap it to find
            // out how deep the group is, and depth is the whole question this
            // screen is asking.
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
                    .fill(isSelected ? Color.backgroundTertiary : Color.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(
                        isSelected ? Color.textTertiaryReadable : Color.surfaceBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            // The chip's box is a 30 pt pill and this is the screen's primary
            // navigation control: the finger gets the 44 pt §2.12 asks for
            // without the drawn chip growing — the same pattern the Stash
            // toggle on this file already uses.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// **Reaching one man in eighty-seven rows.** The chips narrow by room and
    /// the columns sort, but neither answers "where is Braithwaite" — and the
    /// list is long enough that scrolling for a name is the slowest thing on the
    /// screen.
    private var searchField: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "magnifyingglass")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
            TextField("Find a player", text: $nameQuery)
                .textFieldStyle(.plain)
                .font(DSType.text(DSType.Size.footnote, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
            if !nameQuery.isEmpty {
                Button {
                    nameQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .frame(width: 180, height: 44)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    /// **What order the rows are in, what the club's money is, and what the
    /// rooms hold.**
    ///
    /// The list shipped in whatever order SwiftData handed it back and said
    /// nothing about either, so the ranking was invisible and the position
    /// depth — the actual decision variable — was named for the first time
    /// inside the confirm alert, after all twelve men were already picked. Both
    /// read here now, off data the screen has held since it loaded.
    ///
    /// Two more readings joined them, and for the same reason. **The cap** was
    /// nowhere on a screen whose two money columns are both cap money — a user
    /// could price fourteen releases to the tenth of a million without ever
    /// being told what the club was spending against. And **the rooms** were
    /// only ever checked while something was ticked (`selectionImpacts` returns
    /// nothing for an empty selection), so the finished 53 was certified by a
    /// headcount and never inspected for shape.
    private var listHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                orderCaption
                ForEach(stripNotes) { note in
                    Text(note.line.uppercased())
                        .font(DSType.display(11, .heavy))
                        .tracking(0.7)
                        .foregroundStyle(note.tint)
                        .fixedSize()
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.xxs)
        }
        .background(Color.backgroundPrimary)
    }

    /// The order the rows are in — and, once the user has taken the order over
    /// from the staff, the way back to it. A sorted table with no route home
    /// loses the one answer this screen was built to give.
    @ViewBuilder
    private var orderCaption: some View {
        if sort.key == .staff {
            Text("Worst first \u{00B7} your staff's cut order".uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textTertiaryReadable)
                .fixedSize()
        } else {
            Button {
                sort = DSSortState(key: .staff)
            } label: {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Sorted by \(sort.key.label) \u{00B7} back to the staff's order".uppercased())
                        .tracking(0.7)
                }
                .font(DSType.display(11, .heavy))
                .foregroundStyle(Color.accentBlue)
                .fixedSize()
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sorted by \(sort.key.label). Tap to restore your staff's cut order")
        }
    }

    /// One reading on the strip: a short line and the ink it takes.
    private struct StripNote: Identifiable {
        let id: String
        let line: String
        var tint: Color = .textSecondary
    }

    /// The strip's readings, in the order a GM asks for them: the money, the
    /// squad, then the rooms.
    ///
    /// The rooms are the live plan's impacts while something is ticked — that is
    /// the reading that moves and it wins the slot — and the standing shape of
    /// the roster the rest of the time.
    private var stripNotes: [StripNote] {
        var notes: [StripNote] = []
        if let cap = capPosition {
            var line = "Cap \(money(cap.used)) of \(money(cap.cap)) \u{00B7} \(spaceLabel(cap.space))"
            if !selectedIDs.isEmpty {
                // The word "space" is already in the clause before the arrow, so
                // the figure after it is bare — unless it has gone negative,
                // which is a different sentence and has to say so.
                let after = cap.space + selectionSavings
                line += " \u{2192} \(after < 0 ? spaceLabel(after) : money(after)) after"
            }
            notes.append(StripNote(id: "cap", line: line, tint: cap.space < 0 ? .danger : .textSecondary))
        }
        if practiceSquadUsed > 0 {
            notes.append(
                StripNote(
                    id: "ps",
                    line: "PS \(practiceSquadUsed) of \(PracticeSquadEngine.squadSize) flagged",
                    tint: practiceSquadUsed >= PracticeSquadEngine.squadSize ? .alertOrange : .textSecondary
                )
            )
        }
        if selectedIDs.isEmpty {
            notes += shapeWarnings.map {
                StripNote(id: $0.id, line: $0.line, tint: $0.tint)
            }
        } else {
            notes += selectionImpacts.map {
                StripNote(id: $0.id, line: $0.line, tint: $0.isViolation ? .danger : .textSecondary)
            }
        }
        return notes
    }

    /// **The screen's own glossary.** Thirteen column heads, eleven of them
    /// abbreviations, and the plain-English sentence for every one of them was
    /// already written — as text only VoiceOver could hear. This shows the same
    /// sentences to the reader who can see the column.
    ///
    /// A popover rather than a sheet: the screen's one `.sheet(item:)` slot
    /// belongs to the result, and a glossary anchored to the control that opened
    /// it is a reference the reader keeps his place under, not a flow.
    private var legendButton: some View {
        Button {
            showsLegend = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(DSType.display(DSType.Size.footnote, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What the columns mean")
        .popover(isPresented: $showsLegend) {
            legend
        }
    }

    private var legend: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("What the columns mean".uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(Color.textTertiaryReadable)
                ForEach(legendEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {  // ds-lint:allow(spacing) term-over-definition lockup
                        Text(entry.term.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.textPrimary)
                        Text(entry.meaning)
                            .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(DSSpacing.md)
        }
        .frame(minWidth: 340, minHeight: 420)
        .background(Color.backgroundPrimary)
    }

    /// One line of the glossary.
    private struct LegendEntry: Identifiable {
        let term: String
        let meaning: String

        var id: String { term }
    }

    /// The glossary's copy — the same sentences the cells already build for
    /// VoiceOver, so the two can only ever say the same thing. Columns the rung
    /// is not drawing are left out rather than explained in the abstract.
    private var legendEntries: [LegendEntry] {
        var entries: [LegendEntry] = [
            .init(
                term: "Cut",
                meaning: "Where your staff ranks him, worst first. Men the league's roster rules will not let you release are ranked last."
            ),
            .init(term: "OVR", meaning: "His overall rating today.")
        ]
        let since = ovrTrend.values.map(\.sinceSeason).max()
        entries.append(
            .init(
                term: "OVR\u{00B1}",
                meaning: since.map {
                    "What he has gained or lost since the end of \($0) \u{2014} the offseason and camp in one number. "
                        + "A dash means he has no finished season on record."
                } ?? "What he has gained or lost since his last finished season closed."
            )
        )
        entries.append(.init(term: "Camp", meaning: "The grade your staff put on his training camp."))
        if hasPreseasonTape {
            entries.append(
                .init(
                    term: "Reps",
                    meaning: "Chances the box score could see across the exhibitions \u{2014} throws, touches, targets, credited defensive plays, kicks."
                )
            )
            entries.append(
                .init(term: "Gms", meaning: "Exhibitions he was in uniform for, out of the \(slateGamesPlayed) played.")
            )
            entries.append(
                .init(
                    term: "Case",
                    meaning: "What the tape says he did with those chances: helped himself, held his place, went quiet, or slipped."
                )
            )
        }
        if hasDepthChart {
            entries.append(
                .init(
                    term: "Depth",
                    meaning: "His slot on your saved depth chart. A dash means he is not on it at all \u{2014} no lineup you have written has a use for him."
                )
            )
        }
        entries.append(
            .init(term: "Yrs", meaning: "Years still to run on his deal \u{2014} the same term his dead money is priced on.")
        )
        entries.append(
            .init(
                term: "Hit",
                meaning: "What he charges your cap this year. FREES and DEAD are the two halves it splits into when you release him."
            )
        )
        entries.append(
            .init(
                term: "Frees",
                meaning: "Cap space releasing him would free. A red, negative figure means the release COSTS you space: "
                    + "the bonus accelerating onto the books is worth more than the salary you stop paying."
            )
        )
        entries.append(
            .init(
                term: "Dead",
                meaning: "Signing-bonus money that stays on this year's books after he leaves. An R marks a man who has "
                    + "restructured \u{2014} that money accelerates on top of the original deal, which is the one way DEAD "
                    + "can be larger than the contract."
            )
        )
        entries.append(
            .init(
                term: "PS",
                meaning: "The practice squad. \"Eligible\" is a man young enough to be stashed; the Stash button appears once "
                    + "you mark him for release. Your squad holds \(PracticeSquadEngine.squadSize), at most "
                    + "\(PracticeSquadEngine.maxPerPosition) at a position and \(PracticeSquadEngine.maxQuarterbacks) quarterbacks."
            )
        )
        return entries
    }

    // MARK: - The table (§2.2)

    /// The distance from the screen edge to the first cell: the list's own
    /// inset plus the card's. **The header and the rows both read it**, which is
    /// the only thing keeping a fixed-width column header over the numbers it
    /// labels — §2.2 records that exact defect twice, once on the board and once
    /// on the roster.
    private static let rowGutter: CGFloat = DSSpacing.md + DSSpacing.sm

    /// Whether the exhibitions have produced anything to read yet. False at the
    /// cut-to-75 rung, which falls due in training camp.
    private var hasPreseasonTape: Bool { slateGamesPlayed > 0 }

    /// **The column header, and it does not scroll.**
    ///
    /// Built from `DSListHeaderRow` rather than by hand so the leading gutters —
    /// rank, position badge, portrait — are reserved by the same component that
    /// draws them on the row. A header that labels only the columns it can name
    /// puts every label one slot left of the numbers underneath it.
    private var columnHeader: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, Self.rowGutter)
                .padding(.bottom, DSSpacing.xxs)
            // The band's bottom edge. Without it a header that never moves and a
            // list that does look like one stack that has stopped scrolling.
            Divider().overlay(Color.surfaceBorder)
        }
        .background(Color.backgroundPrimary)
    }

    private var headerRow: some View {
        DSListHeaderRow(
            density: .scan,
            // Tied to the same map the rows read. The very first frame draws the
            // shell's snapshot before `loadLedger` has ranked anybody, and a
            // header that reserved a column the rows below it were not drawing
            // would put every label 24 pt right of its numbers for that frame.
            reservesRank: !cutOrder.isEmpty,
            rankLabel: "Cut",
            reservesBadge: true,
            badgeLabel: "Pos",
            portraitWidth: DSListColumn.scanPortrait,
            identityLabel: hasPreseasonTape ? "Player \u{00B7} preseason tape" : "Player"
        ) {
            Group {
                DSSortableColumnHeader("OVR", key: .ovr, sort: $sort, width: DSListColumn.ovr)
                DSSortableColumnHeader("OVR\u{00B1}", key: .trend, sort: $sort, width: DSListColumn.value)
                DSColumnHeader("Camp", width: DSListColumn.tight)
                if hasPreseasonTape {
                    // Two headers, because they are two unlike numbers. One
                    // "REPS" over a "95" stacked on a "3/3" was the `attribute`
                    // step used for value-over-value where the DS specifies it
                    // for value-over-CAPTION, and nothing on the screen said
                    // which figure was which.
                    DSColumnHeader("Reps", width: DSListColumn.tight)
                    DSColumnHeader("Gms", width: DSListColumn.tight)
                    DSColumnHeader("Case", width: DSListColumn.label)
                }
                if hasDepthChart {
                    DSColumnHeader("Depth", width: DSListColumn.label)
                }
            }
            Group {
                DSSortableColumnHeader("Age", key: .age, sort: $sort, width: DSListColumn.tight)
                DSSortableColumnHeader("Yrs", key: .years, sort: $sort, width: DSListColumn.tight)
                DSSortableColumnHeader("Hit", key: .hit, sort: $sort, width: DSListColumn.money, alignment: .trailing)
                DSSortableColumnHeader("Frees", key: .frees, sort: $sort, width: DSListColumn.money, alignment: .trailing)
                DSSortableColumnHeader("Dead", key: .dead, sort: $sort, width: DSListColumn.money, alignment: .trailing)
                DSColumnHeader("PS", width: DSListColumn.state)
                // The card column has no label — a header word over a row of
                // info buttons names the control, not the reading.
                Color.clear.frame(width: DSListColumn.leadingAction, height: 1)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.xxs) {
                ForEach(filteredRoster, id: \.id) { player in
                    row(for: player)
                }
                if filteredRoster.isEmpty { noMatchesLine }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.sm)
        }
    }

    /// The list can be filtered down to nothing now — a name nobody matches, or
    /// a name nobody in the room the chips are showing matches. An empty
    /// scroller under a full header and a live search field reads as a screen
    /// that has broken rather than as an answer.
    private var noMatchesLine: some View {
        Text(
            nameQuery.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Nobody in this group."
                : "Nobody here matches \u{201C}\(nameQuery)\u{201D}."
        )
        .font(DSType.text(DSType.Size.footnote, .semibold, prose: true))
        .foregroundStyle(Color.textTertiaryReadable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DSSpacing.sm)
    }

    /// One man, as a table line.
    ///
    /// The row is `DSListRow`'s anatomy with nothing invented on top of it:
    /// [cut rank][position][portrait][name + what the tape says][the columns].
    /// The two controls that were always here — the practice-squad flag and the
    /// player card — are the last two columns rather than free-floating
    /// trailing views, so they hold an x instead of drifting with the length of
    /// the name above them.
    private func row(for player: Player) -> some View {
        let isSelected = selectedIDs.contains(player.id)
        let isPS = practiceSquadIDs.contains(player.id)
        let blockReason = releaseBlockReason(for: player)
        let split = releaseSplit(for: player)
        let tape = tapeByPlayer[player.id]
        return DSListRow(
            density: .scan,
            rank: cutRank(for: player),
            badge: DSRowBadge(
                text: player.position.rawValue,
                tint: positionTint(player.position),
                accessibilityLabel: "\(player.position.rawValue), \(player.position.side.rawValue)"
            ),
            portraitWidth: DSListColumn.scanPortrait
        ) {
            portrait(for: player)
        } identity: {
            identityBlock(for: player, blockReason: blockReason, tape: tape)
        } columns: {
            Group {
                ovrCell(player)
                trendCell(player)
                campCell(player)
                if hasPreseasonTape {
                    repsCell(tape)
                    gamesCell(tape)
                    caseCell(tape)
                }
                if hasDepthChart {
                    depthCell(player)
                }
            }
            Group {
                ageCell(player)
                contractYearsCell(player)
                capHitCell(split)
                capFreedCell(split)
                deadCapCell(split, isRestructured: player.restructureDeadMoney > 0)
                practiceSquadCell(player, isSelected: isSelected, isPS: isPS)
                playerCardCell(player)
            }
        }
        // A table line, not a card stack: at 87 rows the old 12 pt inset and
        // 8 pt gutter spent a third of the viewport on air between men who are
        // meant to be compared to one another.
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                // **The recession is in the PLATE, not in the ink.** A blanket
                // `.opacity(0.6)` over the row's content took the only
                // imperative sentence on the screen — the lock line telling the
                // user to sign or trade for a quarterback FIRST — down to
                // 4.02 : 1, under the AA floor, on the one row that is asking
                // him to do something. The row is still visibly set back,
                // because the fill it sits on is; the warning stroke and the
                // padlock already say "closed" twice more.
                .fill(rowFill(isSelected: isSelected, isBlocked: blockReason != nil))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(
                    isSelected ? Color.danger : (blockReason != nil ? Color.warning.opacity(0.5) : Color.surfaceBorder),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
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

    /// The row's plate. A marked man is red, a closed one is set back toward
    /// the page, everyone else takes the card surface.
    private func rowFill(isSelected: Bool, isBlocked: Bool) -> Color {
        if isSelected { return Color.danger.opacity(0.18) }
        return isBlocked ? Color.backgroundSecondary.opacity(0.45) : Color.backgroundSecondary
    }

    // MARK: - The leading slots

    /// **The rank the list is already sorted by, finally drawn.**
    ///
    /// `cutOrder` is the evaluator's worst-first ranking over the WHOLE roster,
    /// so the number survives the position tabs: filtering to the receivers does
    /// not renumber them 1..9, it shows where each of them sits among all
    /// eighty-seven. The men inside the rung's own cut count carry the warn
    /// tint — orange, because it is caution at a stated threshold, and because
    /// the row's own selected state owns red and the action bar owns gold.
    /// `DSRank`'s default tint would have painted the most-cuttable man on the
    /// roster in the call-to-action colour.
    ///
    /// Men the league's rules will not let the club release are ranked last —
    /// see `loadLedger` — so rank 1 is always a man the user can act on.
    private func cutRank(for player: Player) -> DSRank? {
        guard let index = cutOrder[player.id] else { return nil }
        let rank = index + 1
        let isInsideTheCut = requiredCuts > 0 && rank <= requiredCuts
        let tint: Color = isInsideTheCut ? .alertOrange : .textSecondary
        return DSRank(value: rank, tint: tint)
    }

    private func portrait(for player: Player) -> some View {
        Circle()
            .fill(Color.backgroundTertiary)
            // 30 pt, which is the content height a scan row is built around —
            // the rank slot's two reserved rows measure 26 inside it.
            .frame(width: 30, height: 30)
            .overlay(
                Text(initials(for: player))
                    .font(DSType.display(DSType.Size.caption, .bold))
                    .foregroundStyle(Color.textSecondary)
            )
            .accessibilityHidden(true)
    }

    /// The name, and the one line underneath it that is worth the width.
    ///
    /// Three candidates in priority order, and only ever one of them: the reason
    /// this row is closed (§2.12 — a closed row says why, in the row), the tape
    /// the exhibitions produced, or where he stands on the roster. A man who is
    /// blocked has a lock line; a man with a box score has his box score; a man
    /// in August of his rookie year has "Rookie".
    private func identityBlock(
        for player: Player,
        blockReason: String?,
        tape: PreseasonTape?
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {  // ds-lint:allow(spacing) name-over-subline lockup inside one row
            HStack(spacing: DSSpacing.xxs) {
                Text(player.fullName)
                    .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if player.isInjured {
                    // An injury is a fact about the MAN, not a column reading,
                    // so it travels with the name — the same place the preseason
                    // evidence table puts it. `keepScore` docks him six points
                    // for it and the row used to show nothing at all.
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.dangerText)
                        .accessibilityLabel("Injured")
                }
            }
            subline(for: player, blockReason: blockReason, tape: tape)
        }
    }

    @ViewBuilder
    private func subline(
        for player: Player,
        blockReason: String?,
        tape: PreseasonTape?
    ) -> some View {
        if let blockReason {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "lock.fill")
                    .font(DSType.display(10, .bold))
                Text(blockReason)
                    .font(DSType.text(DSType.Size.caption, .semibold, prose: true))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.warning)
        } else if let line = tape?.line {
            Text(line)
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        } else {
            Text(standingLine(for: player))
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
                .lineLimit(1)
        }
    }

    /// Where a man with no tape stands, in the club's own words.
    ///
    /// Service time leads it because it is the fact the cut sheet reads and the
    /// table has no column for: a rookie and an eighth-year veteran on the same
    /// OVR are not the same decision. The practice-squad clause is deliberately
    /// NOT here — the PS column carries it, and saying it twice on one line was
    /// what the old row did with the camp grade.
    private func standingLine(for player: Player) -> String {
        var parts: [String] = []
        parts.append(player.yearsPro <= 0 ? "Rookie" : "\(player.yearsPro) yr pro")
        if player.isInjured {
            parts.append(player.injuryWeeksRemaining > 0 ? "out \(player.injuryWeeksRemaining) wk" : "injured")
        }
        if player.isHoldingOut { parts.append("holding out") }
        if player.rosterStatus != .active { parts.append(player.rosterStatus.displayName.lowercased()) }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - The columns

    private func ovrCell(_ player: Player) -> some View {
        Text("\(player.overall)")
            .font(DSType.display(DSType.Size.body, .heavy))
            .foregroundStyle(Color.forRating(player.overall))
            .dsColumn(DSListColumn.ovr)
            .accessibilityLabel("Overall \(player.overall)")
    }

    /// **The direction, next to the level.** An OVR of 72 means one thing on a
    /// man who was 68 in December and the opposite on a man who was 77.
    @ViewBuilder
    private func trendCell(_ player: Player) -> some View {
        if let trend = ovrTrend[player.id] {
            Text(trendLabel(trend.delta))
                .font(DSType.display(DSType.Size.caption, .heavy))
                .foregroundStyle(trendColor(trend.delta))
                .dsColumn(DSListColumn.value)
                .accessibilityLabel(trendSpoken(trend))
        } else {
            Text("\u{2014}")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
                .dsColumn(DSListColumn.value)
                .accessibilityLabel("No finished season on record")
        }
    }

    private func trendLabel(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\u{2212}\(abs(delta))" }
        return "0"
    }

    private func trendColor(_ delta: Int) -> Color {
        if delta > 0 { return .success }
        if delta < 0 { return .dangerText }
        return .textTertiaryReadable
    }

    private func trendSpoken(_ trend: OVRTrend) -> String {
        guard trend.delta != 0 else { return "Unchanged since the end of \(trend.sinceSeason)" }
        let direction = trend.delta > 0 ? "Up" : "Down"
        return "\(direction) \(abs(trend.delta)) since the end of \(trend.sinceSeason)"
    }

    @ViewBuilder
    private func campCell(_ player: Player) -> some View {
        if let grade = player.campGrade {
            Text(grade.displayLabel)
                .font(DSType.display(DSType.Size.footnote, .heavy))
                .foregroundStyle(gradeColor(grade))
                .dsColumn(DSListColumn.tight)
                .accessibilityLabel("Camp grade \(grade.displayLabel)")
        } else {
            // A blank where every neighbouring row carries a letter reads as a
            // data hole rather than as a fact. Men acquired after camp broke
            // were never graded, and the absence is stated rather than inferred.
            Text("\u{2014}")
                .font(DSType.display(DSType.Size.footnote, .heavy))
                .foregroundStyle(Color.textTertiaryReadable)
                .dsColumn(DSListColumn.tight)
                .accessibilityLabel("No camp grade")
        }
    }

    /// How much of him the slate actually showed: the chances the box score
    /// could see.
    ///
    /// **Two columns, not one cell with two figures in it.** Chances and
    /// exhibitions-dressed are unlike numbers, and stacking them under a single
    /// "REPS" head left the reader to guess which was which — "95 / 3/3" and
    /// "7 / 1/3" with no caption between them. The DS's `attribute` step is a
    /// number over a three-letter CAPTION; this was value over value.
    @ViewBuilder
    private func repsCell(_ tape: PreseasonTape?) -> some View {
        if let tape {
            Text("\(tape.opportunities)")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .foregroundStyle(tape.opportunities > 0 ? Color.textPrimary : Color.textTertiaryReadable)
                .dsColumn(DSListColumn.tight)
                .accessibilityLabel("\(tape.opportunities) chances in the exhibitions")
        } else {
            Text("\u{2014}")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
                .dsColumn(DSListColumn.tight)
                .accessibilityLabel("Did not dress in the preseason")
        }
    }

    /// Exhibitions he was in uniform for, out of the ones played. A zero
    /// alongside a three is a real reading — he dressed for the whole slate and
    /// the box score never once mentioned him.
    @ViewBuilder
    private func gamesCell(_ tape: PreseasonTape?) -> some View {
        if let tape {
            Text("\(tape.games)/\(slateGamesPlayed)")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textSecondary)
                .dsColumn(DSListColumn.tight)
                .accessibilityLabel("Dressed for \(tape.games) of \(slateGamesPlayed) exhibitions")
        } else {
            Text("\u{2014}")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
                .dsColumn(DSListColumn.tight)
                .accessibilityLabel("Dressed for none of the exhibitions")
        }
    }

    @ViewBuilder
    private func caseCell(_ tape: PreseasonTape?) -> some View {
        if let tape {
            DSStatusPill(
                label: tape.verdict.pillLabel,
                tone: tape.verdict.tone,
                showsDot: false,
                spokenLabel: "The tape says he \(tape.verdict.spoken)"
            )
            .dsColumn(DSListColumn.label)
        } else {
            DSStatusPill(
                label: "None",
                tone: .empty,
                showsDot: false,
                spokenLabel: "No preseason tape"
            )
            .dsColumn(DSListColumn.label)
        }
    }

    /// His slot on the club's own chart — see the file header, decision 2. Off
    /// the chart is the `empty` tone on purpose: the DS reserves it for the hole
    /// the reader is scanning FOR, and on this screen that is exactly what a man
    /// nobody's lineup has a use for is.
    ///
    /// **"Off" was the one value in this column that was not football.** Every
    /// other cell in it — BACKUP, WR1, LG, LOLB — is a real abbreviation, so the
    /// column itself trains the reader to take three letters as shorthand, and
    /// then printed "OFF" on a defensive end, where "offense" is flatly false. A
    /// dash cannot be misread as a position, it is the mark this file already
    /// uses for a fact a man does not have (no trend, no camp grade, no tape),
    /// and the glossary spells the column out; the alternative, "Not listed",
    /// does not fit the `label` step without clipping and this row has no width
    /// to spare.
    @ViewBuilder
    private func depthCell(_ player: Player) -> some View {
        if let spot = depthByPlayer[player.id] {
            DSStatusPill(label: spot.label, tone: spot.tone, showsDot: false, spokenLabel: spot.spoken)
                .dsColumn(DSListColumn.label)
        } else {
            DSStatusPill(
                label: "\u{2014}",
                tone: .empty,
                showsDot: false,
                spokenLabel: "Not on the depth chart"
            )
            .dsColumn(DSListColumn.label)
        }
    }

    private func ageCell(_ player: Player) -> some View {
        Text("\(player.age)")
            .font(DSType.display(DSType.Size.caption, .semibold))
            .foregroundStyle(Color.textSecondary)
            .dsColumn(DSListColumn.tight)
            .accessibilityLabel("Age \(player.age)")
    }

    /// **The term the money on this row was priced on.**
    ///
    /// It used to print `player.contractYearsRemaining` while the two money
    /// columns beside it took their acceleration term from
    /// `contract.totalYears - contract.currentYear` whenever a `Contract` row
    /// existed (`CapManagementEngine.tradeCapSplit`). Where the two disagree the
    /// row is not arithmetically possible: a 32-year-old on "YRS 1" with
    /// $74.5M of dead money and −$20.5M of savings is a deal with TWO years to
    /// run, priced correctly and labelled wrongly — and it is the number that
    /// ranks the club's best player fifth in the cut order.
    ///
    /// So the cell reads the same source the split does. `contractTerm` returns
    /// 0 for a man with no years left anywhere, which is the expiring deal the
    /// dash has always meant; the engine's own `max(1, …)` on that case is a
    /// divide-by-zero guard, not a year the club owes.
    private func contractYearsCell(_ player: Player) -> some View {
        let term = contractTerm(for: player)
        return Text(term > 0 ? "\(term)" : "\u{2013}")
            .font(DSType.display(DSType.Size.caption, .semibold))
            .foregroundStyle(Color.textSecondary)
            .dsColumn(DSListColumn.tight)
            .accessibilityLabel(
                term > 0
                    ? "\(term) year\(term == 1 ? "" : "s") left on the deal"
                    : "Expiring deal"
            )
    }

    /// **What he charges the cap this year** — the denominator FREES and DEAD
    /// are both shares of, and the one figure the row left the reader to
    /// reconstruct by adding two columns in his head, 53 times.
    ///
    /// The sum is the engine's own, not a fourth opinion: `applyRelease` states
    /// the ledger identity it books against as "the roster loses a cap hit of
    /// `salaryRelieved + salaryRetained + proratedPerYear`". A camp body reads
    /// $0.0M here, which is exactly why his release frees nothing — his minimum
    /// is deliberately never charged to `Team.currentCapUsage`.
    private func capHitCell(_ split: CapManagementEngine.ReleaseCapSplit) -> some View {
        let hit = capHit(split)
        return Text(hit > 0 ? money(hit) : "\u{2013}")
            .font(DSType.display(DSType.Size.footnote, .heavy))
            .foregroundStyle(hit > 0 ? Color.textPrimary : Color.textTertiaryReadable)
            .dsColumn(DSListColumn.money, alignment: .trailing)
            .accessibilityLabel(
                hit > 0 ? "Costs \(money(hit)) against the cap this year" : "Costs nothing against the cap"
            )
    }

    /// **The money, with its sign.** One unlabelled figure, always prefixed "+"
    /// and always painted success green, was two lies on one row: `capSavings`
    /// is signed, so a release that COSTS cap space rendered in the same green
    /// as one that freed $25M; and a man on a minimum deal rounded to "+$0.0M",
    /// which reads as "free to cut" rather than "saves nothing".
    private func capFreedCell(_ split: CapManagementEngine.ReleaseCapSplit) -> some View {
        Text(capSavingsLabel(split))
            .font(DSType.display(DSType.Size.footnote, .heavy))
            .foregroundStyle(capSavingsColor(split))
            .dsColumn(DSListColumn.money, alignment: .trailing)
            .accessibilityLabel(
                split.capSavings < 0
                    ? "Releasing him costs \(money(abs(split.capSavings))) of cap space"
                    : "Releasing him frees \(money(split.capSavings)) of cap space"
            )
    }

    /// The other half of the same release — the number the confirm dialog and
    /// the receipt both lead with, and which appeared nowhere on the row where
    /// the decision is actually made.
    ///
    /// **The R marks the one dead figure that can outrun the deal.**
    /// `player.restructureDeadMoney` is added OUTSIDE the
    /// `min(rawDead, salary × years)` clamp (`CapManagementEngine.tradeCapSplit`
    /// says why: the restructure charge is bounded by its own construction), so
    /// a restructured man is the only case where DEAD may be larger than
    /// everything left on his contract. Unmarked, that reads as a broken number
    /// on the exact row a GM is least willing to take on trust.
    private func deadCapCell(
        _ split: CapManagementEngine.ReleaseCapSplit,
        isRestructured: Bool
    ) -> some View {
        let hasDead = split.deadCap > 0
        let marked = hasDead && isRestructured
        return HStack(spacing: 2) {  // ds-lint:allow(spacing) footnote marker against its figure
            if marked {
                Text("R")
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .foregroundStyle(Color.alertOrange)
            }
            Text(hasDead ? money(split.deadCap) : "\u{2013}")
                .font(DSType.display(DSType.Size.footnote, .heavy))
                .foregroundStyle(hasDead ? Color.dangerText : Color.textTertiaryReadable)
        }
        .dsColumn(DSListColumn.money, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deadCapSpoken(split, isRestructured: marked))
    }

    private func deadCapSpoken(
        _ split: CapManagementEngine.ReleaseCapSplit,
        isRestructured: Bool
    ) -> String {
        guard split.deadCap > 0 else { return "Leaves no dead money" }
        let base = "Leaves \(money(split.deadCap)) of dead money"
        return isRestructured ? "\(base), restructured money included" : base
    }

    /// **The flag only means anything on a man who is leaving.** It is stamped
    /// onto his release receipt and read back by the practice squad's keeper
    /// pass; on a man you keep it was a toggle that lit up, changed nothing, and
    /// was wiped on commit. So it appears when he is marked.
    ///
    /// What the column says the rest of the time is the fact the old row never
    /// carried anywhere: `RosterCutEvaluator.isPracticeSquadEligible` gates the
    /// stash on service time, so the button used to offer a vested veteran a
    /// landing spot he was not entitled to. The eligible men are marked BEFORE
    /// the tick, which is when it changes the plan. The button's own label can
    /// shorten to "Stash" now that a column header says PS above it.
    ///
    /// **And the squad has a ceiling the screen never mentioned.** The flag is
    /// read back months later by `PracticeSquadEngine.userFlaggedKeepers`, which
    /// sorts the flagged cuts newest-first and takes `prefix(squadSize)` — so a
    /// user working three rungs across three phases with no running tally could
    /// flag twenty men and silently lose the four he flagged FIRST, at the camp
    /// rung, with nothing telling him until the squad filled at the regular-season
    /// boundary. The tick is refused at the ceiling now, and the strip above the
    /// list carries the count.
    @ViewBuilder
    private func practiceSquadCell(_ player: Player, isSelected: Bool, isPS: Bool) -> some View {
        if isSelected, let full = practiceSquadBlockReason(for: player) {
            // Not a dead button: §2.12 wants a closed control to SAY what shut
            // it, and a disabled button inside a row whose own tap releases a
            // man is worse than a chip that cannot be pressed at all.
            DSStatusPill(
                label: "Full",
                tone: .empty,
                showsDot: false,
                spokenLabel: "Cannot be stashed \u{2014} \(full)"
            )
            .dsColumn(DSListColumn.state)
        } else if isSelected {
            Button {
                togglePracticeSquad(player)
            } label: {
                Text(isPS ? "On PS \u{2713}" : "Stash")
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, 3)  // ds-lint:allow(spacing) inline toggle inside a fixed row height
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                            .fill(isPS ? Color.accentBlue : Color.backgroundTertiary)
                    )
                    .foregroundStyle(isPS ? Color.textPrimary : Color.textSecondary)
                    // 44 pt of finger around a 19 pt pill: this control shares a
                    // hit area with the row's own tap, and that tap is the
                    // destructive one. A miss must not be a release.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsColumn(DSListColumn.state)
            .accessibilityLabel(
                isPS
                    ? "\(player.fullName) is flagged for the practice squad"
                    : "Flag \(player.fullName) for the practice squad"
            )
        } else if RosterCutEvaluator.isPracticeSquadEligible(player: player) {
            // `neutral`, not `info`: a camp roster is half rookies, so this
            // lands on forty of the eighty-seven rows and it is a stated fact
            // rather than a recommendation. Forty blue chips would read as the
            // screen pointing at them.
            DSStatusPill(
                label: "Eligible",
                tone: .neutral,
                showsDot: false,
                spokenLabel: "Practice-squad eligible"
            )
            .dsColumn(DSListColumn.state)
        } else {
            // A vested veteran cannot be stashed at all, and an empty cell is
            // the true statement. A dashed `empty` pill would advertise a hole
            // the club has no way to fill.
            Color.clear.frame(width: DSListColumn.state, height: 1)
        }
    }

    /// The row carries a dozen numbers and the tap on it is an irreversible
    /// release, so the man himself was one thing the screen would not show you.
    /// His card pushes onto the shell's own stack and pops straight back onto
    /// the sheet, marks intact.
    private func playerCardCell(_ player: Player) -> some View {
        NavigationLink(destination: PlayerDetailView(player: player)) {
            Image(systemName: "info.circle")
                .font(DSType.display(DSType.Size.footnote, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
                .frame(width: DSListColumn.leadingAction, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(player.fullName)'s player card")
    }

    /// The badge tint, by side — the same three-colour split the preseason
    /// evidence table uses, so a position badge means one thing across camp.
    private func positionTint(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
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
            // still possible — the row taps and the commit both stand — so the
            // gesture is NAMED (it is the most consequential one on the screen
            // and it was the only unlabelled one) without being solicited.
            guard let next = nextRung, !isComplete else {
                return .init(
                    title: "Cutdown complete",
                    message: "Your roster is at **\(activeRoster.count)**\(shapeClause). "
                        + "Nothing more is owed \u{2014} tapping a player still marks him for release."
                )
            }
            return .init(
                title: "\(stage.slatTitle) is banked",
                message: "At **\(activeRoster.count)**\(shapeClause). Next: **\(next.slatTitle)**\(dueClause(for: next)). "
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
        // **What the money is FOR.** The bar priced the release in two figures
        // and neither of them was a position: a saving of $14M means one thing
        // to a club $2M under and another to a club $60M under, and the screen
        // had never said which one this was.
        let spaceLine = capPosition.map {
            " Cap space after: **\(spaceLabel($0.space + selectionSavings))**."
        } ?? ""
        return .init(
            title: "Release \(selectedIDs.count) \u{2014} \(activeRoster.count - selectedIDs.count) left on the roster",
            message: "Frees **\(money(selectionSavings))** and leaves **\(money(selectionDeadMoney))** of dead money.\(psLine)\(spaceLine)"
        )
    }

    /// " — LB 4 (thin), K/P 5 (heavy)": what the finished roster is carrying
    /// that a headcount cannot see. Empty when every room is inside its band,
    /// which is the state a green tick is entitled to.
    private var shapeClause: String {
        let warnings = shapeWarnings
        guard !warnings.isEmpty else { return "" }
        return " \u{2014} " + warnings.map(\.note).joined(separator: ", ")
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
    ///
    /// **And any order the user asks for.** Twelve comparable columns were laid
    /// out as a table and behaved as a fixed list: "who costs the most", "who is
    /// 30+", "who lost ground since December" all meant scanning 87 rows by eye.
    /// The staff's ranking stays the default and the CUT column survives every
    /// other sort, so the answer the screen came with is never lost.
    private var filteredRoster: [Player] {
        let matched = activeRoster.filter {
            positionGroup.includes($0.position) && matchesQuery($0)
        }
        guard sort.key != .staff else {
            return matched.sorted { lhs, rhs in
                let left = cutOrder[lhs.id] ?? Int.max
                let right = cutOrder[rhs.id] ?? Int.max
                return left == right ? lhs.fullName < rhs.fullName : left < right
            }
        }
        return matched.dsSorted(sort.ascending, by: { sortValue(for: $0) }, id: \.id)
    }

    /// The name filter. Matched on the full name so "wade b" reaches Wade
    /// Braithwaite the way a user types it.
    private func matchesQuery(_ player: Player) -> Bool {
        let query = nameQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return player.fullName.localizedCaseInsensitiveContains(query)
    }

    /// The number the active column sorts on. Every key is an Int so one
    /// comparator serves the lot; `dsSorted` supplies the id tiebreak that keeps
    /// the order total.
    private func sortValue(for player: Player) -> Int {
        switch sort.key {
        case .staff: return cutOrder[player.id] ?? Int.max
        case .ovr:   return player.overall
        // A man with no finished season on record sorts below every real
        // reading rather than being given the zero the cell's dash refuses to
        // print: the default descending tap leaves the rookies at the bottom of
        // the column, which is where "no reading" belongs.
        case .trend: return ovrTrend[player.id]?.delta ?? Int.min
        case .age:   return player.age
        case .years: return contractTerm(for: player)
        case .hit:   return capHit(releaseSplit(for: player))
        case .frees: return releaseSplit(for: player).capSavings
        case .dead:  return releaseSplit(for: player).deadCap
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

    // MARK: - The shape of the finished roster

    /// What one room is carrying, against what the league's own tables ask of
    /// it.
    ///
    /// **Neither standard is invented here.** The floor is the release door's
    /// (`RosterCutEvaluator.minimumCount`, the table every cut in the app is
    /// measured against) and `typical` is the free-agency engine's per-room
    /// ideal (`FreeAgencyEngine.positionGroupInfo`) — the same count the AI
    /// builds its own roster to. What this type adds is the reading, not the
    /// standard.
    ///
    /// Why it needs to exist at all: `selectionImpacts` dies the moment nothing
    /// is ticked, and `isDueStageComplete` is a pure headcount, so a 53 with
    /// four linebackers and five kickers was stamped COMPLETE by a screen that
    /// had never looked at its shape.
    private struct RoomShape: Identifiable {
        let group: CutPositionGroup
        let count: Int
        let floor: Int
        let typical: Int
        /// The room holds a position the floors give MORE than one body to —
        /// which is only ever the quarterbacks. See `isAtFloor`.
        let hasReinforcedFloor: Bool

        var id: String { group.rawValue }

        /// Fewer bodies than the room is built to carry.
        var isThin: Bool { count < typical }

        /// Standing on a floor that was raised for a reason.
        ///
        /// Read off `hasReinforcedFloor` rather than off the number, because
        /// every group's floor is a SUM and most of them are 2 or more without
        /// meaning anything: a club with one kicker and one punter is at the
        /// special-teams floor and is also every well-built club in the league.
        /// The quarterbacks are the one room the engine gives a second body to,
        /// and for a stated reason — "a club that carries one quarterback has no
        /// football team the moment he is hurt". Standing on THAT floor is the
        /// club-level version of the lock line one row carries, said once
        /// instead of only to the reader who happened to scroll to it.
        var isAtFloor: Bool { hasReinforcedFloor && count <= floor }

        /// More spare bodies than the whole room asks for.
        ///
        /// Twice `typical` is the line because `typical` ALREADY includes the
        /// room's backups: a club carrying double that is spending roster spots
        /// on a position with nothing left to give them, which is how five
        /// kickers and punters reach cutdown day. It is deliberately a wide
        /// line — this warning sits on a roster the screen is certifying, so it
        /// must only fire on a shape that is actually indefensible.
        var isHeavy: Bool { typical > 0 && count > typical * 2 }

        var isFlagged: Bool { isThin || isHeavy || isAtFloor }

        var line: String {
            if isThin { return "\(group.label) \(count) \u{00B7} thin" }
            if isAtFloor { return "\(group.label) \(count) \u{00B7} at the floor" }
            return "\(group.label) \(count) \u{00B7} heavy"
        }

        var note: String {
            if isThin { return "\(group.label) \(count) (thin)" }
            if isAtFloor { return "\(group.label) \(count) (at the floor)" }
            return "\(group.label) \(count) (heavy)"
        }

        /// Thin and at-the-floor are cautions at a stated threshold; heavy is a
        /// stated fact about where the spots went.
        var tint: Color { isHeavy ? .textSecondary : .alertOrange }
    }

    /// The band each room is read against, built once — neither engine table it
    /// reads can move inside a session, and this screen re-renders on every tap
    /// of every one of ~87 rows.
    private static let roomBands: [CutPositionGroup: (floor: Int, typical: Int, reinforced: Bool)] = {
        var bands: [CutPositionGroup: (floor: Int, typical: Int, reinforced: Bool)] = [:]
        for group in CutPositionGroup.allCases where group != .all {
            let positions = Position.allCases.filter { group.includes($0) }
            let floor = positions.reduce(0) { $0 + RosterCutEvaluator.minimumCount(for: $1) }
            let reinforced = positions.contains { RosterCutEvaluator.minimumCount(for: $0) > 1 }
            // The FA engine's ideal is stated per GROUP, so a room whose
            // positions share one entry (RB with FB, the safeties) must count it
            // once — summing per position would ask a backfield for six men.
            var counted: Set<Position> = []
            var typical = 0
            for position in positions where !counted.contains(position) {
                let room = FreeAgencyEngine.positionGroupInfo(for: position)
                counted.formUnion(room.positions)
                typical += room.idealCount
            }
            bands[group] = (floor, typical, reinforced)
        }
        return bands
    }()

    /// Every room, as it stands right now.
    private var roomShapes: [RoomShape] {
        CutPositionGroup.allCases.compactMap { group in
            guard let band = Self.roomBands[group] else { return nil }
            return RoomShape(
                group: group,
                count: count(in: group),
                floor: band.floor,
                typical: band.typical,
                hasReinforcedFloor: band.reinforced
            )
        }
    }

    /// The rooms worth saying something about.
    ///
    /// Only read once the club is at or under the rung it is working to: a camp
    /// roster of 87 is heavy everywhere by construction, and eight orange chips
    /// over a list the user has not started cutting is noise standing where a
    /// warning has to be believed. **Heavy is held back further, to the 53**:
    /// the 75 and 65 rungs exist to be carried over, and a screen that asked for
    /// extra bodies and then complained about them is arguing with itself. A
    /// room that is THIN, or standing on the floor, is worth saying at any rung
    /// — it only gets thinner from here.
    private var shapeWarnings: [RoomShape] {
        guard isDueStageComplete else { return [] }
        let isFinalRung = stage == .cut65To53
        return roomShapes.filter { isFinalRung ? $0.isFlagged : ($0.isThin || $0.isAtFloor) }
    }

    // MARK: - The practice squad's ceiling

    /// Spots this cutdown has already spent, plus the ones the live selection
    /// is holding.
    private var practiceSquadUsed: Int { practiceSquadBanked + practiceSquadIDs.count }

    /// Why this man cannot be stashed, or `nil` when he can.
    ///
    /// Two of the three limits `PracticeSquadEngine` applies are checkable from
    /// here. The third — the per-position cap against men flagged on EARLIER
    /// rungs — is not: `RosterCut` records a `playerID` and the men behind those
    /// rows have already left the roster, so the position they were flagged at
    /// is not in this screen's hands. Under-counting there costs the user
    /// nothing he had before; the ceiling that actually bites (the squad's own
    /// size, across all three rungs) is exact.
    private func practiceSquadBlockReason(for player: Player) -> String? {
        guard !practiceSquadIDs.contains(player.id) else { return nil }
        guard practiceSquadUsed < PracticeSquadEngine.squadSize else {
            return "your \(PracticeSquadEngine.squadSize) squad spots are all flagged"
        }
        let cap = player.position == .QB
            ? PracticeSquadEngine.maxQuarterbacks
            : PracticeSquadEngine.maxPerPosition
        let flaggedHere = practiceSquadIDs
            .compactMap { id in activeRoster.first(where: { $0.id == id }) }
            .filter { $0.position == player.position }
            .count
        guard flaggedHere < cap else {
            return "a squad carries at most \(cap) at \(player.position.rawValue)"
        }
        return nil
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
            // The ceiling is checked here as well as in the cell: the cell can
            // only refuse the tick it draws, and this is the call.
            guard practiceSquadBlockReason(for: player) == nil else { return }
            practiceSquadIDs.insert(player.id)
        }
    }

    private func initials(for player: Player) -> String {
        let f = player.firstName.first.map(String.init) ?? ""
        let l = player.lastName.first.map(String.init) ?? ""
        return "\(f)\(l)"
    }

    // MARK: - Money

    /// **What the club is spending against.**
    ///
    /// Every figure on this screen is cap money and the screen never said what
    /// the cap was: fourteen columns, two of them dollars, and the only summary
    /// it printed was a headcount. `Team` has carried both halves since it was
    /// written and the club is already fetched for the release guard.
    ///
    /// `nil` in sandbox, where the mode short-circuits every cap check — a
    /// "space" figure under a rule nothing enforces is a number to plan against
    /// that means nothing, and the release split is zeroed there too.
    private var capPosition: (used: Int, cap: Int, space: Int)? {
        guard career.capMode != .sandbox, let team = loadedTeam else { return nil }
        return (team.currentCapUsage, team.salaryCap, team.availableCap)
    }

    /// The term the release was priced on — the `Contract` row where one
    /// exists, exactly as `CapManagementEngine.tradeCapSplit` chooses it, and
    /// the player's own field for everyone else.
    private func contractTerm(for player: Player) -> Int {
        if let contract = contractsByPlayer[player.id], contract.totalYears > 0 {
            return max(0, contract.totalYears - contract.currentYear)
        }
        return max(0, player.contractYearsRemaining)
    }

    /// His charge against this year's cap — see `capHitCell`.
    private func capHit(_ split: CapManagementEngine.ReleaseCapSplit) -> Int {
        split.salaryRelieved + split.salaryRetained + split.proratedPerYear
    }

    /// Cap room, in the words that survive going negative. "$−4.2M space" is
    /// not a sentence; being over the cap is.
    private func spaceLabel(_ thousands: Int) -> String {
        thousands < 0 ? "over by \(money(-thousands))" : "\(money(thousands)) space"
    }

    /// A signed figure for a number that can go either way.
    private func signedMoney(_ thousands: Int) -> String {
        thousands < 0 ? "\u{2212}\(money(-thousands))" : "+\(money(thousands))"
    }

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

    /// The release split, from the map priced at load — see `releaseSplits`.
    ///
    /// The engine is still the fallback rather than a precondition: the very
    /// first render draws the shell's snapshot before any fetch has landed, and
    /// a row with no priced split would show a man free to cut.
    private func releaseSplit(for player: Player) -> CapManagementEngine.ReleaseCapSplit {
        if let priced = releaseSplits[player.id] { return priced }
        return CapManagementEngine.releaseCapSplit(
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
    ///
    /// **And everything the table reads.** The four column maps are built here
    /// and only here — the list re-renders on every tap of every one of ~87
    /// rows, so a column that derived itself per row would run its derivation
    /// eighty-seven times for a value that cannot move until the next commit.
    /// They are refreshed with the roster they describe, which is what keeps the
    /// table honest across a commit.
    private func loadLedger() {
        guard let teamID = career.teamID else { return }
        let fetched = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        ))) ?? []
        liveRoster = fetched
        // #208 G1 — the club the row guard measures against, fetched once here
        // rather than per row. Ahead of the ranking below, which needs it.
        let team = try? modelContext.fetch(
            FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.id == teamID })
        ).first
        loadedTeam = team

        // **Men the club cannot release at all go to the back of the plan.**
        // `recommendCuts` has always skipped them, so the machine's answer was
        // already right and only the visible ranking was wrong: a club finishing
        // at the two-quarterback floor was shown "CUT 1" against a padlock and a
        // line telling it to sign somebody first — the first instruction a
        // reader takes off a worst-first list being the one the screen then
        // refuses. Measured with an EMPTY selection, and here rather than per
        // render, so the order cannot move under the user's finger as he ticks
        // rows.
        let blocked = Set(
            team.map { club in
                fetched.filter {
                    CapManagementEngine.releaseBlockReason(
                        player: $0,
                        team: club,
                        roster: fetched,
                        alreadySelected: []
                    ) != nil
                }
                .map(\.id)
            } ?? []
        )
        cutOrder = Dictionary(
            uniqueKeysWithValues: fetched
                .sorted { lhs, rhs in
                    let leftBlocked = blocked.contains(lhs.id)
                    let rightBlocked = blocked.contains(rhs.id)
                    guard leftBlocked == rightBlocked else { return rightBlocked }
                    return RosterCutEvaluator.keepScore(for: lhs) < RosterCutEvaluator.keepScore(for: rhs)
                }
                .enumerated()
                .map { ($0.element.id, $0.offset) }
        )

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
        // The receipts carry the money as well as the man, and the ladder used
        // to reduce them to a headcount — so a finished cutdown could not say
        // what any of it freed. Both halves are summed in the one pass.
        var byStage: [CutDay: StageLedger] = [:]
        var flagged = 0
        for cut in cutRows {
            if cut.practiceSquadEligible { flagged += 1 }
            guard let day = CutDay(rawValue: cut.cutDayRaw) else { continue }
            var ledger = byStage[day] ?? StageLedger()
            ledger.released += 1
            ledger.capFreed += cut.capSavings
            ledger.deadMoney += cut.deadCap
            byStage[day] = ledger
        }
        ledgerByStage = byStage
        practiceSquadBanked = flagged

        // The table's columns, in dependency order: the cap split needs the
        // contracts fetched above it.
        loadCapSplits(roster: fetched)
        loadOVRTrend(roster: fetched)
        loadDepthChart()
        loadPreseasonTape()
    }

    /// Prices every release once, off the deals just fetched.
    private func loadCapSplits(roster: [Player]) {
        let capMode = career.capMode
        let remaining = leagueYearRemaining
        var priced: [UUID: CapManagementEngine.ReleaseCapSplit] = [:]
        priced.reserveCapacity(roster.count)
        for player in roster {
            priced[player.id] = CapManagementEngine.releaseCapSplit(
                player: player,
                contract: contractsByPlayer[player.id],
                capMode: capMode,
                leagueYearRemaining: remaining
            )
        }
        releaseSplits = priced
    }

    /// The offseason swing, off the newest finished season on record.
    ///
    /// One fetch for the whole roster — the same shape the development report
    /// uses for tenure — rather than a fetch per row. Rows come back newest
    /// first and the first row per player is the one the trend is measured
    /// against; his `teamID` on it is deliberately not checked, because a
    /// veteran signed this offseason still developed over it and the number is
    /// about the MAN, not about who paid him in December.
    private func loadOVRTrend(roster: [Player]) {
        let ids = roster.map(\.id)
        guard !ids.isEmpty else {
            ovrTrend = [:]
            return
        }
        let cid = career.id
        let descriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate<PlayerSeasonHistory> {
                $0.careerID == cid && ids.contains($0.playerID)
            },
            sortBy: [SortDescriptor(\.season, order: .reverse)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []

        var newest: [UUID: PlayerSeasonHistory] = [:]
        for row in rows where newest[row.playerID] == nil { newest[row.playerID] = row }

        var trend: [UUID: OVRTrend] = [:]
        trend.reserveCapacity(roster.count)
        for player in roster {
            guard let row = newest[player.id] else { continue }
            trend[player.id] = OVRTrend(
                delta: player.overall - row.overallAtEndOfSeason,
                sinceSeason: row.season
            )
        }
        ovrTrend = trend
    }

    /// Reverses the saved depth chart into a per-player slot, once.
    ///
    /// `depthChartData == nil` is a real state — it is what the required "Set
    /// depth chart" task owns — and the column is dropped rather than filled
    /// with eighty-seven "unset" cells: a chart nobody has written says nothing
    /// about any individual man, and the task row is where the user is told to
    /// write one.
    private func loadDepthChart() {
        guard let data = career.depthChartData,
              let chart = try? JSONDecoder().decode(DepthChart.self, from: data) else {
            depthByPlayer = [:]
            hasDepthChart = false
            return
        }

        // **Three states, not a rung number.** A starter gets his slot's own
        // name, because WR1 and WR3 are different jobs and the position badge
        // cannot tell them apart. Everyone behind a starter gets the word
        // "Backup" rather than "2nd" / "3rd": the chart distributes a room
        // across sibling slots (WR1/WR2/WR3 each carry a starter AND a backup),
        // so index 1 of WR1 is the club's FOURTH receiver and printing "2nd"
        // beside him would be a number that means something different in every
        // room. The exact rung is still spoken, where there is space to name the
        // slot it belongs to.
        var spots: [UUID: DepthSpot] = [:]
        for slot in DepthChartSlot.allCases where !slot.acceptsAnyPosition {
            for (index, id) in chart.depthOrder(for: slot).enumerated() {
                // `DepthChart.assign` keeps a man in at most one position slot,
                // so the first hit is normally the only hit. A chart written by
                // an older build can still double-book, and `allCases` order is
                // the lineup's own order — first hit wins is then the slot the
                // simulator would field him in.
                guard spots[id] == nil else { continue }
                let isStarter = index == 0
                let tone: DSStatusPill.Tone = isStarter ? .ok : .neutral
                spots[id] = DepthSpot(
                    label: isStarter ? slot.rawValue : "Backup",
                    tone: tone,
                    spoken: isStarter
                        ? "Starting \(slot.displayName)"
                        : "\(Self.depthOrdinal(index + 1)) \(slot.displayName)"
                )
            }
        }

        // The returners last, and only for a man no position slot has already
        // placed. "KR" is the most useful thing the chart knows about a fourth
        // running back and the least useful thing it knows about a starting one.
        for slot in [DepthChartSlot.KR, .PR] {
            guard let id = chart.starter(for: slot), spots[id] == nil else { continue }
            spots[id] = DepthSpot(
                label: slot.rawValue,
                tone: .info,
                spoken: "Starting \(slot.displayName)"
            )
        }

        depthByPlayer = spots
        hasDepthChart = true
    }

    private static func depthOrdinal(_ value: Int) -> String {
        switch value {
        case 2:  return "2nd"
        case 3:  return "3rd"
        default: return "\(value)th"
        }
    }

    /// Rolls the exhibition slate up into one reading per man.
    ///
    /// Two things this deliberately does not do. It does not sum the box scores
    /// and hand the total to `PreseasonEngine.CampCase` — that evaluator's bar
    /// is one afternoon's positional expectation, and a three-game total scored
    /// against it would call every man who dressed three times a riser. And it
    /// does not decide anything about football itself: the verdict per game is
    /// the engine's, and what happens here is counting them.
    ///
    /// The summed line IS used for the row's subline, because
    /// `PreseasonCampCase.statLine` is pure formatting — "13/21, 158 yds" across
    /// the slate is the same sentence in the same shorthand.
    private func loadPreseasonTape() {
        guard let state = career.preseasonState,
              state.matches(career: career),
              !state.results.isEmpty else {
            tapeByPlayer = [:]
            slateGamesPlayed = 0
            return
        }
        slateGamesPlayed = state.results.count

        var linesByPlayer: [UUID: [PlayerGameStats]] = [:]
        var gamesByPlayer: [UUID: Int] = [:]
        var chancesByPlayer: [UUID: Int] = [:]
        var verdictsByPlayer: [UUID: [PreseasonEngine.CampCase.Verdict]] = [:]

        for result in state.results {
            // **Who was in uniform, not who registered.** `bubblePlayerIDs` is
            // the dressed cohort minus the starters, so an interior lineman who
            // played sixty snaps and touched nothing still counts a game of
            // tape. Without it he reads identically to a man who never left the
            // sideline, and those are opposite facts on a cut sheet.
            let dressedBubble = Set(result.bubblePlayerIDs)
            for id in dressedBubble { gamesByPlayer[id, default: 0] += 1 }
            for line in result.userLines {
                if !dressedBubble.contains(line.playerID) {
                    gamesByPlayer[line.playerID, default: 0] += 1
                }
                linesByPlayer[line.playerID, default: []].append(line)
                let read = PreseasonEngine.CampCase.read(line)
                chancesByPlayer[line.playerID, default: 0] += read.opportunities
                verdictsByPlayer[line.playerID, default: []].append(read.verdict)
            }
        }

        var tape: [UUID: PreseasonTape] = [:]
        tape.reserveCapacity(gamesByPlayer.count)
        for (id, games) in gamesByPlayer {
            tape[id] = PreseasonTape(
                games: games,
                opportunities: chancesByPlayer[id] ?? 0,
                verdict: Self.slateVerdict(verdictsByPlayer[id] ?? []),
                line: Self.slateLine(linesByPlayer[id] ?? []).map { PreseasonCampCase.statLine($0) }
            )
        }
        tapeByPlayer = tape
    }

    /// The slate's verdict as a count of its games' verdicts. A man who helped
    /// himself twice and hurt himself once has moved forward; a man who did both
    /// once is a wash, which is what `held` means.
    private static func slateVerdict(
        _ verdicts: [PreseasonEngine.CampCase.Verdict]
    ) -> PreseasonCampCase.Verdict {
        let helped = verdicts.filter { $0 == .helped }.count
        let hurt = verdicts.filter { $0 == .hurt }.count
        let rolled: PreseasonEngine.CampCase.Verdict
        if helped > hurt {
            rolled = .helped
        } else if hurt > helped {
            rolled = .hurt
        } else if helped > 0 || verdicts.contains(.held) {
            // Moved both ways, or simply did his job: either slate is a wash.
            rolled = .held
        } else {
            rolled = .quiet
        }
        // The count is kept in the ENGINE'S vocabulary and translated once, here
        // — `PreseasonCampCase` states that its initializer is the only place
        // the two meet, and a rollup that picked display cases directly would
        // be a second crossing.
        return PreseasonCampCase.Verdict(rolled)
    }

    /// The slate's box score, as one line to format. `nil` when he never
    /// appeared in one.
    private static func slateLine(_ lines: [PlayerGameStats]) -> PlayerGameStats? {
        guard let first = lines.first else { return nil }
        var total = PlayerGameStats(
            playerID: first.playerID,
            playerName: first.playerName,
            position: first.position
        )
        for line in lines {
            total.passingYards += line.passingYards
            total.passingTDs += line.passingTDs
            total.interceptions += line.interceptions
            total.completions += line.completions
            total.attempts += line.attempts
            total.rushingYards += line.rushingYards
            total.rushingTDs += line.rushingTDs
            total.carries += line.carries
            total.receivingYards += line.receivingYards
            total.receivingTDs += line.receivingTDs
            total.receptions += line.receptions
            total.targets += line.targets
            total.tackles += line.tackles
            total.sacks += line.sacks
            total.forcedFumbles += line.forcedFumbles
            total.interceptionsCaught += line.interceptionsCaught
            total.fieldGoalsMade += line.fieldGoalsMade
            total.fieldGoalsAttempted += line.fieldGoalsAttempted
        }
        // Not an init parameter — it was added after the type shipped and is
        // optional so older encoded lines still decode.
        total.passDeflections = lines.reduce(0) { $0 + $1.passDeflectionCount }
        return total
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
