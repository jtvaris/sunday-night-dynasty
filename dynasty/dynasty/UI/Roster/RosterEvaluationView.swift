import SwiftUI
import SwiftData

// MARK: - Position Group Definition

private struct EvalPositionGroup: Identifiable {
    let id: String
    let label: String
    let positions: [Position]

    static let allGroups: [EvalPositionGroup] = [
        EvalPositionGroup(id: "QB",  label: "QB",  positions: [.QB]),
        EvalPositionGroup(id: "RB",  label: "RB",  positions: [.RB, .FB]),
        EvalPositionGroup(id: "WR",  label: "WR",  positions: [.WR]),
        EvalPositionGroup(id: "TE",  label: "TE",  positions: [.TE]),
        EvalPositionGroup(id: "OL",  label: "OL",  positions: [.LT, .LG, .C, .RG, .RT]),
        EvalPositionGroup(id: "DL",  label: "DL",  positions: [.DE, .DT]),
        EvalPositionGroup(id: "LB",  label: "LB",  positions: [.OLB, .MLB]),
        EvalPositionGroup(id: "DB",  label: "DB",  positions: [.CB, .FS, .SS]),
        EvalPositionGroup(id: "ST",  label: "ST",  positions: [.K, .P]),
    ]
}

// MARK: - Key Decision

private struct KeyDecision: Identifiable {
    enum DecisionType {
        case expiringContract, overpaid, underpaid, agingVeteran
    }
    let id: UUID
    let player: Player
    let type: DecisionType
    let recommendation: String
}

// MARK: - RosterEvaluationView

