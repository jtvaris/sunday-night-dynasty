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
    @AppStorage("interviewBannerDismissed") private var bannerDismissed = false
    @CareerScopedStorage("prospectWatchlist") private var prospectWatchlistJSON: String = "[]"
    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared
    @State private var isLoading: Bool = true

    private let maxInterviews = 60

    private var remainingSlots: Int {
        max(0, maxInterviews - career.interviewsUsed)
    }

    /// The club's five biggest holes, by rank, computed ONCE per load.
    ///
    /// `teamNeeds` used to re-run `DraftEngine.topTeamNeeds` on every access and
    /// every row asked `teamNeedPositions.contains(...)`, so scrolling a 300-man
    /// list re-ranked a 53-man roster once per row. The NEED column added a
    /// second per-row caller, which is what made the walk worth caching.
    /// `loadTeamData()` is the one writer.
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
                        .foregroundColor(.secondary)
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

                // #19: Interview capacity counter
                Text("\(career.interviewsUsed)/\(maxInterviews) used")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(career.interviewsUsed >= maxInterviews ? Color.danger : Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.backgroundTertiary))

                // #16: Sort/filter icon
                positionFilterMenu
            }

            // #17: Interview info tooltip
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentGold)
                Text("Reveals: Football IQ (exact) \u{00B7} Awareness, Learning, Compete, Leadership, Work Ethic grades \u{00B7} personality & character")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let name = interviewerRoomName {
                Text("Interviews run by \(name)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }

            // #83: Selection progress
            selectionProgress
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Selection Progress (#83)

    private var selectionProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(selectedProspectIDs.count)/\(remainingSlots) selected")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text("NFL teams typically interview 15\u{2013}20 prospects")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(selectedProspectIDs.isEmpty ? Color.textTertiary : Color.accentGold)
                        .frame(width: remainingSlots > 0
                               ? geo.size.width * CGFloat(selectedProspectIDs.count) / CGFloat(remainingSlots)
                               : 0,
                               height: 6)
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
        }
    }

    // MARK: - Selection List

    private var selectionList: some View {
        VStack(spacing: 0) {
            // Task 18: Interview capacity counter (prominent)
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentGold)
                Text("\(remainingSlots)/\(maxInterviews) interviews remaining")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(remainingSlots < 10 ? Color.danger : Color.textPrimary)

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
                                .font(.system(size: 9))
                            Text("View Report (\(completedInterviewResults.count))")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color.accentGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentGold.opacity(0.12)))
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
                    }
                    .buttonStyle(.plain)
                }

                if !selectedProspectIDs.isEmpty {
                    Button {
                        selectedProspectIDs.removeAll()
                    } label: {
                        Text("Deselect All")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.backgroundTertiary))
                    }
                    .buttonStyle(.plain)
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
                    // #82: Explanation banner
                    if !bannerDismissed {
                        infoBanner
                    }

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

    // MARK: - Info Banner (#82)

    private var infoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentGold)

            Text("Interviews reveal personality, football IQ, and character \u{2014} reducing bust risk.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)

            Spacer()

            Button {
                bannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .accessibilityLabel("Dismiss info banner")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentGold.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentGold.opacity(0.2))
                )
        )
        .padding(.vertical, 8)
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.top, 4)
    }

    // MARK: - Table Header (#78)

    /// Column labels. The leading five and the trailing three are PINNED — the
    /// mark, the checkbox, the man, what a room would tell you about him and
    /// what he costs you in risk are the same questions in every mode — and the
    /// block between them follows the mode chips.
    private var tableHeader: some View {
        HStack(spacing: 0) {
            // Mark button + checkbox placeholders.
            Color.clear.frame(width: 36)
            Color.clear.frame(width: 22)

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

            Text("MEET")
                .frame(width: 34, alignment: .center)
            Text("RISK")
                .frame(width: 48, alignment: .center)
            Text("OVR")
                .frame(width: 50, alignment: .center)
        }
        .font(.system(size: 9, weight: .heavy))
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
                        if prospect.scoutReportCount > 0 {
                            Text(prospect.scoutConfidenceDots)
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(prospect.scoutReportCount >= 3 ? Color.success : Color.textTertiary)
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
                    // MEET is the interview read (`ProspectFog.meetRead`): a
                    // dash is a slot not yet spent, which on a screen for
                    // spending slots is the single most useful column there is.
                    ProspectMeetCell(prospect: prospect, width: 34)

                    // #18: bust risk preview.
                    ProspectRiskBadge(risk: prospect.riskLevel)
                        .frame(width: 48, alignment: .center)

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
        }
        .buttonStyle(.plain)
        .opacity(canSelect || isSelected ? 1.0 : 0.4)
        }
        .contextMenu {
            ProspectGradeContextMenu(
                prospect: prospect,
                onChange: { try? modelContext.save() }
            )
        }
    }

    // MARK: - #15: Conduct button - properly disabled when count is 0

    private var conductButton: some View {
        // A dead control that does not say why is the bug this whole wave is
        // about, so the locked case states its reason on the button itself.
        let blocked = selectedProspectIDs.isEmpty || !canAct
        return Button {
            conductInterviews()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: canAct ? "bubble.left.and.bubble.right.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(!canAct
                     ? "The interview room opens at that stage"
                     : (selectedProspectIDs.isEmpty
                        ? "Select Prospects to Interview"
                        : "Conduct \(selectedProspectIDs.count) Interview\(selectedProspectIDs.count == 1 ? "" : "s")"))
                    .font(.system(size: 15, weight: .bold))
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
                .font(.system(size: 40))
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

    private func conductInterviews() {
        // Belt and braces behind the disabled button: spending a slot writes
        // `career.interviewsUsed`, which is evidence the stage machine reads.
        guard canAct else { return }
        var results: [InterviewResult] = []
        let room = interviewer

        for prospectID in selectedProspectIDs {
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
        career.interviewsUsed += selectedProspectIDs.count

        // The revealed grade bands live on the draft class, which is held in
        // `WeekAdvancer` rather than fetched — push them through so the board
        // survives a relaunch instead of forgetting every meeting.
        WeekAdvancer.persistDraftClass(WeekAdvancer.currentDraftClass, to: modelContext)
        try? modelContext.save()

        selectedProspectIDs.removeAll()
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

        // ONE ranking pass per load — see `needRankByPosition`.
        var ranks: [Position: Int] = [:]
        for (index, position) in DraftEngine.topTeamNeeds(roster: teamRoster, limit: 5).enumerated() {
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

    /// Risk level label for summary.
    var riskLabel: String {
        if hasOffFieldConcerns || personality.tier == .risky { return "High" }
        if personality.tier == .neutral || footballIQ < 65 { return "Medium" }
        return "Low"
    }
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

    // Task 4: Results ranked by interview score (best first)
    private var rankedResults: [InterviewResult] {
        results.sorted { $0.interviewScore > $1.interviewScore }
    }

    // Task 6: Summary calculations
    private var lowRiskCount: Int { results.filter { $0.riskLabel == "Low" }.count }
    private var mediumRiskCount: Int { results.filter { $0.riskLabel == "Medium" }.count }
    private var highRiskCount: Int { results.filter { $0.riskLabel == "High" }.count }
    private var offFieldConcernCount: Int { results.filter { $0.hasOffFieldConcerns }.count }
    private var bestResult: InterviewResult? { rankedResults.first }

    // Task 14: Top 3 recommendations
    private var topTargets: [InterviewResult] {
        Array(rankedResults.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            reportHeader
            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            ScrollView {
                LazyVStack(spacing: 12) {
                    // Task 6: Interview summary
                    summarySection

                    // Task 4: Ranked result cards
                    ForEach(Array(rankedResults.enumerated()), id: \.element.id) { index, result in
                        resultCard(result, rank: index + 1)
                    }

                    // Task 14: Scout's recommendation
                    if rankedResults.count >= 2 {
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
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentGold)
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Task 6: Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(0.5)

            HStack(spacing: 12) {
                summaryPill(icon: "person.3.fill", text: "\(results.count) interviewed", color: .accentGold)
                summaryPill(icon: "shield.checkered", text: "\(lowRiskCount) low, \(mediumRiskCount) med, \(highRiskCount) high risk", color: .textSecondary)
            }

            HStack(spacing: 12) {
                if offFieldConcernCount > 0 {
                    summaryPill(
                        icon: "exclamationmark.triangle.fill",
                        text: "\(offFieldConcernCount) off-field concern\(offFieldConcernCount == 1 ? "" : "s")",
                        color: .danger
                    )
                }
                if let best = bestResult {
                    summaryPill(
                        icon: "star.fill",
                        text: "Best: \(best.prospect.firstName) \(best.prospect.lastName) \u{2014} Grade \(best.interviewGrade)",
                        color: .accentGold
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentGold.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentGold.opacity(0.2))
                )
        )
    }

    private func summaryPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
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
                // Task 4: Ranking number
                Text("#\(rank)")
                    .font(.system(size: 14, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isTopPick ? Color.accentGold : Color.textTertiary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(result.prospect.firstName) \(result.prospect.lastName)")
                            .font(.system(size: 15, weight: .bold))
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
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                    // Task 11: Football IQ impact explanation
                    Text("Affects scheme learning speed")
                        .font(.system(size: DSType.Size.micro, weight: .medium))
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
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Color.danger)
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
                            .font(.system(size: 9))
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
                        .font(.system(size: 9))
                        .foregroundStyle(Color.success)
                    Text("High IQ = faster scheme learning, better in-game decisions, fewer penalties")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.success.opacity(0.8))
                }
            } else if result.footballIQ < 55 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.danger)
                    Text("Low IQ = slower scheme learning, more mental errors, penalty-prone")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.danger.opacity(0.8))
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

    // MARK: - Task 8: Bust Risk Impact

    private func bustRiskRow(_ result: InterviewResult) -> some View {
        let prospect = result.prospect
        // Estimate pre-interview bust risk based on prospect profile
        let baseRiskPct = estimateBustRisk(prospect: prospect, hasInterview: false)
        let postRiskPct = estimateBustRisk(prospect: prospect, hasInterview: true, iq: result.footballIQ, personality: result.personality, hasOffField: result.hasOffFieldConcerns)

        return Group {
            if baseRiskPct != postRiskPct {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 10))
                        .foregroundStyle(postRiskPct < baseRiskPct ? Color.success : Color.danger)
                    Text("Bust risk: \(baseRiskPct)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                    Text("\(postRiskPct)% after interview")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(postRiskPct < baseRiskPct ? Color.success : Color.danger)
                }
            }
        }
    }

    private func estimateBustRisk(prospect: CollegeProspect, hasInterview: Bool, iq: Int = 65, personality: PersonalityArchetype = .steadyPerformer, hasOffField: Bool = false) -> Int {
        var risk = 35 // Base bust risk

        // Position-based
        if prospect.position == .QB { risk += 10 }
        else if prospect.position == .WR || prospect.position == .CB { risk += 5 }

        // Age — younger = more risk
        if prospect.age <= 20 { risk += 5 }

        if hasInterview {
            // IQ reduces risk
            if iq >= 85 { risk -= 15 }
            else if iq >= 75 { risk -= 10 }
            else if iq >= 65 { risk -= 5 }
            else if iq < 50 { risk += 10 }

            // Personality
            if personality.tier == .positive { risk -= 5 }
            else if personality.tier == .risky { risk += 5 }

            // Off-field
            if hasOffField { risk += 10 }
        }

        return max(5, min(80, risk))
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
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.danger)
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
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                    Text(parts.joined(separator: " | "))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
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
                        .font(.system(size: 13, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("\(result.prospect.firstName) \(result.prospect.lastName)")
                        .font(.system(size: 13, weight: .bold))
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

    private func iqGradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return Color.success
        case "B": return Color.accentGold
        case "C": return Color.warning
        case "D": return Color.danger
        default:  return Color.danger.opacity(0.8) // F
        }
    }

    private func interviewGradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return Color.success
        case "B": return Color.accentGold
        case "C": return Color.warning
        case "D": return Color.danger
        default:  return Color.danger.opacity(0.8)
        }
    }
}
