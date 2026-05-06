import SwiftUI

struct LiveBigBoardPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @State private var sortMode: SortMode = .projection
    @State private var positionFilter: Position?

    enum SortMode: String, CaseIterable {
        case projection = "BB Rank"
        case ovr = "OVR"
        case position = "Position"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                SectionHeaderText(title: "Big Board")
                Spacer()
                Menu {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) { sortMode = mode }
                    }
                } label: {
                    Text(sortMode.rawValue)
                        .font(.caption)
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 4)
                        .background(Color.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(sortedProspects.prefix(40)), id: \.id) { prospect in
                        prospectRow(prospect)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
    }

    private var sortedProspects: [CollegeProspect] {
        let pool: [CollegeProspect] = {
            if let pos = positionFilter {
                return coordinator.availableProspects.filter { $0.position == pos }
            }
            return coordinator.availableProspects
        }()

        switch sortMode {
        case .projection:
            return pool.sorted {
                (coordinator.publicBoardRanks[$0.id] ?? 999) <
                (coordinator.publicBoardRanks[$1.id] ?? 999)
            }
        case .ovr:
            return pool.sorted { $0.trueOverall > $1.trueOverall }
        case .position:
            return pool.sorted { $0.position.rawValue < $1.position.rawValue }
        }
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        HStack(spacing: DSSpacing.xs) {
            if let rank = coordinator.publicBoardRanks[prospect.id] {
                Text("#\(rank)")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 40, alignment: .leading)
            } else {
                Text("—")
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 40, alignment: .leading)
            }
            Text(prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 30)
            Text("\(prospect.firstName) \(prospect.lastName)")
                .font(.caption)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(stars(for: prospect))
                .font(.caption2)
                .foregroundStyle(Color.draftStealGold)
            Text("\(prospect.trueOverall)")
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(Color.forRating(prospect.trueOverall))
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(needHighlight(for: prospect))
        )
        .overlay(
            Rectangle()
                .fill(Color.draftStealGold)
                .frame(width: (coordinator.teamNeedScores[prospect.position] ?? 0) >= 0.7 ? 3 : 0)
            , alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
    }

    private func stars(for prospect: CollegeProspect) -> String {
        let n = DraftIntel.scoutConfidence(for: prospect)
        return String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n)
    }

    private func needHighlight(for prospect: CollegeProspect) -> Color {
        let need = coordinator.teamNeedScores[prospect.position] ?? 0
        if need >= 0.7  { return Color.draftStealGold.opacity(0.30) }
        if need >= 0.5  { return Color.draftStealGold.opacity(0.15) }
        return Color.backgroundTertiary.opacity(0.4)
    }
}
