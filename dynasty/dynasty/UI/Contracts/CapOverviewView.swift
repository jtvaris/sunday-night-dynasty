import SwiftUI
import SwiftData

struct CapOverviewView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var players: [Player] = []

    /// Detailed contract rows keyed by `playerID`. Only realistic-mode signings
    /// mint one, so most players fall back to `annualSalary` — but where a deal
    /// exists its `capHit` (base + prorated bonus) is what the cap is charged,
    /// and that is the number this screen must show.
    @State private var contractsByPlayer: [UUID: Contract] = [:]

    /// The largest recorded releases of the current season — see ``deadMoneyCard``
    /// for what they can and cannot attribute.
    @State private var releaseReceipts: [ReleaseReceipt] = []

    /// Dead cap recorded across *all* of this season's releases, not just the
    /// handful the card lists — so the "everything else" line stays honest.
    @State private var releaseDeadCapTotal: Int = 0

    /// How many releases were recorded but not listed.
    @State private var releaseOverflowCount: Int = 0

    @State private var contractSort: ContractSort = .capHit

    // MARK: - Contract Sort

    /// How the contract ledger is ordered. The list is the screen's working
    /// surface — 60-odd rows are only useful if you can ask them a question.
    enum ContractSort: String, CaseIterable, Identifiable {
        /// Biggest share of the cap first (identical ordering to cap hit, since
        /// every row divides by the same ceiling — the label names what the GM
        /// is actually reading off the row).
        case capHit
        case salary
        case years
        case expiring

        var id: String { rawValue }

        var label: String {
            switch self {
            case .capHit:   return "Cap %"
            case .salary:   return "Salary"
            case .years:    return "Years"
            case .expiring: return "Expiring"
            }
        }
    }

    /// One recorded release, resolved to a name for display.
    struct ReleaseReceipt: Identifiable {
        let id: UUID
        let name: String
        let deadCap: Int
        let seasonYear: Int
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if let team {
                        capSummaryCard(team: team)
                        capBarCard(team: team)
                        deadMoneyCard(team: team)
                        capOutlookCard(team: team)
                        contractListCard(team: team)
                    } else {
                        ProgressView()
                            .tint(Color.accentBlue)
                            .padding(.top, 80)
                    }
                }
                .padding(20)
                .frame(maxWidth: DSLayout.contentMeasure)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Salary Cap")
        // Inline, not `.large` (#47): a large title is pinned to the window's
        // leading edge, so on an iPad it sat ~230 pt to the left of the centred
        // content column and read as broken alignment. The nav bar still names
        // the screen; the cards keep the reading measure the numbers need.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Cap Summary Card

    private func capSummaryCard(team: Team) -> some View {
        let active = activeCapUsage
        let dead = deadMoney(team: team)

        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("Cap Summary")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                capStatColumn(
                    label: "Total Cap",
                    value: formatMillions(team.salaryCap),
                    color: .textPrimary
                )
                capStatColumn(
                    label: "Used Cap",
                    value: formatMillions(team.currentCapUsage),
                    color: capUsageColor(team: team)
                )
                capStatColumn(
                    label: "Available",
                    value: formatMillions(team.availableCap),
                    color: team.availableCap >= 0 ? .success : .danger
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // The split the screen used to hide. "Used Cap" is one number for
            // two very different commitments: money paid to players who will
            // take a snap this year, and money owed to players who are gone.
            // A GM plans against the first and is punished by the second, so
            // both are named, and they add back up to the number above.
            HStack(spacing: 12) {
                capSplitPill(
                    label: "Active contracts",
                    value: formatMillions(active),
                    color: .textPrimary,
                    icon: "person.2.fill"
                )
                Text("+")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                capSplitPill(
                    label: deadLabel(dead),
                    value: formatMillions(dead),
                    color: dead > 0 ? .danger : .textTertiary,
                    icon: "xmark.circle.fill"
                )
            }

            Text("Active + \(deadLabel(dead).lowercased()) = used cap")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    private func capStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func capSplitPill(label: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundTertiary.opacity(0.5), in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Cap Bar Card

    private func capBarCard(team: Team) -> some View {
        let dead = deadMoney(team: team)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cap Usage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(String(format: "%.1f%%", usagePercentage(team: team) * 100))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(capUsageColor(team: team))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 14)

                    // Two segments, one bar: the dead-money tail sits at the
                    // right edge of the fill so the eye reads "this much of the
                    // spend buys nothing" without needing a second chart.
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(capBarGradient(team: team))
                            .frame(width: geo.size.width * clampedFraction(activeCapUsage, of: team.salaryCap))
                        if dead > 0 {
                            Rectangle()
                                .fill(Color.danger)
                                .frame(width: geo.size.width * clampedFraction(dead, of: team.salaryCap))
                        }
                    }
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .animation(.easeOut(duration: 0.4), value: team.currentCapUsage)
                }
            }
            .frame(height: 14)

            if dead > 0 {
                HStack(spacing: 12) {
                    legendDot(color: .accentBlue, label: "Active \(formatMillions(activeCapUsage))")
                    legendDot(color: .danger, label: "Dead \(formatMillions(dead))")
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Dead Money Card

    /// Dead money, named and attributed as far as the store allows.
    ///
    /// **What the ledger actually knows.** `Team.currentCapUsage` is a single
    /// running total; nothing stores a dead-money column and nothing stores who
    /// each dollar belonged to. The total here is therefore derived the only way
    /// it can be — the cap charge that no player on the roster accounts for:
    ///
    /// ```
    /// dead = team.currentCapUsage − Σ roster cap hits
    /// ```
    ///
    /// which is exactly what `TradeEngine.executeTrade` leaves behind when it
    /// subtracts a traded player's salary and adds `split.deadCap` back on.
    ///
    /// **Attribution** exists for one path only: `RosterCut` rows record a
    /// per-player `deadCap` for camp releases. Those are shown as receipts, and
    /// the remainder is labelled honestly rather than being silently split up —
    /// trades and in-season releases leave no per-player record to read.
    private func deadMoneyCard(team: Team) -> some View {
        let dead = deadMoney(team: team)
        let unattributed = dead - releaseDeadCapTotal

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dead > 0 ? Color.danger : Color.textSecondary)
                Text("Dead Money")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(formatMillions(dead))
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(dead > 0 ? Color.danger : Color.textTertiary)
            }

            Divider().overlay(Color.surfaceBorder)

            if dead <= 0 {
                Text("No dead money on the books — every dollar of cap charge belongs to a player on the roster.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !releaseReceipts.isEmpty {
                    Text("RECORDED RELEASES THIS SEASON")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.textSecondary)

                    ForEach(releaseReceipts) { receipt in
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill.xmark")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textTertiary)
                            Text(receipt.name)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(formatMillions(receipt.deadCap))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }
                        .padding(.vertical, 2)
                    }

                    if releaseOverflowCount > 0 {
                        Text("+ \(releaseOverflowCount) more release\(releaseOverflowCount == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                if unattributed > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                        Text(releaseReceipts.isEmpty
                             ? "Charged to players no longer on the roster"
                             : "Trades and earlier releases")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                        Spacer()
                        Text(formatMillions(unattributed))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.vertical, 2)
                }

                Text("The cap ledger keeps dead money as one team total, so only recorded releases can be named player-by-player.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
    }

    // MARK: - Cap Outlook Card

    /// Estimated replacement cost for a position at league-minimum level (in thousands).
    private func replacementCost(for position: Position) -> Int {
        switch position {
        case .QB:                            return 1_350
        case .DE, .CB:                       return 975
        case .WR:                            return 940
        case .OLB:                           return 900
        case .LT:                            return 860
        case .DT, .FS, .SS:                  return 825
        case .TE, .MLB:                      return 790
        case .LG, .RG, .C, .RT:             return 715
        case .RB:                            return 675
        case .FB:                            return 525
        case .K, .P:                         return 450
        }
    }

    /// Annual cap growth the projection assumes (NFL trend).
    private static let capGrowthRate = 1.07

    private func capOutlookCard(team: Team) -> some View {
        let expiringPlayers = players.filter { $0.contractYearsRemaining == 1 }
        let totalFreed = expiringPlayers.reduce(0) { $0 + $1.annualSalary }
        let totalReplacement = expiringPlayers.reduce(0) { $0 + replacementCost(for: $1.position) }
        let netChange = totalFreed - totalReplacement
        // Gold discipline: one number in this list is the story — the biggest
        // deal coming off the books. Seventeen gold values were seventeen equal
        // alarms, which is the same as none.
        let largestExpiring = expiringPlayers.map(\.annualSalary).max() ?? 0

        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("Cap Outlook")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("3 seasons")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Divider().overlay(Color.surfaceBorder)

            // Three years of committed money against the projected ceiling.
            // Y+1 alone answered "can I re-sign this guy"; it could not answer
            // "can I afford all three of these deals at once", which is the
            // question a dynasty is actually decided by.
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { offset in
                    outlookYearRow(team: team, yearOffset: offset)
                }
            }

            Text("Committed vs projected cap (+7%/yr). Future years count only money already under contract — draft picks, re-signings and dead money from later cuts are not in these bars.")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Expiring contracts list
            if expiringPlayers.isEmpty {
                Text("No contracts expiring after this season")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Expiring Contracts")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(expiringPlayers.count) player\(expiringPlayers.count == 1 ? "" : "s")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.bottom, 8)

                    ForEach(expiringPlayers, id: \.id) { player in
                        HStack(spacing: 8) {
                            Text(player.position.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                                .frame(width: 30)
                                .padding(.vertical, 2)
                                .background(positionColor(player.position).opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                            Text(player.fullName)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(formatMillions(player.annualSalary))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(
                                    player.annualSalary == largestExpiring
                                        ? Color.accentGold
                                        : Color.textPrimary
                                )
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Summary line
            HStack(spacing: 4) {
                Text("Cap freed:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text(formatMillions(totalFreed))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.success)

                Text("|")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)

                Text("Est. replacement:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text(formatMillions(totalReplacement))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)

                Text("|")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)

                Text("Net:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("\(netChange >= 0 ? "+" : "")\(formatMillions(netChange))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(netChange >= 0 ? Color.success : Color.danger)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    private func outlookYearRow(team: Team, yearOffset: Int) -> some View {
        let cap = projectedCap(team: team, yearOffset: yearOffset)
        let committed = committedCap(team: team, yearOffset: yearOffset)
        let room = cap - committed
        let fraction = clampedFraction(committed, of: cap)
        let isCurrent = yearOffset == 0
        let barColor: Color = fraction > 1.0 ? .danger : (fraction > 0.9 ? .warning : .accentBlue)

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(seasonLabel(yearOffset: yearOffset))
                    .font(.system(size: 11, weight: isCurrent ? .bold : .semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.textPrimary : Color.textSecondary)
                    .frame(width: 44, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.backgroundTertiary)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor)
                            .frame(width: geo.size.width * min(fraction, 1.0), height: 10)
                    }
                }
                .frame(height: 10)

                Text(formatMillions(committed))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 58, alignment: .trailing)

                Text("\(room >= 0 ? "+" : "")\(formatMillions(room))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(room >= 0 ? Color.success : Color.danger)
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seasonLabel(yearOffset: yearOffset)), committed \(formatMillions(committed)) of \(formatMillions(cap)), room \(formatMillions(room))")
    }

    // MARK: - Contract List Card

    private func contractListCard(team: Team) -> some View {
        let ordered = sortedContractPlayers
        let dead = deadMoney(team: team)

        return VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("Player Contracts")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Text("\(players.count) players")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Picker("Sort contracts", selection: $contractSort) {
                ForEach(ContractSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider().overlay(Color.surfaceBorder)
                .padding(.horizontal, 20)

            if players.isEmpty {
                Text("No contracts on file")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding(24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, player in
                        NavigationLink {
                            PlayerDetailView(player: player)
                        } label: {
                            contractRow(player: player, team: team)
                        }
                        .buttonStyle(.plain)

                        if index < ordered.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 20)
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)
                    .padding(.horizontal, 20)

                // Total row. This is the number that used to lie: it summed
                // `annualSalary` and printed $221.5M under a Used-Cap card that
                // said $189.4M, because base salary is not what the cap is
                // charged. It sums the same cap hits the summary card does, and
                // the reconciliation line underneath names the difference.
                VStack(spacing: 4) {
                    HStack {
                        Text("Total cap hits")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(formatMillions(activeCapUsage))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                    HStack {
                        Text("+ \(deadLabel(dead).lowercased()) \(formatMillions(dead))  =  used cap")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text(formatMillions(team.currentCapUsage))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func contractRow(player: Player, team: Team) -> some View {
        let hit = capHit(for: player)
        let share = team.salaryCap > 0 ? Double(hit) / Double(team.salaryCap) * 100.0 : 0

        return HStack(spacing: 12) {
            // Position badge
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 4)
                .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: 4))

            // Name
            Text(player.fullName)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer()

            // Years remaining
            HStack(spacing: 4) {
                Text("\(player.contractYearsRemaining)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(yearsColor(player.contractYearsRemaining))
                Text("yr\(player.contractYearsRemaining == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            // Cap hit + share of the ceiling
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatMillions(hit))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                Text(String(format: "%.1f%%", share))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(share >= 8 ? Color.warning : Color.textTertiary)
            }
            .frame(minWidth: 64, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.fullName), \(player.position.rawValue), cap hit \(formatMillions(hit)), \(player.contractYearsRemaining) years remaining")
        .accessibilityHint("Opens player detail")
    }

    // MARK: - Cap Math

    /// The cap charge a player actually carries: his detailed contract's cap hit
    /// (base + prorated bonus) when a `Contract` row exists, and `annualSalary`
    /// when it does not. `PlayerRowView` reads the same precedence.
    private func capHit(for player: Player) -> Int {
        contractsByPlayer[player.id]?.capHit ?? player.annualSalary
    }

    /// Cap charged to players who are on the roster right now.
    private var activeCapUsage: Int {
        players.reduce(0) { $0 + capHit(for: $1) }
    }

    /// Cap charged to nobody on the roster — see ``deadMoneyCard`` for why this
    /// is derived rather than stored.
    private func deadMoney(team: Team) -> Int {
        team.currentCapUsage - activeCapUsage
    }

    /// The residual can go negative if a detailed contract's cap hit outruns the
    /// `annualSalary` the ledger was charged. That is a bookkeeping variance, not
    /// dead money, and calling it dead money would be a lie in the other
    /// direction from the bug this screen just fixed.
    private func deadLabel(_ dead: Int) -> String {
        dead < 0 ? "Ledger variance" : "Dead money"
    }

    /// Money already committed for a future season, in thousands.
    ///
    /// Reads the contract's own year table where one exists (`baseSalary[year] +
    /// prorated bonus`, exactly `yearlyBreakdown`'s arithmetic), and falls back
    /// to "still under contract that year → this year's salary" for the majority
    /// of players who only have `contractYearsRemaining`.
    ///
    /// Year 0 is the live ledger, dead money included, so the first bar ties back
    /// to the Used Cap number at the top of the screen.
    private func committedCap(team: Team, yearOffset: Int) -> Int {
        guard yearOffset > 0 else { return team.currentCapUsage }

        return players.reduce(0) { total, player in
            if let contract = contractsByPlayer[player.id], contract.totalYears > 0 {
                let index = contract.currentYear + yearOffset
                guard index < contract.totalYears else { return total }
                let base = index < contract.baseSalary.count ? contract.baseSalary[index] : 0
                return total + base + contract.signingBonus / contract.totalYears
            }
            return player.contractYearsRemaining > yearOffset ? total + player.annualSalary : total
        }
    }

    private func projectedCap(team: Team, yearOffset: Int) -> Int {
        guard yearOffset > 0 else { return team.salaryCap }
        return Int(Double(team.salaryCap) * pow(Self.capGrowthRate, Double(yearOffset)))
    }

    private func seasonLabel(yearOffset: Int) -> String {
        "\(career.currentSeason + yearOffset)"
    }

    private var sortedContractPlayers: [Player] {
        switch contractSort {
        case .capHit:
            return players.sorted { capHit(for: $0) > capHit(for: $1) }
        case .salary:
            return players.sorted { $0.annualSalary > $1.annualSalary }
        case .years:
            return players.sorted {
                $0.contractYearsRemaining == $1.contractYearsRemaining
                    ? capHit(for: $0) > capHit(for: $1)
                    : $0.contractYearsRemaining > $1.contractYearsRemaining
            }
        case .expiring:
            return players.sorted {
                $0.contractYearsRemaining == $1.contractYearsRemaining
                    ? capHit(for: $0) > capHit(for: $1)
                    : $0.contractYearsRemaining < $1.contractYearsRemaining
            }
        }
    }

    // MARK: - Helpers

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == fetchedTeamID })
        playerDescriptor.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDescriptor)) ?? []

        // Detailed deals for this club. Team IDs are minted per save, so the
        // team predicate already scopes the fetch to this career.
        let contractDescriptor = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.teamID == fetchedTeamID }
        )
        let contracts = (try? modelContext.fetch(contractDescriptor)) ?? []
        contractsByPlayer = Dictionary(contracts.map { ($0.playerID, $0) }, uniquingKeysWith: { first, _ in first })

        loadReleaseReceipts(teamID: fetchedTeamID)
    }

    /// Resolves this season's recorded releases into names + dead-cap charges.
    ///
    /// Only the rows that will actually be rendered are resolved to players: the
    /// dead-cap totals live on the `RosterCut` rows themselves, so the sum costs
    /// one fetch and the names cost at most six more.
    private func loadReleaseReceipts(teamID: UUID) {
        let season = career.currentSeason
        let cutDescriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> { $0.teamID == teamID && $0.seasonYear == season }
        )
        let cuts = ((try? modelContext.fetch(cutDescriptor)) ?? [])
            .filter { $0.deadCap > 0 && $0.claimedByTeamID == nil }
            .sorted { $0.deadCap > $1.deadCap }

        releaseDeadCapTotal = cuts.reduce(0) { $0 + $1.deadCap }
        releaseOverflowCount = max(0, cuts.count - 6)

        releaseReceipts = cuts.prefix(6).map { cut in
            let playerID = cut.playerID
            let descriptor = FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.id == playerID })
            let name = (try? modelContext.fetch(descriptor).first)?.fullName ?? "Released player"
            return ReleaseReceipt(id: cut.id, name: name, deadCap: cut.deadCap, seasonYear: cut.seasonYear)
        }
    }

    private func usagePercentage(team: Team) -> Double {
        guard team.salaryCap > 0 else { return 0 }
        return Double(team.currentCapUsage) / Double(team.salaryCap)
    }

    private func clampedFraction(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return max(0, Double(value) / Double(total))
    }

    private func capUsageColor(team: Team) -> Color {
        let pct = usagePercentage(team: team)
        if pct > 1.0 { return .danger }
        if pct > 0.9 { return .warning }
        return .textSecondary
    }

    private func capBarGradient(team: Team) -> LinearGradient {
        let pct = usagePercentage(team: team)
        let color: Color = pct > 1.0 ? .danger : (pct > 0.9 ? .warning : .accentBlue)
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func yearsColor(_ years: Int) -> Color {
        switch years {
        case 3...: return .success
        case 2:    return .accentGold
        case 1:    return .warning
        default:   return .danger
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let sign = thousands < 0 ? "-" : ""
        let magnitude = abs(thousands)
        let millions = Double(magnitude) / 1000.0
        if millions >= 1.0 {
            return sign + String(format: "$%.1fM", millions)
        } else {
            return sign + "$\(magnitude)K"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CapOverviewView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Team.self, Player.self], inMemory: true)
}
