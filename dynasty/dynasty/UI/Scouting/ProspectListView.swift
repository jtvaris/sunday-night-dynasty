import SwiftUI
import SwiftData

// MARK: - Attribute View Tab

enum ProspectAttributeTab: String, CaseIterable, Identifiable {
    case overview, physical, mental, position

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .physical: return "Physical"
        case .mental:   return "Mental"
        case .position: return "Position"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "list.bullet"
        case .physical: return "figure.run"
        case .mental:   return "brain.head.profile"
        case .position: return "figure.american.football"
        }
    }
}

struct ProspectListView: View {
    let career: Career
    let prospects: [CollegeProspect]
    var scoutsSentToCombine: Bool = false
    /// Shared with the Big Board and the Combine table — the chips live in
    /// `ScoutingHubView` now, so a filter survives a tab switch.
    @Binding var positionFilter: ProspectPositionFilter

    @Environment(\.modelContext) private var modelContext
    @State private var sortOrder: ProspectSort = .draftProjection
    @State private var attributeTab: ProspectAttributeTab = .overview
    @State private var coaches: [Coach] = []
    @State private var teamPlayers: [Player] = []

    @State private var teamDraftPicks: [DraftPick] = []
    @State private var isLoading: Bool = true
    @State private var cachedDisplayed: [CollegeProspect] = []
    @State private var cachedPositionRanks: [UUID: Int] = [:]
    @State private var cachedValueReads: [UUID: ProspectFog.ValueRead] = [:]

    /// Read only to migrate the legacy bookmark set onto the unified mark.
    @CareerScopedStorage("prospectWatchlist") private var prospectWatchlistJSON: String = "[]"

