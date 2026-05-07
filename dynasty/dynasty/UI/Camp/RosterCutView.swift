import SwiftUI
import SwiftData

// MARK: - Roster Cut View
//
// 3-stage cut flow: 90 → 75 → 65 → 53. Tabs filter by position group;
// each row shows OVR / age / camp grade / cap savings. Multi-select via
// tap. Bottom action bar performs the cut and persists `RosterCut` rows.

struct RosterCutView: View {

    let career: Career
    let roster: [Player]

    @Environment(\.modelContext) private var modelContext

    @State private var stage: CutDay = .cut90To75
    @State private var positionGroup: CutPositionGroup = .all
    @State private var selectedIDs: Set<UUID> = []
    /// Player IDs that the user has flagged as practice-squad-eligible.
    @State private var practiceSquadIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            list
            footer
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Roster Cuts")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stageTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(roster.count - selectedIDs.count) / \(targetCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(remainingTint)
                    .monospacedDigit()
            }
            Text("Select players to release. \(remaining) more cuts needed.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(DSSpacing.md)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(CutPositionGroup.allCases) { group in
                    Button {
                        positionGroup = group
                    } label: {
                        Text(group.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .fill(positionGroup == group ? Color.accentGold : Color.backgroundTertiary)
                            )
                            .foregroundStyle(positionGroup == group ? Color.backgroundPrimary : Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.xs) {
                ForEach(filteredRoster, id: \.id) { player in
                    row(for: player)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
    }

    private func row(for player: Player) -> some View {
        let isSelected = selectedIDs.contains(player.id)
        let isPS = practiceSquadIDs.contains(player.id)
        return HStack(spacing: DSSpacing.sm) {
            // Avatar placeholder
            Circle()
                .fill(Color.backgroundTertiary)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(initials(for: player))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.position.rawValue)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.backgroundTertiary)
                        )
                        .foregroundStyle(Color.textSecondary)
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text("OVR \(player.overall)")
                        .font(.caption2)
                        .foregroundStyle(Color.forRating(player.overall))
                    Text("Age \(player.age)")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    if let grade = player.campGrade {
                        Text("Camp \(grade.displayLabel)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(capSavingsLabel(for: player))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.success)
                    .monospacedDigit()
                Button {
                    togglePracticeSquad(player)
                } label: {
                    Text(isPS ? "PS ✓" : "PS")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isPS ? Color.accentGold : Color.backgroundTertiary)
                        )
                        .foregroundStyle(isPS ? Color.backgroundPrimary : Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(isSelected ? Color.danger.opacity(0.18) : Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(isSelected ? Color.danger : Color.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection(player) }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DSSpacing.xs) {
            Divider().background(Color.surfaceBorder)
            HStack {
                Text("\(selectedIDs.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button(action: performCuts) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(canCut ? Color.danger : Color.backgroundTertiary)
                        )
                        .foregroundStyle(canCut ? Color.textPrimary : Color.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canCut)
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundSecondary)
    }

    // MARK: - Helpers

    private var stageTitle: String {
        switch stage {
        case .cut90To75: return "Cut Day 1: 90 → 75"
        case .cut75To65: return "Cut Day 2: 75 → 65"
        case .cut65To53: return "Final Cut: 65 → 53"
        }
    }

    private var targetCount: Int {
        switch stage {
        case .cut90To75: return 75
        case .cut75To65: return 65
        case .cut65To53: return 53
        }
    }

    private var remaining: Int {
        max(0, roster.count - selectedIDs.count - targetCount)
    }

    private var remainingTint: Color {
        remaining == 0 ? Color.success : Color.warning
    }

    private var canCut: Bool {
        !selectedIDs.isEmpty
    }

    private var actionTitle: String {
        selectedIDs.isEmpty ? "Cut players" : "Cut \(selectedIDs.count) player\(selectedIDs.count == 1 ? "" : "s")"
    }

    private var filteredRoster: [Player] {
        roster.filter { positionGroup.includes($0.position) }
    }

    private func toggleSelection(_ player: Player) {
        if selectedIDs.contains(player.id) {
            selectedIDs.remove(player.id)
        } else {
            selectedIDs.insert(player.id)
        }
    }

    private func togglePracticeSquad(_ player: Player) {
        if practiceSquadIDs.contains(player.id) {
            practiceSquadIDs.remove(player.id)
        } else {
            practiceSquadIDs.insert(player.id)
        }
    }

    private func initials(for player: Player) -> String {
        let f = player.firstName.first.map(String.init) ?? ""
        let l = player.lastName.first.map(String.init) ?? ""
        return "\(f)\(l)"
    }

    private func capSavingsLabel(for player: Player) -> String {
        // Quick cap-savings preview: 80% of remaining base salary recovered
        // (rough placeholder — RosterCutEvaluator will compute the canonical value).
        let savings = max(0, Int(Double(player.annualSalary) * 0.8))
        return "+$\(savings / 1_000)M"
    }

    private func performCuts() {
        guard let teamID = career.teamID, !selectedIDs.isEmpty else { return }
        let now = Date()
        for id in selectedIDs {
            guard let player = roster.first(where: { $0.id == id }) else { continue }
            let savings = max(0, Int(Double(player.annualSalary) * 0.8))
            let dead = max(0, player.annualSalary - savings)
            let cut = RosterCut(
                playerID: player.id,
                teamID: teamID,
                seasonYear: career.currentSeason,
                cutDayRaw: stage.rawValue,
                capSavings: savings,
                deadCap: dead,
                practiceSquadEligible: practiceSquadIDs.contains(player.id),
                occurredAt: now
            )
            modelContext.insert(cut)
        }
        try? modelContext.save()
        selectedIDs.removeAll()
        practiceSquadIDs.removeAll()
        advanceStageIfNeeded()
    }

    private func advanceStageIfNeeded() {
        switch stage {
        case .cut90To75: stage = .cut75To65
        case .cut75To65: stage = .cut65To53
        case .cut65To53: break
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
