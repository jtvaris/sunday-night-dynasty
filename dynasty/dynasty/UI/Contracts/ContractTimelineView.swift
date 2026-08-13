import SwiftUI
import SwiftData

// MARK: - ContractTimelineView

/// Visual multi-year contract timeline for cap planning.
/// Displays every rostered player as a horizontal bar spanning their remaining contract years.
struct ContractTimelineView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var players: [Player] = []
    @State private var team: Team?
    @State private var filter: ContractFilter = .all

    // MARK: - The Open League Year

    /// **The league year column 0 depicts.**
    ///
    /// `Career.currentSeason` is one behind it from proDays through rosterCuts:
    /// `FreeAgencyEngine.executeNewLeagueYear` opens the new league year — the
    /// contract clocks this screen draws bars from are decremented there — while
    /// the counter is only bumped at the rosterCuts→regularSeason boundary. So
    /// the bars, and the forward rows priced against them, belong to
    /// `currentSeason + 1` for that whole stretch.
    ///
    /// Delegated to `DealTargetYear.openSeason` rather than re-tested here, so
    /// this screen, `CapOverviewView` and the negotiation gate cannot end up
    /// with three readings of which side of March it is.
    private var openYear: Int {
        DealTargetYear.openSeason(
            currentSeason: career.currentSeason,
            hasRolledOver: career.lastRolloverSeason >= career.currentSeason
        )
    }

    // MARK: - Season Columns

    /// The five seasons shown in the timeline (open league year + next 4).
    private var seasons: [Int] {
        (0..<5).map { openYear + $0 }
    }

    // MARK: - Filtered Players

    private var filteredPlayers: [Player] {
        let base = players.sorted { $0.annualSalary > $1.annualSalary }
        switch filter {
        case .all:
            return base
        case .expiring:
            return base.filter { $0.contractYearsRemaining == 1 }
        case .longTerm:
            return base.filter { $0.contractYearsRemaining >= 3 }
        }
    }

    // MARK: - Per-Season Cap Totals

    /// Total committed salary for a given season offset (0 = current season).
    ///
    /// #127: franchise-tagged men are held out of the salary sum from offset 1
    /// onward and added back from the forward ledger. Their `annualSalary` is
    /// still the EXPIRING deal until the March rollover settles the tag onto it,
    /// so counting the row would price a future year off a contract that ends
    /// before it — and counting nothing (which is what
    /// `contractYearsRemaining > offset` did for a tagged man at 1 year) left the
    /// club's biggest new commitment invisible on the one screen built to plan
    /// future years.
    ///
    /// **Offset 0 keeps him**, matching `CapOverviewView.committedCap`, whose
    /// year-0 bar is the live ledger: the club is paying his expiring deal
    /// through the season just played, and dropping it made the current-year
    /// column understate used cap by his whole salary. The forward row cannot
    /// double-count him there — it binds the year after the open one, and
    /// `forwardCoverage` is empty for a season before the binding year.
    ///
    /// #186: the forward read is the WHOLE roster, not the tagged men, and a
    /// covered man is priced by his row INSTEAD of his salary. A deferred
    /// extension (`ContractEngine.applyNegotiatedDeal`) writes the new clock at
    /// signing, leaves `annualSalary` at the old rate until the binding
    /// rollover, and never sets `isFranchiseTagged` — so a tags-only read
    /// skipped the new money entirely while still charging the superseded
    /// salary, and this screen quoted a future year the cap gate
    /// (`CapOverviewView.committedCap`, `DealTargetYear.space`) priced
    /// differently. Same rows, same netting, one future per season.
    ///
    /// The row lookup is keyed off ``openYear``, not `career.currentSeason`, for
    /// the same reason the column headers are: offset 0 is the ledger as it
    /// stands now, so during the offseason phases that follow the rollover a
    /// raw-counter key asked for the year BEFORE the one the column draws, and
    /// a deferred extension's money landed one column late.
    private func committedSalary(forOffset offset: Int) -> Int {
        // Player-scoped, not a blind sum of the table: an orphaned row (tagged
        // or extended, then released) must not keep charging a club for a man it
        // no longer employs.
        let coverage = CommittedCapLedger.forwardCoverage(
            playerIDs: players.map(\.id),
            careerID: career.id,
            season: openYear + offset
        )
        let contracts = players
            .filter {
                coverage[$0.id] == nil
                    && $0.contractYearsRemaining > offset
                    && (offset == 0 || !$0.isFranchiseTagged)
            }
            .reduce(0) { $0 + $1.annualSalary }
        return contracts + coverage.values.reduce(0, +)
    }

    /// Available cap for a given season offset.
    private func projectedCap(forOffset offset: Int) -> Int {
        guard let team else { return 0 }
        // The league's ONE projection (`ContractEngine.capGrowthPerSeason`), not
        // a local 3 % guess: this screen used to grow the cap slower than the
        // franchise-tag banner, the cap-overview bars and the dashboard tile, so
        // the same future year had two different sizes depending on where the
        // user looked.
        let projectedTotal = Int(Double(team.salaryCap) * pow(1.0 + ContractEngine.capGrowthPerSeason, Double(offset)))
        return projectedTotal - committedSalary(forOffset: offset)
    }

    /// Number of expiring contracts for a given season offset.
    private func expiringCount(forOffset offset: Int) -> Int {
        players.filter { $0.contractYearsRemaining == offset + 1 }.count
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    capProjectionCard
                    filterBar
                    timelineCard
                }
                .padding(20)
                .frame(maxWidth: DSLayout.wideMeasure)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Contract Timeline")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Cap Projection Card

    private var capProjectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(Color.accentGold)
                Text("Projected Cap Space")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let team {
                    Text("Cap: \(formatMillions(team.salaryCap))")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // Bar chart header
            HStack(spacing: 0) {
                ForEach(Array(seasons.enumerated()), id: \.element) { idx, season in
                    VStack(spacing: 6) {
                        Text(String(season))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(idx == 0 ? Color.accentGold : Color.textSecondary)
                            .monospacedDigit()
                        capProjectionBar(offset: idx)
                        capProjectionLabel(offset: idx)
                        expiringBadge(offset: idx)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func capProjectionBar(offset: Int) -> some View {
        let cap = projectedCap(forOffset: offset)
        let maxCapDisplay: Int = (team.map { Int(Double($0.salaryCap) * 1.15) }) ?? 300_000
        let fraction = max(0.0, min(1.0, Double(cap) / Double(maxCapDisplay)))
        let barColor: Color = cap < 0 ? .danger : cap < 5_000 ? .warning : .success

        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(Color.backgroundTertiary)
                    .frame(width: geo.size.width * 0.6)

                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(barColor)
                    .frame(width: geo.size.width * 0.6, height: geo.size.height * fraction)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 60)
    }

    private func capProjectionLabel(offset: Int) -> some View {
        let cap = projectedCap(forOffset: offset)
        return Text(formatMillions(cap))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(cap < 0 ? Color.danger : cap < 5_000 ? Color.warning : Color.success)
    }

    private func expiringBadge(offset: Int) -> some View {
        let count = expiringCount(forOffset: offset)
        return Group {
            if count > 0 {
                Text("\(count) exp.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.warning.opacity(0.15), in: Capsule())
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ContractFilter.allCases) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Timeline Card

    private var timelineCard: some View {
        VStack(spacing: 0) {
            // Header row
            timelineHeaderRow

            Divider().overlay(Color.surfaceBorder)

            if filteredPlayers.isEmpty {
                Text("No contracts match this filter.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding(24)
            } else {
                ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { idx, player in
                    NavigationLink(destination: PlayerContractView(player: player, career: career)) {
                        timelineRow(player: player)
                    }
                    .buttonStyle(.plain)

                    if idx < filteredPlayers.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.4))
                            .padding(.leading, 160)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private var timelineHeaderRow: some View {
        HStack(spacing: 0) {
            // Player name column
            Text("Player")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 160, alignment: .leading)
                .padding(.leading, 16)

            // Season columns
            ForEach(Array(seasons.enumerated()), id: \.element) { idx, season in
                Text(String(season))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(idx == 0 ? Color.accentGold : Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }

            // Salary column
            Text("AAV")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(height: 36)
    }

    private func timelineRow(player: Player) -> some View {
        HStack(spacing: 0) {
            // Player info
            playerInfoCell(player: player)

            // Contract bars
            ForEach(Array(seasons.enumerated()), id: \.element) { idx, _ in
                contractCell(player: player, offset: idx)
            }

            // Annual salary
            Text(formatMillions(player.annualSalary))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func playerInfoCell(player: Player) -> some View {
        HStack(spacing: 8) {
            // Position badge
            Text(player.position.rawValue)
                .font(.system(size: DSType.Size.caption, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 28)
                .padding(.vertical, 3)
                .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("Age \(player.age)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: 160, alignment: .leading)
        .padding(.leading, 16)
    }

    private func contractCell(player: Player, offset: Int) -> some View {
        let isUnderContract = player.contractYearsRemaining > offset
        let isFinalYear = player.contractYearsRemaining == offset + 1

        return GeometryReader { geo in
            ZStack {
                if isUnderContract {
                    // Gold bar for years under contract
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isFinalYear ? Color.warning : Color.accentGold.opacity(0.75))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 12)
                        .overlay(alignment: .leading) {
                            if isFinalYear {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.danger)
                                    .frame(width: 3)
                                    .padding(.vertical, 12)
                            }
                        }
                } else {
                    // Gray for expired years
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary.opacity(0.5))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(
            isUnderContract
                ? (isFinalYear ? "Final contract year" : "Under contract")
                : "Free agent"
        )
    }

    // MARK: - Helpers

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first

        guard let fetchedID = team?.id else { return }
        var playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == fetchedID })
        playerDescriptor.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDescriptor)) ?? []
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if abs(millions) >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else if thousands < 0 {
            return "-$\(abs(thousands))K"
        } else {
            return "$\(thousands)K"
        }
    }
}

// MARK: - Contract Filter

enum ContractFilter: String, CaseIterable, Identifiable {
    case all
    case expiring
    case longTerm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "All"
        case .expiring: return "Expiring"
        case .longTerm: return "Long-Term"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContractTimelineView(
            career: Career(playerName: "Coach Smith", role: .gm, capMode: .realistic)
        )
    }
    .modelContainer(for: [Career.self, Player.self, Team.self], inMemory: true)
}
