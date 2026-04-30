import SwiftUI
import SwiftData

struct ScoutingHubView: View {
    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: ScoutingTab = .bigBoard
    @State private var scouts: [Scout] = []
    @State private var prospects: [CollegeProspect] = []
    @State private var teamPlayers: [Player] = []
    @State private var showHireScout = false
    @State private var nextYearProspects: [ScoutingEngine.NextYearProspect] = []
    @State private var showCombineReport = false
    @State private var combineMedia: [ScoutingEngine.CombineMediaMention] = []
    @AppStorage("scoutsSentToCombine") private var scoutsSentToCombine = false
    @AppStorage("combineResultsReviewed") private var combineResultsReviewed = false
    @State private var isLoading: Bool = true

    private let maxScouts = 8

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentGold)
                    Text("Loading Scouting...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
            VStack(spacing: 0) {
                overviewMetrics
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if career.currentPhase == .combine && selectedTab != .scouts {
                    sendScoutsToCombineButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                tabPicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                Divider()
                    .overlay(Color.surfaceBorder)

                tabContent
            }
            } // end else (not loading)
        }
        .navigationTitle("Scouting")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if scouts.count < maxScouts {
                    Button { showHireScout = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .tint(Color.accentGold)
                    .accessibilityLabel("Hire scout")
                }
            }
        }
        .task {
            loadData()
            // Honor a pending tab hint set by CareerShellView when the user
            // tapped a task that should land them on a specific tab
            // (e.g. "Review interview report" → Interviews tab).
            if let pending = UserDefaults.standard.string(forKey: "scoutingPendingTab"),
               !pending.isEmpty {
                switch pending {
                case "interviews": if career.currentPhase == .combine { selectedTab = .interviews }
                case "combine":    selectedTab = .combine
                case "bigBoard":   selectedTab = .bigBoard
                case "prospects":  selectedTab = .prospects
                case "proDays":    selectedTab = .proDays
                default: break
                }
                UserDefaults.standard.removeObject(forKey: "scoutingPendingTab")
            } else if career.currentPhase == .proDays {
                // Auto-select Pro Days tab when in proDays phase
                selectedTab = .proDays
            }
            isLoading = false
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .combine && scoutsSentToCombine {
                combineResultsReviewed = true
            }
        }
        .sheet(isPresented: $showHireScout, onDismiss: { loadData() }) {
            HireScoutSheet(career: career)
        }
        .sheet(isPresented: $showCombineReport) {
            CombineReportSheet(mentions: combineMedia)
        }
    }

    // MARK: - Send Scouts to Combine (#258)

    private var sendScoutsToCombineButton: some View {
        Group {
            if scoutsSentToCombine && combineResultsReviewed {
                // State 3: scouts sent + results reviewed — show a quiet, completed banner
                // (or hide entirely on the Combine tab to reduce noise).
                if selectedTab != .combine {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(Color.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Combine Reviewed")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text("Combine results have been reviewed.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                        Button {
                            selectedTab = .combine
                        } label: {
                            Text("Re-open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentGold)
                        }
                    }
                    .padding(12)
                    .background(Color.backgroundTertiary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.surfaceBorder, lineWidth: 1))
                }
            } else if scoutsSentToCombine {
                // State 2: scouts sent, results NOT yet reviewed — actionable green banner
                Button {
                    selectedTab = .combine
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scouts at Combine")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.success)
                            Text("Results are in \u{2014} tap to review")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.success)
                    }
                    .padding(12)
                    .background(Color.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.success.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                // #22: More visually prominent CTA
                Button {
                    sendScoutsToCombine()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "binoculars.fill")
                            .font(.title2)
                            .foregroundStyle(Color.backgroundPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Scouts to NFL Combine")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.backgroundPrimary)
                            Text("\(scouts.count) scout\(scouts.count == 1 ? "" : "s") will evaluate ~330 prospects")
                                .font(.caption)
                                .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.backgroundPrimary)
                    }
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [Color.success, Color.success.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.success.opacity(0.6), lineWidth: 1.5)
                    )
                    .shadow(color: Color.success.opacity(0.3), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sendScoutsToCombine() {
        var draftClass = WeekAdvancer.currentDraftClass

        // Snapshot pre-combine grades so we can show grade change arrows later.
        for i in draftClass.indices {
            draftClass[i].preCombineGrade = draftClass[i].scoutGrade
        }

        // Compute average scouting ability from coaching staff
        let staffScoutingAbility: Int = {
            guard let teamID = career.teamID else { return 50 }
            let desc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            let coaches = (try? modelContext.fetch(desc)) ?? []
            guard !coaches.isEmpty else { return 50 }
            let total = coaches.reduce(0) { $0 + $1.scoutingAbility }
            return total / coaches.count
        }()

        // Generate combine results if not yet available (WeekAdvancer may have already done this)
        let hasCombineResults = draftClass.contains { $0.fortyTime != nil }
        if !hasCombineResults {
            ScoutingEngine.generateCombineResults(for: &draftClass, scoutingAbility: staffScoutingAbility)
        }

        combineMedia = ScoutingEngine.generateCombineMedia(prospects: &draftClass)
        WeekAdvancer.currentDraftClass = draftClass
        scoutsSentToCombine = true
        loadData()
        showCombineReport = true
    }

    // MARK: - Overview Metrics (#223)

    private var scoutCountColor: Color {
        if scouts.count >= 6 { return .success }
        if scouts.count >= 3 { return .accentGold }
        return .danger
    }

    private var scoutedCount: Int {
        prospects.filter { $0.scoutedOverall != nil }.count
    }

    private var scoutedPercentage: Int {
        guard !prospects.isEmpty else { return 0 }
        return Int((Double(scoutedCount) / Double(prospects.count) * 100).rounded())
    }

    private var topProspect: CollegeProspect? {
        prospects
            .filter { $0.scoutedOverall != nil }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
            .first
    }

    private var phaseLabel: String {
        switch career.currentPhase {
        case .combine:      return "NFL Combine"
        case .freeAgency:   return "Free Agency"
        case .proDays:      return "Pro Days & Workouts"
        case .draft:        return "NFL Draft"
        case .regularSeason: return "Regular Season"
        default:            return career.currentPhase.rawValue
        }
    }

    private var overviewMetrics: some View {
        HStack(spacing: 0) {
            // Scouts hired
            metricItem(
                icon: "person.3.fill",
                label: "Scouts: \(scouts.count)/\(maxScouts) hired",
                color: scoutCountColor
            )

            metricDivider

            // Scouted percentage
            metricItem(
                icon: "doc.text.magnifyingglass",
                label: "Scouted: \(scoutedPercentage)% of prospects",
                color: .accentBlue
            )

            metricDivider

            // Top prospect
            if let top = topProspect, let ovr = top.scoutedOverall {
                metricItem(
                    icon: "star.fill",
                    label: "Top: \(top.lastName) (OVR \(ovr))",
                    color: .accentGold
                )
            } else {
                metricItem(
                    icon: "star",
                    label: "Top: None scouted",
                    color: .textTertiary
                )
            }

            metricDivider

            // Current phase
            metricItem(
                icon: "calendar",
                label: "Phase: \(phaseLabel)",
                color: .textSecondary
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metricItem(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.surfaceBorder)
            .frame(width: 1, height: 16)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabs) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.label, systemImage: tab.icon)
                            .font(.callout.weight(isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isSelected ? Color.clear : Color.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
            }
        )
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .scouts:
            ScoutTeamView(
                scouts: scouts,
                canHire: scouts.count < maxScouts,
                career: career,
                scoutsSentToCombine: scoutsSentToCombine,
                prospects: prospects,
                coachingBudget: fetchCoachingBudget(),
                onHire: { showHireScout = true },
                onFire: { fireScout($0) },
                onSendToCombine: { sendScoutsToCombine() }
            )
        case .prospects:
            ProspectListView(career: career, prospects: prospects, scoutsSentToCombine: scoutsSentToCombine)
        case .bigBoard:
            BigBoardView(career: career, prospects: prospects, teamRoster: teamPlayers, scoutsSentToCombine: scoutsSentToCombine)
        case .combine:
            CombineResultsView(career: career, prospects: prospects)
        case .interviews:
            InterviewSelectionView(career: career)
        case .mockDraft:
            MockDraftView(career: career, prospects: prospects)
        case .draftOrder:
            DraftOrderView(career: career)
        case .proDays:
            ProDayListView(career: career, scouts: scouts, prospects: $prospects, teamRoster: teamPlayers, onRefresh: loadData)
        case .nextYear:
            NextYearClassPreview(career: career, prospects: nextYearProspects)
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let scoutDesc = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        scouts = (try? modelContext.fetch(scoutDesc)) ?? []

        // Re-generate draft class if lost (app restart)
        if WeekAdvancer.currentDraftClass.isEmpty {
            let validPhases: [SeasonPhase] = [.coachingChanges, .reviewRoster, .combine, .freeAgency, .proDays, .draft, .otas]
            if validPhases.contains(career.currentPhase) {
                WeekAdvancer.currentDraftClass = ScoutingEngine.generateDraftClass()
                WeekAdvancer.draftClassGenerated = true
                // Apply pre-scouted data for first season
                ScoutingEngine.applyPreScoutedData(prospects: &WeekAdvancer.currentDraftClass)
            }
        }

        // Prospects live in WeekAdvancer.currentDraftClass (not persisted in SwiftData)
        let allProspects = WeekAdvancer.currentDraftClass
        prospects = allProspects.filter { $0.isDeclaringForDraft }

        let playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        teamPlayers = (try? modelContext.fetch(playerDesc)) ?? []

        if nextYearProspects.isEmpty {
            nextYearProspects = ScoutingEngine.generateNextYearPreview()
        }
    }

    private func fetchCoachingBudget() -> Int {
        guard let teamID = career.teamID else { return 20_000 }
        let desc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        return (try? modelContext.fetch(desc))?.first?.owner?.coachingBudget ?? 20_000
    }

    private var visibleTabs: [ScoutingTab] {
        ScoutingTab.allCases.filter { tab in
            switch tab {
            case .interviews:
                return career.currentPhase == .combine
            default:
                return true
            }
        }
    }

    private func fireScout(_ scout: Scout) {
        modelContext.delete(scout)
        try? modelContext.save()
        loadData()
    }
}

// MARK: - Combine Report Sheet (#259)

private struct CombineReportSheet: View {
    let mentions: [ScoutingEngine.CombineMediaMention]
    @Environment(\.dismiss) private var dismiss

    private let categories = ["Standout", "Stock Riser", "Stock Faller", "Surprise"]

    private func mentionsFor(_ category: String) -> [ScoutingEngine.CombineMediaMention] {
        mentions.filter { $0.category == category }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "Standout":     return "star.fill"
        case "Stock Riser":  return "arrow.up.right.circle.fill"
        case "Stock Faller": return "arrow.down.right.circle.fill"
        case "Surprise":     return "exclamationmark.triangle.fill"
        default:             return "newspaper"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Standout":     return .accentGold
        case "Stock Riser":  return .success
        case "Stock Faller": return .danger
        case "Surprise":     return .accentBlue
        default:             return .textSecondary
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                List {
                    // Header
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "newspaper.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.accentGold)
                            Text("NFL COMBINE REPORT")
                                .font(.title2.weight(.black))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(mentions.count) notable performances")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    ForEach(categories, id: \.self) { category in
                        let items = mentionsFor(category)
                        if !items.isEmpty {
                            Section {
                                ForEach(items, id: \.prospectID) { mention in
                                    HStack(spacing: 12) {
                                        Text(mention.position)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 32, height: 22)
                                            .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 4))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mention.prospectName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.textPrimary)
                                            Text(mention.headline)
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            } header: {
                                Label(category, systemImage: categoryIcon(category))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(categoryColor(category))
                                    .textCase(nil)
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Combine Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tab Enum

enum ScoutingTab: String, CaseIterable, Identifiable {
    case scouts     = "scouts"
    case prospects  = "prospects"
    case bigBoard   = "bigBoard"
    case combine    = "combine"
    case interviews = "interviews"
    case mockDraft  = "mockDraft"
    case draftOrder = "draftOrder"
    case proDays    = "proDays"
    case nextYear   = "nextYear"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scouts:     return "Scout Team"
        case .prospects:  return "Prospects"
        case .bigBoard:   return "Big Board"
        case .combine:    return "Combine"
        case .interviews: return "Interviews"
        case .mockDraft:  return "Mock Draft"
        case .draftOrder: return "Draft Order"
        case .proDays:    return "Pro Days"
        case .nextYear:   return "Next Yr"
        }
    }

    var icon: String {
        switch self {
        case .scouts:     return "binoculars"
        case .prospects:  return "person.3"
        case .bigBoard:   return "list.number"
        case .combine:    return "figure.run"
        case .interviews: return "bubble.left.and.bubble.right"
        case .mockDraft:  return "doc.text"
        case .draftOrder: return "number.circle"
        case .proDays:    return "mappin.and.ellipse"
        case .nextYear:   return "calendar.badge.clock"
        }
    }
}

// MARK: - Hire Scout Sheet (placeholder)

private struct HireScoutSheet: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Determine the next available scout role that isn't filled yet.
    private var nextAvailableRole: ScoutRole? {
        guard let teamID = career.teamID else { return ScoutRole.regionalScout1 }
        let descriptor = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let filledRoles = Set(existing.map(\.scoutRole))
        return ScoutRole.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { !filledRoles.contains($0) }
    }

    var body: some View {
        NavigationStack {
            if let role = nextAvailableRole {
                HireScoutView(
                    scoutRole: role,
                    teamID: career.teamID ?? UUID(),
                    remainingBudget: 5_000
                ) { _, _ in
                    dismiss()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            } else {
                ZStack {
                    Color.backgroundPrimary.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.textTertiary)
                        Text("Scout Staff Full")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("You have filled all 8 scout slots.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
                .navigationTitle("Hire Scout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Pro Day List View

struct ProDayListView: View {
    let career: Career
    let scouts: [Scout]
    @Binding var prospects: [CollegeProspect]
    let teamRoster: [Player]
    var onRefresh: () -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage("prospectWatchlist") private var prospectWatchlistJSON: String = "[]"
    @AppStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"
    @State private var expandedColleges: Set<String> = []
    @State private var showSendScoutSheet = false
    @State private var selectedCollege: String?
    @State private var showProDayResults = false
    @State private var proDayResultSummary: ProDayResultSummary?
    @State private var showPersonalWorkouts = false
    @State private var personalWorkoutIDs: Set<UUID> = []
    @AppStorage("personalWorkoutsUsed") private var personalWorkoutsUsed: Int = 0

    // MARK: - Computed Data

    private var teamNeeds: Set<Position> {
        Set(DraftEngine.topTeamNeeds(roster: teamRoster, limit: 5))
    }

    private var watchlist: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(prospectWatchlistJSON.utf8))) ?? [])
    }

    private var boardOrder: [UUID] {
        let strings = (try? JSONDecoder().decode([String].self, from: Data(prospectCustomBoardJSON.utf8))) ?? []
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private func boardRank(for prospectID: UUID) -> Int? {
        guard let idx = boardOrder.firstIndex(of: prospectID) else { return nil }
        return idx + 1
    }

    private func isStarred(_ prospect: CollegeProspect) -> Bool {
        prospect.prospectFlag == .mustHave || watchlist.contains(prospect.id.uuidString)
    }

    private func isTopProspect(_ prospect: CollegeProspect) -> Bool {
        guard let rank = boardRank(for: prospect.id) else { return false }
        return rank <= 50
    }

    private func isNeedPosition(_ prospect: CollegeProspect) -> Bool {
        teamNeeds.contains(prospect.position)
    }

    /// Colleges grouped with rich metadata.
    private var collegeData: [ProDayCollegeInfo] {
        let declaring = prospects.filter { $0.isDeclaringForDraft }
        let grouped = Dictionary(grouping: declaring) { $0.college }
        return grouped.map { college, collegePros in
            let hasAttended = collegePros.contains { $0.proDayCompleted }
            let starredCount = collegePros.filter { isStarred($0) }.count
            let topCount = collegePros.filter { isTopProspect($0) }.count
            let needCount = collegePros.filter { isNeedPosition($0) }.count
            let attendedScout = scouts.first { $0.proDayColleges.contains(college) }

            // Position breakdown
            let posCounts = Dictionary(grouping: collegePros) { $0.position }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }

            // Best prospect at this school for matching
            let bestProspect = collegePros
                .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
                .first

            // Relevance score for recommendations
            let relevance = starredCount * 10 + topCount * 5 + needCount * 3 + collegePros.count

            return ProDayCollegeInfo(
                college: college,
                prospects: collegePros.sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) },
                hasAttended: hasAttended,
                attendedScoutName: attendedScout?.fullName,
                starredCount: starredCount,
                topCount: topCount,
                needCount: needCount,
                positionBreakdown: posCounts,
                bestProspect: bestProspect,
                relevanceScore: relevance
            )
        }
        .sorted { $0.relevanceScore > $1.relevanceScore }
    }

    private var recommendedColleges: [ProDayCollegeInfo] {
        collegeData.filter { !$0.hasAttended && $0.relevanceScore > 5 }.prefix(5).map { $0 }
    }

    private var totalAssigned: Int {
        scouts.reduce(0) { $0 + $1.proDaysAttended }
    }

    private var totalCapacity: Int {
        scouts.reduce(0) { $0 + $1.maxProDays }
    }

    private var availableScouts: [Scout] {
        scouts.filter { $0.canAttendProDay }
    }

    private var isProDayPhase: Bool {
        career.currentPhase == .combine || career.currentPhase == .proDays || career.currentPhase == .draft || career.currentPhase == .freeAgency
    }

    // MARK: - Scout-School Matching

    private func bestScoutFor(college: String) -> (scout: Scout, reason: String)? {
        let collegePros = prospects.filter { $0.college == college && $0.isDeclaringForDraft }
        guard !collegePros.isEmpty else { return nil }

        // Find the best prospect position at this school
        let posCounts = Dictionary(grouping: collegePros) { $0.position }.mapValues { $0.count }
        let topPosition = posCounts.max { $0.value < $1.value }?.key

        // Find a scout specializing in that position
        for scout in availableScouts {
            if let spec = scout.positionSpecialization, spec == topPosition {
                let bestAtPos = collegePros.filter { $0.position == spec }
                    .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
                    .first
                let prospectName = bestAtPos?.fullName ?? "prospects"
                return (scout, "\(scout.fullName) (\(spec.rawValue) specialist) for \(prospectName)")
            }
        }

        // Fallback: highest accuracy scout
        if let best = availableScouts.max(by: { $0.accuracy < $1.accuracy }) {
            return (best, "\(best.fullName) (highest accuracy: \(best.accuracy))")
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        if !isProDayPhase {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.textTertiary)
                Text("Pro Days Not Available Yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Pro Days are available during the Combine and Draft phases.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scouts.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "person.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.textTertiary)
                Text("No Scouts Available")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Hire scouts to send them to Pro Days.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                // Info banner (Task 7)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color.accentGold)
                            Text("Pro Day Benefits")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentGold)
                        }
                        Text("Pro Days reveal: updated measurables, position-specific drills, injury/medical checks, and private workout results. Reports improve scouting accuracy by 10-15%.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // Capacity counter (Task 8)
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "gauge.with.needle")
                            .font(.title3)
                            .foregroundStyle(Color.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Assignment Capacity")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(scouts.count) scouts \u{2192} \(totalCapacity) max Pro Days | \(totalAssigned)/\(totalCapacity) assigned")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()

                        // Capacity bar
                        GeometryReader { geo in
                            let progress = totalCapacity > 0 ? CGFloat(totalAssigned) / CGFloat(totalCapacity) : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.backgroundTertiary)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(progress > 0.8 ? Color.danger : Color.accentGold)
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(width: 60, height: 6)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // Scout Availability (Task 1, 2, 11)
                Section {
                    ForEach(scouts) { scout in
                        proDayScoutCard(scout)
                    }
                } header: {
                    HStack {
                        Text("Scout Availability")
                        Spacer()
                        Text("\(availableScouts.count) available")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // Recommended Schools (Task 5, 6, 10)
                if !recommendedColleges.isEmpty {
                    Section {
                        ForEach(recommendedColleges, id: \.college) { info in
                            recommendedSchoolRow(info)
                        }

                        if !availableScouts.isEmpty {
                            Button {
                                sendAllRecommended()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperplane.circle.fill")
                                        .font(.body)
                                    Text("Send All Recommended")
                                        .font(.caption.weight(.bold))
                                    Spacer()
                                    Text("\(min(availableScouts.count, recommendedColleges.filter { !$0.hasAttended }.count)) assignments")
                                        .font(.caption2)
                                        .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                                }
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label("Recommended", systemImage: "star.circle.fill")
                            .foregroundStyle(Color.accentGold)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }

                // All Schools (Task 3, 4, 9, 12, 13)
                Section {
                    ForEach(collegeData, id: \.college) { info in
                        proDaySchoolCard(info)
                    }
                } header: {
                    HStack {
                        Text("All Pro Days")
                        Spacer()
                        Text("\(collegeData.count) schools")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // Task 9: "Send Scouts to Pro Days" confirmation + results
                if totalAssigned > 0 && proDayResultSummary == nil {
                    Section {
                        Button {
                            executeProDays()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "paperplane.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.backgroundPrimary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Send Scouts to Pro Days")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.backgroundPrimary)
                                    Text("\(totalAssigned) assignment\(totalAssigned == 1 ? "" : "s") ready")
                                        .font(.caption)
                                        .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.backgroundPrimary)
                            }
                            .padding(12)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                // Task 9: Pro Day results summary
                if let summary = proDayResultSummary {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.success)
                                Text("Pro Day Results")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.success)
                            }
                            Text("\(summary.prospectsEvaluated) prospects evaluated across \(summary.schoolsVisited) schools")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            if !summary.keyFindings.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(summary.keyFindings, id: \.self) { finding in
                                        HStack(spacing: 4) {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 8))
                                                .foregroundStyle(Color.accentGold)
                                            Text(finding)
                                                .font(.caption2)
                                                .foregroundStyle(Color.textPrimary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.success.opacity(0.08))
                }

                // Task 10: Personal Workouts section
                if career.currentPhase == .proDays || career.currentPhase == .combine {
                    Section {
                        Button {
                            showPersonalWorkouts = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.body)
                                    .foregroundStyle(Color.accentBlue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Personal Workouts")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Schedule private workouts with up to 10 prospects (\(personalWorkoutsUsed)/10 used)")
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Label("Private Workouts", systemImage: "dumbbell.fill")
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .sheet(isPresented: $showSendScoutSheet) {
                if let college = selectedCollege {
                    ProDaySendScoutSheet(
                        college: college,
                        scouts: scouts,
                        prospects: prospects.filter { $0.college == college && $0.isDeclaringForDraft },
                        bestMatch: bestScoutFor(college: college),
                        onSend: { scout in
                            sendScoutToProDay(scout: scout, college: college)
                            showSendScoutSheet = false
                        },
                        onCancel: { showSendScoutSheet = false }
                    )
                }
            }
            .sheet(isPresented: $showPersonalWorkouts) {
                PersonalWorkoutSheet(
                    prospects: prospects.filter { $0.isDeclaringForDraft && !$0.proDayCompleted },
                    selectedIDs: $personalWorkoutIDs,
                    workoutsUsed: personalWorkoutsUsed,
                    onConduct: { ids in
                        conductPersonalWorkouts(prospectIDs: ids)
                        showPersonalWorkouts = false
                    }
                )
            }
        }
    }

    // MARK: - Execute Pro Days (Task 9)

    private func executeProDays() {
        var findings: [String] = []
        var schoolsVisited = 0
        var prospectsEvaluated = 0

        let assignedColleges = Set(scouts.flatMap { $0.proDayColleges })
        schoolsVisited = assignedColleges.count

        for college in assignedColleges {
            let collegePros = prospects.filter { $0.college == college && $0.isDeclaringForDraft }
            prospectsEvaluated += collegePros.count
            // Check for notable findings
            for p in collegePros {
                if let ovr = p.scoutedOverall, ovr >= 80 {
                    findings.append("\(p.fullName) (\(p.position.rawValue)) impressed at \(college) pro day")
                }
            }
        }

        proDayResultSummary = ProDayResultSummary(
            schoolsVisited: schoolsVisited,
            prospectsEvaluated: prospectsEvaluated,
            keyFindings: Array(findings.prefix(5))
        )
    }

    // MARK: - Personal Workouts (Task 10)

    private func conductPersonalWorkouts(prospectIDs: Set<UUID>) {
        for id in prospectIDs {
            guard let idx = prospects.firstIndex(where: { $0.id == id }) else { continue }
            // Personal workout reveals more detailed physical + mental attributes
            let prospect = prospects[idx]
            let bestScout = scouts.max(by: { $0.accuracy < $1.accuracy })
            if let scout = bestScout {
                ScoutingEngine.attendProDay(
                    scout: scout,
                    college: prospect.college,
                    prospects: &prospects
                )
            }
            prospect.proDayCompleted = true
        }
        personalWorkoutsUsed += prospectIDs.count
        try? modelContext.save()
        onRefresh()
    }

    // MARK: - Scout Card (Task 1, 2, 11)

    private func proDayScoutCard(_ scout: Scout) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Specialty icon
                ZStack {
                    Circle()
                        .fill(scout.canAttendProDay ? Color.accentGold.opacity(0.15) : Color.backgroundTertiary)
                        .frame(width: 36, height: 36)
                    Image(systemName: specialtyIcon(for: scout))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(scout.canAttendProDay ? Color.accentGold : Color.textTertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(scout.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(scout.specialtyLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentBlue.opacity(0.12), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        // Accuracy bar
                        HStack(spacing: 4) {
                            Text("ACC")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.textTertiary)
                            proDayAccuracyBar(value: scout.accuracy)
                            Text("\(scout.accuracy)")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(accuracyColor(scout.accuracy))
                        }

                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)

                        Text("\(scout.proDaysAttended)/\(scout.maxProDays) Pro Days")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(scout.proDaysAttended >= scout.maxProDays ? Color.danger : Color.textSecondary)
                    }
                }

                Spacer()

                // Status indicator
                if scout.proDaysAttended >= scout.maxProDays {
                    Text("FULL")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("\(scout.maxProDays - scout.proDaysAttended) LEFT")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            // Show assigned colleges (Task 2)
            if !scout.proDayColleges.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentGold)
                    Text(scout.proDayColleges.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.top, 6)
                .padding(.leading, 46)
            }
        }
        .padding(.vertical, 4)
    }

    private func proDayAccuracyBar(value: Int) -> some View {
        GeometryReader { geo in
            let pct = CGFloat(min(max(value, 0), 100)) / 100.0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.backgroundTertiary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(accuracyColor(value))
                    .frame(width: geo.size.width * pct)
            }
        }
        .frame(width: 40, height: 4)
    }

    private func accuracyColor(_ value: Int) -> Color {
        if value >= 75 { return .success }
        if value >= 55 { return .accentGold }
        return .danger
    }

    private func specialtyIcon(for scout: Scout) -> String {
        if let pos = scout.positionSpecialization {
            switch pos.side {
            case .offense:      return "sportscourt.fill"
            case .defense:      return "shield.fill"
            case .specialTeams: return "figure.run"
            }
        }
        if let focus = scout.focusAttribute {
            return focus.icon
        }
        return scout.scoutRole.isChief ? "star.fill" : "binoculars.fill"
    }

    // MARK: - Recommended School Row (Task 5, 6)

    private func recommendedSchoolRow(_ info: ProDayCollegeInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
                Text(info.college)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                schoolBadges(info)
            }

            // Why recommended
            VStack(alignment: .leading, spacing: 2) {
                if let best = info.bestProspect, let rank = boardRank(for: best.id) {
                    Text("Has your #\(rank) ranked prospect: \(best.fullName)")
                        .font(.caption2)
                        .foregroundStyle(Color.accentGold)
                }
                if info.starredCount > 0 {
                    Text("\(info.starredCount) starred prospect\(info.starredCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(Color.accentGold)
                }
                if info.needCount > 0 {
                    Text("\(info.needCount) at need position\(info.needCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(Color.danger)
                }
            }

            // Smart scout recommendation (Task 6)
            if let match = bestScoutFor(college: info.college), !info.hasAttended {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentGold.opacity(0.8))
                    Text("Send \(match.reason)")
                        .font(.caption2.italic())
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - School Card (Task 3, 4, 9, 12, 13)

    private func proDaySchoolCard(_ info: ProDayCollegeInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: tappable to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedColleges.contains(info.college) {
                        expandedColleges.remove(info.college)
                    } else {
                        expandedColleges.insert(info.college)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        // Expand/collapse chevron
                        Image(systemName: expandedColleges.contains(info.college) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 14)

                        Text(info.college)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)

                        schoolBadges(info)

                        Spacer()

                        // Attended status (Task 13)
                        if info.hasAttended {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.success)
                                    .font(.caption)
                                if let scoutName = info.attendedScoutName {
                                    Text(scoutName)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Color.success)
                                } else {
                                    Text("Attended")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Color.success)
                                }
                            }
                        } else if availableScouts.isEmpty {
                            Text("No scouts available")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        } else {
                            Button {
                                selectedCollege = info.college
                                showSendScoutSheet = true
                            } label: {
                                Label("Send Scout", systemImage: "paperplane.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentGold)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Position breakdown (Task 12)
                    HStack(spacing: 6) {
                        Text("\(info.prospects.count) prospect\(info.prospects.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)

                        if !info.positionBreakdown.isEmpty {
                            Text("\u{2022}")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Text(info.positionBreakdown.prefix(4).map { "\($0.value) \($0.key.rawValue)" }.joined(separator: ", ") + (info.positionBreakdown.count > 4 ? ", +\(info.positionBreakdown.dropFirst(4).map(\.value).reduce(0, +)) other" : ""))
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }

                        // Big Board integration (Task 9)
                        let boardCount = info.prospects.filter { boardRank(for: $0.id) != nil && (boardRank(for: $0.id) ?? 999) <= 50 }.count
                        if boardCount > 0 {
                            Text("\u{2022}")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Text("\(boardCount) on Board top-50")
                                .font(.caption2)
                                .foregroundStyle(Color.success)
                        }
                    }
                    .padding(.leading, 22)

                    // Summary: starred, top, need (Task 4)
                    if info.starredCount > 0 || info.topCount > 0 || info.needCount > 0 {
                        HStack(spacing: 8) {
                            if info.starredCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.accentGold)
                                    Text("\(info.starredCount) starred")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentGold)
                                }
                            }
                            if info.topCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.success)
                                    Text("\(info.topCount) top-50")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.success)
                                }
                            }
                            if info.needCount > 0 {
                                HStack(spacing: 2) {
                                    Text("NEED")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundStyle(Color.danger)
                                    Text("\(info.needCount)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.danger)
                                }
                            }
                        }
                        .padding(.leading, 22)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(expandedColleges.contains(info.college) ? "Collapse college details" : "Expand college details")

            // Expanded prospect list (Task 3)
            if expandedColleges.contains(info.college) {
                Divider()
                    .padding(.vertical, 6)
                    .overlay(Color.surfaceBorder)

                ForEach(info.prospects) { prospect in
                    proDayProspectRow(prospect)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func schoolBadges(_ info: ProDayCollegeInfo) -> some View {
        HStack(spacing: 4) {
            if info.starredCount > 0 {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentGold)
            }
            if info.topCount > 0 {
                Text("TOP")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.success)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            }
            if info.needCount > 0 {
                Text("NEED")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - Prospect Row (Task 3)

    private func proDayProspectRow(_ prospect: CollegeProspect) -> some View {
        HStack(spacing: 8) {
            // Board rank
            if let rank = boardRank(for: prospect.id) {
                Text("#\(rank)")
                    .font(.system(size: 10, weight: .heavy).monospacedDigit())
                    .foregroundStyle(rank <= 10 ? Color.accentGold : Color.textTertiary)
                    .frame(width: 28, alignment: .trailing)
            } else {
                Text("--")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 28, alignment: .trailing)
            }

            // Position badge
            Text(prospect.position.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 28, height: 18)
                .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if isStarred(prospect) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.accentGold)
                    }
                }
                HStack(spacing: 4) {
                    if let grade = prospect.effectiveOverallGrade {
                        Text(grade.displayText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(gradeColor(grade.displayText))
                    }
                    if let proj = prospect.draftProjection {
                        Text("Rd \(projectedRound(proj))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer()

            // Need/top indicators
            HStack(spacing: 4) {
                if isNeedPosition(prospect) {
                    Text("NEED")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 2))
                }
                if isTopProspect(prospect) {
                    Text("TOP")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Color.success)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 22)
    }

    // MARK: - Helpers

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        PositionGradeCalculator.gradeColorForLetter(grade)
    }

    private func projectedRound(_ pick: Int) -> String {
        switch pick {
        case 1...32:    return "1"
        case 33...64:   return "2"
        case 65...100:  return "3"
        case 101...140: return "4"
        case 141...180: return "5"
        case 181...224: return "6"
        default:        return "7"
        }
    }

    // MARK: - Actions

    private func sendScoutToProDay(scout: Scout, college: String) {
        ScoutingEngine.attendProDay(
            scout: scout,
            college: college,
            prospects: &prospects
        )
        try? modelContext.save()
        onRefresh()
    }

    private func sendBestScout(to college: String) {
        if let match = bestScoutFor(college: college) {
            sendScoutToProDay(scout: match.scout, college: college)
        } else if let first = availableScouts.first {
            sendScoutToProDay(scout: first, college: college)
        }
    }

    private func sendAllRecommended() {
        let unattended = recommendedColleges.filter { !$0.hasAttended }
        var scoutsLeft = availableScouts

        for info in unattended {
            guard !scoutsLeft.isEmpty else { break }

            // Try to find best matching scout
            let collegePros = prospects.filter { $0.college == info.college && $0.isDeclaringForDraft }
            let topPos = Dictionary(grouping: collegePros) { $0.position }.max { $0.value.count < $1.value.count }?.key

            var chosenIdx: Int?
            if let pos = topPos {
                chosenIdx = scoutsLeft.firstIndex { $0.positionSpecialization == pos }
            }
            if chosenIdx == nil {
                chosenIdx = scoutsLeft.indices.max(by: { scoutsLeft[$0].accuracy < scoutsLeft[$1].accuracy })
            }
            guard let idx = chosenIdx else { break }

            let scout = scoutsLeft[idx]
            sendScoutToProDay(scout: scout, college: info.college)
            scoutsLeft.remove(at: idx)
        }
    }
}

