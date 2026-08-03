import SwiftUI

struct LiveBigBoardPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @State private var sortMode: SortMode = .projection
    @State private var positionFilter: Position?
    /// The man whose scouting card is open. Presented from this panel rather
    /// than from `DraftDayView` because that view already owns two `.sheet`
    /// modifiers (pick sheet, round recap) and one view can only present one.
    @State private var cardProspect: CollegeProspect?

    enum SortMode: String, CaseIterable {
        /// The user's own board — the persisted `prospectCustomBoard` order,
        /// grouped by his marks. Deliberately first: the spring's work is the
        /// point of the room.
        case myBoard = "My Board"
        case projection = "BB Rank"
        case grade = "Grade"
        case position = "Position"

        var isMyBoard: Bool { self == .myBoard }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                SectionHeaderText(title: sortMode.isMyBoard ? "My Board" : "Big Board")
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
            Text(footnote)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    if sortMode.isMyBoard {
                        myBoardSections
                    } else {
                        ForEach(Array(sortedProspects.prefix(40)), id: \.id) { prospect in
                            prospectRow(prospect)
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
        .sheet(item: $cardProspect) { prospect in
            NavigationStack {
                // Read-only on the clock: the card's paid, rationed spring
                // actions mutate the man and re-persist the class underneath
                // the coordinator's cached ranks (finding C6).
                ProspectDetailView(
                    career: coordinator.careerRef,
                    prospect: prospect,
                    isLiveDraftCard: true
                )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { cardProspect = nil }
                        }
                    }
            }
        }
    }

    private var footnote: String {
        sortMode.isMyBoard
            ? "Your board, in the order you left it — MY #N is the slot the Big Board prints. Tap a name for his card; the phone calls about moving up for him."
            : "#N is the media's consensus slot. Gold bands are your scouts; grey bands are the media's projection — scout them to narrow it. Tap a name for his card; the phone calls about moving up."
    }

    // MARK: - My Board (persisted order, grouped by the user's marks)

    /// The user's board with the drafted men already gone: `availableProspects`
    /// in `prospectCustomBoard` order, split into the mark tiers.
    @ViewBuilder
    private var myBoardSections: some View {
        let pool: [CollegeProspect] = {
            if let pos = positionFilter {
                return coordinator.availableProspects.filter { $0.position == pos }
            }
            return coordinator.availableProspects
        }()
        let groups = UserDraftBoard.groupedByMark(pool)
        if groups.isEmpty {
            Text("Nobody left on your board.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        } else {
            ForEach(groups, id: \.tier) { group in
                Section {
                    // Only the tiers the user actually filled deserve the whole
                    // column: an unmarked class is 285 men and the board still
                    // has to scroll to the bottom of it.
                    ForEach(Array(group.prospects.prefix(group.tier == .none ? 40 : 60)), id: \.id) { prospect in
                        prospectRow(prospect)
                    }
                } header: {
                    tierHeader(tier: group.tier, count: group.prospects.count)
                }
            }
        }
    }

    private func tierHeader(tier: ProspectMarkTier, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tier.icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tier == .none ? Color.textTertiary : tier.color)
            Text(tier == .none ? "UNMARKED" : tier.label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tier == .none ? Color.textTertiary : tier.color)
            Text("\(count)")
                .font(.system(size: 9).monospaced())
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, DSSpacing.xxs)
        .background(Color.backgroundSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier == .none ? "Unmarked" : tier.label) tier, \(count) prospects")
    }

    private var sortedProspects: [CollegeProspect] {
        let pool: [CollegeProspect] = {
            if let pos = positionFilter {
                return coordinator.availableProspects.filter { $0.position == pos }
            }
            return coordinator.availableProspects
        }()

        switch sortMode {
        case .myBoard:
            return UserDraftBoard.sorted(pool)
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

    /// A row is two targets, because it has two jobs on the night: reading the
    /// man (his card — notes, medical, the interview your staff took) and
    /// calling about him. Tapping the name used to open the trade-up phone,
    /// which meant the one screen with the whole board on it had no way at all
    /// to look a prospect up.
    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        HStack(spacing: 0) {
            Button {
                cardProspect = prospect
            } label: {
                prospectRowContent(prospect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the scouting card")

            Button {
                coordinator.openTradeUpBoard(for: prospect)
            } label: {
                Image(systemName: "phone.arrow.up.right.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.draftStealGold.opacity(0.85))
                    .frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Call about moving up for \(prospect.lastName)")
        }
        .contextMenu {
            Button {
                cardProspect = prospect
            } label: {
                Label("Scouting Card", systemImage: "person.text.rectangle")
            }
            Button {
                coordinator.openTradeUpBoard(for: prospect)
            } label: {
                Label("Call About Moving Up", systemImage: "phone.arrow.up.right.fill")
            }
        }
    }

    /// One board row in a 288 pt panel. Fixed columns are kept to 136 pt total
    /// so the name gets the residual ~120 pt: at 42 pt every name truncated and
    /// a dozen of them collapsed to the same "Harlan…" string, which made the
    /// board unreadable as a board. Same "F. Lastname" convention the War
    /// Room's Best Available panel uses.
    private func prospectRowContent(_ prospect: CollegeProspect) -> some View {
        let need = coordinator.teamNeedScores[prospect.position] ?? 0
        let mark = DraftIntel.mark(for: prospect)
        // On My Board the number is HIS board slot, not the media's — the whole
        // point of the mode is that the room finally prints the user's order.
        let myRank = coordinator.userBoardRanks[prospect.id]
        return HStack(spacing: DSSpacing.xxs) {
            if sortMode.isMyBoard {
                Text(myRank.map { "\($0)" } ?? "—")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(myRank == nil ? Color.textTertiary : Color.accentGold)
                    .frame(width: 34, alignment: .leading)
                    .accessibilityLabel(myRank.map { "Your board slot \($0)" } ?? "Not on your board")
            } else if let rank = coordinator.publicBoardRanks[prospect.id] {
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
            // and nothing shouty on the ones he does not. Inside a tier group
            // the icon would be the header repeated on every row, so My Board
            // spends the width on the name instead.
            if let mark, !sortMode.isMyBoard {
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