struct RosterEvaluationView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var team: Team?
    @State private var players: [Player] = []

    // MARK: - Table Sorting (#250)
    @State private var sortColumn: SortColumn = .group
    @State private var sortAscending: Bool = true

    private enum SortColumn: String {
        case group, avgOVR, starter, depth, avgAge, capAllocation
    }

    // MARK: - Cap Detail Popover (#253)
    @State private var showCapDetailPopover = false

    // MARK: - Roster Notes & Priorities (#245)
    @AppStorage("rosterNotes") private var rosterNotesJSON: String = "{}"
    @AppStorage("rosterPriorities") private var rosterPrioritiesJSON: String = "{}"
    @AppStorage("rosterOwnAssessments") private var rosterOwnAssessmentsJSON: String = "{}"
    @AppStorage("rosterEvaluationConfirmed") private var rosterEvaluationConfirmed: Bool = false
    @State private var editingGroup: EvalPositionGroup?
    @State private var editingNote: String = ""
    @State private var editingPriority: String = "none"
    @State private var editingOwnAssessment: String = "none"

    // #251: Expandable key decision rows
    @State private var expandedDecisions: Set<UUID> = []

    // Own assessment options (#266)
    private static let ownAssessmentOptions = [
        "none", "Solid", "Starter needed", "Depth needed", "Upgrade needed", "Aging", "Priority"
    ]

    private var rosterNotes: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterNotesJSON.utf8))) ?? [:]
    }
    private var rosterPriorities: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterPrioritiesJSON.utf8))) ?? [:]
    }
    private var rosterOwnAssessments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterOwnAssessmentsJSON.utf8))) ?? [:]
    }

    private func saveNote(groupID: String, note: String, priority: String, ownAssessment: String = "none") {
        var notes = rosterNotes
        var priorities = rosterPriorities
        var ownAssessments = rosterOwnAssessments
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.removeValue(forKey: groupID)
        } else {
            notes[groupID] = note
        }
        if priority == "none" {
            priorities.removeValue(forKey: groupID)
        } else {
            priorities[groupID] = priority
        }
        if ownAssessment == "none" {
            ownAssessments.removeValue(forKey: groupID)
        } else {
            ownAssessments[groupID] = ownAssessment
        }
        if let data = try? JSONEncoder().encode(notes) { rosterNotesJSON = String(data: data, encoding: .utf8) ?? "{}" }
        if let data = try? JSONEncoder().encode(priorities) { rosterPrioritiesJSON = String(data: data, encoding: .utf8) ?? "{}" }
        if let data = try? JSONEncoder().encode(ownAssessments) { rosterOwnAssessmentsJSON = String(data: data, encoding: .utf8) ?? "{}" }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if team != nil {
                    ScrollView {
                        VStack(spacing: 24) {
                            ownerDemandsSection
                            positionGradesSection
                            keyDecisionsSection
                            strengthsWeaknessesSection
                            capOutlookSection
                            confirmEvaluationButton
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProgressView()
                        .tint(Color.accentGold)
                        .padding(.top, 80)
                }
            }
        }
        .navigationTitle("Roster Evaluation")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .sheet(item: $editingGroup) { group in
            rosterNoteSheet(group: group)
        }
    }

    // MARK: - Confirm Evaluation Button

    private var confirmEvaluationButton: some View {
        Button {
            rosterEvaluationConfirmed = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: rosterEvaluationConfirmed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3)
                Text(rosterEvaluationConfirmed ? "Evaluation Confirmed" : "Confirm Evaluation Complete")
                    .font(.headline)
            }
            .foregroundStyle(rosterEvaluationConfirmed ? Color.success : Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                rosterEvaluationConfirmed ? Color.success.opacity(0.15) : Color.accentGold,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(rosterEvaluationConfirmed ? Color.success.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(rosterEvaluationConfirmed)
    }

    // MARK: - Section 0: Owner Demands (#248)

    @ViewBuilder
    private var ownerDemandsSection: some View {
        if !career.ownerDemands.isEmpty, let owner = team?.owner {
            sectionCard(title: "Owner Demands", icon: "person.crop.circle.badge.exclamationmark") {
                VStack(alignment: .leading, spacing: 16) {
                    // Owner quote header
                    HStack(alignment: .top, spacing: 14) {
                        // Owner avatar
                        Image(systemName: "person.crop.square.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentGold)
                            .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(owner.name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text(ownerQuote)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Divider().overlay(Color.surfaceBorder)

                    // Demand rows
                    ForEach(Array(career.ownerDemands.enumerated()), id: \.offset) { index, demand in
                        let isAddressed = career.ownerDemandsAddressed.contains(demand)
                        let severity = demandSeverity(owner: owner)

                        HStack(spacing: 12) {
                            // Status icon
                            Image(systemName: isAddressed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(isAddressed ? Color.success : severity.color)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(demand)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isAddressed ? Color.textTertiary : Color.textPrimary)
                                    .strikethrough(isAddressed)

                                if !isAddressed {
                                    HStack(spacing: 6) {
                                        Text(severity.label)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(severity.color)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(severity.color.opacity(0.15), in: Capsule())
                                            .overlay(Capsule().strokeBorder(severity.color.opacity(0.4), lineWidth: 1))

                                        let penalty = owner.patience <= 3 ? 15 : 10
                                        Text("Ignoring costs -\(penalty) satisfaction (current: \(owner.satisfaction)%)")
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)

                        if index < career.ownerDemands.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var ownerQuote: String {
        guard let owner = team?.owner else { return "" }
        let demandCount = career.ownerDemands.count
        if owner.prefersWinNow {
            return demandCount > 1
                ? "We need to make moves now. I expect results this season."
                : "I want to see a key addition before the season starts."
        } else {
            return demandCount > 1
                ? "Let's build smart. I have a few areas I'd like us to address."
                : "There's one area I'd really like us to focus on this offseason."
        }
    }

    private func demandSeverity(owner: Owner) -> (label: String, color: Color) {
        if owner.patience <= 3 {
            return ("Must address", .danger)
        } else {
            return ("Would like", .accentGold)
        }
    }

    // MARK: - Section 1: Position Group Grades

    /// Pre-computed data for a single position group row, used for sorting (#250).
    private struct GroupRowData: Identifiable {
        let id: String
        let group: EvalPositionGroup
        let avgOvr: Int
        let starterGrade: String
        let depthGrade: String
        let starterOVR: Int
        let depthOVR: Int
        let avgAge: Int
        let capAllocation: Int
        let needs: [NeedInfo]
    }

    private var sortedGroupRows: [GroupRowData] {
        let rows: [GroupRowData] = EvalPositionGroup.allGroups.map { group in
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            let grades = PositionGradeCalculator.calculatePositionGrades(
                players: groupPlayers,
                positions: group.positions
            )
            let avgOvr = groupPlayers.isEmpty ? 0 : groupPlayers.map(\.overall).reduce(0, +) / groupPlayers.count
            let needs = assessNeeds(group: group, players: groupPlayers, grades: grades)
            let avgAge = groupPlayers.isEmpty ? 0 : groupPlayers.map(\.age).reduce(0, +) / groupPlayers.count
            let capAllocation = groupPlayers.reduce(0) { $0 + $1.annualSalary }
            return GroupRowData(
                id: group.id, group: group, avgOvr: avgOvr,
                starterGrade: grades.starterGrade, depthGrade: grades.depthGrade,
                starterOVR: grades.starterOVR, depthOVR: grades.depthOVR,
                avgAge: avgAge, capAllocation: capAllocation, needs: needs
            )
        }

        switch sortColumn {
        case .group:
            return sortAscending ? rows : rows.reversed()
        case .avgOVR:
            return rows.sorted { sortAscending ? $0.avgOvr < $1.avgOvr : $0.avgOvr > $1.avgOvr }
        case .starter:
            return rows.sorted { sortAscending ? $0.starterOVR < $1.starterOVR : $0.starterOVR > $1.starterOVR }
        case .depth:
            return rows.sorted { sortAscending ? $0.depthOVR < $1.depthOVR : $0.depthOVR > $1.depthOVR }
        case .avgAge:
            return rows.sorted { sortAscending ? $0.avgAge < $1.avgAge : $0.avgAge > $1.avgAge }
        case .capAllocation:
            return rows.sorted { sortAscending ? $0.capAllocation < $1.capAllocation : $0.capAllocation > $1.capAllocation }
        }
    }

    private func sortableHeader(_ title: String, column: SortColumn, width: CGFloat, alignment: Alignment = .center) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sortColumn == column ? Color.accentGold : Color.textTertiary)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Color.accentGold)
                }
            }
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    // #249: Priorities progress
    private var prioritiesSetCount: Int {
        rosterPriorities.values.filter { $0 != "none" }.count
    }

    private var positionGradesSection: some View {
        sectionCard(title: "Position Group Grades", icon: "chart.bar.doc.horizontal") {
            VStack(spacing: 0) {
                // #249: Priorities intro text and progress
                VStack(alignment: .leading, spacing: 6) {
                    Text("Setting priorities affects draft board rankings and scouting focus")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("Priorities set: \(prioritiesSetCount)/\(EvalPositionGroup.allGroups.count) position groups")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(prioritiesSetCount == EvalPositionGroup.allGroups.count ? Color.success : Color.accentGold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().overlay(Color.surfaceBorder)

                // Column headers — sortable (#250)
                HStack {
                    sortableHeader("Group", column: .group, width: 44, alignment: .leading)
                    sortableHeader("Avg OVR", column: .avgOVR, width: 64)
                    sortableHeader("Strt / Depth", column: .starter, width: 80)
                    if isIPad {
                        sortableHeader("Avg Age", column: .avgAge, width: 60)
                        sortableHeader("Cap $", column: .capAllocation, width: 72)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Staff")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                        Text("Own")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider().overlay(Color.surfaceBorder)

                ForEach(Array(sortedGroupRows.enumerated()), id: \.element.id) { index, rowData in
                    positionGroupRow(rowData: rowData)

                    if index < sortedGroupRows.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private func positionGroupRow(rowData: GroupRowData) -> some View {
        let group = rowData.group

        return Button {
            editingNote = rosterNotes[group.id] ?? ""
            editingPriority = rosterPriorities[group.id] ?? "none"
            editingOwnAssessment = rosterOwnAssessments[group.id] ?? "none"
            editingGroup = group
        } label: {
            HStack(alignment: .center) {
                // Group label
                Text(group.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, alignment: .leading)

                // Avg overall
                Text(rowData.avgOvr == 0 ? "\u{2014}" : "\(rowData.avgOvr)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rowData.avgOvr == 0 ? Color.textTertiary : Color.forRating(rowData.avgOvr))
                    .frame(width: 64, alignment: .center)

                // Dual grade: Starter / Depth
                HStack(spacing: 2) {
                    Text("S:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                    Text(rowData.starterGrade)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(rowData.starterGrade))
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Text("D:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                    Text(rowData.depthGrade)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(rowData.depthGrade))
                }
                .frame(width: 80)

                // iPad extra columns (#250)
                if isIPad {
                    Text(rowData.avgAge == 0 ? "\u{2014}" : "\(rowData.avgAge)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 60, alignment: .center)

                    Text(formatMillions(rowData.capAllocation))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 72, alignment: .center)
                }

                Spacer()

                // #266: Dual assessment badges — Staff (smaller, left) + Own (right, larger)
                HStack(spacing: 4) {
                    // Staff assessment (auto-generated, smaller)
                    if rowData.needs.isEmpty {
                        needBadge(label: "Solid", color: .success, small: true)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(rowData.needs.prefix(2), id: \.label) { need in
                                needBadge(label: need.label, color: need.color, small: true)
                            }
                        }
                    }

                    // Own assessment (user's, slightly larger)
                    if let ownAssessment = rosterOwnAssessments[group.id] {
                        needBadge(label: ownAssessment, color: ownAssessmentColor(ownAssessment), small: false)
                    }
                }

                // Priority dot + note indicator (#245)
                HStack(spacing: 4) {
                    if let priority = rosterPriorities[group.id], priority != "none" {
                        Circle()
                            .fill(priorityColor(priority))
                            .frame(width: 8, height: 8)
                    }
                    if rosterNotes[group.id] != nil {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(rowData.needs.contains(where: { $0.label == "Starter needed" }) ? Color.danger.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Needs Assessment

    private struct NeedInfo: Equatable {
        let label: String
        let color: Color
    }

    private func assessNeeds(
        group: EvalPositionGroup,
        players: [Player],
        grades: (starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int)
    ) -> [NeedInfo] {
        var needs: [NeedInfo] = []

        let starterBad = ["D", "F"].contains(grades.starterGrade)
        let depthBad = ["D", "F"].contains(grades.depthGrade)
        let starterWeak = ["C-", "D", "F"].contains(grades.starterGrade)
        let starterGood = grades.starterGrade.hasPrefix("A") || grades.starterGrade.hasPrefix("B")
        let depthGood = grades.depthGrade.hasPrefix("A") || grades.depthGrade.hasPrefix("B")

        // Starter needed
        if starterBad {
            needs.append(NeedInfo(label: "Starter needed", color: .danger))
        }

        // Depth needed
        if depthBad {
            needs.append(NeedInfo(label: "Depth needed", color: .warning))
        }

        // Upgrade recommended: weak starters + expiring contracts
        if starterWeak && !starterBad {
            let hasExpiring = players.contains { $0.contractYearsRemaining <= 1 }
            if hasExpiring {
                needs.append(NeedInfo(label: "Upgrade recommended", color: .accentGold))
            }
        }

        // Aging — plan ahead
        let n = PositionGradeCalculator.starterCount(for: group.positions)
        let sorted = players.sorted { $0.overall > $1.overall }
        let starters = Array(sorted.prefix(n))
        if !starters.isEmpty {
            let avgAge = starters.map(\.age).reduce(0, +) / starters.count
            let peakUpper = group.positions.map { $0.peakAgeRange.upperBound }.reduce(0, +) / max(group.positions.count, 1)
            if avgAge > peakUpper {
                needs.append(NeedInfo(label: "Aging — plan ahead", color: .accentBlue))
            }
        }

        // If both starter and depth are good, return empty (will show "Solid")
        if starterGood && depthGood && needs.isEmpty {
            return []
        }

        return needs
    }

    private func needBadge(label: String, color: Color, small: Bool = false) -> some View {
        Text(label)
            .font(small ? .system(size: 8, weight: .bold) : .caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, small ? 4 : 6)
            .padding(.vertical, small ? 1 : 2)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func ownAssessmentColor(_ assessment: String) -> Color {
        switch assessment {
        case "Solid":           return .success
        case "Starter needed":  return .danger
        case "Depth needed":    return .warning
        case "Upgrade needed":  return .accentGold
        case "Aging":           return .accentBlue
        case "Priority":        return .danger
        default:                return .textTertiary
        }
    }

    // MARK: - Section 2: Key Decisions

    private var keyDecisionsSection: some View {
        sectionCard(title: "Key Decisions", icon: "checklist.unchecked") {
            let decisions = buildKeyDecisions()

            if decisions.isEmpty {
                emptyStateRow("No pressing decisions at this time.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(decisions.enumerated()), id: \.element.id) { index, decision in
                        VStack(spacing: 0) {
                            // Tappable header row
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedDecisions.contains(decision.id) {
                                        expandedDecisions.remove(decision.id)
                                    } else {
                                        expandedDecisions.insert(decision.id)
                                    }
                                }
                            } label: {
                                keyDecisionRow(decision)
                            }
                            .buttonStyle(.plain)

                            // #251: Expandable financial details
                            if expandedDecisions.contains(decision.id) {
                                keyDecisionFinancialDetails(decision)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        if index < decisions.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    private func keyDecisionRow(_ decision: KeyDecision) -> some View {
        HStack(spacing: 12) {
            // Position badge
            Text(decision.player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 4)
                .background(positionSideColor(decision.player.position), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(decision.player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    decisionTypeBadge(decision.type)
                }
                Text(decision.recommendation)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(decision.player.overall) OVR")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.forRating(decision.player.overall))
                Text(formatMillions(decision.player.annualSalary))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }

            // Expand chevron
            Image(systemName: expandedDecisions.contains(decision.id) ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - #251: Financial Details for Key Decisions

    private func keyDecisionFinancialDetails(_ decision: KeyDecision) -> some View {
        let player = decision.player
        let marketValue = ContractEngine.estimateMarketValue(player: player)
        let salary = player.annualSalary
        let remainingValue = salary * max(player.contractYearsRemaining, 1)
        let deadMoney = Int(Double(remainingValue) * 0.4)
        let capSavings = salary - deadMoney
        let draftRound = estimatedDraftRound(ovr: player.overall, position: player.position)

        return VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Color.surfaceBorder.opacity(0.3)).padding(.horizontal, 8)

            // Common: market value + replacement
            financialDetailLine(
                icon: "chart.line.uptrend.xyaxis",
                text: "Market value: \(formatMillions(marketValue))/yr",
                color: .accentBlue
            )
            financialDetailLine(
                icon: "arrow.triangle.2.circlepath",
                text: "Replacement via FA ~\(formatMillions(marketValue)), via draft ~Rd\(draftRound)",
                color: .textSecondary
            )

            // Type-specific financial breakdown
            switch decision.type {
            case .expiringContract:
                financialDetailLine(
                    icon: "signature",
                    text: "Re-sign est: \(formatMillions(marketValue))/yr (market value)",
                    color: .warning
                )
                financialDetailLine(
                    icon: "figure.walk.departure",
                    text: "Let walk: $0 cost, need replacement",
                    color: .textSecondary
                )

            case .overpaid:
                financialDetailLine(
                    icon: "scissors",
                    text: "Cut: saves \(formatMillions(max(capSavings, 0))) cap (\(formatMillions(deadMoney)) dead money)",
                    color: .danger
                )
                let restructureSavings = Int(Double(salary) * 0.5)
                financialDetailLine(
                    icon: "doc.text",
                    text: "Restructure: convert \(formatMillions(restructureSavings)) to bonus, save \(formatMillions(restructureSavings)) this year",
                    color: .accentGold
                )

            case .underpaid:
                financialDetailLine(
                    icon: "signature",
                    text: "Extension est: \(formatMillions(marketValue))/yr to lock up",
                    color: .success
                )
                financialDetailLine(
                    icon: "exclamationmark.triangle",
                    text: "Risk: holdout or walks in \(player.contractYearsRemaining) yr\(player.contractYearsRemaining == 1 ? "" : "s")",
                    color: .warning
                )

            case .agingVeteran:
                financialDetailLine(
                    icon: "scissors",
                    text: "Cut: saves \(formatMillions(max(capSavings, 0))) cap (\(formatMillions(deadMoney)) dead money, net \(formatMillions(max(capSavings, 0))))",
                    color: .danger
                )
                financialDetailLine(
                    icon: "arrow.down.right",
                    text: "Declining value — replacement cost only \(formatMillions(marketValue))/yr",
                    color: .textSecondary
                )
            }

            // Link to player detail
            NavigationLink(destination: PlayerDetailView(player: player)) {
                HStack(spacing: 4) {
                    Text("View Player Details")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                }
                .foregroundStyle(Color.accentGold)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 4)
        .background(Color.backgroundSecondary.opacity(0.5))
    }

    private func financialDetailLine(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Estimate what draft round a player of this OVR/position would be picked.
    private func estimatedDraftRound(ovr: Int, position: Position) -> Int {
        // Premium positions get drafted higher
        let posBonus: Int = {
            switch position {
            case .QB: return 10
            case .DE, .CB, .LT: return 5
            case .WR, .OLB: return 3
            default: return 0
            }
        }()
        let effectiveOVR = ovr + posBonus
        if effectiveOVR >= 85 { return 1 }
        if effectiveOVR >= 78 { return 2 }
        if effectiveOVR >= 72 { return 3 }
        if effectiveOVR >= 66 { return 4 }
        if effectiveOVR >= 60 { return 5 }
        return 6
    }

    private func decisionTypeBadge(_ type: KeyDecision.DecisionType) -> some View {
        let (label, color): (String, Color) = {
            switch type {
            case .expiringContract: return ("EXPIRING", .warning)
            case .overpaid:         return ("OVERPAID", .danger)
            case .underpaid:        return ("UNDERPAID", .success)
            case .agingVeteran:     return ("AGING", .textTertiary)
            }
        }()

        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Section 3: Strengths & Weaknesses

    private var strengthsWeaknessesSection: some View {
        sectionCard(title: "Roster Strengths & Weaknesses", icon: "chart.xyaxis.line") {
            VStack(spacing: 16) {
                // Top 5
                groupBlock(title: "Top 5 Players", icon: "star.fill", iconColor: .accentGold) {
                    VStack(spacing: 0) {
                        ForEach(Array(top5Players.enumerated()), id: \.element.id) { index, player in
                            playerSnapshotRow(player: player, rank: index + 1)
                            if index < top5Players.count - 1 {
                                Divider().overlay(Color.surfaceBorder.opacity(0.4)).padding(.horizontal, 8)
                            }
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)

                // Bottom 5 starters
                groupBlock(title: "Bottom 5 Starters", icon: "arrow.down.circle.fill", iconColor: .danger) {
                    VStack(spacing: 0) {
                        ForEach(Array(bottom5Starters.enumerated()), id: \.element.id) { index, player in
                            playerSnapshotRow(player: player, rank: nil)
                            if index < bottom5Starters.count - 1 {
                                Divider().overlay(Color.surfaceBorder.opacity(0.4)).padding(.horizontal, 8)
                            }
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)

                // Biggest need callout
                if let needGroup = biggestNeedGroup {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Biggest Need: \(needGroup.label)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("The \(needGroup.label) group is the weakest on the roster. Prioritize this position in free agency or the draft.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.warning.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    private func groupBlock<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            content()
        }
    }

    private func playerSnapshotRow(player: Player, rank: Int?) -> some View {
        HStack(spacing: 10) {
            if let rank {
                Text("#\(rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 26, alignment: .trailing)
            } else {
                Spacer().frame(width: 26)
            }

            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 3)
                .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: 4))

            Text(player.fullName)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer()

            Text("\(player.overall)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Section 4: Cap Outlook

    private var capOutlookSection: some View {
        sectionCard(title: "Cap Outlook", icon: "dollarsign.circle.fill") {
            guard let team else {
                return AnyView(emptyStateRow("No cap data available."))
            }

            let expiringCap = expiringContractCapRelief
            let projectedUsage = max(0, team.currentCapUsage - expiringCap)
            let projectedSpace  = team.salaryCap - projectedUsage

            return AnyView(
                VStack(spacing: 16) {
                    // Four stat columns
                    HStack(spacing: 0) {
                        capStatColumn(label: "Total Cap",    value: formatMillions(team.salaryCap),      color: .accentGold)
                        capStatColumn(label: "Used",         value: formatMillions(team.currentCapUsage), color: capUsageColor(team))
                        capStatColumn(label: "Available",    value: formatMillions(team.availableCap),    color: team.availableCap >= 0 ? .success : .danger)
                        capStatColumn(label: "Dead Cap Est.", value: formatMillions(estimatedDeadCap),    color: estimatedDeadCap > 5_000 ? .danger : .textSecondary)
                    }

                    Divider().overlay(Color.surfaceBorder)

                    // Projected cap after expiring contracts
                    projectedCapRow(
                        label: "Expiring Contracts Relief",
                        value: "+\(formatMillions(expiringCap))",
                        color: .success
                    )
                    projectedCapRow(
                        label: "Projected Cap After Expirations",
                        value: formatMillions(projectedUsage),
                        color: .textPrimary
                    )
                    projectedCapRow(
                        label: "Projected FA Budget",
                        value: formatMillions(projectedSpace),
                        color: projectedSpace > 20_000 ? .success : (projectedSpace > 5_000 ? .accentGold : .danger)
                    )

                    Divider().overlay(Color.surfaceBorder)

                    // Cap bar (#253: enhanced with color thresholds + tap popover)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Cap Usage")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f%%", capPct(team) * 100))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(capThresholdColor(team))
                        }
                        Button {
                            showCapDetailPopover = true
                        } label: {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.backgroundTertiary)
                                        .frame(height: 10)
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(capBarGradientThreshold(team))
                                        .frame(width: geo.size.width * min(capPct(team), 1.0), height: 10)
                                }
                            }
                            .frame(height: 10)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showCapDetailPopover) {
                            capDetailPopover(team: team)
                        }

                        // League average context line
                        Text("League avg: ~78%")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }

                    // #253: Cap warning cards
                    if capPct(team) > 0.95 {
                        capWarningCard(
                            icon: "exclamationmark.octagon.fill",
                            title: "CRITICAL: Must cut or restructure before signings",
                            color: .danger
                        )
                    } else if capPct(team) > 0.90 {
                        capWarningCard(
                            icon: "exclamationmark.triangle.fill",
                            title: "Cap tight \u{2014} review restructure opportunities",
                            color: .warning
                        )
                    }

                    // MARK: #252: Cap Scenarios
                    Divider().overlay(Color.surfaceBorder)

                    capScenariosBlock(team: team)
                }
            )
        }
    }

    private func capStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func projectedCapRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: - Section Card Shell

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Gold header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.accentGold.opacity(0.08))

            Divider().overlay(Color.surfaceBorder)

            content()
                .padding(.vertical, 8)
        }
        .cardBackground()
    }

    private func emptyStateRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.textTertiary)
            .padding(20)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Roster Notes Sheet (#245)

    private func rosterNoteSheet(group: EvalPositionGroup) -> some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // #266: Your Assessment picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Assessment")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(Self.ownAssessmentOptions, id: \.self) { option in
                                    let isSelected = editingOwnAssessment == option
                                    let displayLabel = option == "none" ? "None" : option
                                    let badgeColor = option == "none" ? Color.textTertiary : ownAssessmentColor(option)

                                    Button {
                                        editingOwnAssessment = option
                                    } label: {
                                        Text(displayLabel)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isSelected ? Color.backgroundPrimary : badgeColor)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(
                                                isSelected ? badgeColor : badgeColor.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 8)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(badgeColor.opacity(isSelected ? 1 : 0.4), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Priority picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Priority")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Picker("Priority", selection: $editingPriority) {
                                Text("None").tag("none")
                                Text("Low").tag("low")
                                Text("Medium").tag("medium")
                                Text("High").tag("high")
                            }
                            .pickerStyle(.segmented)
                        }

                        // Notes field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            TextEditor(text: $editingNote)
                                .scrollContentBackground(.hidden)
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                                .frame(minHeight: 120)
                                .padding(10)
                                .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    Group {
                                        if editingNote.isEmpty {
                                            Text("Add your evaluation notes...")
                                                .font(.body)
                                                .foregroundStyle(Color.textTertiary)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 18)
                                                .allowsHitTesting(false)
                                        }
                                    },
                                    alignment: .topLeading
                                )
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("\(group.label) Evaluation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingGroup = nil }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote(groupID: group.id, note: editingNote, priority: editingPriority, ownAssessment: editingOwnAssessment)
                        editingGroup = nil
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "high":   return .danger
        case "medium": return .warning
        case "low":    return .accentBlue
        default:       return .clear
        }
    }

    // MARK: - Computed Roster Properties

    private var top5Players: [Player] {
        players.sorted { $0.overall > $1.overall }.prefix(5).map { $0 }
    }

    /// Starters: the best-rated player at each individual starting position.
    private var startersByPosition: [Player] {
        let positionOrder: [Position] = [
            .QB, .RB, .WR, .WR, .TE,
            .LT, .LG, .C, .RG, .RT,
            .DE, .DT, .DT, .DE,
            .OLB, .MLB, .MLB, .OLB,
            .CB, .CB, .FS, .SS,
            .K, .P
        ]
        var result: [Player] = []
        var used = Set<UUID>()

        for pos in positionOrder {
            if let starter = players
                .filter({ $0.position == pos && !used.contains($0.id) })
                .sorted(by: { $0.overall > $1.overall })
                .first {
                result.append(starter)
                used.insert(starter.id)
            }
        }
        return result
    }

    private var bottom5Starters: [Player] {
        startersByPosition
            .sorted { $0.overall < $1.overall }
            .prefix(5)
            .map { $0 }
    }

    private var biggestNeedGroup: EvalPositionGroup? {
        EvalPositionGroup.allGroups.min(by: { a, b in
            averageOverall(players.filter { a.positions.contains($0.position) })
            < averageOverall(players.filter { b.positions.contains($0.position) })
        })
    }

    // MARK: - Key Decision Builder

    private func buildKeyDecisions() -> [KeyDecision] {
        var decisions: [KeyDecision] = []

        for player in players {
            let marketValue = ContractEngine.estimateMarketValue(player: player)
            let salary = player.annualSalary
            let isPastPeak = player.age > player.position.peakAgeRange.upperBound

            // Expiring contracts
            if player.contractYearsRemaining <= 1 {
                let rec = expiringRecommendation(player: player, marketValue: marketValue)
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .expiringContract,
                    recommendation: rec
                ))
            }
            // Overpaid: salary is more than 30% above market value
            else if salary > Int(Double(marketValue) * 1.3) {
                let excess = formatMillions(salary - marketValue)
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .overpaid,
                    recommendation: "Paying \(excess) above market value. Consider restructuring or cutting."
                ))
            }
            // Underpaid: market value more than 40% above salary — trade/holdout risk
            else if marketValue > Int(Double(salary) * 1.4) && player.contractYearsRemaining <= 2 {
                let upside = formatMillions(marketValue - salary)
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .underpaid,
                    recommendation: "Worth \(upside) more than current deal. Extension risk — act before he walks."
                ))
            }
            // Aging veteran: past peak, still on a meaningful salary
            else if isPastPeak && salary > 3_000 && player.overall < 75 {
                let yearsOver = player.age - player.position.peakAgeRange.upperBound
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .agingVeteran,
                    recommendation: "\(yearsOver) year\(yearsOver == 1 ? "" : "s") past peak age. Declining production — evaluate before committing long-term."
                ))
            }
        }

        // Sort: expiring first, then overpaid, underpaid, aging
        let order: [KeyDecision.DecisionType: Int] = [
            .expiringContract: 0, .overpaid: 1, .underpaid: 2, .agingVeteran: 3
        ]
        return decisions
            .sorted { (order[$0.type] ?? 99) < (order[$1.type] ?? 99) }
            .prefix(12)
            .map { $0 }
    }

    private func expiringRecommendation(player: Player, marketValue: Int) -> String {
        let isPastPeak = player.age > player.position.peakAgeRange.upperBound
        if player.overall >= 80 && !isPastPeak {
            return "Elite player still in his prime. Prioritize extension before free agency."
        } else if player.overall >= 70 && !isPastPeak {
            return "Solid contributor with value. Re-sign at or slightly above market."
        } else if isPastPeak || player.overall < 65 {
            return "Declining output relative to cost. Consider letting him walk."
        } else {
            return "Franchise tag is an option to buy time before committing long-term."
        }
    }

    // MARK: - Cap Helpers

    private var expiringContractCapRelief: Int {
        players
            .filter { $0.contractYearsRemaining <= 1 }
            .reduce(0) { $0 + $1.annualSalary }
    }

    private var estimatedDeadCap: Int {
        // Approximate: players past peak and below 70 OVR who could be cut
        players
            .filter { $0.age > $0.position.peakAgeRange.upperBound && $0.overall < 70 && $0.contractYearsRemaining > 1 }
            .reduce(0) { $0 + $1.annualSalary / 2 }   // rough dead-cap estimate
    }

    private func capPct(_ team: Team) -> Double {
        guard team.salaryCap > 0 else { return 0 }
        return Double(team.currentCapUsage) / Double(team.salaryCap)
    }

    private func capUsageColor(_ team: Team) -> Color {
        let pct = capPct(team)
        if pct > 1.0 { return .danger }
        if pct > 0.9 { return .warning }
        return .textSecondary
    }

    /// #253: Color thresholds: <80% green, 80-90% yellow, 90-95% orange, >95% red
    private func capThresholdColor(_ team: Team) -> Color {
        let pct = capPct(team)
        if pct > 0.95 { return .danger }
        if pct > 0.90 { return .orange }
        if pct > 0.80 { return .warning }
        return .success
    }

    private func capBarGradient(_ team: Team) -> LinearGradient {
        let pct = capPct(team)
        let color: Color = pct > 1.0 ? .danger : (pct > 0.9 ? .warning : .accentGold)
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }

    /// #253: Cap bar gradient using threshold colors
    private func capBarGradientThreshold(_ team: Team) -> LinearGradient {
        let color = capThresholdColor(team)
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }

    /// #253: Warning card for cap section
    private func capWarningCard(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    /// #253: Popover explaining cap consequences
    private func capDetailPopover(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cap Usage Breakdown")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                capDetailRow(range: "Under 80%", color: .success, desc: "Healthy cap space. Room for signings and extensions.")
                capDetailRow(range: "80% \u{2013} 90%", color: .warning, desc: "Moderate usage. Be selective with new deals.")
                capDetailRow(range: "90% \u{2013} 95%", color: .orange, desc: "Tight cap. Restructures may be needed for signings.")
                capDetailRow(range: "Over 95%", color: .danger, desc: "Critical. Must cut or restructure to make any moves.")
            }

            Divider()

            HStack {
                Text("Your usage:")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(String(format: "%.1f%%", capPct(team) * 100))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(capThresholdColor(team))
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Color.backgroundPrimary)
    }

    private func capDetailRow(range: String, color: Color, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(range)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - #252: Cap Scenarios

    private func capScenariosBlock(team: Team) -> some View {
        let expiringPlayers = players
            .filter { $0.contractYearsRemaining <= 1 }
            .sorted { $0.overall > $1.overall }
        let expiringCount = expiringPlayers.count
        let totalExpiringCap = expiringPlayers.reduce(0) { $0 + $1.annualSalary }

        // Re-sign cost estimates based on market value
        let top3Expiring = Array(expiringPlayers.prefix(3))
        let top3ReSignCost = top3Expiring.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1) }
        let allReSignCost = expiringPlayers.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1) }

        let currentUsage = team.currentCapUsage
        let cap = team.salaryCap

        // Scenario A: Release all expiring
        let scenAUsage = currentUsage - totalExpiringCap
        let scenASpace = cap - scenAUsage
        let scenAPct = cap > 0 ? Double(scenAUsage) / Double(cap) : 0

        // Scenario B: Re-sign top 3, release rest
        let otherExpiringCap = expiringPlayers.dropFirst(3).reduce(0) { $0 + $1.annualSalary }
        let scenBUsage = currentUsage - totalExpiringCap + top3ReSignCost
        let scenBSpace = cap - scenBUsage
        let scenBPct = cap > 0 ? Double(scenBUsage) / Double(cap) : 0

        // Scenario C: Re-sign all
        let scenCUsage = currentUsage - totalExpiringCap + allReSignCost
        let scenCSpace = cap - scenCUsage
        let scenCPct = cap > 0 ? Double(scenCUsage) / Double(cap) : 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
                Text("Cap Scenarios")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            capScenarioCard(
                label: "A",
                title: "Release All Expiring",
                capPct: scenAPct,
                available: scenASpace,
                tradeoff: "Max flexibility, lose \(expiringCount) player\(expiringCount == 1 ? "" : "s")"
            )

            capScenarioCard(
                label: "B",
                title: "Re-sign Top 3",
                capPct: scenBPct,
                available: scenBSpace,
                tradeoff: "Keep core\(top3Expiring.isEmpty ? "" : " (\(top3Expiring.map(\.lastName).joined(separator: ", ")))"), release \(max(expiringCount - 3, 0))"
            )

            capScenarioCard(
                label: "C",
                title: "Re-sign All",
                capPct: scenCPct,
                available: scenCSpace,
                tradeoff: scenCSpace < 5_000 ? "Retain all, very tight cap" : "Retain all, moderate flexibility"
            )
        }
    }

    private func capScenarioCard(
        label: String,
        title: String,
        capPct: Double,
        available: Int,
        tradeoff: String
    ) -> some View {
        let pctClamped = min(max(capPct, 0), 1.5)
        let pctColor: Color = pctClamped > 1.0 ? .danger : (pctClamped > 0.9 ? .warning : .success)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(width: 22, height: 22)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 5))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text(String(format: "%.0f%%", pctClamped * 100))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(pctColor)
            }

            // Mini cap bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pctColor)
                        .frame(width: geo.size.width * min(pctClamped, 1.0), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Available: \(formatMillions(available))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(available >= 0 ? Color.success : Color.danger)

                Spacer()

                Text(tradeoff)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.surfaceBorder.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Grade Helpers (delegates to PositionGradeCalculator)

    private func averageOverall(_ group: [Player]) -> Int {
        guard !group.isEmpty else { return 0 }
        return group.reduce(0) { $0 + $1.overall } / group.count
    }

    // MARK: - Formatting Helpers

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDesc)) ?? []
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Sam Greer", role: .gm, capMode: .simple)
    NavigationStack {
        RosterEvaluationView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Player.self, Owner.self], inMemory: true)
}