// MARK: - Pro Day College Info

private struct ProDayCollegeInfo {
    let college: String
    let prospects: [CollegeProspect]
    let hasAttended: Bool
    let attendedScoutName: String?
    let starredCount: Int
    let topCount: Int
    let needCount: Int
    let positionBreakdown: [(key: Position, value: Int)]
    let bestProspect: CollegeProspect?
    let relevanceScore: Int
}

// MARK: - Pro Day Result Summary (Task 9)

private struct ProDayResultSummary {
    let schoolsVisited: Int
    let prospectsEvaluated: Int
    let keyFindings: [String]
}

// MARK: - Send Scout to Pro Day Sheet (Tasks 1-6)

private struct ProDaySendScoutSheet: View {
    let college: String
    let scouts: [Scout]
    let prospects: [CollegeProspect]
    let bestMatch: (scout: Scout, reason: String)?
    let onSend: (Scout) -> Void
    let onCancel: () -> Void

    @State private var selectedScoutID: UUID?

    private var sortedScouts: [Scout] {
        scouts.sorted { $0.scoutRole.sortOrder < $1.scoutRole.sortOrder }
    }

    /// Determines if a scout is recommended for this school's prospect pool.
    private func isRecommended(_ scout: Scout) -> Bool {
        guard let spec = scout.positionSpecialization else { return false }
        return prospects.contains { $0.position == spec }
    }

