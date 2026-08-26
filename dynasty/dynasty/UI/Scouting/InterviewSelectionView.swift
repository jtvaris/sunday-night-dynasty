import SwiftUI
import SwiftData

/// Allows the player to select combine-invited prospects for batch interviews.
/// After conducting interviews, reveals personality, football IQ, and character notes.
struct InterviewSelectionView: View {
    let career: Career
    /// Whether the club may spend an interview slot right now.
    ///
    /// This screen is the one stage surface that shipped with NO stage guard at
    /// all, which is what let a locked stage be worked from a task deep-link —
    /// and a worked stage raises `Career.derivedPrepStepFloor`, so one interview
    /// conducted out of turn stepped the whole pipeline over `.combineReview`
    /// and drew it as passed. The hub decides with
    /// ``DraftPrepProgress/canAct(_:)``; every stage screen asks the same
    /// question of the same struct. Defaults to `true` so a preview or a future
    /// non-hub entry point is not silently dead.
    var canAct: Bool = true
    /// The man a board row asked for, ticked on arrival. `nil` for a plain visit
    /// to the tab — see the `.task` that consumes it.
    var focusProspectID: UUID? = nil
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProspectIDs: Set<UUID> = []
    /// Which block of columns the list renders, driven by the shared mode chips.
    /// Opens on `.overview` — the same block the Big Board opens on, and the one
    /// that answers "who is worth a slot" before you have met anybody.
    @State private var mode: ProspectAttributeTab = .overview
    @State private var prospects: [CollegeProspect] = []
    @State private var showResults = false
    @State private var interviewResults: [InterviewResult] = []
    /// When the user explicitly opens the saved report (e.g. tapping "View Past Report"
    /// while there are still interview slots remaining), we route to the report view
    /// rebuilt from prospects with `interviewCompleted == true`.
    @State private var viewingPastReport = false
    @State private var positionFilter: Position?
    @State private var roundFilter: Int?
    @State private var needFilter: Bool = false
    @State private var shortlistFilter: Bool = false
    @State private var filterStarredOnly: Bool = false
    @State private var filterMyGradeFirstRound: Bool = false
    @State private var teamRoster: [Player] = []
    @State private var coaches: [Coach] = []
    @CareerScopedStorage("prospectWatchlist") private var prospectWatchlistJSON: String = "[]"
    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared
    @State private var isLoading: Bool = true

    // Single source with the hub's quick-action gate — two 60s that drift
    // apart would let the row shortcut run past the room's own ration.
    private let maxInterviews = DraftPrepProgress.interviewSlots

    private var remainingSlots: Int {
        max(0, maxInterviews - career.interviewsUsed)
    }

    /// The club's actual holes, by rank, computed ONCE per load.
    ///
    /// `teamNeeds` used to re-run `DraftEngine.topTeamNeeds` on every access and
    /// every row asked `teamNeedPositions.contains(...)`, so scrolling a 300-man
    /// list re-ranked a 53-man roster once per row. The NEED column added a
    /// second per-row caller, which is what made the walk worth caching.
    /// `loadTeamData()` is the one writer.
    ///
    /// #fleet review F3: the RANKING is `DraftEngine.teamNeedDeficits`, not
    /// `topTeamNeeds`. `topTeamNeeds` ranks by value × weight and hands back
    /// {QB, DE, CB, WR, LT} for every full roster in the league — its own doc
    /// says so — so this list stamped NEED on a fifth receiver while the Big
    /// Board, which reads a roster-count deficit, said "Set" for the same man on
    /// the next tab. `teamNeedDeficits` returns only the positions whose
    /// evidence clears the bar, so an empty answer (a well-built roster) is a
    /// real one and the two tabs stop contradicting each other.
    @State private var needRankByPosition: [Position: Int] = [:]

    private var teamNeedPositions: Set<Position> {
        Set(needRankByPosition.keys)
    }

    /// The board's NEED vocabulary — "High" for the two biggest holes, "Med" for
    /// the rest of the top five, "Set" for a group that is stocked.
    private func needLevel(for position: Position) -> String {
        guard let rank = needRankByPosition[position] else { return "Set" }
        return rank < 2 ? "High" : "Med"
    }

