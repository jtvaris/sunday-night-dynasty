import SwiftUI

struct LiveBigBoardPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @State private var sortMode: SortMode = .projection
    @State private var positionFilter: Position?

    enum SortMode: String, CaseIterable {
        case projection = "BB Rank"
        case grade = "Grade"
        case position = "Position"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
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
            // The board no longer prints a number, so it has to say whose read
            // it is showing: gold = your scouts' band, grey = the media's
            // projected round and nothing more. The rank column is the media's
            // consensus slot, which is why it is NOT gold — gold in this panel
            // means "this is your building's opinion".
            Text("#N is the media's consensus slot. Gold bands are your scouts; grey bands are the media's projection — scout them to narrow it.")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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
        case .grade:
            // Sorting by `trueOverall` used to hand the user a perfectly
            // ordered board for free — the sort itself was a bigger leak than
            // the number it printed. Ranks by the fogged band instead, ties
            // broken by the public consensus rank.
            return pool.sorted {
                let lhs = ProspectFog.rank($0)
                let rhs = ProspectFog.rank($1)
                if lhs != rhs { return lhs > rhs }
                return (coordinator.publicBoardRanks[$0.id] ?? 999) <
                       (coordinator.publicBoardRanks[$1.id] ?? 999)
            }
        case .position:
            return pool.sorted { $0.position.rawValue < $1.position.rawValue }
        }
    }

    /// Wave 4: the board is the natural place to start a move-up call — the
    /// user is looking at the man he wants when the thought occurs. Tapping a
    /// row opens the call sheet pre-targeted at that prospect, which filters
    /// the quotes to the slots where he is plausibly still on the board.
    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        Button {
            coordinator.openTradeUpBoard(for: prospect)
        } label: {
            prospectRowContent(prospect)
        }
        .buttonStyle(.plain)
    }

    /// One board row in a 288 pt panel. Fixed columns are kept to 136 pt total
    /// so the name gets the residual ~120 pt: at 42 pt every name truncated and
    /// a dozen of them collapsed to the same "Harlan…" string, which made the
    /// board unreadable as a board. Same "F. Lastname" convention the War
    /// Room's Best Available panel uses.
    private func prospectRowContent(_ prospect: CollegeProspect) -> some View {
        let need = coordinator.teamNeedScores[prospect.position] ?? 0
        let mark = DraftIntel.mark(for: prospect)
        return HStack(spacing: DSSpacing.xxs) {
            if let rank = coordinator.publicBoardRanks[prospect.id] {
                Text("#\(rank)")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 34, alignment: .leading)
            } else {
                Text("—")
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 34, alignment: .leading)
            }
            Text(prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(need >= 0.7 ? Color.draftStealGold : Color.textSecondary)
                .frame(width: 26, alignment: .leading)
            // The user's own mark, carried from the scouting board to the one
            // screen where it decides something: a star on the men he wants,
            // and nothing shouty on the ones he does not.
            if let mark {
                Image(systemName: mark.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(mark.color)
                    .accessibilityLabel(mark.label)
            }
            Text("\(prospect.firstName.prefix(1)). \(prospect.lastName)")
                .font(.caption)
                .foregroundStyle(mark == .avoid ? Color.textTertiary : Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // College production tier (3-char chip)
            ProductionTierChip(tier: prospect.collegeProductionTier, width: 30, showsBackground: false, fontSize: 9)
            // The band replaces BOTH the raw OVR and the 5-star widget that
            // wrapped onto two lines on every row: fewer stars = wider band.
            ProspectGradeBand(prospect: prospect, width: 46)
        }
        .padding(.vertical, 3)
        .padding(.leading, DSSpacing.xs)
        .padding(.trailing, DSSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary.opacity(need >= 0.5 ? 0.55 : 0.35))
        )
        // Need is an accent bar in the gutter, not a gold wash over the whole
        // row — the wash dropped the rank number's contrast to 3.42:1.
        .overlay(
            Rectangle()
                .fill(need >= 0.7 ? Color.draftStealGold : Color.draftStealGold.opacity(0.55))
                .frame(width: need >= 0.5 ? 3 : 0)
            , alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
        // An "avoid" is not hidden — the user still has to see who is left on
        // the board — it just stops competing for his eye with the rest.
        .opacity(mark == .avoid ? 0.5 : 1.0)
        .accessibilityElement(children: .combine)
    }
}