    private func accuracyColor(_ value: Int) -> Color {
        if value >= 80 { return .success }
        if value >= 70 { return .accentGold }
        return .danger
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Scout list
                    List {
                        Section("Select a Scout") {
                            ForEach(sortedScouts) { scout in
                                let isFull = !scout.canAttendProDay
                                let isRec = isRecommended(scout) || bestMatch?.scout.id == scout.id

                                Button {
                                    if !isFull {
                                        selectedScoutID = scout.id
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        // Radio button / checkmark
                                        Image(systemName: selectedScoutID == scout.id ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(selectedScoutID == scout.id ? Color.accentGold : (isFull ? Color.textTertiary.opacity(0.3) : Color.textTertiary))

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(scout.fullName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(isFull ? Color.textTertiary : Color.textPrimary)

                                                Text(scout.specialtyLabel)
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(isFull ? Color.textTertiary : Color.accentBlue)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.accentBlue.opacity(isFull ? 0.05 : 0.12), in: Capsule())

                                                if isRec && !isFull {
                                                    Text("Recommended")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundStyle(Color.success)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.success.opacity(0.12), in: Capsule())
                                                }
                                            }

                                            HStack(spacing: 8) {
                                                HStack(spacing: 3) {
                                                    Text("Accuracy:")
                                                        .font(.caption2)
                                                        .foregroundStyle(Color.textTertiary)
                                                    Text("\(scout.accuracy)")
                                                        .font(.caption2.weight(.bold).monospacedDigit())
                                                        .foregroundStyle(accuracyColor(scout.accuracy))
                                                }

                                                Text("\(scout.proDaysAttended)/\(scout.maxProDays)")
                                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                                    .foregroundStyle(isFull ? Color.danger : Color.textSecondary)
                                            }
                                        }

                                        Spacer()

                                        if isFull {
                                            Text("FULL")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundStyle(Color.danger)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                }
                                .disabled(isFull)
                                .opacity(isFull ? 0.5 : 1.0)
                                .listRowBackground(Color.backgroundSecondary)
                                .accessibilityLabel("\(scout.fullName)\(selectedScoutID == scout.id ? ", selected" : "")\(isFull ? ", schedule full" : "")")
                            }
                        }

                        // Prospects at this school
                        Section("\(college) Prospects") {
                            ForEach(prospects.sorted(by: { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) })) { prospect in
                                HStack(spacing: 8) {
                                    Text(prospect.position.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.textPrimary)
                                        .frame(width: 28, height: 18)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(prospect.position.side == .offense ? Color.accentBlue.opacity(0.25) : Color.danger.opacity(0.25))
                                        )

                                    Text(prospect.fullName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(prospect.overallGradeDisplay)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(prospect.overallGradeDisplay))

                                    if let proj = prospect.draftProjection {
                                        Text("Rd \(proj)")
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)

                    // Send button
                    Button {
                        if let id = selectedScoutID, let scout = scouts.first(where: { $0.id == id }) {
                            onSend(scout)
                        }
                    } label: {
                        Text(selectedScoutID == nil ? "Select a Scout" : "Send Scout to \(college)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selectedScoutID == nil ? Color.textTertiary : Color.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedScoutID == nil ? Color.backgroundTertiary : Color.accentGold)
                            )
                    }
                    .disabled(selectedScoutID == nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("\(college) Pro Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}

// MARK: - Personal Workout Sheet (Task 10)

private struct PersonalWorkoutSheet: View {
    let prospects: [CollegeProspect]
    @Binding var selectedIDs: Set<UUID>
    let workoutsUsed: Int
    let onConduct: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localSelection: Set<UUID> = []

    private let maxWorkouts = 10

    private var remaining: Int {
        max(0, maxWorkouts - workoutsUsed)
    }

    private var sortedProspects: [CollegeProspect] {
        prospects.sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Info banner
                    HStack(spacing: 8) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(Color.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Private Workouts")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text("Reveals detailed physical and mental attributes. \(localSelection.count)/\(remaining) selected.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.backgroundSecondary)

                    List {
                        ForEach(sortedProspects) { prospect in
                            let isSelected = localSelection.contains(prospect.id)
                            let canSelect = isSelected || localSelection.count < remaining

                            Button {
                                if isSelected {
                                    localSelection.remove(prospect.id)
                                } else if canSelect {
                                    localSelection.insert(prospect.id)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiary)

                                    Text(prospect.position.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.textPrimary)
                                        .frame(width: 28, height: 18)
                                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 3))

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(prospect.fullName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(prospect.college)
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                    }

                                    Spacer()

                                    Text(prospect.overallGradeDisplay)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(prospect.overallGradeDisplay))
                                }
                            }
                            .buttonStyle(.plain)
                            .opacity(canSelect || isSelected ? 1.0 : 0.4)
                            .listRowBackground(Color.backgroundSecondary)
                            .accessibilityLabel("\(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), grade \(prospect.overallGradeDisplay)\(isSelected ? ", selected" : "")")
                            .accessibilityHint(isSelected ? "Tap to deselect" : (canSelect ? "Tap to select for interview" : "Selection limit reached"))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)

                    Button {
                        onConduct(localSelection)
                    } label: {
                        Text(localSelection.isEmpty ? "Select Prospects" : "Conduct \(localSelection.count) Workout\(localSelection.count == 1 ? "" : "s")")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(localSelection.isEmpty ? Color.textTertiary : Color.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(localSelection.isEmpty ? Color.backgroundTertiary : Color.accentBlue)
                            )
                    }
                    .disabled(localSelection.isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Personal Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Next Year's Class Preview

struct NextYearClassPreview: View {
    let career: Career
    let prospects: [ScoutingEngine.NextYearProspect]

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(Color.accentGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Early Look \u{2014} \(career.currentSeason + 1) Draft Class")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Full scouting begins next season")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)

            Section("Top Prospects") {
                ForEach(Array(prospects.enumerated()), id: \.element.id) { index, prospect in
                    nextYearProspectRow(rank: index + 1, prospect: prospect)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func nextYearProspectRow(rank: Int, prospect: ScoutingEngine.NextYearProspect) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .heavy).monospacedDigit())
                .foregroundStyle(rank <= 3 ? Color.accentGold : Color.textTertiary)
                .frame(width: 28, alignment: .trailing)

            Text(prospect.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, height: 22)
                .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.fullName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(prospect.college)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(prospect.classYear)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            Text(prospect.projectedGrade)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(projectedGradeColor(prospect.projectedGrade))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(projectedGradeColor(prospect.projectedGrade).opacity(0.12))
                )
        }
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func projectedGradeColor(_ grade: String) -> Color {
        switch grade {
        case "Top 10 Pick": return .accentGold
        case "1st Round":   return .success
        default:            return .textSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScoutingHubView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Scout.self, CollegeProspect.self], inMemory: true)
}