    private var legacyWatchlistIDs: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(prospectWatchlistJSON.utf8))) ?? [])
    }

    // MARK: - #3: Compare mode (up to four)
    @State private var compareMode: Bool = false
    @State private var compareSelection: [CollegeProspect] = []
    @State private var showCompareSheet: Bool = false
    @State private var editingMarkNoteProspect: CollegeProspect?

    // MARK: - Filtered & Sorted Prospects

    private var displayed: [CollegeProspect] {
        let filtered: [CollegeProspect]
        if positionFilter == .all {
            filtered = prospects
        } else {
            filtered = prospects.filter { positionFilter.matches($0.position) }
        }

        switch sortOrder {
        case .draftProjection:
            return filtered.sorted {
                let a = $0.draftProjection ?? Int.max
                let b = $1.draftProjection ?? Int.max
                return a < b
            }
        case .scoutedOverall:
            return filtered.sorted {
                let a = $0.scoutedOverall ?? -1
                let b = $1.scoutedOverall ?? -1
                return a > b
            }
        case .footballIQ:
            // Interview number and scouts' tape band on one fog-safe scale;
            // un-met, un-scouted prospects sink to the bottom.
            return filtered.sorted {
                let a = ProspectFog.iqRank($0)
                let b = ProspectFog.iqRank($1)
                if a != b { return a > b }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .position:
            return filtered.sorted {
                let ai = Position.allCases.firstIndex(of: $0.position) ?? 0
                let bi = Position.allCases.firstIndex(of: $1.position) ?? 0
                if ai != bi { return ai < bi }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .name:
            return filtered.sorted { $0.lastName < $1.lastName }
        }
    }

    /// Pre-computed position ranks keyed by prospect ID.
    private var positionRanks: [UUID: Int] {
        var ranks: [UUID: Int] = [:]
        let byPosition = Dictionary(grouping: prospects.filter { $0.scoutedOverall != nil }, by: \.position)
        for (_, group) in byPosition {
            let sorted = group.sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
            for (index, p) in sorted.enumerated() {
                ranks[p.id] = index + 1
            }
        }
        return ranks
    }

    /// Team needs for the need indicator column.
    private var teamNeedsList: [Position] {
        DraftEngine.topTeamNeeds(roster: teamPlayers, limit: 5)
    }

    private var teamNeeds: Set<Position> {
        Set(teamNeedsList)
    }

    /// Need level label for a position based on roster depth.
    private func needLevel(for position: Position) -> String {
        let idealCounts: [Position: Int] = [
            .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
            .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
            .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
            .CB: 5, .FS: 2, .SS: 2, .K: 1, .P: 1
        ]
        let ideal = idealCounts[position] ?? 2
        let current = teamPlayers.filter { $0.position == position }.count
        let deficit = ideal - current
        if deficit >= 2 { return "High" }
        if deficit >= 1 { return "Med" }
        return "Set"
    }

    /// Current starter at a position for comparison.
    private func starterComparison(for prospect: CollegeProspect) -> String? {
        guard let prospectOVR = prospect.scoutedOverall else { return nil }
        let starters = teamPlayers
            .filter { $0.position == prospect.position }
            .sorted { $0.overall > $1.overall }
        guard let starter = starters.first else {
            return "No \(prospect.position.rawValue) on roster"
        }
        let diff = prospectOVR - starter.overall
        let name = starter.lastName.prefix(8)
        if diff > 0 {
            return "+\(diff) vs \(name)"
        } else if diff == 0 {
            return "= \(name)"
        } else {
            return "\(diff) vs \(name)"
        }
    }

    /// Format the team's draft picks for display.
    private var draftPicksSummary: String {
        let sorted = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }
        if sorted.isEmpty { return "No picks" }
        return sorted.map { "Rd\($0.round) #\($0.pickNumber)" }.joined(separator: ", ")
    }

    /// Position need summary text for the top bar.
    private var positionNeedSummary: String {
        let needs = teamNeedsList.prefix(5)
        if needs.isEmpty { return "No major needs" }
        return needs.map { "\($0.rawValue)(\(needLevel(for: $0)))" }.joined(separator: " ")
    }

    private func refreshCachedData() {
        // Fold the legacy star / flag / bookmark opinions into the ONE mark
        // before anything on this screen reads it.
        let migrated = CollegeProspect.migrateLegacyMarks(
            in: prospects,
            watchlistIDs: legacyWatchlistIDs
        )
        if migrated > 0 { try? modelContext.save() }

        // Publish the media consensus board so `DraftIntel.consensusRank`
        // answers for this class (per-session cache, not a save).
        DraftIntel.refreshConsensusBoard(for: prospects)

        cachedDisplayed = displayed
        cachedPositionRanks = positionRanks

        // Value-vs-my-grade reads, one pass rather than per row.
        let store = UserProspectGradeStore.shared
        var reads: [UUID: ProspectFog.ValueRead] = [:]
        for prospect in cachedDisplayed {
            if let read = ProspectFog.valueRead(
                for: prospect,
                marketRank: DraftIntel.consensusRank(for: prospect.id),
                myGrade: store.grade(for: prospect.id)
            ) {
                reads[prospect.id] = read
            }
        }
        cachedValueReads = reads
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentBlue)
                    Text("Loading Prospects...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
            VStack(spacing: 0) {
                // #7: Position need summary bar + #8: Draft picks
                if !teamPlayers.isEmpty {
                    needAndPicksBar
                }

                // Position chips live in the hub's shared bar above the tabs.
                analysisModePicker

                if cachedDisplayed.isEmpty {
                    emptyState
                } else {
                    // Column headers. The insets MIRROR the rows'
                    // `listRowInsets` (leading 8 / trailing 16) rather than a
                    // round 20/20 — with a different leading inset every
                    // labelled column sat a dozen points off its data, on top
                    // of the unlabelled columns compensated inside
                    // `columnHeaders`.
                    columnHeaders
                        .padding(.leading, 8)
                        .padding(.trailing, 16)
                        .padding(.vertical, 4)
                        .background(Color.backgroundPrimary)

                    Divider().overlay(Color.surfaceBorder)

                    if compareMode {
                        compareModeBar
                    }

                    List {
                        ForEach(cachedDisplayed) { prospect in
                            HStack(spacing: 0) {
                                if compareMode {
                                    Button {
                                        toggleCompareSelection(for: prospect)
                                    } label: {
                                        Image(systemName: isSelectedForCompare(prospect) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(isSelectedForCompare(prospect) ? Color.accentBlue : Color.textTertiary)
                                            .frame(width: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isSelectedForCompare(prospect) ? "Deselect \(prospect.fullName) for compare" : "Select \(prospect.fullName) for compare")

                                    ProspectRowView(
                                        prospect: prospect,
                                        positionRank: cachedPositionRanks[prospect.id],
                                        attributeTab: attributeTab,
                                        scoutsSentToCombine: scoutsSentToCombine,
                                        schemeFit: schemeFitLabel(for: prospect),
                                        isTeamNeed: teamNeeds.contains(prospect.position),
                                        needLevel: needLevel(for: prospect.position),
                                        starterComparison: starterComparison(for: prospect),
                                        valueRead: cachedValueReads[prospect.id]
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { toggleCompareSelection(for: prospect) }
                                } else {
                                    ProspectMarkButton(
                                        prospect: prospect,
                                        onChange: {
                                            try? modelContext.save()
                                            refreshCachedData()
                                        },
                                        onEditNote: { editingMarkNoteProspect = prospect }
                                    )

                                    NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                        ProspectRowView(
                                            prospect: prospect,
                                            positionRank: cachedPositionRanks[prospect.id],
                                            attributeTab: attributeTab,
                                            scoutsSentToCombine: scoutsSentToCombine,
                                            schemeFit: schemeFitLabel(for: prospect),
                                            isTeamNeed: teamNeeds.contains(prospect.position),
                                            needLevel: needLevel(for: prospect.position),
                                            starterComparison: starterComparison(for: prospect),
                                            valueRead: cachedValueReads[prospect.id]
                                        )
                                    }
                                }
                            }
                            .listRowBackground(
                                isSelectedForCompare(prospect)
                                    ? Color.accentBlue.opacity(0.15)
                                    : Color.backgroundSecondary
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
                            .contextMenu {
                                ProspectGradeContextMenu(
                                    prospect: prospect,
                                    onChange: {
                                        try? modelContext.save()
                                        refreshCachedData()
                                    },
                                    onEditNote: { editingMarkNoteProspect = prospect }
                                )
                                Divider()
                                Button {
                                    toggleCompareSelection(for: prospect)
                                } label: {
                                    Label(
                                        isSelectedForCompare(prospect) ? "Remove From Compare" : "Add to Compare",
                                        systemImage: "rectangle.on.rectangle.angled"
                                    )
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            } // end else (not loading)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        compareMode.toggle()
                        if !compareMode { compareSelection.removeAll() }
                    }
                } label: {
                    Label(compareMode ? "Cancel Compare" : "Compare", systemImage: compareMode ? "xmark.circle" : "rectangle.on.rectangle.angled")
                }
            }
        }
        .sheet(isPresented: $showCompareSheet) {
            if compareSelection.count >= 2 {
                ProspectCompareSheet(
                    career: career,
                    prospects: compareSelection,
                    schemeFits: Dictionary(
                        uniqueKeysWithValues: compareSelection.compactMap { prospect in
                            schemeFitLabel(for: prospect).map { (prospect.id, $0) }
                        }
                    ),
                    starterComparisons: Dictionary(
                        uniqueKeysWithValues: compareSelection.compactMap { prospect in
                            starterComparison(for: prospect).map { (prospect.id, $0) }
                        }
                    ),
                    onDismiss: { showCompareSheet = false }
                )
            }
        }
        .sheet(item: $editingMarkNoteProspect) { prospect in
            ProspectMarkNoteSheet(
                prospectName: prospect.fullName,
                initialNote: prospect.userMarkNote,
                onSave: { note in
                    prospect.setUserMark(prospect.isMarked ? prospect.userMark : .target, note: note)
                    try? modelContext.save()
                    editingMarkNoteProspect = nil
                    refreshCachedData()
                },
                onCancel: { editingMarkNoteProspect = nil }
            )
        }
        .task {
            loadCoachesAndRoster()
            refreshCachedData()
            isLoading = false
        }
        .onChange(of: positionFilter) { _, _ in refreshCachedData() }
        .onChange(of: sortOrder) { _, _ in refreshCachedData() }
        .onChange(of: attributeTab) { _, _ in refreshCachedData() }
    }

    // MARK: - Need & Picks Bar (#7, #8)

    private var needAndPicksBar: some View {
        VStack(spacing: 4) {
            // Position needs
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.warning)
                Text("Needs:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                Text(positionNeedSummary)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer()
            }

            // Draft picks
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentBlue)
                Text("Your Picks:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                Text(draftPicksSummary)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Data Loading

    private func loadCoachesAndRoster() {
        guard let teamID = career.teamID else { return }
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(coachDesc)) ?? []
        let playerDesc = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamPlayers = (try? modelContext.fetch(playerDesc)) ?? []
        // This cycle's draft only — the future-pick horizon carries provisional
        // slots that would otherwise read as extra picks in the same round.
        let pickSeason = career.currentSeason
        let pickDesc = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> {
                $0.currentTeamID == teamID && $0.seasonYear == pickSeason
            }
        )
        teamDraftPicks = (try? modelContext.fetch(pickDesc)) ?? []
    }

    /// Compute scheme fit label for a prospect based on team's coordinators.
    private func schemeFitLabel(for prospect: CollegeProspect) -> String? {
        guard prospect.scoutedOverall != nil else { return nil }
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })

        if prospect.position.side == .offense, let scheme = oc?.offensiveScheme {
            return ProspectSchemeFitHelper.offensiveFit(prospect: prospect, scheme: scheme)
        } else if prospect.position.side == .defense, let scheme = dc?.defensiveScheme {
            return ProspectSchemeFitHelper.defensiveFit(prospect: prospect, scheme: scheme)
        }
        return nil
    }

    // MARK: - Column Headers

    @ViewBuilder
    private var columnHeaders: some View {
        HStack(spacing: 0) {
            // Leading control column: the star button (44 pt) — or the compare
            // checkbox (32 pt) while comparing. It has no label but it is in
            // every row, so the header has to reserve it.
            Spacer().frame(width: compareMode ? 32 : 44)

            // Always-visible: POS
            Text("POS")
                .frame(width: 36, alignment: .center)

            // Portrait column — unlabelled, but it MUST be reserved here or the
            // header stops lining up with the rows: `ProspectRowView` draws a
            // 30 pt `PersonFaceView` plus 6 pt of leading padding between the
            // badge and the name, and both sides absorb the difference in the
            // shared `Spacer`, so the only visible symptom would be "NAME"
            // sitting 36 pt left of the first name.
            Spacer().frame(width: 36)

            // NAME
            Text("NAME")
                .frame(minWidth: 80, alignment: .leading)
                .padding(.leading, 6)

            Spacer(minLength: 2)

            // Tab-specific headers
            switch attributeTab {
            case .overview:
                overviewHeaders
            case .physical:
                physicalHeaders
            case .mental:
                mentalHeaders
            case .position:
                positionHeaders
            }

            // Always-visible: Football IQ
            HStack(spacing: 2) {
                Text("IQ")
                InfoTooltipButton(
                    text: "Football IQ. A blue number is your own interview's read \u{2014} exact, because you sat in the room. A gold letter band is the scouting department reading tape (awareness + learning), and a dash means nobody has done either.",
                    size: 9
                )
            }
            .frame(width: 40, alignment: .center)

            // Always-visible: value vs the user's own grade.
            HStack(spacing: 2) {
                Text("VAL")
                InfoTooltipButton(
                    text: "Value versus your own grade. The market number is media consensus \u{2014} the latest mock's pick and the projected round, never your scouts' read. Green means he will last past where you have him; amber means taking him there is a reach. Blank until you grade him.",
                    size: 9
                )
            }
            .frame(width: 34, alignment: .center)

            // Always-visible: OVR (with tooltip explaining the dual grade format)
            HStack(spacing: 2) {
                Text("OVR")
                InfoTooltipButton(
                    text: "Scout's read on the prospect. When you have logged your own grade you'll see \"Yours / Scout\" — a wider gap means more uncertainty in the scout's evaluation. Letter grades use the standard A-F tiers (see legend).",
                    showLetterGradeKey: true,
                    size: 9
                )
            }
            .frame(width: 50, alignment: .center)

            // Always-visible: Proj Rd (overview only shows text, others show grade)
            if attributeTab == .overview {
                Text("PROJ")
                    .frame(width: 52, alignment: .center)
            } else {
                HStack(spacing: 2) {
                    Text("GRD")
                    InfoTooltipButton(
                        text: "Letter grade summarizes the scout's overall evaluation. A = elite / first-round talent, B = quality starter, C = average, D = back-end roster, F = undraftable.",
                        showLetterGradeKey: true,
                        size: 9
                    )
                }
                .frame(width: 30, alignment: .center)
            }
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
        .textCase(.uppercase)
    }

    private var overviewHeaders: some View {
        Group {
            Text("AGE")
                .frame(width: 28, alignment: .center)
            HStack(spacing: 2) {
                Text("PROD")
                InfoTooltipButton(
                    text: "College production tier — ELI elite, AA above average, AVG average, BA below average. Production is a real but imperfect signal: workout warriors under-produce, and system players over-produce against weak competition.",
                    size: 9
                )
            }
            .frame(width: 46, alignment: .center)
            Text("FIT")
                .frame(width: 32, alignment: .center)
            Text("NEED")
                .frame(width: 32, alignment: .center)
            Text("RISK")
                .frame(width: 64, alignment: .center)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

    private var physicalHeaders: some View {
        Group {
            Text("SPD")
                .frame(width: 32, alignment: .center)
            Text("STR")
                .frame(width: 32, alignment: .center)
            Text("AGI")
                .frame(width: 32, alignment: .center)
            Text("ACC")
                .frame(width: 32, alignment: .center)
            Text("STA")
                .frame(width: 32, alignment: .center)
            Text("DUR")
                .frame(width: 32, alignment: .center)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

    private var mentalHeaders: some View {
        // 8 columns (LRN + CMP added) — widths shrink 32 → 26 so the row fits.
        Group {
            Text("AWR")
                .frame(width: 26, alignment: .center)
            Text("DEC")
                .frame(width: 26, alignment: .center)
            Text("WRK")
                .frame(width: 26, alignment: .center)
            Text("CLT")
                .frame(width: 26, alignment: .center)
            Text("COA")
                .frame(width: 26, alignment: .center)
            Text("LDR")
                .frame(width: 26, alignment: .center)
            Text("LRN")
                .frame(width: 26, alignment: .center)
            Text("CMP")
                .frame(width: 26, alignment: .center)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

    private var positionHeaders: some View {
        Group {
            // Show generic headers since position-specific labels are in the rows
            ForEach(0..<4, id: \.self) { _ in
                Text("--")
                    .frame(width: 32, alignment: .center)
            }
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

    // MARK: - Analysis Mode Picker (matches RosterView style)

    // MARK: - Analysis Mode Picker (#3 - prominent segmented control)

    private var analysisModePicker: some View {
        HStack(spacing: 0) {
            ForEach(ProspectAttributeTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        attributeTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(attributeTab == tab ? Color.backgroundPrimary : Color.textSecondary)
                    .background(
                        attributeTab == tab
                            ? Color.accentBlue
                            : Color.backgroundTertiary
                    )
                }
                .accessibilityLabel("View mode: \(tab.label)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.backgroundPrimary)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(ProspectSort.allCases) { sort in
                    Label(sort.label, systemImage: sort.icon).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort prospects, currently by \(sortOrder.label)")
    }

    // MARK: - #3: Compare Mode UI

    private func isSelectedForCompare(_ prospect: CollegeProspect) -> Bool {
        compareSelection.contains(where: { $0.id == prospect.id })
    }

    private func toggleCompareSelection(for prospect: CollegeProspect) {
        if let idx = compareSelection.firstIndex(where: { $0.id == prospect.id }) {
            compareSelection.remove(at: idx)
        } else {
            if compareSelection.count >= ProspectCompareSheet.maxProspects {
                // Replace oldest selection.
                compareSelection.removeFirst()
            }
            compareSelection.append(prospect)
        }
    }

    private var compareModeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.caption)
                .foregroundStyle(Color.accentBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Compare Mode")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.accentBlue)
                Text(compareSelection.isEmpty
                     ? "Tap up to four prospects to compare"
                     : "Selected: \(compareSelection.map { $0.lastName }.joined(separator: " vs ")) (\(compareSelection.count)/\(ProspectCompareSheet.maxProspects))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if !compareSelection.isEmpty {
                Button {
                    compareSelection.removeAll()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.textTertiary)
                }
                .accessibilityLabel("Clear compare selection")
            }
            Button {
                showCompareSheet = true
            } label: {
                Text("Compare")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(compareSelection.count >= 2 ? Color.backgroundPrimary : Color.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        compareSelection.count >= 2 ? Color.accentBlue : Color.backgroundTertiary,
                        in: Capsule()
                    )
            }
            .disabled(compareSelection.count < 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.accentBlue)
                .frame(height: 1)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Prospects Found")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            if prospects.isEmpty {
                Text("The draft class hasn't been generated yet. Prospects declare around mid-season (week 9+).")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text("No prospects match this position filter.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Prospect Row View (Compact Table Row)

struct ProspectRowView: View {
    let prospect: CollegeProspect
    var positionRank: Int? = nil
    var attributeTab: ProspectAttributeTab = .overview
    var scoutsSentToCombine: Bool = false
    var schemeFit: String? = nil
    var isTeamNeed: Bool = false
    var needLevel: String = "Set"
    var starterComparison: String? = nil
    /// Market-vs-my-grade read; `nil` when the user has not graded him or the
    /// media has no consensus slot for him.
    var valueRead: ProspectFog.ValueRead? = nil

    private var isScouted: Bool { prospect.scoutedOverall != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Always-visible: Position badge
            positionBadge

            // Always-visible: Portrait (30 pt — matches the row's existing
            // two-line content height, so the list rhythm does not change).
            PersonFaceView(prospect: prospect, size: .small)
                .padding(.leading, 6)

            // Always-visible: Name column
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    // The ONE mark, same badge the board shows.
                    ProspectMarkChip(
                        mark: prospect.userMark,
                        showsNote: !prospect.userMarkNote.isEmpty
                    )

                    UserGradeBadge(prospectID: prospect.id)
                }

                // Compact sub-info
                HStack(spacing: 4) {
                    // Prep state: reports filed / room taken / numbers measured.
                    ProspectPrepChips(prospect: prospect)
                    // R27: "scouted by X" attribution + confidence of the latest report
                    if let scoutedBy = prospect.latestScoutName {
                        Text("by \(shortScoutName(scoutedBy))\(latestConfidenceSuffix)")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                    if prospect.combineInvite {
                        Text("CMB")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 2))
                    }
                    // Is he even in this draft? (S11)
                    ProspectDeclarationChip(prospect: prospect)
                    if let mention = prospect.combineMediaMention, !mention.isEmpty {
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(mediaColor(for: prospect))
                    }
                    if let rank = positionRank {
                        Text("#\(rank) \(prospect.position.rawValue)")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(rank <= 3 ? Color.accentGold : Color.textTertiary)
                    }
                    // #6: Current starter comparison
                    if let comparison = starterComparison {
                        Text(comparison)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(comparison.hasPrefix("+") ? Color.success : comparison.hasPrefix("-") ? Color.danger : Color.textTertiary)
                    }
                }
            }
            .frame(minWidth: 80, alignment: .leading)
            .padding(.leading, 6)

            Spacer(minLength: 2)

            // Tab-specific columns
            switch attributeTab {
            case .overview:
                overviewColumns
            case .physical:
                physicalColumns
            case .mental:
                mentalColumns
            case .position:
                positionColumns
            }

            // Always-visible: Football IQ (fogged until somebody meets him)
            ProspectIQCell(prospect: prospect, width: 40)

            // Always-visible: value vs the user's own grade.
            ProspectValueChip(read: valueRead)
                .frame(width: 34, alignment: .center)

            // Always-visible: OVR
            overallBadge

            // Always-visible: Proj Rd or Grade
            if attributeTab == .overview {
                projectedRoundBadge
            } else {
                gradeColumn
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Scouted-By Attribution (R27)

    /// "Ray Collins" → "R. Collins" to keep the sub-info row compact.
    private func shortScoutName(_ fullName: String) -> String {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let firstInitial = parts.first?.first else { return fullName }
        return "\(firstInitial). \(parts.last!)"
    }

    /// Latest report confidence as a compact percent suffix, e.g. " · 70%".
    private var latestConfidenceSuffix: String {
        guard let confidence = prospect.latestReportConfidence else { return "" }
        return " \u{00B7} \(Int(confidence * 100))%"
    }

    // MARK: - Overview Columns

    private var overviewColumns: some View {
        Group {
            // Age
            Text("\(prospect.age)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .center)

            // College production tier
            ProductionTierChip(tier: prospect.collegeProductionTier, width: 46)

            // Scheme Fit
            schemeFitIcon
                .frame(width: 32, alignment: .center)

            // Need indicator
            needIndicator
                .frame(width: 32, alignment: .center)

            // Risk label
            compactRiskBadge
                .frame(width: 64, alignment: .center)
        }
    }

    // MARK: - Physical Columns

    private var physicalColumns: some View {
        Group {
            if prospect.fortyTime != nil {
                colorCodedMiniAttribute(value: prospect.truePhysical.speed, label: "SPD")
                    .frame(width: 32, alignment: .center)
                colorCodedMiniAttribute(value: prospect.truePhysical.strength, label: "STR")
                    .frame(width: 32, alignment: .center)
                colorCodedMiniAttribute(value: prospect.truePhysical.agility, label: "AGI")
                    .frame(width: 32, alignment: .center)
                colorCodedMiniAttribute(value: prospect.truePhysical.acceleration, label: "ACC")
                    .frame(width: 32, alignment: .center)
                colorCodedMiniAttribute(value: prospect.truePhysical.stamina, label: "STA")
                    .frame(width: 32, alignment: .center)
                colorCodedMiniAttribute(value: prospect.truePhysical.durability, label: "DUR")
                    .frame(width: 32, alignment: .center)
            } else {
                ForEach(0..<6, id: \.self) { _ in
                    Text("?")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .center)
                }
            }
        }
    }

    // MARK: - Mental Columns

    /// An interview writes mental grade bands without ever touching
    /// `scoutedOverall`, so gating this block on "is scouted" alone would blank
    /// out the one column set the user's sixty combine slots actually bought.
    /// Missing individual keys still render "?" inside the block.
    private var hasMentalRead: Bool {
        isScouted || !(prospect.scoutedMentalGrades ?? [:]).isEmpty
    }

    private var mentalColumns: some View {
        // 8 columns (LRN + CMP added) — widths shrink 32 → 26 so the row fits.
        Group {
            if hasMentalRead {
                gradeRangeMiniAttribute(key: "AWR", label: "AWR", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
                gradeRangeMiniAttribute(key: "DEC", label: "DEC", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
                gradeRangeMiniAttribute(key: "WRK", label: "WRK", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
                gradeRangeMiniAttribute(key: "CLT", label: "CLT", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
                gradeRangeMiniAttribute(key: "COA", label: "COA", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
                gradeRangeMiniAttribute(key: "LDR", label: "LDR", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
                gradeRangeMiniAttribute(key: "LRN", label: "LRN", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
                // CMP = competitiveness, the fighter mentality (plan §2.1).
                gradeRangeMiniAttribute(key: "CMP", label: "CMP", grades: prospect.scoutedMentalGrades)
                    .frame(width: 26, alignment: .center)
            } else {
                ForEach(0..<8, id: \.self) { _ in
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 26, alignment: .center)
                }
            }
        }
    }

    // MARK: - Position Columns

    private var positionColumns: some View {
        Group {
            if isScouted {
                let keys = positionSkillKeys
                ForEach(Array(keys.prefix(4).enumerated()), id: \.offset) { _, skill in
                    gradeRangeMiniAttribute(key: skill.key, label: skill.label, grades: prospect.scoutedPositionGrades)
                        .frame(width: 32, alignment: .center)
                }
                // Pad to 4 columns if fewer
                if keys.count < 4 {
                    ForEach(0..<(4 - min(keys.count, 4)), id: \.self) { _ in
                        Spacer().frame(width: 32)
                    }
                }
            } else {
                ForEach(0..<4, id: \.self) { _ in
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .center)
                }
            }
        }
    }

    /// Returns position-specific attribute keys and labels for grade lookup.
    private var positionSkillKeys: [(key: String, label: String)] {
        switch prospect.truePositionAttributes {
        case .quarterback:
            return [("ARM", "ARM"), ("SAc", "SAc"), ("DAc", "DAc"), ("PKT", "PKT")]
        case .wideReceiver:
            return [("RTE", "RTE"), ("CTH", "CTH"), ("RLS", "RLS"), ("SPC", "SPC")]
        case .runningBack:
            return [("VIS", "VIS"), ("ELU", "ELU"), ("BTK", "BTK"), ("RCV", "RCV")]
        case .tightEnd:
            return [("BLK", "BLK"), ("CTH", "CTH"), ("RTE", "RTE"), ("SPD", "SPD")]
        case .offensiveLine:
            return [("RBK", "RBK"), ("PBK", "PBK"), ("PUL", "PUL"), ("ANC", "ANC")]
        case .defensiveLine:
            return [("PRU", "PRU"), ("BSH", "BSH"), ("PWR", "PWR"), ("FIN", "FIN")]
        case .linebacker:
            return [("TAK", "TAK"), ("ZCV", "ZCV"), ("MCV", "MCV"), ("BLZ", "BLZ")]
        case .defensiveBack:
            return [("MCV", "MCV"), ("ZCV", "ZCV"), ("PRS", "PRS"), ("BSK", "BSK")]
        case .kicking:
            return [("PWR", "PWR"), ("ACC", "ACC")]
        }
    }

    // MARK: - Mini Attribute Helper (matches PlayerRowView style)

    private func colorCodedMiniAttribute(value: Int, label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(attributeColor(for: value))
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func attributeColor(for value: Int) -> Color {
        switch value {
        case 90...:   return .accentGold
        case 80..<90: return .success
        case 70..<80: return .accentBlue
        default:      return .warning
        }
    }

    // MARK: - Grade Range Mini Attribute Helper

    private func gradeRangeMiniAttribute(key: String, label: String, grades: [String: GradeRange]?) -> some View {
        VStack(spacing: 0) {
            if let gradeRange = grades?[key] {
                Text(gradeRange.displayText)
                    .font(.system(size: gradeRange.isSingleGrade ? 10 : 8, weight: .bold))
                    .foregroundStyle(gradeColor(gradeRange.midGrade))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("?")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func gradeColor(_ grade: LetterGrade) -> Color {
        // Unified 5-tier palette: A+ bright green, A green, B blue, C yellow, D/F red.
        PositionGradeCalculator.gradeColorForLetter(grade.rawValue)
    }

    // MARK: - Always-Visible Subviews

    private var positionBadge: some View {
        Text(prospect.position.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 24)
            .background(positionColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
    }

    private var overallBadge: some View {
        Group {
            if let gradeRange = prospect.scoutedOverallGrade {
                DualGradeDisplay(
                    prospectID: prospect.id,
                    scoutGradeText: gradeRange.displayText,
                    scoutGradeColor: gradeColor(gradeRange.midGrade),
                    trajectory: prospect.stockTrajectory
                )
            } else if let grade = prospect.scoutGrade {
                DualGradeDisplay(
                    prospectID: prospect.id,
                    scoutGradeText: grade,
                    scoutGradeColor: Color.textPrimary,
                    trajectory: prospect.stockTrajectory
                )
            } else if prospect.scoutedOverall != nil {
                Text("\(prospect.scoutedOverall!)")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(prospect.scoutedOverall!))
            } else {
                Text("?")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: 50, alignment: .center)
    }

    private var projectedRoundBadge: some View {
        let text = Self.projectedRoundText(for: prospect.draftProjection)
        let color = projectedRoundColor
        return VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // Two arrows, two sources: the market's move on the projected round
            // (blue/amber) beside your own scouts' grade change (green/red).
            HStack(spacing: 3) {
                ProspectMarketArrow(prospect: prospect)
                gradeChangeIndicator
            }
        }
        .frame(width: 52, alignment: .center)
    }

    private var gradeColumn: some View {
        VStack(spacing: 0) {
            if let grade = prospect.scoutGrade {
                Text(grade)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            } else {
                Text("--")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            gradeChangeIndicator
        }
        .frame(width: 30, alignment: .center)
    }

    // MARK: - Overview-Specific Column Views

    // MARK: - #1: FIT column - show text label with color

    @ViewBuilder
    private var schemeFitIcon: some View {
        if let fit = schemeFit {
            let color: Color = fit == "Good" ? .success : (fit == "Fair" ? .warning : .danger)
            Text(fit)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        } else {
            Text("--")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - #2: NEED column - clearer labels

    @ViewBuilder
    private var needIndicator: some View {
        let level = needLevel
        if isTeamNeed {
            Text(level)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(level == "High" ? Color.danger : Color.warning)
        } else {
            Text("Set")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - #4: RISK badges - larger with background colors

    @ViewBuilder
    private var compactRiskBadge: some View {
        let risk = prospect.riskLevel
        if risk != .unknown {
            let bgColor: Color = {
                switch risk {
                case .boomOrBust:  return .danger
                case .highCeiling: return .accentBlue
                case .safePick:    return .success
                case .unknown:     return .textTertiary
                }
            }()
            HStack(spacing: 2) {
                Image(systemName: risk.icon)
                    .font(.system(size: 8))
                Text(compactRiskLabel(risk))
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bgColor.opacity(0.85), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
        } else {
            Text("--")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func compactRiskLabel(_ risk: ProspectRiskLevel) -> String {
        switch risk {
        case .safePick:    return "Safe"
        case .highCeiling: return "Ceiling"
        case .boomOrBust:  return "Boom/Bust"
        case .unknown:     return "--"
        }
    }

    // MARK: - Grade Change Indicator

    @ViewBuilder
    private var gradeChangeIndicator: some View {
        if let preGrade = prospect.preCombineGrade,
           let currentGrade = prospect.scoutGrade,
           preGrade != currentGrade {
            let improved = Self.gradeRank(currentGrade) > Self.gradeRank(preGrade)
            Text(improved ? "\u{2191}" : "\u{2193}")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(improved ? Color.success : Color.danger)
        }
    }

    /// Maps letter grades to numeric ranks for comparison (higher = better).
    static func gradeRank(_ grade: String) -> Int {
        switch grade {
        case "A+": return 13
        case "A":  return 12
        case "A-": return 11
        case "B+": return 10
        case "B":  return 9
        case "B-": return 8
        case "C+": return 7
        case "C":  return 6
        case "C-": return 5
        case "D+": return 4
        case "D":  return 3
        case "D-": return 2
        case "F":  return 1
        default:   return 0
        }
    }

    /// Maps a projected draft round (1-7) to a display label.
    /// Note: `draftProjection` stores a round number (1-7), not a pick number.
    static func projectedRoundText(for round: Int?) -> String {
        guard let round = round else { return "UDFA" }
        switch round {
        case 1:  return "Rd 1"
        case 2:  return "Rd 2"
        case 3:  return "Rd 3"
        case 4:  return "Rd 4"
        case 5:  return "Rd 5"
        case 6:  return "Rd 6"
        case 7:  return "Rd 7"
        default: return "UDFA"
        }
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var projectedRoundColor: Color {
        switch prospect.draftProjection {
        case .some(1):    return .accentGold
        case .some(2):    return .accentGold.opacity(0.8)
        case .some(3):    return .accentBlue
        case .some(4):    return .accentBlue.opacity(0.7)
        case .some(5...6): return .textSecondary
        default:           return .textTertiary
        }
    }

    private var accessibilityDescription: String {
        let overall = prospect.scoutedOverall.map { "\($0)" } ?? "unscouted"
        return "\(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), overall \(overall)"
    }

    private func mediaColor(for prospect: CollegeProspect) -> Color {
        guard let mention = prospect.combineMediaMention else { return Color.textTertiary }
        if mention.contains("Standout") { return Color.success }
        if mention.contains("Riser") { return Color.accentGold }
        if mention.contains("Faller") { return Color.danger }
        if mention.contains("Surprise") { return Color.accentBlue }
        return Color.textSecondary
    }
}

// MARK: - Market arrow (task #78)

/// How far the MEDIA has moved a prospect since the class was generated.
///
/// The board already had one arrow — `stockTrajectory` / the pre-combine grade
/// diff — but that one is YOUR scouts changing their mind. This is the other
/// half of the same picture and it is the half a GM actually trades on: the
/// consensus is a separate opinion now (`CollegeProspect.consensusErrorStored`),
/// it moves all spring on the Senior Bowl, the combine, four mocks and the
/// pro-day circuit, and a man whose public round has slid two rounds while your
/// own grade held is exactly the man you want at the price the room is asking.
///
/// Renders nothing at all when the market has not moved him, so a board full of
/// arrows means something.
struct ProspectMarketArrow: View {
    let prospect: CollegeProspect
    var font: Font = .system(size: 9, weight: .heavy)

    var body: some View {
        if let move = prospect.marketMove, move != 0 {
            Text("\(move > 0 ? "\u{25B2}" : "\u{25BC}")\(abs(move))")
                .font(font)
                .foregroundStyle(move > 0 ? Color.accentBlue : Color.warning)
                .lineLimit(1)
                .accessibilityLabel(
                    move > 0
                        ? "media board has him up \(abs(move)) rounds since the class opened"
                        : "media board has him down \(abs(move)) rounds since the class opened"
                )
        }
    }
}

// MARK: - Declaration chip (task #78, finding S11)

/// Whether an underclassman is even in this draft.
///
/// `isDeclaringForDraft` carries a model default of `true`, so from September to
/// January every board in the game showed all ~175 underclassmen as locks — and
/// roughly 100 of them never come out. The chip shows the PUBLIC read
/// (`CollegeProspect.declarationLikelihood`, built from class year and college
/// production, never from the hidden rating) until the window closes in January,
/// and the decision itself after.
struct ProspectDeclarationChip: View {
    let prospect: CollegeProspect

    var body: some View {
        switch prospect.declarationStatus {
        case .undecided:
            if let likelihood = prospect.declarationLikelihood {
                chip(likelihood.shortLabel, likelihood.color)
                    .accessibilityLabel("declaration \(likelihood.rawValue)")
            }
        case .withdrawn:
            chip("OUT", Color.danger)
                .accessibilityLabel("withdrew from the draft")
        case .declared:
            EmptyView()
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.55), lineWidth: 0.5)
            )
    }
}

// MARK: - Stat Pill

struct ProspectStatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.backgroundPrimary.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Supporting Enums

enum ProspectPositionFilter: String, CaseIterable, Identifiable {
    case all
    case qb, rb, wr, te, ol, dl, lb, db

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .qb:  return "QB"
        case .rb:  return "RB"
        case .wr:  return "WR"
        case .te:  return "TE"
        case .ol:  return "OL"
        case .dl:  return "DL"
        case .lb:  return "LB"
        case .db:  return "DB"
        }
    }

    func matches(_ position: Position) -> Bool {
        switch self {
        case .all: return true
        case .qb:  return position == .QB
        case .rb:  return position == .RB || position == .FB
        case .wr:  return position == .WR
        case .te:  return position == .TE
        case .ol:  return [.LT, .LG, .C, .RG, .RT].contains(position)
        case .dl:  return position == .DE || position == .DT
        case .lb:  return position == .OLB || position == .MLB
        case .db:  return position == .CB || position == .FS || position == .SS
        }
    }
}

enum ProspectSort: String, CaseIterable, Identifiable {
    case draftProjection, scoutedOverall, footballIQ, position, name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draftProjection: return "Draft Projection"
        case .scoutedOverall:  return "Scouted Overall"
        case .footballIQ:      return "Football IQ"
        case .position:        return "Position"
        case .name:            return "Name"
        }
    }

    var icon: String {
        switch self {
        case .draftProjection: return "list.number"
        case .scoutedOverall:  return "star.fill"
        case .footballIQ:      return "brain.head.profile"
        case .position:        return "rectangle.3.group"
        case .name:            return "textformat"
        }
    }
}

// MARK: - Prospect Compare Sheet

/// Side-by-side comparison of two to four prospects.
///
/// ## Two things were wrong with the old sheet
///
/// It printed a **"Physical (True)"** section straight off
/// `prospect.truePhysical` — speed 91, strength 78, durability 44 — for men the
/// user had never scouted. Every other surface in the game runs its numbers
/// through `ProspectFog`; this one handed over the generator's own attribute
/// block, which made the compare tool the cheapest scouting in the build. It
/// leaked the header too, printing `scoutedOverall` as a bare number where the
/// rest of the game shows a grade band.
///
/// It also capped at two. A draft board is a series of "which of these three do
/// I take" questions, and a two-way compare answers none of them.
///
/// Everything here now comes from the same two legitimate sources as the rest
/// of the draft UI: the user's own scouting (grade bands, mental / position
/// grade ranges) and public combine measurables, at the fidelity
/// `ProspectFog.combineFidelity` allows.
struct ProspectCompareSheet: View {
    /// Four columns is the cap: a fifth does not fit a portrait iPad, and a
    /// five-way compare is not a decision anybody actually makes.
    static let maxProspects = 4

    let career: Career
    let prospects: [CollegeProspect]
    /// Scheme fit per prospect id, computed by the calling screen (it owns the
    /// coordinator lookup).
    var schemeFits: [UUID: String] = [:]
    /// "vs Starter" line per prospect id.
    var starterComparisons: [UUID: String] = [:]
    let onDismiss: () -> Void

    private var columns: [CollegeProspect] {
        Array(prospects.prefix(Self.maxProspects))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerRow
                    compareSection(title: "Overview", rows: overviewRows)
                    compareSection(title: "Measurables", rows: measurableRows)
                    compareSection(title: "Mental Grades", rows: mentalRows)
                    compareSection(title: "Position Skills", rows: positionRows)
                    compareSection(title: "Scouting", rows: scoutingRows)
                    fogFootnote
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Compare \(columns.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(columns) { prospect in
                prospectHeaderColumn(prospect: prospect)
            }
        }
    }

    private func prospectHeaderColumn(prospect: CollegeProspect) -> some View {
        VStack(spacing: 4) {
            Text(prospect.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            Text(prospect.fullName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(prospect.college)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ProspectMarkChip(mark: prospect.userMark)

            // The grade the user is entitled to, not the number the engine
            // knows: gold when it is his own scouts' read, grey when it is
            // only the media's projected round.
            let read = ProspectFog.read(prospect)
            VStack(spacing: 1) {
                Text(read.text)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(read.source.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(read.source.label.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(read.accessibilityText)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var fogFootnote: some View {
        Text("Gold values are your own scouting. Grey values are public \u{2014} the media's projected round and whatever the broadcast showed at the combine. A \"?\" is work nobody in your building has done yet.")
            .font(.caption2)
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Section

    private func compareSection(title: String, rows: [CompareRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.accentBlue)
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    compareRowView(row: row)
                }
            }
            .padding(8)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func compareRowView(row: CompareRow) -> some View {
        HStack(spacing: 6) {
            Text(row.label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 66, alignment: .leading)
            ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption.monospacedDigit())
                    .fontWeight(row.bestIndices.contains(index) ? .heavy : .medium)
                    .foregroundStyle(row.bestIndices.contains(index) ? Color.success : Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label): \(row.values.joined(separator: ", "))")
    }

    // MARK: - Rows

    private struct CompareRow: Identifiable {
        let id = UUID()
        let label: String
        let values: [String]
        /// Columns to highlight. Empty when the row has no "better".
        var bestIndices: Set<Int> = []
    }

    /// Builds a row from a per-prospect value plus an optional score used to
    /// pick the winners. `nil` scores never win, so an unknown never beats a
    /// known — the highlight can no longer leak "the one you haven't scouted
    /// is the good one".
    private func row(
        _ label: String,
        _ text: (CollegeProspect) -> String,
        score: ((CollegeProspect) -> Int?)? = nil,
        higherIsBetter: Bool = true
    ) -> CompareRow {
        let values = columns.map(text)
        guard let score else { return CompareRow(label: label, values: values) }
        let scores = columns.map(score)
        let known = scores.compactMap { $0 }
        guard known.count >= 2 else { return CompareRow(label: label, values: values) }
        guard let best = higherIsBetter ? known.max() : known.min() else {
            return CompareRow(label: label, values: values)
        }
        // A row where everybody ties has no winner to point at.
        guard known.contains(where: { $0 != best }) else {
            return CompareRow(label: label, values: values)
        }
        var winners: Set<Int> = []
        for (index, value) in scores.enumerated() where value == best { winners.insert(index) }
        return CompareRow(label: label, values: values, bestIndices: winners)
    }

    private var overviewRows: [CompareRow] {
        [
            row("AGE", { "\($0.age)" }, score: { $0.age }, higherIsBetter: false),
            row("HT", { heightString($0.height) }),
            row("WT", { "\($0.weight)" }),
            row("PROD",
                { $0.collegeProductionTier.displayName },
                score: { -$0.collegeProductionTier.sortRank }),
            row("PROJ RD", { $0.draftProjection.map { "Rd \($0)" } ?? "\u{2014}" },
                score: { $0.draftProjection }, higherIsBetter: false),
            row("MY MARK", { $0.isMarked ? $0.userMark.label : "\u{2014}" },
                score: { prospect -> Int? in
                    guard prospect.isMarked else { return nil }
                    return -prospect.userMark.sortRank
                }),
            row("FIT", { schemeFits[$0.id] ?? "\u{2014}" },
                score: { schemeFits[$0.id].map { fit in fit == "Good" ? 2 : (fit == "Fair" ? 1 : 0) } }),
            row("RISK", { riskString($0.riskLevel) }),
            row("vs STARTER", { starterComparisons[$0.id] ?? "\u{2014}" })
        ]
    }

    /// Height, weight and the combine card — public the moment a man runs in
    /// front of thirty-two clubs, and only then. This replaced the old
    /// "Physical (True)" block, which read the generator's attributes directly.
    private var measurableRows: [CompareRow] {
        func measurable(
            _ label: String,
            _ text: @escaping (CollegeProspect, ProspectFog.MeasurableFidelity) -> String?,
            score: ((CollegeProspect) -> Int?)? = nil,
            higherIsBetter: Bool = true
        ) -> CompareRow {
            row(
                label,
                { prospect in
                    guard ProspectFog.showsMeasurables(prospect) else { return "?" }
                    let fidelity = ProspectFog.combineFidelity(for: prospect)
                    return text(prospect, fidelity) ?? "\u{2014}"
                },
                score: score.map { scorer in
                    { prospect in ProspectFog.showsMeasurables(prospect) ? scorer(prospect) : nil }
                },
                higherIsBetter: higherIsBetter
            )
        }

        return [
            measurable("40 YD", { ProspectFog.fortyText($0.fortyTime, fidelity: $1) },
                       score: { $0.fortyTime.map { Int($0 * 100) } }, higherIsBetter: false),
            measurable("BENCH", { ProspectFog.benchText($0.benchPress, fidelity: $1) },
                       score: { $0.benchPress }),
            measurable("VERT", { ProspectFog.verticalText($0.verticalJump, fidelity: $1) },
                       score: { $0.verticalJump.map { Int($0 * 10) } }),
            measurable("BROAD", { ProspectFog.broadJumpText($0.broadJump, fidelity: $1) },
                       score: { $0.broadJump }),
            measurable("3-CONE", { ProspectFog.agilityText($0.coneDrill, fidelity: $1) },
                       score: { $0.coneDrill.map { Int($0 * 100) } }, higherIsBetter: false),
            measurable("SHUTTLE", { ProspectFog.agilityText($0.shuttleTime, fidelity: $1) },
                       score: { $0.shuttleTime.map { Int($0 * 100) } }, higherIsBetter: false),
            measurable("DRILL", { ProspectFog.drillGradeText($0.positionDrillGrade, fidelity: $1) },
                       score: { $0.positionDrillGrade.flatMap { LetterGrade(rawValue: $0)?.rank } })
        ]
    }

    private var mentalRows: [CompareRow] {
        let keys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR", "LRN", "CMP"]
        var rows = keys.map { key in
            row(
                key,
                { $0.scoutedMentalGrades?[key]?.displayText ?? "?" },
                score: { $0.scoutedMentalGrades?[key]?.midGrade.rank }
            )
        }
        // Football IQ belongs beside the mental grades: it is the one line the
        // interview actually buys, and comparing it is the point of spending a
        // combine slot.
        rows.insert(
            row(
                "FB IQ",
                { ProspectFog.footballIQ($0).text },
                score: { prospect in
                    let read = ProspectFog.footballIQ(prospect)
                    return read.source == .none ? nil : read.rank
                }
            ),
            at: 0
        )
        return rows
    }

    private var positionRows: [CompareRow] {
        // Only meaningful when every column shares a position.
        let positions = Set(columns.map(\.position))
        guard positions.count == 1, let first = columns.first else {
            return [CompareRow(label: "NOTE", values: columns.map { $0.position.rawValue })]
        }
        return positionSkillKeys(for: first).map { key in
            row(
                key,
                { $0.scoutedPositionGrades?[key]?.displayText ?? "?" },
                score: { $0.scoutedPositionGrades?[key]?.midGrade.rank }
            )
        }
    }

    private var scoutingRows: [CompareRow] {
        [
            row("REPORTS", { "\($0.scoutReportCount)" }, score: { $0.scoutReportCount }),
            row("INTERVIEW", { $0.interviewCompleted ? "Yes" : "No" },
                score: { $0.interviewCompleted ? 1 : 0 }),
            row("PRO DAY", { $0.proDayCompleted ? "Yes" : "No" },
                score: { $0.proDayCompleted ? 1 : 0 }),
            row("COMBINE", { $0.combineInvite ? "Invited" : "\u{2014}" }),
            row("FLAGS", { flagSummary(for: $0) })
        ]
    }

    // MARK: - Helpers

    /// Medical / character flags at the disclosure the user has earned. Never
    /// the contents here — the compare sheet is a scan, and the file itself
    /// lives on the prospect card.
    private func flagSummary(for prospect: CollegeProspect) -> String {
        let total = (prospect.medicalConcerns?.count ?? 0) + (prospect.redFlags?.count ?? 0)
        switch ProspectFog.flagDisclosure(for: prospect, userTeamID: career.teamID) {
        case .hidden: return "?"
        case .count:  return total == 0 ? "None" : "\(total) on file"
        case .full:   return total == 0 ? "Clean" : "\(total)"
        }
    }

    private func positionSkillKeys(for prospect: CollegeProspect) -> [String] {
        switch prospect.truePositionAttributes {
        case .quarterback:    return ["ARM", "SAc", "DAc", "PKT"]
        case .wideReceiver:   return ["RTE", "CTH", "RLS", "SPC"]
        case .runningBack:    return ["VIS", "ELU", "BTK", "RCV"]
        case .tightEnd:       return ["BLK", "CTH", "RTE", "SPD"]
        case .offensiveLine:  return ["RBK", "PBK", "PUL", "ANC"]
        case .defensiveLine:  return ["PRU", "BSH", "PWR", "FIN"]
        case .linebacker:     return ["TAK", "ZCV", "MCV", "BLZ"]
        case .defensiveBack:  return ["MCV", "ZCV", "PRS", "BSK"]
        case .kicking:        return ["PWR", "ACC"]
        }
    }

    private func heightString(_ inches: Int) -> String {
        let ft = inches / 12
        let inch = inches % 12
        return "\(ft)'\(inch)\""
    }

    private func riskString(_ risk: ProspectRiskLevel) -> String {
        switch risk {
        case .safePick:    return "Safe"
        case .highCeiling: return "Ceiling"
        case .boomOrBust:  return "Boom/Bust"
        case .unknown:     return "?"
        }
    }

    private func positionColor(for prospect: CollegeProspect) -> Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProspectListView(
            career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
            prospects: [
                CollegeProspect(
                    firstName: "Caleb", lastName: "Williams",
                    college: "USC", position: .QB,
                    age: 21, height: 74, weight: 214,
                    truePositionAttributes: .quarterback(QBAttributes(
                        armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                        accuracyDeep: 85, pocketPresence: 87, scrambling: 78
                    )),
                    truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                    scoutedOverall: 89, scoutGrade: "A", draftProjection: 1
                ),
                CollegeProspect(
                    firstName: "Rome", lastName: "Odunze",
                    college: "Washington", position: .WR,
                    age: 21, height: 75, weight: 215,
                    truePositionAttributes: .wideReceiver(WRAttributes(
                        routeRunning: 85, catching: 88, release: 86, spectacularCatch: 82
                    )),
                    truePersonality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
                    draftProjection: 9
                ),
            ],
            positionFilter: .constant(.all)
        )
    }
}