    /// Read only to migrate the legacy bookmark set onto the unified mark.
    private var legacyWatchlistIDs: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(prospectWatchlistJSON.utf8))) ?? [])
    }

    private var selectableProspects: [CollegeProspect] {
        var filtered = prospects
            .filter { $0.combineInvite && !$0.interviewCompleted }
        if let pos = positionFilter {
            filtered = filtered.filter { $0.position == pos }
        }
        if let round = roundFilter {
            filtered = filtered.filter { $0.draftProjection == round }
        }
        if needFilter {
            filtered = filtered.filter { teamNeedPositions.contains($0.position) }
        }
        if shortlistFilter {
            // ONE mark system: Elite and Target are "men I want".
            filtered = filtered.filter { $0.userMark.isBoardPositive }
        }
        if filterStarredOnly {
            filtered = filtered.filter(\.isMarked)
        }
        if filterMyGradeFirstRound {
            filtered = filtered.filter { userGradeStore.isFirstRoundPlus($0.id) }
        }
        return filtered.sorted { ($0.draftProjection ?? 999) < ($1.draftProjection ?? 999) }
    }

    /// Prospects that match a team need AND have OVR in the top 50% of all selectable prospects.
    private var recommendedProspects: [CollegeProspect] {
        let all = selectableProspects
        guard !all.isEmpty else { return [] }
        let overalls = all.map { ovrValue(for: $0) }
        let median = overalls.sorted()[overalls.count / 2]
        return all.filter { prospect in
            teamNeedPositions.contains(prospect.position) && ovrValue(for: prospect) >= median
        }
    }

    /// Everyone not in the recommended section.
    private var otherProspects: [CollegeProspect] {
        let recommendedIDs = Set(recommendedProspects.map(\.id))
        return selectableProspects.filter { !recommendedIDs.contains($0.id) }
    }

    /// Recomputes interview results from any prospects that have already been
    /// interviewed (data persisted on `CollegeProspect`). Used to render the
    /// saved report when the user revisits the Interviews tab post-completion.
    private var completedInterviewResults: [InterviewResult] {
        prospects
            .filter { $0.interviewCompleted }
            .compactMap { prospect -> InterviewResult? in
                guard let personality = prospect.scoutedPersonality,
                      let iq = prospect.interviewFootballIQ else { return nil }
                return InterviewResult(
                    prospect: prospect,
                    personality: personality,
                    footballIQ: iq,
                    notes: prospect.interviewCharacterNotes ?? []
                )
            }
    }

    private var hasCompletedInterviews: Bool {
        prospects.contains { $0.interviewCompleted }
    }

    /// Whether the body is drawing the selection list rather than a report.
    ///
    /// `header` is rendered above the branch, so it is shared by both states.
    /// The chrome that only steers a selection — the filter menu, the slot
    /// meter — asks this before drawing itself, rather than sitting live over a
    /// report where there is nothing left to select or filter. Mirrors the
    /// branch order in `body`.
    private var isSelecting: Bool {
        !showResults && !(viewingPastReport && hasCompletedInterviews) && remainingSlots > 0
    }

    // MARK: - Body

    var body: some View {
        Group {
        if isLoading {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentGold)
                    Text("Loading Interviews...")
                        .font(.subheadline)
                        // `.secondary` resolves against the system's light
                        // scheme here and lands ~3:1 on the midnight ground.
                        .foregroundStyle(Color.textSecondary)
                }
            }
        } else {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            if showResults {
                // Just-conducted interviews — show the live report from this batch.
                InterviewReportView(results: interviewResults) {
                    showResults = false
                    interviewResults = []
                    loadProspects()
                }
            } else if viewingPastReport && hasCompletedInterviews {
                // User explicitly requested the saved report view (still has slots).
                InterviewReportView(results: completedInterviewResults) {
                    viewingPastReport = false
                    loadProspects()
                }
            } else if remainingSlots == 0 && hasCompletedInterviews {
                // All slots used and we have data — the report IS this tab's
                // steady state, so no "Complete Review" bar: dismissing would
                // just re-render this same screen (#118).
                InterviewReportView(
                    results: completedInterviewResults,
                    onDismiss: {
                        CareerScopedDefaults.set(true, "interviewReportReviewed")
                        loadProspects()
                    },
                    showsCompleteCTA: false
                )
            } else if remainingSlots == 0 {
                // Edge case: slots used but no data (legacy save). Show empty state.
                allInterviewsUsedView
            } else {
                selectionList
            }
        }
        } // end else (not loading)
        } // end Group
        .task {
            loadProspects()
            loadTeamData()
            // Fold the legacy star / flag / bookmark opinions into the ONE mark.
            let migrated = CollegeProspect.migrateLegacyMarks(
                in: prospects,
                watchlistIDs: legacyWatchlistIDs
            )
            if migrated > 0 { try? modelContext.save() }
            // Arrived from a board row's "Conduct Interview": open with the man
            // the user long-pressed already ticked, so the Conduct button is one
            // tap away rather than a scroll through 300 rows (#125). Only if he
            // is still selectable — an already-interviewed man is filtered out
            // of this list and would tick nothing.
            if let focusProspectID,
               selectableProspects.contains(where: { $0.id == focusProspectID }) {
                selectedProspectIDs = [focusProspectID]
            }
            isLoading = false
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROSPECT INTERVIEWS")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)

                Spacer()

                // The ration used to be printed here as "N/60 used" on top of
                // the list's own meter and its "N/60 remaining" row — three
                // counters for one fact, two of them on different denominators.
                // `selectionProgress` states it once, and the list owns it.
                //
                // #16: the filter only has a list to filter. This header is
                // shared with the report, where a live Filter pill steered
                // nothing at all.
                if isSelecting {
                    positionFilterMenu
                }
            }

            // #17: Interview info tooltip
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.accentGold)
                Text("Reveals: Football IQ (exact) \u{00B7} Awareness, Learning, Compete, Leadership, Work Ethic grades \u{00B7} personality & character \u{2014} which is what reduces bust risk")
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let name = interviewerRoomName {
                Text("Interviews run by \(name)")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Selection Progress (#83)

    /// The one place this screen prints the interview ration.
    ///
    /// The words and the bar used to run on a different denominator from the
    /// header pill beside them: this line counted ticks against slots REMAINING
    /// while the pill counted spend against the 60, so "0/7 selected" could sit
    /// one line under "53/60 used" and mean a different scale. Both halves
    /// measure the same 60 now — the bar fills with what is already spent plus
    /// what is ticked, so it never rebases mid-cycle.
    private var selectionProgress: some View {
        let slotsLeft = max(0, remainingSlots - selectedProspectIDs.count)
        let committed = min(maxInterviews, career.interviewsUsed + selectedProspectIDs.count)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(selectedProspectIDs.count) selected \u{00B7} \(slotsLeft) of \(maxInterviews) left")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                // This used to read "League teams typically interview 15-20
                // prospects", which advised the user into a strictly worse
                // choice than the screen's own "Select All Recommended" gives
                // him: a slot is the ONLY cost — `conductInterviews` spends no
                // money and the stage takes its one week whether you meet one
                // man or sixty — and `WeekAdvancer.startNewSeason` zeroes
                // `interviewsUsed` with the class, so restraint buys nothing
                // and destroys forty reads. The line says the fact instead.
                Text("Unused slots expire with this draft class")
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            GeometryReader { geo in
                let unit = geo.size.width / CGFloat(max(1, maxInterviews))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)

                    // Gold is what this batch would spend; the spent prefix is
                    // drawn over its head in the muted tint, so one bar shows
                    // both halves of the same 60.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentGold)
                        .frame(width: unit * CGFloat(committed), height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.textTertiary)
                        .frame(width: unit * CGFloat(career.interviewsUsed), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private var positionFilterMenu: some View {
        Menu {
            // Position filter
            Menu("Position") {
                Button("All Positions") { positionFilter = nil }
                Divider()
                ForEach(Position.allCases, id: \.self) { pos in
                    Button(pos.rawValue) { positionFilter = pos }
                }
            }

            // Round filter
            Menu("Projected Round") {
                Button("All Rounds") { roundFilter = nil }
                Divider()
                ForEach(1...7, id: \.self) { round in
                    Button("Round \(round)") { roundFilter = round }
                }
            }

            Divider()

            // Toggle filters
            Button(needFilter ? "Show All (not just needs)" : "Team Needs Only") {
                needFilter.toggle()
            }
            Button(shortlistFilter ? "Show All (not just shortlist)" : "Shortlisted Only") {
                shortlistFilter.toggle()
            }
            Button(filterStarredOnly ? "Show All (not just starred)" : "Starred Only") {
                filterStarredOnly.toggle()
            }
            Button(filterMyGradeFirstRound ? "Show All Grades" : "My Grade: 1st Round+") {
                filterMyGradeFirstRound.toggle()
            }

            Divider()

            // Deselect All
            Button("Deselect All") {
                selectedProspectIDs.removeAll()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                let activeFilterCount = [positionFilter != nil, roundFilter != nil, needFilter, shortlistFilter].filter { $0 }.count
                Text(activeFilterCount > 0 ? "Filters (\(activeFilterCount))" : "Filter")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.accentGold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentGold.opacity(0.12)))
            // The pill keeps its density; the tap target gets the 44 pt floor.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Selection List

    private var selectionList: some View {
        VStack(spacing: 0) {
            // Task 18: the ration and the controls that spend it, in one block.
            // The meter states the count once (see `selectionProgress`) and this
            // row acts on it; the row used to restate the same 60 in its own
            // words, two lines under a header pill saying it a third time.
            VStack(alignment: .leading, spacing: 8) {
                selectionProgress

                // Every capsule in this row carries `minHeight: 44` under a
                // small pill: "Select All Recommended" is the highest-leverage
                // control on the screen — one tap for a whole batch — and it
                // shipped as a ~21 pt target, under half the HIG floor.
                HStack(spacing: 8) {
                    Spacer()

                    // View Past Report button — surfaces prior interview results
                    // so the dashboard "Review interview report" task can be completed
                    // mid-combine, before all slots are used.
                    if hasCompletedInterviews {
                        Button {
                            viewingPastReport = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: DSType.Size.caption))
                                Text("View Report (\(completedInterviewResults.count))")
                                    .font(.system(size: DSType.Size.footnote, weight: .bold))
                            }
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentGold.opacity(0.12)))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Task 20: Select All Recommended
                    if !recommendedProspects.isEmpty {
                        Button {
                            let available = recommendedProspects.filter { !selectedProspectIDs.contains($0.id) }
                            for p in available.prefix(remainingSlots - selectedProspectIDs.count) {
                                selectedProspectIDs.insert(p.id)
                            }
                        } label: {
                            Text("Select All Recommended")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentGold.opacity(0.12)))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if !selectedProspectIDs.isEmpty {
                        Button {
                            selectedProspectIDs.removeAll()
                        } label: {
                            Text("Deselect All")
                                .font(.system(size: DSType.Size.caption, weight: .bold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.backgroundTertiary))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color.backgroundTertiary.opacity(0.4))

            // The board's view modes, on the interview room's list. The list
            // shipped with one frozen column set while the board a tab away
            // could be asked five different questions about the same men — and
            // the two questions this stage is actually about (what does the
            // department already have on his head, and what did he run) were
            // both on the board and neither here.
            //
            // The position binding is inert on purpose: this screen's own
            // Filter menu owns its position filter, and a second visible chip
            // row would be a third opinion of the same list.
            ProspectListControls(
                positionFilter: .constant(.all),
                mode: $mode,
                modes: ProspectAttributeTab.allCases,
                showsPositionChips: false,
                background: Color.backgroundTertiary.opacity(0.4)
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    // The gold "interviews reveal personality, football IQ and
                    // character" banner used to open the list. The header's
                    // Reveals line names the exact attributes three rows above
                    // it, so the banner was the same sentence with less in it —
                    // and the only gold card in the upper half of the screen,
                    // taking the emphasis that belongs to the ration.

                    // #78: Table header
                    tableHeader

                    // #81: Recommended section
                    if !recommendedProspects.isEmpty {
                        sectionHeader("RECOMMENDED", subtitle: "Matches team needs with top-half talent")
                        ForEach(recommendedProspects) { prospect in
                            prospectRow(prospect)
                            Divider().overlay(Color.surfaceBorder.opacity(0.3))
                        }
                    }

                    // #81: All Prospects section
                    sectionHeader("ALL PROSPECTS", subtitle: nil)
                    ForEach(otherProspects) { prospect in
                        prospectRow(prospect)
                        Divider().overlay(Color.surfaceBorder.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
            }

            conductButton
        }
    }

    // MARK: - Section Header (#81)

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.top, 4)
    }

    // MARK: - Table Header (#78)

    /// Column labels. The leading five and the trailing two are PINNED — the
    /// mark, the checkbox, the man, what he costs you in risk and what the
    /// department has him at are the same questions in every mode — and the
    /// block between them follows the mode chips.
    private var tableHeader: some View {
        HStack(spacing: 0) {
            // The two leading controls are BOTH circles — `ProspectMarkButton`
            // draws `circle.dashed` when a man is unmarked, and the selection
            // checkbox is an empty circle — so a row reads "○ ✓" with nothing
            // saying which one spends the interview slot. The gutter is named
            // rather than left as two blank placeholders.
            Text("MARK")
                .frame(width: 36, alignment: .center)
            Image(systemName: "checkmark")
                .frame(width: 22)

            Text("POS")
                .frame(width: 36, alignment: .center)
            // Portrait column — unlabelled, reserved so the header keeps
            // matching the row (30 pt `PersonFaceView` + 6 pt leading padding).
            Color.clear.frame(width: 36)
            Text("NAME")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)

            // Risk is pinned in this list's own trailing block, so the Overview
            // block drops its copy rather than printing the fact twice.
            ProspectColumns.headers(mode: mode, context: ProspectColumnContext(includesRisk: false))

            // #fleet review F13: no MEET column here. This list only ever holds
            // men with `interviewCompleted == false`, and `interviewFootballIQ`
            // — the field the cell reads — is written only alongside
            // `interviewCompleted = true`, so the column could print nothing but
            // a dash on every row of every page.
            Text("RISK")
                .frame(width: 80, alignment: .center)
            Text("OVR")
                .frame(width: 50, alignment: .center)
        }
        // The display voice at its 11 pt floor — the same font
        // `ProspectColumns.headers` now sets on the block between the pinned
        // columns, so the two halves of one header row read as one row.
        .font(DSType.display(11, .heavy))
        .foregroundStyle(Color.textTertiary)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Prospect Row (#78, #79, #80)

    // MARK: - #13: Priority classification for visual differentiation

    private var medianOVR: Int {
        let all = selectableProspects.map { ovrValue(for: $0) }
        guard !all.isEmpty else { return 50 }
        return all.sorted()[all.count / 2]
    }

    private func interviewPriority(for prospect: CollegeProspect) -> InterviewPriority {
        let isNeed = teamNeedPositions.contains(prospect.position)
        let ovr = ovrValue(for: prospect)
        let median = medianOVR
        if isNeed && ovr >= median { return .must }
        if isNeed || ovr >= median { return .should }
        return .optional
    }

    /// What a column block needs that lives on this SCREEN rather than on the
    /// prospect: the coordinators' scheme verdict and the club's own holes.
    /// Both are loaded here, so both are answered; RISK is dropped because this
    /// list pins it in its own trailing column.
    private func columnContext(for prospect: CollegeProspect) -> ProspectColumnContext {
        ProspectColumnContext(
            schemeFit: schemeFitLabel(for: prospect),
            knowsSchemeFit: !coaches.isEmpty,
            needLevel: needLevel(for: prospect.position),
            knowsNeeds: !teamRoster.isEmpty,
            includesRisk: false,
            userTeamID: career.teamID
        )
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        let isSelected = selectedProspectIDs.contains(prospect.id)
        let canSelect = isSelected || selectedProspectIDs.count < remainingSlots
        let isNeed = teamNeedPositions.contains(prospect.position)
        let priority = interviewPriority(for: prospect)

        return HStack(spacing: 0) {
            ProspectMarkButton(
                prospect: prospect,
                onChange: { try? modelContext.save() }
            )
            .frame(width: 36)

            Button {
                if isSelected {
                    selectedProspectIDs.remove(prospect.id)
                } else if canSelect {
                    selectedProspectIDs.insert(prospect.id)
                }
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // Checkbox
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)
                            .frame(width: 22)

                    ProspectSelectionPositionBadge(position: prospect.position)

                    // Portrait + name + mark + my grade over college · projected
                    // round — the board row's identity block, shared.
                    //
                    // The old sub-line printed `fortyTime` and `verticalJump`
                    // raw: exact decimals for a club that may never have sent
                    // anybody to Indianapolis. Those numbers are the Physical
                    // block's now, where `ProspectFog.combineFidelity` decides
                    // whether the user gets "4.52" or "~4.5".
                    ProspectRowIdentity(prospect: prospect) {
                        // #20: how much the department has on him.
                        //
                        // #184: own reports only. Off raw `scoutReportCount`
                        // this row lit a dot for the inherited "Previous
                        // Staff" freebie on a third of the class, and the card
                        // the user opens from it (`scoutConfidenceBadge`)
                        // answered "Unscouted · 0/3 reports" on the same man.
                        // Same counter, same cap, same glyphs — all three now
                        // come from `ProspectFog`.
                        let ownReports = ProspectFog.ownReportCount(prospect)
                        if ownReports > 0 {
                            Text(ProspectFog.confidenceDots(prospect))
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(ownReports >= ScoutEvaluationBudget.maxReportsPerProspect
                                                 ? Color.success : Color.textTertiary)
                        }
                        // #12: the NEED badge lives on the name line rather than
                        // in a trailing column, so it survives a mode switch —
                        // the NEED *column* only exists in the Overview block.
                        if isNeed {
                            Text("NEED")
                                .font(.system(size: DSType.Size.micro, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.success))
                        }
                    }

                    ProspectColumns.cells(
                        for: prospect,
                        mode: mode,
                        context: columnContext(for: prospect)
                    )

                    // PINNED regardless of mode — this room's own questions.
                    //
                    // #fleet review F13: the MEET column is gone. Every row here
                    // is a man nobody has been in a room with yet (the list
                    // filters `!interviewCompleted`), so the cell was a column of
                    // dashes charging 34 pt for a fact the screen's own filter
                    // already guarantees. See `tableHeader`.

                    // #18: bust risk preview. 80 pt, not 48: the shared Overview
                    // block measured that floor (`ProspectColumns.cells`) and
                    // anything under it truncates "Boom/Bust" and "Ceiling" to
                    // an ellipsis. The width comes out of the elastic NAME
                    // column, same as it does there.
                    ProspectRiskBadge(risk: prospect.riskLevel)
                        .frame(width: 80, alignment: .center)

                    // #14: OVR — the fogged band, widened by the department's
                    // confidence, exactly as the Big Board's OVR column reads
                    // it. This used to print `overallGradeDisplay`, i.e. the raw
                    // stored range, which is TIGHTER than the department's
                    // actual certainty.
                    ProspectScoutBandCell(prospect: prospect, width: 50)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
            .contentShape(Rectangle())
            // #13: Visual differentiation - border for must-interview
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .strokeBorder(Color.accentGold.opacity(priority == .must ? 0.4 : 0), lineWidth: 1)
            )
            .opacity(priority == .optional && !isSelected ? 0.7 : 1.0)
            // Additive on purpose: an `accessibilityLabel` here would replace
            // the row's name, position and grades with one sentence. The row
            // needs to say which of its two circles is the slot, not less.
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint(isSelected
                               ? "Removes him from this interview batch"
                               : "Adds him to this interview batch")
        }
        .buttonStyle(.plain)
        .opacity(canSelect || isSelected ? 1.0 : 0.4)
        }
        .contextMenu {
            ProspectGradeContextMenu(
                prospect: prospect,
                onChange: { try? modelContext.save() },
                // The room's own flow, on one man: batching is the default, but
                // a user who long-presses the name he came here for should not
                // have to tick him, scroll to the bar and tap Conduct. Same
                // chokepoint, same slot arithmetic — `conductInterviews(on:)`.
                // The closure is `nil` — and the menu item therefore absent —
                // whenever the Conduct button would be dead (#125).
                onInterview: canInterviewNow
                    ? { conductInterviews(on: [prospect.id]) }
                    : nil
            )
        }
    }

    /// Whether a single-man shortcut may spend a slot right now.
    ///
    /// The two predicates the Conduct button already reads, and nothing else:
    /// `canAct` is `DraftPrepProgress.canAct(.interviews)` handed down by the
    /// hub, and `remainingSlots` is the 60-a-cycle ration. Every row this list
    /// draws is already `!interviewCompleted` — that is the list's own filter.
    private var canInterviewNow: Bool {
        canAct && remainingSlots > 0
    }

    // MARK: - #15: Conduct button - properly disabled when count is 0

    private var conductButton: some View {
        // A dead control that does not say why is the bug this whole wave is
        // about, so the locked case states its reason on the button itself.
        let blocked = selectedProspectIDs.isEmpty || !canAct
        return Button {
            conductInterviews(on: selectedProspectIDs)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: canAct ? "bubble.left.and.bubble.right.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(!canAct
                     ? "The interview room opens at that stage"
                     : (selectedProspectIDs.isEmpty
                        ? "Select Prospects to Interview"
                        : "Conduct \(selectedProspectIDs.count) Interview\(selectedProspectIDs.count == 1 ? "" : "s")"))
                    .font(.system(size: DSType.Size.callout, weight: .bold))
            }
            .foregroundStyle(blocked ? Color.textTertiary : Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(blocked ? Color.backgroundTertiary.opacity(0.5) : Color.accentGold)
            )
        }
        .disabled(blocked)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - All Used View

    private var allInterviewsUsedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: DSType.Size.display))
                .foregroundStyle(Color.success)

            Text("All Interview Slots Used")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Text("You've used all \(maxInterviews) interviews this combine, but no interview data is available to display.")
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Interview Logic

    // MARK: - Interviewer

    /// The man who actually runs the room, and how good he is at it.
    ///
    /// The head coach takes the meeting when there is one; otherwise the best
    /// available coordinator. Quality is his `scoutingAbility` blended with
    /// `motivation` — reading a twenty-two-year-old across a table is half
    /// evaluation and half getting him to talk.
    /// `nil` while the staff list has not loaded, so the header does not flash
    /// a placeholder name.
    private var interviewerRoomName: String? {
        coaches.isEmpty ? nil : interviewer.name
    }

    private var interviewer: (name: String, quality: Int) {
        let ranked: [CoachRole] = [.headCoach, .offensiveCoordinator, .defensiveCoordinator]
        let coach = ranked.compactMap { role in coaches.first(where: { $0.role == role }) }.first
            ?? coaches.first
        guard let coach else { return (name: "Scouting Staff", quality: 50) }
        let quality = max(1, min(99, (coach.scoutingAbility * 2 + coach.motivation) / 3))
        return (name: "\(roleAbbreviation(coach.role)) \(coach.fullName)", quality: quality)
    }

    private func roleAbbreviation(_ role: CoachRole) -> String {
        switch role {
        case .headCoach:            return "HC"
        case .offensiveCoordinator: return "OC"
        case .defensiveCoordinator: return "DC"
        default:                    return "Coach"
        }
    }

    /// "Combine · 2027" — phase plus season, so a report read back in April
    /// still says when the room happened.
    private var occasionLabel: String {
        let phase = career.currentPhase == .proDays ? "Pro Days" : "Combine"
        return "\(phase) \u{00B7} " + String(career.currentSeason)
    }

    /// Runs the room on a set of men and shows the report.
    ///
    /// Takes the ids rather than reading `selectedProspectIDs` so the row's
    /// "Conduct Interview" shortcut (#125) is the SAME call the Conduct button
    /// makes, on a set of one — one engine call, one slot ledger, one report.
    private func conductInterviews(on ids: Set<UUID>) {
        // Belt and braces behind the disabled button: spending a slot writes
        // `career.interviewsUsed`, which is evidence the stage machine reads.
        guard canAct, !ids.isEmpty else { return }
        var results: [InterviewResult] = []
        let room = interviewer

        for prospectID in ids {
            guard let prospect = prospects.first(where: { $0.id == prospectID }) else { continue }

            // One interview engine, one set of rules. This view used to run its
            // own football-IQ formula — floors and ceilings keyed off the draft
            // projection, so a projected first rounder could not interview below
            // 70 and the room told the user nothing he did not already know from
            // the media board. `ScoutingEngine.conductInterview` reads the two
            // attributes that actually describe football IQ (awareness +
            // learning), applies interviewer-quality noise, and — the part that
            // makes the slot worth spending — writes the revealed AWR / LRN /
            // CMP / LDR / WRK grade bands onto the prospect so the Big Board's
            // Mental tab and the new IQ column light up.
            let outcome = ScoutingEngine.conductInterview(
                prospect: prospect,
                interviewerQuality: room.quality,
                interviewerName: room.name,
                occasionLabel: occasionLabel
            )

            // Flavour notes stay this view's job — the engine returns terse
            // character tags, this writes the prose the report screen shows.
            let notes = generateCharacterNotes(prospect: prospect, personality: outcome.personality)
            let merged = notes + outcome.characterNotes.filter { !notes.contains($0) }
            prospect.interviewCharacterNotes = merged
            prospect.interviewNotes = "Personality: \(outcome.personality.displayName). Football IQ: \(outcome.footballIQ). \(merged.joined(separator: " "))"

            results.append(InterviewResult(
                prospect: prospect,
                personality: outcome.personality,
                footballIQ: outcome.footballIQ,
                notes: merged
            ))
        }

        // Update career
        career.interviewsUsed += ids.count

        // The revealed grade bands live on the draft class, which is held in
        // `WeekAdvancer` rather than fetched — push them through so the board
        // survives a relaunch instead of forgetting every meeting.
        WeekAdvancer.persistDraftClass(WeekAdvancer.currentDraftClass, to: modelContext)
        try? modelContext.save()

        // The row shortcut passes a single id — don't wipe a batch selection
        // the user built for the Conduct button; only clear what was spent.
        selectedProspectIDs.subtract(ids)
        interviewResults = results
        showResults = true
    }

    // Task 10: Personality description variety — 4 variants per type
    private func generateCharacterNotes(prospect: CollegeProspect, personality: PersonalityArchetype) -> [String] {
        var notes: [String] = []

        let personalityNotes: [PersonalityArchetype: [String]] = [
            .teamLeader: [
                "Natural leader \u{2014} teammates gravitate to him.",
                "Vocal presence in the meeting room. Commands respect from peers.",
                "Led his college team through adversity. Players rally around him.",
                "Coaches describe him as the emotional heartbeat of the team."
            ],
            .loneWolf: [
                "Keeps to himself. Doesn't engage much with teammates.",
                "Prefers to work alone. Not a locker room problem, just distant.",
                "Quiet in group settings but focused during individual drills.",
                "Independent worker. May need time to integrate into team culture."
            ],
            .feelPlayer: [
                "Plays by instinct. Can be brilliant but inconsistent.",
                "Relies on natural talent over preparation. Flashes of greatness.",
                "Improviser on the field \u{2014} makes plays no one else sees coming.",
                "Instinctive player who trusts his gut. Coaches want more discipline."
            ],
            .steadyPerformer: [
                "Even-keeled personality. Consistent day in, day out.",
                "Reliable and dependable. Won't wow you but won't let you down.",
                "Coaches love his consistency. Same player every single practice.",
                "Low maintenance, high output. The kind of player you can count on."
            ],
            .dramaQueen: [
                "High-maintenance personality. Wants to be the center of attention.",
                "Needs constant validation. Can be disruptive when not the focus.",
                "Emotional player who wears his feelings on his sleeve. Volatile.",
                "Media-savvy personality. Could become a locker room distraction."
            ],
            .quietProfessional: [
                "Very professional. Does his work without fanfare.",
                "First one in, last one out. Lets his play do the talking.",
                "Low-key demeanor masks fierce competitive drive. Model pro.",
                "College coaches describe him as the ultimate professional."
            ],
            .mentor: [
                "Mature beyond his years. Already helping younger players.",
                "Takes younger players under his wing. Natural teacher.",
                "Emotional maturity stands out. Could be a team captain early.",
                "Selfless attitude. Puts team success above individual stats."
            ],
            .fieryCompetitor: [
                "Extremely competitive. Could be an issue in the locker room.",
                "Plays with an edge that can cross the line. Discipline concerns.",
                "Intensity is unmatched \u{2014} but comes with occasional outbursts.",
                "Passionate competitor. Coaches love the fire, worry about control."
            ],
            .classClown: [
                "Fun personality but can be a distraction at times.",
                "Keeps the locker room loose. Sometimes too loose for coaches.",
                "Entertaining personality, but focus can wander during film study.",
                "Great teammate energy. Question is whether he can be serious when needed."
            ]
        ]

        if let variants = personalityNotes[personality] {
            notes.append(variants.randomElement() ?? variants[0])
        }

        // Football IQ note
        let baseIQ = (prospect.trueMental.awareness + prospect.trueMental.decisionMaking) / 2
        if baseIQ >= 80 {
            notes.append("Exceptional football intelligence. Picks up concepts quickly.")
        } else if baseIQ >= 65 {
            notes.append("Solid understanding of the game. Should adapt well.")
        } else if baseIQ < 50 {
            notes.append("Concerns about his ability to handle a complex playbook.")
        }

        // Random character flag
        let flagRoll = Int.random(in: 0...100)
        if flagRoll < 10 {
            notes.append("\u{1F6A9} Off-field concerns reported by multiple sources.")
        } else if flagRoll < 25 {
            notes.append("\u{2705} Exemplary character. Community involvement noted.")
        }

        return notes
    }

    // MARK: - Helpers

    private func loadProspects() {
        prospects = WeekAdvancer.currentDraftClass
    }

    private func loadTeamData() {
        guard let teamID = career.teamID else { return }
        let playerDesc = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamRoster = (try? modelContext.fetch(playerDesc)) ?? []

        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(coachDesc)) ?? []

        // ONE ranking pass per load, off the deficit-only read — see
        // `needRankByPosition` (#fleet review F3).
        var ranks: [Position: Int] = [:]
        for (index, position) in DraftEngine.teamNeedDeficits(roster: teamRoster, limit: 5).enumerated() {
            ranks[position] = index
        }
        needRankByPosition = ranks
    }

    /// Returns the numeric OVR value for sorting/comparison.
    private func ovrValue(for prospect: CollegeProspect) -> Int {
        if let ovr = prospect.scoutedOverall { return ovr }
        if let grade = prospect.scoutedOverallGrade {
            // Convert grade midpoint rank back to approximate numeric value
            return 40 + grade.midGrade.rank * 5
        }
        return 50 // default mid-range
    }

    /// Compute scheme fit label for a prospect based on team's coordinators.
    private func schemeFitLabel(for prospect: CollegeProspect) -> String? {
        guard prospect.scoutedOverall != nil || prospect.scoutedOverallGrade != nil else { return nil }
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })

        if prospect.position.side == .offense, let scheme = oc?.offensiveScheme {
            return ProspectSchemeFitHelper.offensiveFit(prospect: prospect, scheme: scheme)
        } else if prospect.position.side == .defense, let scheme = dc?.defensiveScheme {
            return ProspectSchemeFitHelper.defensiveFit(prospect: prospect, scheme: scheme)
        }
        return nil
    }

    // `schemeFitColor` and `positionColor` are gone: the FIT cell is
    // `ProspectColumns`' now (one tint table, shared with the board) and the
    // POS chip is `ProspectSelectionPositionBadge`, which the film-study list
    // carried a byte-identical copy of.

}

