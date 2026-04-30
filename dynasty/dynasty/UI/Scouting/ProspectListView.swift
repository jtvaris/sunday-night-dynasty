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

    @Environment(\.modelContext) private var modelContext
    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var sortOrder: ProspectSort = .draftProjection
    @State private var attributeTab: ProspectAttributeTab = .overview
    @State private var coaches: [Coach] = []
    @State private var teamPlayers: [Player] = []

    @State private var teamDraftPicks: [DraftPick] = []
    @State private var isLoading: Bool = true
    @State private var cachedDisplayed: [CollegeProspect] = []
    @State private var cachedPositionRanks: [UUID: Int] = [:]

    // MARK: - #3: Compare 2 Prospects mode
    @State private var compareMode: Bool = false
    @State private var compareSelection: [CollegeProspect] = []
    @State private var showCompareSheet: Bool = false

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
        cachedDisplayed = displayed
        cachedPositionRanks = positionRanks
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

                positionFilterChips
                analysisModePicker

                if cachedDisplayed.isEmpty {
                    emptyState
                } else {
                    // Column headers
                    columnHeaders
                        .padding(.horizontal, 20)
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

                                    ProspectRowView(
                                        prospect: prospect,
                                        positionRank: cachedPositionRanks[prospect.id],
                                        attributeTab: attributeTab,
                                        scoutsSentToCombine: scoutsSentToCombine,
                                        schemeFit: schemeFitLabel(for: prospect),
                                        isTeamNeed: teamNeeds.contains(prospect.position),
                                        needLevel: needLevel(for: prospect.position),
                                        starterComparison: starterComparison(for: prospect)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { toggleCompareSelection(for: prospect) }
                                } else {
                                    ProspectStarButton(prospectID: prospect.id)

                                    NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                        ProspectRowView(
                                            prospect: prospect,
                                            positionRank: cachedPositionRanks[prospect.id],
                                            attributeTab: attributeTab,
                                            scoutsSentToCombine: scoutsSentToCombine,
                                            schemeFit: schemeFitLabel(for: prospect),
                                            isTeamNeed: teamNeeds.contains(prospect.position),
                                            needLevel: needLevel(for: prospect.position),
                                            starterComparison: starterComparison(for: prospect)
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
                                ProspectGradeContextMenu(prospectID: prospect.id)
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
            if compareSelection.count == 2 {
                ProspectCompareSheet(
                    career: career,
                    left: compareSelection[0],
                    right: compareSelection[1],
                    schemeFitLeft: schemeFitLabel(for: compareSelection[0]),
                    schemeFitRight: schemeFitLabel(for: compareSelection[1]),
                    starterComparisonLeft: starterComparison(for: compareSelection[0]),
                    starterComparisonRight: starterComparison(for: compareSelection[1]),
                    onDismiss: { showCompareSheet = false }
                )
            }
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
        let pickDesc = FetchDescriptor<DraftPick>(predicate: #Predicate { $0.currentTeamID == teamID })
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
            // Always-visible: POS
            Text("POS")
                .frame(width: 36, alignment: .center)

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
        Group {
            Text("AWR")
                .frame(width: 32, alignment: .center)
            Text("DEC")
                .frame(width: 32, alignment: .center)
            Text("WRK")
                .frame(width: 32, alignment: .center)
            Text("CLT")
                .frame(width: 32, alignment: .center)
            Text("COA")
                .frame(width: 32, alignment: .center)
            Text("LDR")
                .frame(width: 32, alignment: .center)
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

    // MARK: - Position Filter Chips

    // MARK: - Position Filter Chips (#3 - smaller capsule pills)

    private var positionFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            positionFilter = filter
                        }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 11, weight: positionFilter == filter ? .bold : .medium))
                            .foregroundStyle(positionFilter == filter ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                positionFilter == filter ? Color.accentBlue : Color.backgroundTertiary,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(positionFilter == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
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
            if compareSelection.count >= 2 {
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
                     ? "Tap two prospects to compare"
                     : "Selected: \(compareSelection.map { $0.lastName }.joined(separator: " vs ")) (\(compareSelection.count)/2)")
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
            }
            Button {
                showCompareSheet = true
            } label: {
                Text("Compare")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(compareSelection.count == 2 ? Color.backgroundPrimary : Color.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        compareSelection.count == 2 ? Color.accentBlue : Color.backgroundTertiary,
                        in: Capsule()
                    )
            }
            .disabled(compareSelection.count != 2)
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

    private var isScouted: Bool { prospect.scoutedOverall != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Always-visible: Position badge
            positionBadge

            // Always-visible: Name column
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    UserGradeBadge(prospectID: prospect.id)
                }

                // Compact sub-info
                HStack(spacing: 4) {
                    // #5: Scouting report count
                    if prospect.scoutReportCount > 0 {
                        Text(prospect.scoutConfidenceDots)
                            .font(.system(size: 7))
                            .foregroundStyle(prospect.scoutReportCount >= 3 ? Color.success : prospect.scoutReportCount >= 2 ? Color.accentBlue : Color.textTertiary)
                    }
                    if prospect.combineInvite {
                        Text("CMB")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 2))
                    }
                    if prospect.interviewCompleted {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.accentBlue)
                    }
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

    // MARK: - Overview Columns

    private var overviewColumns: some View {
        Group {
            // Age
            Text("\(prospect.age)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .center)

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

    private var mentalColumns: some View {
        Group {
            if isScouted {
                gradeRangeMiniAttribute(key: "AWR", label: "AWR", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                gradeRangeMiniAttribute(key: "DEC", label: "DEC", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                gradeRangeMiniAttribute(key: "WRK", label: "WRK", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                gradeRangeMiniAttribute(key: "CLT", label: "CLT", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                gradeRangeMiniAttribute(key: "COA", label: "COA", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                gradeRangeMiniAttribute(key: "LDR", label: "LDR", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
            } else {
                ForEach(0..<6, id: \.self) { _ in
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .center)
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
        switch grade.rank {
        case 10...12: return .accentGold   // A range — elite
        case 7...9:   return .success      // B range
        case 4...6:   return .warning      // C range
        case 2...3:   return .danger       // D range
        default:      return .danger       // F
        }
    }

    // MARK: - Always-Visible Subviews

    private var positionBadge: some View {
        Text(prospect.position.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 24)
            .background(positionColor, in: RoundedRectangle(cornerRadius: 4))
    }

    private var overallBadge: some View {
        Group {
            if let gradeRange = prospect.scoutedOverallGrade {
                DualGradeDisplay(
                    prospectID: prospect.id,
                    scoutGradeText: gradeRange.displayText,
                    scoutGradeColor: gradeColor(gradeRange.midGrade)
                )
            } else if let grade = prospect.scoutGrade {
                DualGradeDisplay(
                    prospectID: prospect.id,
                    scoutGradeText: grade,
                    scoutGradeColor: Color.textPrimary
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
            gradeChangeIndicator
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
            .background(bgColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
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
    case draftProjection, scoutedOverall, position, name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draftProjection: return "Draft Projection"
        case .scoutedOverall:  return "Scouted Overall"
        case .position:        return "Position"
        case .name:            return "Name"
        }
    }

    var icon: String {
        switch self {
        case .draftProjection: return "list.number"
        case .scoutedOverall:  return "star.fill"
        case .position:        return "rectangle.3.group"
        case .name:            return "textformat"
        }
    }
}

// MARK: - #3: Prospect Compare Sheet

/// Side-by-side comparison view for two prospects.
struct ProspectCompareSheet: View {
    let career: Career
    let left: CollegeProspect
    let right: CollegeProspect
    let schemeFitLeft: String?
    let schemeFitRight: String?
    let starterComparisonLeft: String?
    let starterComparisonRight: String?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerRow
                    compareSection(title: "Overview", rows: overviewRows)
                    compareSection(title: "Physical (True)", rows: physicalRows)
                    compareSection(title: "Mental Grades", rows: mentalRows)
                    compareSection(title: "Position Skills", rows: positionRows)
                    compareSection(title: "Scouting", rows: scoutingRows)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Compare")
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
        HStack(alignment: .top, spacing: 12) {
            prospectHeaderColumn(prospect: left)
            Image(systemName: "arrow.left.arrow.right")
                .font(.title3)
                .foregroundStyle(Color.accentBlue)
                .padding(.top, 24)
            prospectHeaderColumn(prospect: right)
        }
    }

    private func prospectHeaderColumn(prospect: CollegeProspect) -> some View {
        VStack(spacing: 4) {
            Text(prospect.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: 4))
            Text(prospect.fullName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(prospect.college)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 4) {
                Text("OVR")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                Text(prospect.scoutedOverall.map { "\($0)" } ?? "?")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.forRating(prospect.scoutedOverall ?? 0))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
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
        HStack(spacing: 8) {
            Text(row.leftValue)
                .font(.caption.monospacedDigit())
                .fontWeight(row.leftBetter ? .heavy : .medium)
                .foregroundStyle(row.leftBetter ? Color.success : Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 64, alignment: .center)
            Text(row.rightValue)
                .font(.caption.monospacedDigit())
                .fontWeight(row.rightBetter ? .heavy : .medium)
                .foregroundStyle(row.rightBetter ? Color.success : Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Rows

    private struct CompareRow: Identifiable {
        let id = UUID()
        let label: String
        let leftValue: String
        let rightValue: String
        let leftBetter: Bool
        let rightBetter: Bool
    }

    private func numericRow(label: String, lhs: Int?, rhs: Int?) -> CompareRow {
        let l = lhs.map { "\($0)" } ?? "--"
        let r = rhs.map { "\($0)" } ?? "--"
        let lBetter = (lhs ?? -1) > (rhs ?? -1)
        let rBetter = (rhs ?? -1) > (lhs ?? -1)
        return CompareRow(label: label, leftValue: l, rightValue: r, leftBetter: lBetter, rightBetter: rBetter)
    }

    private func textRow(label: String, lhs: String, rhs: String, lhsBetter: Bool = false, rhsBetter: Bool = false) -> CompareRow {
        CompareRow(label: label, leftValue: lhs, rightValue: rhs, leftBetter: lhsBetter, rightBetter: rhsBetter)
    }

    private var overviewRows: [CompareRow] {
        [
            numericRow(label: "AGE", lhs: left.age, rhs: right.age),
            textRow(label: "HT", lhs: heightString(left.height), rhs: heightString(right.height)),
            numericRow(label: "WT", lhs: left.weight, rhs: right.weight),
            numericRow(label: "PROJ RD", lhs: left.draftProjection, rhs: right.draftProjection),
            textRow(label: "FIT", lhs: schemeFitLeft ?? "--", rhs: schemeFitRight ?? "--",
                    lhsBetter: schemeFitLeft == "Good" && schemeFitRight != "Good",
                    rhsBetter: schemeFitRight == "Good" && schemeFitLeft != "Good"),
            textRow(label: "RISK", lhs: riskString(left.riskLevel), rhs: riskString(right.riskLevel)),
            textRow(label: "vs STARTER", lhs: starterComparisonLeft ?? "--", rhs: starterComparisonRight ?? "--")
        ]
    }

    private var physicalRows: [CompareRow] {
        let lp = left.truePhysical
        let rp = right.truePhysical
        return [
            numericRow(label: "SPD", lhs: lp.speed, rhs: rp.speed),
            numericRow(label: "STR", lhs: lp.strength, rhs: rp.strength),
            numericRow(label: "AGI", lhs: lp.agility, rhs: rp.agility),
            numericRow(label: "ACC", lhs: lp.acceleration, rhs: rp.acceleration),
            numericRow(label: "STA", lhs: lp.stamina, rhs: rp.stamina),
            numericRow(label: "DUR", lhs: lp.durability, rhs: rp.durability)
        ]
    }

    private var mentalRows: [CompareRow] {
        let keys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR"]
        return keys.map { k in
            let l = left.scoutedMentalGrades?[k]?.displayText ?? "?"
            let r = right.scoutedMentalGrades?[k]?.displayText ?? "?"
            let lRank = left.scoutedMentalGrades?[k]?.midGrade.rank ?? -1
            let rRank = right.scoutedMentalGrades?[k]?.midGrade.rank ?? -1
            return CompareRow(label: k, leftValue: l, rightValue: r,
                              leftBetter: lRank > rRank, rightBetter: rRank > lRank)
        }
    }

    private var positionRows: [CompareRow] {
        // Only meaningful when both prospects share a position; otherwise show note.
        guard left.position == right.position else {
            return [CompareRow(label: "Note",
                               leftValue: left.position.rawValue,
                               rightValue: right.position.rawValue,
                               leftBetter: false,
                               rightBetter: false)]
        }
        let keys = positionSkillKeys(for: left)
        return keys.map { k in
            let l = left.scoutedPositionGrades?[k]?.displayText ?? "?"
            let r = right.scoutedPositionGrades?[k]?.displayText ?? "?"
            let lRank = left.scoutedPositionGrades?[k]?.midGrade.rank ?? -1
            let rRank = right.scoutedPositionGrades?[k]?.midGrade.rank ?? -1
            return CompareRow(label: k, leftValue: l, rightValue: r,
                              leftBetter: lRank > rRank, rightBetter: rRank > lRank)
        }
    }

    private var scoutingRows: [CompareRow] {
        [
            numericRow(label: "REPORTS", lhs: left.scoutReportCount, rhs: right.scoutReportCount),
            textRow(label: "GRADE", lhs: left.scoutGrade ?? "--", rhs: right.scoutGrade ?? "--"),
            textRow(label: "FLAG", lhs: left.prospectFlag.rawValue, rhs: right.prospectFlag.rawValue),
            textRow(label: "INTERVIEW", lhs: left.interviewCompleted ? "Yes" : "No", rhs: right.interviewCompleted ? "Yes" : "No"),
            textRow(label: "COMBINE", lhs: left.combineInvite ? "Invited" : "—", rhs: right.combineInvite ? "Invited" : "—")
        ]
    }

    // MARK: - Helpers

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
            ]
        )
    }
}
