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
    private var teamNeeds: Set<Position> {
        Set(DraftEngine.topTeamNeeds(roster: teamPlayers, limit: 5))
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                positionFilterChips
                analysisModePicker

                if displayed.isEmpty {
                    emptyState
                } else {
                    // Column headers
                    columnHeaders
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .background(Color.backgroundPrimary)

                    Divider().overlay(Color.surfaceBorder)

                    List {
                        ForEach(displayed) { prospect in
                            NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                ProspectRowView(
                                    prospect: prospect,
                                    positionRank: positionRanks[prospect.id],
                                    attributeTab: attributeTab,
                                    scoutsSentToCombine: scoutsSentToCombine,
                                    schemeFit: schemeFitLabel(for: prospect),
                                    isTeamNeed: teamNeeds.contains(prospect.position)
                                )
                            }
                            .listRowBackground(Color.backgroundSecondary)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
        }
        .task { loadCoachesAndRoster() }
    }

    // MARK: - Data Loading

    private func loadCoachesAndRoster() {
        guard let teamID = career.teamID else { return }
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(coachDesc)) ?? []
        let playerDesc = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamPlayers = (try? modelContext.fetch(playerDesc)) ?? []
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

            // Always-visible: OVR
            Text("OVR")
                .frame(width: 34, alignment: .center)

            // Always-visible: Proj Rd (overview only shows text, others show grade)
            if attributeTab == .overview {
                Text("PROJ")
                    .frame(width: 52, alignment: .center)
            } else {
                Text("GRD")
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
                .frame(width: 28, alignment: .center)
            Text("NEED")
                .frame(width: 28, alignment: .center)
            Text("RISK")
                .frame(width: 52, alignment: .center)
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

    private var analysisModePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProspectAttributeTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            attributeTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10))
                            Text(tab.label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(attributeTab == tab ? Color.backgroundPrimary : Color.textSecondary)
                        .background(
                            attributeTab == tab ? Color.accentGold : Color.backgroundTertiary,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    attributeTab == tab ? Color.accentGold : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .accessibilityLabel("View mode: \(tab.label)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: - Position Filter Chips

    private var positionFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            positionFilter = filter
                        }
                    } label: {
                        Text(filter.label)
                            .font(.subheadline.weight(positionFilter == filter ? .bold : .medium))
                            .foregroundStyle(positionFilter == filter ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                positionFilter == filter ? Color.accentBlue : Color.backgroundSecondary,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(positionFilter == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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

    private var isScouted: Bool { prospect.scoutedOverall != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Always-visible: Position badge
            positionBadge

            // Always-visible: Name column
            VStack(alignment: .leading, spacing: 1) {
                Text(prospect.fullName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // Compact sub-info
                HStack(spacing: 4) {
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
                .frame(width: 28, alignment: .center)

            // Need indicator
            needIndicator
                .frame(width: 28, alignment: .center)

            // Risk label
            compactRiskBadge
                .frame(width: 52, alignment: .center)
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
        case 10...12: return .success      // A range
        case 7...9:   return .accentGold   // B range
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
                Text(gradeRange.displayText)
                    .font(.system(size: gradeRange.isSingleGrade ? 14 : 11, weight: .bold))
                    .foregroundStyle(gradeColor(gradeRange.midGrade))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if let grade = prospect.scoutGrade {
                Text(grade)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.accentGold)
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
        .frame(width: 34, alignment: .center)
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
                    .foregroundStyle(Color.accentGold)
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

    @ViewBuilder
    private var schemeFitIcon: some View {
        if let fit = schemeFit {
            let isGood = fit == "Good"
            let color: Color = isGood ? .success : (fit == "Fair" ? .warning : .danger)
            let icon = isGood ? "checkmark.circle.fill" : (fit == "Fair" ? "minus.circle.fill" : "xmark.circle.fill")
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
        } else {
            Text("--")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    @ViewBuilder
    private var needIndicator: some View {
        if isTeamNeed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentGold)
        } else {
            Text("")
                .font(.system(size: 9))
        }
    }

    @ViewBuilder
    private var compactRiskBadge: some View {
        let risk = prospect.riskLevel
        if risk != .unknown {
            HStack(spacing: 2) {
                Image(systemName: risk.icon)
                    .font(.system(size: 7))
                Text(compactRiskLabel(risk))
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(risk.color)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(risk.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
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