// MARK: - #13: Interview Priority

enum InterviewPriority {
    case must, should, optional
}

// MARK: - Interview Risk Tier

/// What the MEETING made of a man — off-field flags, temperament, football IQ.
///
/// Deliberately NOT the board's `ProspectRiskLevel` (Safe / Ceiling /
/// Boom-Bust), which every result card still prints in its BOARD RISK row: that
/// one reads the spread of his grade, this one reads the room. Two questions,
/// two answers, and the card shows both.
///
/// It is a type rather than the free string `InterviewResult` used to hand
/// back, because the summary pills are FILTERS now and a filter that matches on
/// `riskLabel == "Medium"` is one spelling away from selecting nobody at all.
/// The thresholds are untouched — only the vocabulary is typed.
private enum InterviewRiskTier: Hashable {
    case low, medium, high

    var label: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    /// The ident a table cell has room for — `DSStatusPill`'s vocabulary rule:
    /// one short word, because a label that overruns paints over its neighbour.
    var shortLabel: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Med"
        case .high:   return "High"
        }
    }

    var tone: DSStatusPill.Tone {
        switch self {
        case .low:    return .ok
        case .medium: return .warn
        case .high:   return .bad
        }
    }

    /// Sort key. Ascending is safest-first, so a fresh (descending) tap on the
    /// RISK column opens on the men who worry you — which is the question
    /// somebody taps a risk column to ask.
    var severity: Int {
        switch self {
        case .low:    return 0
        case .medium: return 1
        case .high:   return 2
        }
    }
}

