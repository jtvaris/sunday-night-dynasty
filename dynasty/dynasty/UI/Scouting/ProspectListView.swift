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

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                positionFilterChips
                attributeTabPicker

                if displayed.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(displayed) { prospect in
                            NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                ProspectRowView(
                                    prospect: prospect,
                                    positionRank: positionRanks[prospect.id],
                                    attributeTab: attributeTab,
                                    scoutsSentToCombine: scoutsSentToCombine,
                                    schemeFit: schemeFitLabel(for: prospect),
                                    starterComparison: starterComparison(for: prospect)
                                )
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
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

    /// Compute starter comparison text for a prospect.
    private func starterComparison(for prospect: CollegeProspect) -> (text: String, isUpgrade: Bool)? {
        guard let prospectOVR = prospect.scoutedOverall else { return nil }
        let starters = teamPlayers
            .filter { $0.position == prospect.position }
            .sorted { $0.overall > $1.overall }
        guard let starter = starters.first else {
            return ("No \(prospect.position.rawValue) on roster", true)
        }
        let diff = prospectOVR - starter.overall
        if diff > 0 {
            return ("vs \(starter.fullName): +\(diff) OVR upgrade", true)
        } else if diff == 0 {
            return ("vs \(starter.fullName): lateral move", false)
        } else {
            return ("vs \(starter.fullName): depth add (\(diff) OVR)", false)
        }
    }

    // MARK: - Attribute Tab Picker

    private var attributeTabPicker: some View {
        Picker("Attributes", selection: $attributeTab) {
            ForEach(ProspectAttributeTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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

// MARK: - Prospect Row View

struct ProspectRowView: View {
    let prospect: CollegeProspect
    var positionRank: Int? = nil
    var attributeTab: ProspectAttributeTab = .overview
    var scoutsSentToCombine: Bool = false
    var schemeFit: String? = nil
    var starterComparison: (text: String, isUpgrade: Bool)? = nil

    private var isScouted: Bool { prospect.scoutedOverall != nil }

    var body: some View {
        HStack(spacing: 12) {
            positionBadge

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prospect.fullName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)

                    Text("Age \(prospect.age)")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)

                    if prospect.combineInvite {
                        Text("COMBINE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentGold, in: Capsule())
                    }

                    riskBadge

                    // Media mention indicator
                    if let mention = prospect.combineMediaMention, !mention.isEmpty {
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(mediaColor(for: prospect))
                            .help(mention.replacingOccurrences(of: "\\[\\w+\\s?\\w*\\]\\s*", with: "", options: .regularExpression))
                    }

                    // Interview completed indicator
                    if prospect.interviewCompleted {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentBlue)
                            .help("Interviewed")
                    }
                }

                // Combine stats badges
                if scoutsSentToCombine && prospect.combineInvite {
                    combineStatsBadges
                }

                attributeRow

                // Scheme fit + starter comparison badges
                if schemeFit != nil || starterComparison != nil {
                    HStack(spacing: 6) {
                        if let fit = schemeFit {
                            schemeFitBadge(fit)
                        }
                        if let comp = starterComparison {
                            starterComparisonBadge(comp)
                        }
                    }
                }
            }

            Spacer()

            if attributeTab == .overview {
                projectedRoundBadge
            }

            VStack(alignment: .trailing, spacing: 4) {
                overallBadge
                HStack(spacing: 4) {
                    if let rank = positionRank {
                        Text("#\(rank) \(prospect.position.rawValue)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(rank <= 3 ? Color.accentGold : Color.textTertiary)
                    }
                    gradeLabel
                    gradeChangeIndicator
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Attribute Row (Tab-dependent)

    @ViewBuilder
    private var attributeRow: some View {
        switch attributeTab {
        case .overview:
            overviewRow
        case .physical:
            physicalRow
        case .mental:
            mentalRow
        case .position:
            positionAttributeRow
        }
    }

    private var overviewRow: some View {
        HStack(spacing: 6) {
            Text(prospect.college)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text("\u{00B7}")
                .foregroundStyle(Color.textTertiary)
                .font(.caption)
            Text(heightWeightLabel)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            Text("\u{00B7}")
                .foregroundStyle(Color.textTertiary)
                .font(.caption)
            interestBadge
            Text("\u{00B7}")
                .foregroundStyle(Color.textTertiary)
                .font(.caption)
            reportCountLabel
        }
    }

    private var physicalRow: some View {
        HStack(spacing: 8) {
            if let forty = prospect.fortyTime {
                ProspectStatPill(label: "40yd", value: String(format: "%.2fs", forty))
            }
            if let bench = prospect.benchPress {
                ProspectStatPill(label: "Bench", value: "\(bench)")
            }
            if let vert = prospect.verticalJump {
                ProspectStatPill(label: "Vert", value: String(format: "%.1f\"", vert))
            }
            if let broad = prospect.broadJump {
                ProspectStatPill(label: "Broad", value: "\(broad)\"")
            }
            if let cone = prospect.coneDrill {
                ProspectStatPill(label: "3-Cone", value: String(format: "%.2fs", cone))
            }
            if let shuttle = prospect.shuttleTime {
                ProspectStatPill(label: "Shuttle", value: String(format: "%.2fs", shuttle))
            }
            if prospect.fortyTime == nil && prospect.benchPress == nil {
                Text("No combine data")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private var mentalRow: some View {
        HStack(spacing: 8) {
            if isScouted {
                ProspectStatPill(label: "AWR", value: "\(prospect.trueMental.awareness)")
                ProspectStatPill(label: "DEC", value: "\(prospect.trueMental.decisionMaking)")
                ProspectStatPill(label: "WRK", value: "\(prospect.trueMental.workEthic)")
                ProspectStatPill(label: "CLT", value: "\(prospect.trueMental.clutch)")
                ProspectStatPill(label: "COA", value: "\(prospect.trueMental.coachability)")
                ProspectStatPill(label: "LDR", value: "\(prospect.trueMental.leadership)")
            } else {
                Text("Scout to reveal mental attributes")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var positionAttributeRow: some View {
        if isScouted {
            HStack(spacing: 8) {
                switch prospect.truePositionAttributes {
                case .quarterback(let attrs):
                    ProspectStatPill(label: "ARM", value: "\(attrs.armStrength)")
                    ProspectStatPill(label: "SAcc", value: "\(attrs.accuracyShort)")
                    ProspectStatPill(label: "MAcc", value: "\(attrs.accuracyMid)")
                    ProspectStatPill(label: "DAcc", value: "\(attrs.accuracyDeep)")
                    ProspectStatPill(label: "PKT", value: "\(attrs.pocketPresence)")
                    ProspectStatPill(label: "SCR", value: "\(attrs.scrambling)")
                case .wideReceiver(let attrs):
                    ProspectStatPill(label: "RTE", value: "\(attrs.routeRunning)")
                    ProspectStatPill(label: "CTH", value: "\(attrs.catching)")
                    ProspectStatPill(label: "RLS", value: "\(attrs.release)")
                    ProspectStatPill(label: "SPC", value: "\(attrs.spectacularCatch)")
                case .runningBack(let attrs):
                    ProspectStatPill(label: "VIS", value: "\(attrs.vision)")
                    ProspectStatPill(label: "ELU", value: "\(attrs.elusiveness)")
                    ProspectStatPill(label: "BTK", value: "\(attrs.breakTackle)")
                    ProspectStatPill(label: "RCV", value: "\(attrs.receiving)")
                case .tightEnd(let attrs):
                    ProspectStatPill(label: "BLK", value: "\(attrs.blocking)")
                    ProspectStatPill(label: "CTH", value: "\(attrs.catching)")
                    ProspectStatPill(label: "RTE", value: "\(attrs.routeRunning)")
                    ProspectStatPill(label: "SPD", value: "\(attrs.speed)")
                case .offensiveLine(let attrs):
                    ProspectStatPill(label: "RBK", value: "\(attrs.runBlock)")
                    ProspectStatPill(label: "PBK", value: "\(attrs.passBlock)")
                    ProspectStatPill(label: "PUL", value: "\(attrs.pull)")
                    ProspectStatPill(label: "ANC", value: "\(attrs.anchor)")
                case .defensiveLine(let attrs):
                    ProspectStatPill(label: "PRU", value: "\(attrs.passRush)")
                    ProspectStatPill(label: "BSH", value: "\(attrs.blockShedding)")
                    ProspectStatPill(label: "PWR", value: "\(attrs.powerMoves)")
                    ProspectStatPill(label: "FIN", value: "\(attrs.finesseMoves)")
                case .linebacker(let attrs):
                    ProspectStatPill(label: "TAK", value: "\(attrs.tackling)")
                    ProspectStatPill(label: "ZCV", value: "\(attrs.zoneCoverage)")
                    ProspectStatPill(label: "MCV", value: "\(attrs.manCoverage)")
                    ProspectStatPill(label: "BLZ", value: "\(attrs.blitzing)")
                case .defensiveBack(let attrs):
                    ProspectStatPill(label: "MCV", value: "\(attrs.manCoverage)")
                    ProspectStatPill(label: "ZCV", value: "\(attrs.zoneCoverage)")
                    ProspectStatPill(label: "PRS", value: "\(attrs.press)")
                    ProspectStatPill(label: "BSK", value: "\(attrs.ballSkills)")
                case .kicking(let attrs):
                    ProspectStatPill(label: "PWR", value: "\(attrs.kickPower)")
                    ProspectStatPill(label: "ACC", value: "\(attrs.kickAccuracy)")
                }
            }
        } else {
            Text("Scout to reveal position attributes")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Combine Stats Badges

    @ViewBuilder
    private var combineStatsBadges: some View {
        let parts = combineStatsParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " | "))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var combineStatsParts: [String] {
        var parts: [String] = []
        if let forty = prospect.fortyTime {
            parts.append(String(format: "%.2fs", forty))
        }
        if let bench = prospect.benchPress {
            parts.append("\(bench) bench")
        }
        if let vert = prospect.verticalJump {
            parts.append(String(format: "%.0f\" vert", vert))
        }
        return parts
    }

    // MARK: - Grade Change Indicator

    @ViewBuilder
    private var gradeChangeIndicator: some View {
        if let preGrade = prospect.preCombineGrade,
           let currentGrade = prospect.scoutGrade,
           preGrade != currentGrade {
            let improved = Self.gradeRank(currentGrade) > Self.gradeRank(preGrade)
            Text(improved ? "\u{2191}" : "\u{2193}")
                .font(.caption.weight(.bold))
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

    // MARK: - Subviews

    private var positionBadge: some View {
        Text(prospect.position.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 28)
            .background(positionColor, in: RoundedRectangle(cornerRadius: 4))
    }

    private var overallBadge: some View {
        Group {
            if let overall = prospect.scoutedOverall {
                Text("\(overall)")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(overall))
            } else {
                Text("?")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: 32, alignment: .trailing)
    }

    private var projectedRoundBadge: some View {
        let text = Self.projectedRoundText(for: prospect.draftProjection)
        let color: Color = {
            switch prospect.draftProjection {
            case .some(1...5):   return .accentGold
            case .some(6...10):  return .accentGold.opacity(0.8)
            case .some(11...32): return .accentBlue
            case .some(33...64): return .accentBlue.opacity(0.7)
            case .some(65...100): return .textSecondary
            case .some(101...150): return .textTertiary
            case .some(151...):  return .textTertiary
            default:             return .textTertiary
            }
        }()
        return Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .frame(width: 72, alignment: .trailing)
    }

    static func projectedRoundText(for pick: Int?) -> String {
        guard let pick = pick else { return "Undrafted" }
        switch pick {
        case 1...5:     return "Top 5"
        case 6...10:    return "Top 10"
        case 11...32:   return "1st Round"
        case 33...64:   return "2nd Round"
        case 65...100:  return "3rd Round"
        case 101...150: return "Mid Rounds"
        default:        return "Late Rounds"
        }
    }

    private var gradeLabel: some View {
        Group {
            if let grade = prospect.scoutGrade {
                Text(grade)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
            } else {
                Text("Unscouted")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Interest & Reports (#224)

    private var interestBadge: some View {
        let level = prospect.interestLevel
        let color: Color
        switch level {
        case "Hot":  color = .danger
        case "Warm": color = .warning
        case "Cold": color = .accentBlue
        default:     color = .textTertiary
        }
        return Text(level == "Unknown" ? "No buzz" : level)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private var reportCountLabel: some View {
        let count = prospect.scoutingReports.count
        return Text(count > 0 ? "\(count) report\(count == 1 ? "" : "s")" : "Unscouted")
            .font(.caption2)
            .foregroundStyle(count > 0 ? Color.textSecondary : Color.textTertiary)
    }

    // MARK: - Risk Badge

    @ViewBuilder
    private var riskBadge: some View {
        let risk = prospect.riskLevel
        if risk != .unknown {
            HStack(spacing: 2) {
                Image(systemName: risk.icon)
                    .font(.system(size: 7))
                Text(risk.rawValue)
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(risk.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(risk.color.opacity(0.15), in: Capsule())
        }
    }

    // MARK: - Scheme Fit Badge

    private func schemeFitBadge(_ fit: String) -> some View {
        let isGood = fit == "Good"
        let color: Color = isGood ? .success : (fit == "Fair" ? .warning : .danger)
        let icon = isGood ? "checkmark.circle.fill" : (fit == "Fair" ? "minus.circle.fill" : "xmark.circle.fill")
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(isGood ? "Scheme Fit" : (fit == "Fair" ? "Scheme OK" : "Scheme Mismatch"))
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Starter Comparison Badge

    private func starterComparisonBadge(_ comp: (text: String, isUpgrade: Bool)) -> some View {
        let color: Color = comp.isUpgrade ? .success : .textSecondary
        return Text(comp.text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var heightWeightLabel: String {
        let feet = prospect.height / 12
        let inches = prospect.height % 12
        return "\(feet)'\(inches)\"  \(prospect.weight) lbs"
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
