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

    private let maxScouts = 8

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                overviewMetrics
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if career.currentPhase == .combine {
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
        }
        .navigationTitle("Scouting")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
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
            if scoutsSentToCombine {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scouts at Combine")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.success)
                        Text("Results are in — check the Combine tab")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.success.opacity(0.3), lineWidth: 1))
            } else {
                Button {
                    sendScoutsToCombine()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "binoculars.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Scouts to NFL Combine")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(scouts.count) scout\(scouts.count == 1 ? "" : "s") will evaluate ~330 prospects")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentGold)
                    }
                    .padding(12)
                    .background(Color.accentGold.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sendScoutsToCombine() {
        var draftClass = WeekAdvancer.currentDraftClass

        // Generate combine results if not yet available (WeekAdvancer may have already done this)
        let hasCombineResults = draftClass.contains { $0.fortyTime != nil }
        if !hasCombineResults {
            ScoutingEngine.generateCombineResults(for: &draftClass)
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
                ForEach(ScoutingTab.allCases) { tab in
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
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .scouts:
            ScoutTeamView(
                scouts: scouts,
                canHire: scouts.count < maxScouts,
                onHire: { showHireScout = true },
                onFire: { fireScout($0) }
            )
        case .prospects:
            ProspectListView(career: career, prospects: prospects)
        case .bigBoard:
            BigBoardView(career: career, prospects: prospects, teamRoster: teamPlayers)
        case .combine:
            CombineResultsView(career: career, prospects: prospects)
        case .mockDraft:
            MockDraftView(career: career, prospects: prospects)
        case .proDays:
            ProDayListView(career: career, scouts: scouts, prospects: $prospects, onRefresh: loadData)
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
    case mockDraft  = "mockDraft"
    case proDays    = "proDays"
    case nextYear   = "nextYear"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scouts:    return "Scout Team"
        case .prospects: return "Prospects"
        case .bigBoard:  return "Big Board"
        case .combine:   return "Combine"
        case .mockDraft: return "Mock Draft"
        case .proDays:   return "Pro Days"
        case .nextYear:  return "Next Year"
        }
    }

    var icon: String {
        switch self {
        case .scouts:    return "binoculars"
        case .prospects: return "person.3"
        case .bigBoard:  return "list.number"
        case .combine:   return "figure.run"
        case .mockDraft: return "doc.text"
        case .proDays:   return "mappin.and.ellipse"
        case .nextYear:  return "calendar.badge.clock"
        }
    }
}

// MARK: - Hire Scout Sheet (placeholder)

private struct HireScoutSheet: View {
    let career: Career
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentGold)
                    Text("Hire Scout")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Scout hiring market coming soon.")
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

// MARK: - Pro Day List View

struct ProDayListView: View {
    let career: Career
    let scouts: [Scout]
    @Binding var prospects: [CollegeProspect]
    var onRefresh: () -> Void

    @Environment(\.modelContext) private var modelContext

    /// Colleges grouped by number of declaring prospects.
    private var collegesWithProspects: [(college: String, count: Int, hasAttended: Bool)] {
        let declaring = prospects.filter { $0.isDeclaringForDraft }
        let grouped = Dictionary(grouping: declaring) { $0.college }
        return grouped
            .map { (college: $0.key, count: $0.value.count, hasAttended: $0.value.contains { $0.proDayCompleted }) }
            .sorted { $0.count > $1.count }
    }

    private var isProDayPhase: Bool {
        career.currentPhase == .combine || career.currentPhase == .draft || career.currentPhase == .freeAgency
    }

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
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.accentGold)
                        Text("Each scout can attend up to 5 Pro Days. Send scouts to evaluate all prospects at a school.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // Scout availability
                Section("Scout Availability") {
                    ForEach(scouts) { scout in
                        HStack {
                            Text(scout.fullName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(scout.proDaysAttended)/5 Pro Days")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(scout.proDaysAttended >= 5 ? Color.danger : Color.textSecondary)
                        }
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // College list
                Section("Available Pro Days") {
                    ForEach(collegesWithProspects, id: \.college) { entry in
                        ProDayCollegeRow(
                            college: entry.college,
                            prospectCount: entry.count,
                            hasAttended: entry.hasAttended,
                            availableScouts: scouts.filter { $0.proDaysAttended < 5 },
                            onSendScout: { scout in
                                sendScoutToProDay(scout: scout, college: entry.college)
                            }
                        )
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
    }

    private func sendScoutToProDay(scout: Scout, college: String) {
        ScoutingEngine.attendProDay(
            scout: scout,
            college: college,
            prospects: &prospects
        )
        try? modelContext.save()
        onRefresh()
    }
}

// MARK: - Pro Day College Row

private struct ProDayCollegeRow: View {
    let college: String
    let prospectCount: Int
    let hasAttended: Bool
    let availableScouts: [Scout]
    let onSendScout: (Scout) -> Void

    @State private var showScoutPicker = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(college)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(prospectCount) prospect\(prospectCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if hasAttended {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    Text("Attended")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.success)
                }
            } else if availableScouts.isEmpty {
                Text("No scouts available")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Button {
                    showScoutPicker = true
                } label: {
                    Label("Send Scout", systemImage: "paperplane.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showScoutPicker) {
            NavigationStack {
                ZStack {
                    Color.backgroundPrimary.ignoresSafeArea()
                    List {
                        Section("Select Scout for \(college) Pro Day") {
                            ForEach(availableScouts) { scout in
                                Button {
                                    onSendScout(scout)
                                    showScoutPicker = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(scout.fullName)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(Color.textPrimary)
                                            Text("Accuracy: \(scout.accuracy) | Pro Days: \(scout.proDaysAttended)/5")
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
                .navigationTitle("Send Scout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showScoutPicker = false }
                    }
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