// MARK: - Interview Result Model

struct InterviewResult: Identifiable {
    let id = UUID()
    let prospect: CollegeProspect
    let personality: PersonalityArchetype
    let footballIQ: Int
    let notes: [String]

    // Task 7: Overall interview grade (A-F)
    var interviewGrade: String {
        let score = interviewScore
        if score >= 85 { return "A" }
        if score >= 75 { return "B" }
        if score >= 65 { return "C" }
        if score >= 55 { return "D" }
        return "F"
    }

    /// Combined interview score used for ranking and grading.
    var interviewScore: Int {
        var score = footballIQ
        // Personality contribution
        score += personality.interviewScoreContribution
        // Character bonus/penalty
        let hasOffField = notes.contains(where: { $0.contains("\u{1F6A9}") })
        let hasExemplary = notes.contains(where: { $0.contains("\u{2705}") })
        if hasOffField { score -= 15 }
        if hasExemplary { score += 10 }
        return max(0, min(99, score))
    }

    /// Football IQ letter grade (Task 2).
    var footballIQGrade: String {
        if footballIQ >= 85 { return "A" }
        if footballIQ >= 75 { return "B" }
        if footballIQ >= 65 { return "C" }
        if footballIQ >= 55 { return "D" }
        return "F"
    }

    /// Whether this prospect has off-field concerns.
    var hasOffFieldConcerns: Bool {
        notes.contains(where: { $0.contains("\u{1F6A9}") })
    }

    /// Whether this prospect has exemplary character.
    var hasExemplaryCharacter: Bool {
        notes.contains(where: { $0.contains("\u{2705}") })
    }

    /// The meeting's own risk read — see ``InterviewRiskTier``.
    ///
    /// Was `riskLabel: String`, returning "Low" / "Medium" / "High" for the
    /// summary line to count by string comparison. Same three words and the
    /// same thresholds; the tier is where they are decided now, because the
    /// summary counts became FILTERS and a filter keyed off a spelling is a
    /// filter that can silently match nobody.
    fileprivate var riskTier: InterviewRiskTier {
        if hasOffFieldConcerns || personality.tier == .risky { return .high }
        if personality.tier == .neutral || footballIQ < 65 { return .medium }
        return .low
    }
}

// MARK: - Report Facets — the summary pills, made operable

/// One question the summary row asks of the batch, and the scope it puts the
/// list into when you tap it.
///
/// The pills were four read-only sentences printed over a page of up to sixty
/// cards: the report could tell you "6 off-field concerns" and then gave you no
/// way to SEE the six men except by scrolling every card hunting for a red
/// border. Each pill is now the question and the answer both.
///
/// `all` is a member rather than an optional wrapper so the row speaks one
/// vocabulary, and every facet is drawn at every count — "0 off-field concerns"
/// is the answer to the question the user came here with, and hiding the pill
/// makes the good news invisible. A facet nobody matches is drawn dim and
/// refuses the tap, so a chip can never lead to a blank page.
private enum InterviewReportFacet: String, CaseIterable, Identifiable {
    case all
    case low, medium, high
    case concerns
    case marked

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:      return "person.3.fill"
        case .low:      return "checkmark.shield.fill"
        case .medium:   return "shield.fill"
        case .high:     return "exclamationmark.shield.fill"
        case .concerns: return "exclamationmark.triangle.fill"
        case .marked:   return "star.fill"
        }
    }

    /// P5 allows one gold per screen and the report already spends it on the
    /// header ident, so "everybody" — the scope the screen opens in — is the
    /// quiet neutral and the gold goes to the user's OWN verdict.
    var tint: Color {
        switch self {
        case .all:      return .textSecondary
        case .low:      return .success
        case .medium:   return .alertOrange
        case .high:     return .danger
        case .concerns: return .dangerText
        case .marked:   return .accentGold
        }
    }

    func pillText(count: Int) -> String {
        switch self {
        case .all:      return "\(count) interviewed"
        case .low:      return "\(count) low risk"
        case .medium:   return "\(count) medium risk"
        case .high:     return "\(count) high risk"
        case .concerns: return "\(count) off-field"
        case .marked:   return "\(count) marked"
        }
    }

    func spokenLabel(count: Int) -> String {
        switch self {
        case .all:      return "All \(count) interviews"
        case .low:      return "\(count) at low interview risk"
        case .medium:   return "\(count) at medium interview risk"
        case .high:     return "\(count) at high interview risk"
        case .concerns: return "\(count) with off-field concerns"
        case .marked:   return "\(count) marked Elite or Target"
        }
    }

    func matches(_ result: InterviewResult) -> Bool {
        switch self {
        case .all:      return true
        case .low:      return result.riskTier == .low
        case .medium:   return result.riskTier == .medium
        case .high:     return result.riskTier == .high
        case .concerns: return result.hasOffFieldConcerns
        // ONE mark system, same bar the rest of the draft flow reads: Elite and
        // Target are "men I want".
        case .marked:   return result.prospect.userMark.isBoardPositive
        }
    }

    var emptyTitle: String {
        switch self {
        case .marked: return "Nothing marked yet"
        default:      return "Nobody reads that way"
        }
    }

    /// Beat three of `DSEmptyState`: the CONDITION that is missing, not "no
    /// data".
    var emptyMessage: String {
        switch self {
        case .marked:
            return "Elite and Target are the two marks that mean \u{201C}I want this man\u{201D}. Give one to a prospect from his card and he appears here."
        case .concerns:
            return "Nobody in this batch came back with an off-field flag."
        default:
            return "No man in this batch reads that way after his meeting."
        }
    }
}

// MARK: - Report Layout

/// How the report draws its men.
///
/// The cards are right for the batch you just ran — they are the moment the
/// meetings pay off. They are wrong for the hundredth visit to a spent cycle,
/// where the same sixty cards are ~10,000 pt of scrolling to answer "which of
/// these did I flag". The table is the same report at row height.
private enum InterviewReportLayout: String, CaseIterable, Identifiable {
    case cards, table

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cards: return "Cards"
        case .table: return "Table"
        }
    }

    var icon: String {
        switch self {
        case .cards: return "rectangle.grid.1x2"
        case .table: return "tablecells"
        }
    }

    var spokenLabel: String {
        switch self {
        case .cards: return "Show full cards"
        case .table: return "Show compact table"
        }
    }
}

/// The table's sortable columns. GRD is not among them on purpose: the letter
/// is `interviewScore` banded, so sorting by it would be the SCORE column under
/// a second name.
private enum InterviewReportSort: Hashable {
    case score, iq, risk
}

// MARK: - Interview Report View

struct InterviewReportView: View {
    let results: [InterviewResult]
    let onDismiss: () -> Void
    /// The gold "Complete Review" bar only earns its place when dismissing
    /// actually goes somewhere — after a just-run batch it returns to the
    /// selection list. In the all-slots-spent steady state the report IS the
    /// tab, `onDismiss` re-renders the same screen, and the bar read as a
    /// required action weeks after the stage was behind the club (#118).
    /// Reading is still recorded by `onAppear` either way.
    var showsCompleteCTA: Bool = true

    @Environment(\.modelContext) private var modelContext

    /// Which slice of the batch the list is showing. See
    /// ``InterviewReportFacet``.
    @State private var activeFacet: InterviewReportFacet = .all
    /// Which column the TABLE is ordered by. Opens on the score, descending —
    /// byte-identical to the card order, so switching renderer re-orders
    /// nothing under the user's finger.
    @State private var tableSort = DSSortState<InterviewReportSort>(key: .score)
    /// The one man whose full card is open under his table row. One at a time:
    /// the table exists to be scanned, and a page of expanded rows is the card
    /// list again with a header on it.
    @State private var expandedResultID: UUID?
    /// Cards or table, remembered across visits.
    ///
    /// `@AppStorage` rather than `@CareerScopedStorage`: this is a preference
    /// about how a screen draws, not a fact about a save, and a GM who reads in
    /// tables reads in tables in his second franchise too.
    @AppStorage("interviewReportLayout") private var layoutRaw: String =
        InterviewReportLayout.cards.rawValue

    private var layout: InterviewReportLayout {
        InterviewReportLayout(rawValue: layoutRaw) ?? .cards
    }

    // Task 4: Results ranked by interview score (best first)
    private var rankedResults: [InterviewResult] {
        results.sorted { $0.interviewScore > $1.interviewScore }
    }

    /// Every pill's number, counted in ONE pass over the batch.
    ///
    /// Six pills each running their own `filter` would be six passes per body
    /// pass, on a report that can hold sixty men and redraws every time a mark
    /// changes on any of them.
    private var facetCounts: [InterviewReportFacet: Int] {
        var counts: [InterviewReportFacet: Int] = [.all: results.count]
        for result in results {
            switch result.riskTier {
            case .low:    counts[.low, default: 0] += 1
            case .medium: counts[.medium, default: 0] += 1
            case .high:   counts[.high, default: 0] += 1
            }
            if result.hasOffFieldConcerns { counts[.concerns, default: 0] += 1 }
            if result.prospect.userMark.isBoardPositive { counts[.marked, default: 0] += 1 }
        }
        return counts
    }

    /// The rows the list draws: ranked by interview score, scoped by the live
    /// facet, and — in table mode only — re-ordered by the column the user
    /// tapped. The cards keep the ranking they are numbered by.
    private var visibleRows: [InterviewResult] {
        let scoped = activeFacet == .all
            ? rankedResults
            : rankedResults.filter { activeFacet.matches($0) }
        guard layout == .table else { return scoped }
        let asc = tableSort.ascending
        // #134a's rule: every list sort ends in an id tiebreak, or two men on
        // the same score swap places on a redraw with nothing having changed.
        switch tableSort.key {
        case .score: return scoped.dsSorted(asc, by: { $0.interviewScore }, id: { $0.id })
        case .iq:    return scoped.dsSorted(asc, by: { $0.footballIQ }, id: { $0.id })
        case .risk:  return scoped.dsSorted(asc, by: { $0.riskTier.severity }, id: { $0.id })
        }
    }

    /// #N for every man in the batch, frozen on the interview-score order.
    ///
    /// The ordinal is his place in the BATCH, not his place in whatever column
    /// the table is sorted by — so a table sorted by IQ still prints the numbers
    /// the cards print, and the header's "ranked by interview score" line stays
    /// true of both renderers.
    private var scoreRankByID: [UUID: Int] {
        var map: [UUID: Int] = [:]
        map.reserveCapacity(results.count)
        for (index, result) in rankedResults.enumerated() {
            map[result.id] = index + 1
        }
        return map
    }

    // Task 6: Summary calculations
    private var bestResult: InterviewResult? { rankedResults.first }

    // Task 14: Top 3 recommendations
    private var topTargets: [InterviewResult] {
        Array(rankedResults.prefix(3))
    }

    var body: some View {
        // Filtered, ranked and (in table mode) sorted ONCE per body pass, with
        // the batch ranking resolved alongside. Both were read inside the
        // `ForEach` before there was anything to filter; a sort per row on a
        // sixty-man report is the difference between a linear pass and a
        // quadratic one every time a mark is set.
        let rows = visibleRows
        let rankByID = scoreRankByID

        return VStack(spacing: 0) {
            reportHeader
            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            ScrollView {
                LazyVStack(spacing: 12) {
                    // Task 6: Interview summary — and, since this wave, the
                    // control that scopes everything under it.
                    summarySection

                    if rows.isEmpty {
                        noMatchState
                    } else if layout == .table {
                        tableSection(rows: rows, rankByID: rankByID)
                    } else {
                        // Task 4: Ranked result cards
                        ForEach(rows) { result in
                            resultCard(result, rank: rankByID[result.id] ?? 0)
                        }
                    }

                    // Task 14: Scout's recommendation. It is the report's
                    // conclusion about the WHOLE batch, so it is printed only
                    // when the whole batch is what is showing — under a filtered
                    // page it named three men the list was hiding.
                    if activeFacet == .all && rankedResults.count >= 2 {
                        recommendationSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Task 15: Complete Review button with clarity
            if showsCompleteCTA {
                Button {
                    // Mark the "Review interview report" dashboard task as reviewed.
                    CareerScopedDefaults.set(true, "interviewReportReviewed")
                    onDismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Complete Review \u{2192} Return to Interviews")
                            .font(.system(size: 14, weight: .bold))
                    }
                    // Bordered, not filled. This bar is a dismiss — it goes
                    // BACK to the selection list — and it was drawing a
                    // full-width gold primary directly above the hub's stage
                    // advance, which is the actual forward move and the one
                    // gold the action bar's own rule allows.
                    .foregroundStyle(Color.accentGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            // Viewing the report itself counts as "reviewing" — guarantees the
            // dashboard task can complete even if the user navigates away
            // before tapping the explicit "Complete Review" button.
            CareerScopedDefaults.set(true, "interviewReportReviewed")
        }
    }

    // MARK: - Report Header (Task 5: Unified interview counts)

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("INTERVIEW REPORT")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)

                Spacer()

                // Task 5: Unified count display
                Text("\(results.count) interview\(results.count == 1 ? "" : "s") completed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                // One man is not a list, and a renderer switch over a single
                // card is a control that does nothing worth doing.
                if results.count > 1 {
                    layoutToggle
                }
            }

            // The cards are stamped #1…#53 with no stated basis, so a projected
            // seventh-rounder sitting second reads as a bug until you know the
            // ordinal is `interviewScore` — which is not the board's grade and
            // is not what the club drafts on. Say what the order means.
            if results.count > 1 {
                Text("Ranked by interview score \u{2014} football IQ, personality and character")
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Task 6: Summary Section

    private var summarySection: some View {
        let counts = facetCounts
        let shown = counts[activeFacet] ?? 0
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Text("SUMMARY")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)

                Spacer(minLength: DSSpacing.xxs)

                // What the scope is doing, in one line, so a page that is
                // suddenly eight cards long says why.
                if activeFacet != .all {
                    Text("Showing \(shown) of \(results.count)")
                        .font(.system(size: DSType.Size.footnote, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // The pills. Horizontally scrolled rather than wrapped: six of them
            // set at ~700 pt on the iPad's portrait column but the report is
            // also rendered in a split view, and a chip row that wraps to three
            // lines pushes the first card off the screen.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(InterviewReportFacet.allCases) { facet in
                        facetPill(facet, count: counts[facet] ?? 0)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }

            // The best man is a STATEMENT, not a scope — there is no "list of
            // the best man" to filter to — so he is deliberately NOT drawn as
            // one of the capsules above him. A row where some chips act and
            // others only inform is the defect §2.12 records against the first
            // iteration of the status pill.
            if let best = bestResult {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "star.fill")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.accentGold)
                    Text("Best: \(best.prospect.fullName) \u{2014} Grade \(best.interviewGrade) \u{00B7} score \(best.interviewScore)")
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(12)
        // Without this the card hugged its own text in a centre-aligned
        // LazyVStack — the densest block on the screen drew at ~40 % width,
        // sharing no left edge with the full-bleed result cards under it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentGold.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentGold.opacity(0.2))
                )
        )
    }

    /// One summary pill.
    ///
    /// A pill here is a CONTROL, which is exactly why it is not `DSStatusPill`:
    /// that component is documented as never being a button, so that a row of
    /// facts and a row of controls can never look alike. These carry a selected
    /// fill and the 44 pt target a control owes the user.
    private func facetPill(_ facet: InterviewReportFacet, count: Int) -> some View {
        let isSelected = activeFacet == facet
        // A facet nobody matches is a stated fact ("0 off-field"), not a route
        // to a blank page. The live facet stays tappable at zero, because that
        // tap is the way back out of it.
        let isDead = count == 0 && !isSelected
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                // A second tap on the live facet is the way back to the whole
                // batch — the same gesture the board's own chips answer to.
                activeFacet = isSelected ? .all : facet
                // A scope change re-lays the list under the open card; leaving
                // it open would scroll a man the filter may have just removed.
                expandedResultID = nil
            }
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: facet.icon)
                    .font(.system(size: DSType.Size.caption))
                Text(facet.pillText(count: count))
                    .font(.system(size: DSType.Size.caption,
                                  weight: isSelected ? .heavy : .semibold).monospacedDigit())
            }
            .lineLimit(1)
            .foregroundStyle(isSelected ? Color.backgroundPlate : facet.tint)
            .padding(.horizontal, DSSpacing.sm)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSelected ? facet.tint : facet.tint.opacity(0.12)))
            .overlay(
                Capsule().strokeBorder(
                    facet.tint.opacity(isSelected ? 1 : 0.35),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .opacity(isDead ? 0.45 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDead)
        .accessibilityLabel(facet.spokenLabel(count: count))
        .accessibilityHint(isSelected
                           ? "Shows the whole batch again"
                           : "Filters the report to these men")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Layout toggle

    /// Cards or table.
    ///
    /// Deliberately NOT `DSLensTabs`: that control is documented as swapping a
    /// list's trailing COLUMNS and nothing else, and this swaps the renderer
    /// under them. It wears the same capsule spec — blue selected fill, 44 pt,
    /// hairline when unselected — so the two read as one family anyway.
    private var layoutToggle: some View {
        HStack(spacing: 2) {
            ForEach(InterviewReportLayout.allCases) { option in
                let isSelected = layout == option
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layoutRaw = option.rawValue
                        expandedResultID = nil
                    }
                } label: {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: option.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(option.label)
                            .font(DSType.text(13, isSelected ? .bold : .medium))
                    }
                    .lineLimit(1)
                    .padding(.horizontal, DSSpacing.sm)
                    .frame(minHeight: 44)
                    .foregroundStyle(isSelected ? Color.backgroundPlate : Color.textSecondary)
                    .background(isSelected ? Color.accentBlue : Color.backgroundTertiary, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            isSelected ? Color.accentBlue : Color.surfaceBorder,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.spokenLabel)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Empty state

    /// What the list says when the live facet holds nobody.
    ///
    /// Only `marked` can actually land here — every other pill is dimmed at
    /// zero — and it gets there the honest way: filter to your marked men, then
    /// take the last mark off one from his card. The state names that condition
    /// rather than saying "no results".
    private var noMatchState: some View {
        // A batch with nothing in it at all is a different sentence from a
        // scope that caught nobody, and only the second one has a way out.
        let isEmptyBatch = results.isEmpty
        let actions: [DSEmptyState.Action] = isEmptyBatch ? [] : [
            DSEmptyState.Action(
                title: "Show all \(results.count)",
                systemImage: "person.3.fill",
                isPrimary: true
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { activeFacet = .all }
            }
        ]
        return DSEmptyState(
            density: .scan,
            icon: isEmptyBatch ? "person.crop.circle.badge.questionmark" : activeFacet.icon,
            title: isEmptyBatch ? "No interviews on file" : activeFacet.emptyTitle,
            message: isEmptyBatch
                ? "Nothing was recorded from this batch."
                : activeFacet.emptyMessage,
            actions: actions
        )
    }

    // MARK: - Compact Table

    /// The report at row height — the list standard (`UI_REDESIGN_VISION` §2.2)
    /// rather than a second hand-rolled table, so the header and the cells read
    /// their widths from the same `DSListColumn` constants and cannot drift.
    ///
    /// The header sits INSIDE the scroll, directly over the rows it labels,
    /// which is what the selection list one screen back does with its own
    /// column labels. Pinning it outside would put a row of column idents above
    /// the summary card, labelling a card.
    @ViewBuilder
    private func tableSection(rows: [InterviewResult], rankByID: [UUID: Int]) -> some View {
        VStack(spacing: 0) {
            tableHeaderRow
            Divider().overlay(Color.surfaceBorder.opacity(0.5))
            ForEach(rows) { result in
                tableEntry(result, rank: rankByID[result.id] ?? 0)
            }
        }
    }

    private var tableHeaderRow: some View {
        DSListHeaderRow(
            density: .scan,
            // The mark button lives outside the row's anatomy, exactly as it
            // does on the Big Board.
            leadingGutter: DSListColumn.leadingAction,
            reservesRank: true,
            rankLabel: "#",
            reservesBadge: true,
            badgeLabel: "POS",
            // `ProspectRowIdentity` carries its own portrait, so the row has no
            // separate portrait slot to reserve here.
            portraitWidth: 0,
            identityLabel: "PROSPECT",
            affordance: .disclosure
        ) {
            Spacer(minLength: DSSpacing.xxs)
            DSColumnHeader("GRD", width: DSListColumn.tight)
            DSSortableColumnHeader("SCORE", key: .score, sort: $tableSort, width: DSListColumn.value)
            DSSortableColumnHeader("IQ", key: .iq, sort: $tableSort, width: DSListColumn.meet)
            DSColumnHeader("PERSONALITY", width: DSListColumn.state)
            DSSortableColumnHeader("RISK", key: .risk, sort: $tableSort, width: DSListColumn.label)
            DSColumnHeader("FLAG", width: DSListColumn.glyph)
        }
        .padding(.vertical, DSSpacing.xxs)
    }

    /// One table line: the row, the card it opens, and the rule under both.
    @ViewBuilder
    private func tableEntry(_ result: InterviewResult, rank: Int) -> some View {
        tableRow(result, rank: rank)
        if expandedResultID == result.id {
            // The SAME card the cards mode draws. A compact mode that had to
            // re-state personality, flags, combine numbers and the notes in a
            // second layout would be two renderers of one report, and they would
            // disagree within a wave.
            resultCard(result, rank: rank)
                .padding(.bottom, DSSpacing.xs)
        }
        Divider().overlay(Color.surfaceBorder.opacity(0.3))
    }

    private func tableRow(_ result: InterviewResult, rank: Int) -> some View {
        let prospect = result.prospect
        let isExpanded = expandedResultID == result.id
        return HStack(spacing: 0) {
            // The one verdict this screen writes, on the row rather than behind
            // the disclosure: the point of the table is a pass down sixty men
            // stamping Elite / Target / Depth without opening anything.
            ProspectMarkButton(
                prospect: prospect,
                onChange: { try? modelContext.save() }
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedResultID = isExpanded ? nil : result.id
                }
            } label: {
                DSListRow(
                    density: .scan,
                    rank: DSRank(value: rank),
                    badge: DSRowBadge(
                        text: prospect.position.rawValue,
                        tint: ProspectSelectionPositionBadge.tint(prospect.position),
                        accessibilityLabel: "\(prospect.position.rawValue), \(prospect.position.side.rawValue)"
                    ),
                    portraitWidth: 0,
                    affordance: .icon(isExpanded ? "chevron.up" : "chevron.down")
                ) {
                    EmptyView()
                } identity: {
                    // The board's identity block, shared — portrait, name, the
                    // ONE mark, my grade, college and projected round. A fourth
                    // hand-rolled name column is how the two selection lists
                    // ended up poorer than the board in the first place.
                    ProspectRowIdentity(prospect: prospect)
                } columns: {
                    Spacer(minLength: DSSpacing.xxs)

                    // The card's top-right letter, in a column.
                    Text(result.interviewGrade)
                        .font(DSType.display(14, .heavy))
                        .foregroundStyle(Color.forGrade(result.interviewGrade))
                        .dsColumn(DSListColumn.tight)

                    // What the ranking is actually ON — printed because the
                    // letter bands three men into one grade and the order
                    // between them is otherwise unreadable.
                    Text("\(result.interviewScore)")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .dsColumn(DSListColumn.value)

                    // Football IQ — the exact number the meeting bought,
                    // tinted by its own letter on the one grade ladder.
                    Text("\(result.footballIQ)")
                        .font(DSType.display(12, .bold))
                        .foregroundStyle(Color.forGrade(result.footballIQGrade))
                        .dsColumn(DSListColumn.meet)

                    Text(result.personality.shortLabel)
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(personalityTextColor(result.personality))
                        .dsColumn(DSListColumn.state)

                    DSStatusPill(
                        label: result.riskTier.shortLabel,
                        tone: result.riskTier.tone,
                        showsDot: false,
                        spokenLabel: "\(result.riskTier.label) interview risk"
                    )
                    .dsColumn(DSListColumn.label)

                    tableFlagCell(result)
                        .dsColumn(DSListColumn.glyph)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // One sentence per row rather than eleven cells read out in column
            // order — the row IS one fact about one man.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tableRowSpoken(result, rank: rank))
            .accessibilityHint(isExpanded ? "Closes his full card" : "Opens his full card")
        }
    }

    /// The character flag, in a slot that is reserved on every line.
    ///
    /// §2.2's fixed-slot rule: what the user scans a sixty-row table for is the
    /// column of gaps, so an unflagged man draws a dash rather than nothing.
    @ViewBuilder
    private func tableFlagCell(_ result: InterviewResult) -> some View {
        if result.hasOffFieldConcerns {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.danger)
        } else if result.hasExemplaryCharacter {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.success)
        } else {
            Image(systemName: "minus")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func tableRowSpoken(_ result: InterviewResult, rank: Int) -> String {
        var parts = [
            "Rank \(rank)",
            result.prospect.fullName,
            result.prospect.position.rawValue,
            "grade \(result.interviewGrade)",
            "score \(result.interviewScore)",
            "football IQ \(result.footballIQ)",
            result.personality.displayName,
            "\(result.riskTier.label) interview risk"
        ]
        if result.hasOffFieldConcerns { parts.append("off-field concerns") }
        if result.hasExemplaryCharacter { parts.append("exemplary character") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Result Card (Tasks 1-4, 7-9, 12-13)

    private func resultCard(_ result: InterviewResult, rank: Int) -> some View {
        let isTopPick = rank == 1
        let borderColor: Color = {
            if result.hasOffFieldConcerns { return Color.danger }
            if result.hasExemplaryCharacter { return Color.success }
            if isTopPick { return Color.accentGold }
            return Color.surfaceBorder.opacity(0.3)
        }()
        let borderWidth: CGFloat = (result.hasOffFieldConcerns || result.hasExemplaryCharacter || isTopPick) ? 1.5 : 0.5

        return VStack(alignment: .leading, spacing: 10) {
            // Top row: rank, name, position, interview grade
            HStack {
                // Task 4: Ranking number, with the number it ranks on. Two men
                // can hold the same letter grade — the summary's "Best: …" is
                // undecidable from a page of A's — so the score that decided
                // the order is printed where the order is.
                VStack(spacing: 1) {
                    Text("#\(rank)")
                        .font(.system(size: 14, weight: .heavy).monospacedDigit())
                        .foregroundStyle(isTopPick ? Color.accentGold : Color.textTertiary)
                    Text("\(result.interviewScore)")
                        .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 28)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rank \(rank), interview score \(result.interviewScore)")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(result.prospect.firstName) \(result.prospect.lastName)")
                            .font(.system(size: DSType.Size.callout, weight: .bold))
                            .foregroundStyle(Color.textPrimary)

                        Text(result.prospect.position.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                    }

                    HStack(spacing: 6) {
                        Text(result.prospect.college)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                        if let proj = result.prospect.draftProjection {
                            Text("Rd \(proj)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }

                Spacer()

                // Task 7: Interview grade badge
                VStack(spacing: 1) {
                    Text(result.interviewGrade)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(interviewGradeColor(result.interviewGrade))
                    Text("Grade")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 40)
            }

            // Task 1: Personality badge with colored background
            // Task 2: Football IQ with letter grade and color
            HStack(spacing: 10) {
                // Personality badge
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                    Text(result.personality.displayName)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(personalityBadgeColor(result.personality))
                )

                // Football IQ with letter grade
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(iqGradeColor(result.footballIQGrade))
                        Text("Football IQ: \(result.footballIQGrade)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(iqGradeColor(result.footballIQGrade))
                        Text("(\(result.footballIQ))")
                            .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                    // Task 11: Football IQ impact explanation
                    Text("Affects scheme learning speed")
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Task 3: Off-field concerns / exemplary character — LARGER
            if result.hasOffFieldConcerns || result.hasExemplaryCharacter {
                HStack(spacing: 8) {
                    if result.hasOffFieldConcerns {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.danger)
                            Text("OFF-FIELD CONCERNS")
                                .font(.system(size: DSType.Size.caption, weight: .heavy))
                                .foregroundStyle(Color.dangerText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if result.hasExemplaryCharacter {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.success)
                            Text("EXEMPLARY CHARACTER")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Color.success)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Task 8: Bust risk change
            bustRiskRow(result)

            // Task 12: Red flags vs green flags compact summary
            flagsSummary(result)

            // Task 13: Combine data inline
            combineDataRow(result)

            // Character notes
            ForEach(result.notes, id: \.self) { note in
                // Skip the off-field / exemplary notes since shown above prominently
                if !note.contains("\u{1F6A9}") && !note.contains("\u{2705}") {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 12)
                            .padding(.top, 2)
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            // Task 11: Football IQ impact explanation — more detail for high/low
            if result.footballIQ >= 85 {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.success)
                    // Full-strength green: the 80 % wash put an explanatory
                    // sentence under the AA floor on the card surface.
                    Text("High IQ = faster scheme learning, better in-game decisions, fewer penalties")
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
                        .foregroundStyle(Color.success)
                }
            } else if result.footballIQ < 55 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.danger)
                    // `dangerText` at full strength — `danger` at 80 % is ~2.7:1
                    // as words, and this line is the warning itself.
                    Text("Low IQ = slower scheme learning, more mental errors, penalty-prone")
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
                        .foregroundStyle(Color.dangerText)
                }
            }

            // Task 9: Action buttons per prospect
            actionButtons(result)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
        )
    }

    // MARK: - Task 8: Risk, in the board's words

    /// What this meeting did to the club's risk read on him.
    ///
    /// It used to print "Bust risk: 35 % → 15 % after interview" off a
    /// view-local `estimateBustRisk` — a THIRD risk model in a feature that
    /// already had two, and the weakest of them: its before-figure was a flat
    /// 35 for every prospect who was not a QB, WR or CB, so a 53-man report
    /// printed the identical delta on man after man, while the RISK chip on the
    /// selection list called that same prospect "Safe" and the summary line at
    /// the top of this report called him "low". Nothing in the engine ever read
    /// the percentage — the only bust concept the sim has is post-hoc
    /// (`DraftGradeEngine.isBust`), so it could not have been a forecast of
    /// anything.
    ///
    /// `riskLevel` is the model the chip, the Big Board and the prospect card
    /// all speak, and the interview genuinely moves it: `conductInterview`
    /// records the personality read, which is one of its terms. So the report
    /// shows the same badge the row showed, re-read after the meeting — one
    /// claim the user can carry back to the board.
    private func bustRiskRow(_ result: InterviewResult) -> some View {
        let risk = result.prospect.riskLevel
        return Group {
            if risk != .unknown {
                HStack(spacing: 6) {
                    Text("BOARD RISK")
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                    ProspectRiskBadge(risk: risk)
                    Text("updated with this meeting")
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Task 12: Red/Green Flags Summary

    private func flagsSummary(_ result: InterviewResult) -> some View {
        let greenFlags = collectGreenFlags(result)
        let redFlags = collectRedFlags(result)

        return Group {
            if !greenFlags.isEmpty || !redFlags.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(greenFlags, id: \.self) { flag in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.success)
                                .frame(width: 6, height: 6)
                            Text(flag)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.success)
                        }
                    }
                    ForEach(redFlags, id: \.self) { flag in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.danger)
                                .frame(width: 6, height: 6)
                            Text(flag)
                                .font(.system(size: DSType.Size.footnote, weight: .semibold))
                                .foregroundStyle(Color.dangerText)
                        }
                    }
                }
            }
        }
    }

    private func collectGreenFlags(_ result: InterviewResult) -> [String] {
        var flags: [String] = []
        if result.footballIQ >= 75 { flags.append("High Football IQ") }
        if result.personality.tier == .positive { flags.append(result.personality.displayName) }
        if result.hasExemplaryCharacter { flags.append("No off-field issues") }
        if !result.hasOffFieldConcerns && !result.hasExemplaryCharacter { flags.append("Clean record") }
        return flags
    }

    private func collectRedFlags(_ result: InterviewResult) -> [String] {
        var flags: [String] = []
        if result.hasOffFieldConcerns { flags.append("Off-field concerns") }
        if result.footballIQ < 55 { flags.append("Low Football IQ") }
        if result.personality.tier == .risky { flags.append(result.personality.displayName) }
        return flags
    }

    // MARK: - Task 13: Combine Data Inline

    private func combineDataRow(_ result: InterviewResult) -> some View {
        let p = result.prospect
        let parts: [String] = [
            p.fortyTime.map { String(format: "40yd: %.2f", $0) },
            p.verticalJump.map { String(format: "Vert: %.0f\"", $0) },
            p.benchPress.map { "Bench: \($0)" },
            p.broadJump.map { "Broad: \($0)\"" }
        ].compactMap { $0 }

        return Group {
            if !parts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)
                    Text(parts.joined(separator: " | "))
                        .font(.system(size: DSType.Size.footnote, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Task 9: Action Buttons

    private func actionButtons(_ result: InterviewResult) -> some View {
        let prospect = result.prospect
        // The meeting just told you something about this man; this is where
        // you record what it changed. The star and the red-flag toggle that
        // used to sit here wrote two DIFFERENT halves of `prospectFlag`, so
        // starring a man silently cleared the flag you had put on him.
        return HStack(spacing: 12) {
            ForEach(ProspectMarkTier.choices) { tier in
                let isSelected = prospect.userMark == tier
                Button {
                    withAnimation {
                        prospect.setUserMark(isSelected ? .none : tier)
                        try? modelContext.save()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: tier.icon)
                            .font(.system(size: 11))
                        Text(tier.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? tier.color : Color.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            isSelected ? tier.color.opacity(0.15) : Color.backgroundTertiary.opacity(0.5)
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tier.label): \(tier.blurb)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }

            Spacer()
        }
    }

    // MARK: - Task 14: Scout's Recommendation

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentGold)
                Text("SCOUT'S RECOMMENDATION")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)
            }

            Text("Based on interviews, top targets are:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)

            ForEach(Array(topTargets.enumerated()), id: \.element.id) { index, result in
                HStack(spacing: 6) {
                    Text("\(index + 1).")
                        .font(.system(size: DSType.Size.body, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("\(result.prospect.firstName) \(result.prospect.lastName)")
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(result.prospect.position.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("Grade \(result.interviewGrade)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(interviewGradeColor(result.interviewGrade))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentGold.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentGold.opacity(0.25))
                )
        )
    }

    // MARK: - Helpers

    private func personalityBadgeColor(_ p: PersonalityArchetype) -> Color {
        switch p.tier {
        case .positive: return Color.success
        case .risky:    return Color.danger
        case .neutral:  return Color.warning.opacity(0.8)
        }
    }

    /// The same three tiers as INK rather than as a fill behind white text.
    ///
    /// The badge colours cannot be reused for the table cell: `danger` reads
    /// ~3.4:1 as words on a card (which is why `dangerText` exists) and
    /// `warning` at 80 % is dimmer still. A capsule fill is held to the 3:1
    /// component threshold; a word in a column is held to 4.5.
    private func personalityTextColor(_ p: PersonalityArchetype) -> Color {
        switch p.tier {
        case .positive: return Color.success
        case .risky:    return Color.dangerText
        case .neutral:  return Color.textSecondary
        }
    }

    /// Football-IQ and interview letters read the ONE ladder. These were two
    /// byte-identical switches that painted B gold where the board next door
    /// paints it blue, gave D the same red as F, and dimmed F to 80 % opacity —
    /// so the worst grade in the room was the quietest thing on the row.
    private func iqGradeColor(_ grade: String) -> Color {
        Color.forGrade(grade)
    }

    private func interviewGradeColor(_ grade: String) -> Color {
        Color.forGrade(grade)
    }
}
