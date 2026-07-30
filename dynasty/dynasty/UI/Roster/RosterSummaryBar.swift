import SwiftUI

/// Always-visible summary bar at the top of the Roster view showing key team stats.
struct RosterSummaryBar: View {
    let players: [Player]
    /// The team's current salary cap in thousands. Falls back to 265_000 if not provided.
    var teamSalaryCap: Int = 265_000
    /// `Team.currentCapUsage` in thousands — the league's cap ledger.
    ///
    /// THE number, not a number: it is what the Cap screen, the dashboard, the
    /// trade validator, free-agency affordability and the cap-floor check all
    /// read, and it is the one that carries dead money and survives the
    /// league-year true-up. Summing `annualSalary` over the roster (the
    /// fallback below, kept only for previews and call sites without a team)
    /// answers a different question and drifts from the ledger the moment a
    /// contract's cap hit differs from its annual average — which is why the
    /// header claimed $221.5M while every other screen said $189.4M.
    var capUsed: Int? = nil
    /// The league phase, so the Players column can name the ceiling that
    /// actually applies right now. `nil` (previews, call sites with no career)
    /// prints the bare count exactly as before.
    var phase: SeasonPhase? = nil

    private var totalCount: Int { players.count }
    private var healthyCount: Int { players.filter { !$0.isInjured }.count }
    private var injuredCount: Int { players.filter { $0.isInjured }.count }

    private var averageOVR: Int {
        guard !players.isEmpty else { return 0 }
        return players.reduce(0) { $0 + $1.overall } / players.count
    }

    private var totalCapUsed: Int {
        capUsed ?? players.reduce(0) { $0 + $1.annualSalary }
    }

    /// Salary cap ceiling in thousands (e.g., 265000 = $265M).
    private var salaryCap: Int { teamSalaryCap }

    /// Cap used expressed in millions (Double). Source of truth for all $-display.
    private var capUsedMillions: Double {
        Double(totalCapUsed) / 1000.0
    }

    /// Cap ceiling expressed in millions (Double). Source of truth for all $-display.
    private var capTotalMillions: Double {
        Double(salaryCap) / 1000.0
    }

    private var formattedCapUsed: String {
        String(format: "$%.1fM", capUsedMillions)
    }

    private var formattedCapTotal: String {
        String(format: "$%.1fM", capTotalMillions)
    }

    private var capUsageRatio: Double {
        guard salaryCap > 0 else { return 0 }
        return min(Double(totalCapUsed) / Double(salaryCap), 1.0)
    }

    /// True when total cap used exceeds the salary cap ceiling.
    private var isOverCap: Bool {
        totalCapUsed > salaryCap
    }

    /// Cap overage in thousands (positive when over cap, 0 otherwise).
    private var capOverage: Int {
        max(0, totalCapUsed - salaryCap)
    }

    /// Cap overage in millions (Double) for display formatting.
    /// Computed from the *rounded display millions* so the banner number
    /// is always consistent with `formattedCapUsed - formattedCapTotal`.
    /// Falls back to the raw thousands diff when both display values
    /// round to the same tenth (e.g. used 265.04 vs cap 265.00) so a
    /// real overage is never masked as "$0.0M".
    private var capOverageMillions: Double {
        let displayDelta = (capUsedMillions * 10).rounded() / 10
                         - (capTotalMillions * 10).rounded() / 10
        if displayDelta > 0 {
            return displayDelta
        }
        // Display rounds to the same tenth; surface the true overage.
        return Double(capOverage) / 1000.0
    }

    private var formattedCapOverage: String {
        // Use 2-decimal precision when the overage is < $1M so a small but
        // real overage isn't masked as "$0.0M" by single-decimal rounding.
        if capOverageMillions > 0 && capOverageMillions < 1.0 {
            return String(format: "$%.2fM", capOverageMillions)
        }
        return String(format: "$%.1fM", capOverageMillions)
    }

    private var capColor: Color {
        if isOverCap { return .danger }
        switch capUsageRatio {
        case 0.9...:  return .danger
        case 0.75..<0.9: return .warning
        default:      return .accentGold
        }
    }

    // MARK: - Roster Limit

    /// The roster ceiling in force this phase, named honestly.
    ///
    /// Both numbers come from the engine's own constants, not from a literal
    /// retyped here: `PracticeSquadEngine.activeRosterCeiling` is the 53 a poach
    /// has to open a spot under and the number `WeekAdvancer.trimAIRosters` cuts
    /// AI clubs to, and `TradeValueEngine.offseasonRosterCeiling` is the 90 the
    /// offseason trade market validates against. The bar used to print "63
    /// Players" with no ceiling anywhere on the screen, so the user's roster
    /// could sit 10 over the active limit with nothing to say so.
    private struct RosterLimit {
        let ceiling: Int
        let caption: String
        /// True when going over it is illegal RIGHT NOW rather than a deadline
        /// still ahead of the user.
        let isBinding: Bool
    }

    private var rosterLimit: RosterLimit? {
        guard let phase else { return nil }
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs, .proBowl, .superBowl:
            return RosterLimit(
                ceiling: PracticeSquadEngine.activeRosterCeiling,
                caption: "53 limit",
                isBinding: true
            )
        case .rosterCuts:
            // Cutdown day: still legally at 90, but 53 is the gate at the end
            // of this phase — say which one is coming, not just which one holds.
            return RosterLimit(
                ceiling: TradeValueEngine.offseasonRosterCeiling,
                caption: "cut to 53",
                isBinding: false
            )
        default:
            return RosterLimit(
                ceiling: TradeValueEngine.offseasonRosterCeiling,
                caption: "offseason",
                isBinding: false
            )
        }
    }

    private var playersValue: String {
        guard let limit = rosterLimit else { return "\(totalCount)" }
        return "\(totalCount) / \(limit.ceiling)"
    }

    private var playersLabel: String {
        guard let limit = rosterLimit else { return "Players" }
        return "Players · \(limit.caption)"
    }

    private var playersColor: Color {
        guard let limit = rosterLimit else { return .textPrimary }
        if totalCount > limit.ceiling { return .danger }
        // Cutdown day with an over-53 roster: a warning, not an error — the
        // user still has the phase to fix it.
        if !limit.isBinding && totalCount > PracticeSquadEngine.activeRosterCeiling { return .warning }
        return .textPrimary
    }

    private var rosterStrength: Int {
        switch averageOVR {
        case 80...: return 5
        case 75..<80: return 4
        case 70..<75: return 3
        case 65..<70: return 2
        default: return 1
        }
    }

    private var strengthLabel: String {
        switch rosterStrength {
        case 5:  return "Elite"
        case 4:  return "Strong"
        case 3:  return "Average"
        case 2:  return "Below Avg"
        default: return "Weak"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Over-cap warning banner (#55) — shown when usedCap > salaryCap.
            if isOverCap {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.danger)
                    Text("OVER CAP")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.danger)
                        .tracking(0.5)
                    Text("-\(formattedCapOverage)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.danger)
                    Text("\u{2014} Resolve before adding players")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.danger.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.danger.opacity(0.4)),
                    alignment: .bottom
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Over salary cap by \(formattedCapOverage). Resolve before adding players.")
            }

            // Over-limit warning — the 53-man ceiling was enforced only for AI
            // clubs (`WeekAdvancer.trimAIRosters` skips `career.teamID`), so a
            // user roster could carry 63 men into week 1 with nothing anywhere
            // on the screen saying so. The advance itself is gated in
            // `CareerShellView`; this is the standing reminder.
            if let limit = rosterLimit, totalCount > PracticeSquadEngine.activeRosterCeiling {
                let over = totalCount - PracticeSquadEngine.activeRosterCeiling
                let tint: Color = limit.isBinding ? .danger : .warning
                HStack(spacing: 6) {
                    Image(systemName: "person.2.badge.minus.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    Text(limit.isBinding ? "OVER ROSTER LIMIT" : "CUTDOWN PENDING")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(tint)
                        .tracking(0.5)
                    Text("+\(over)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(tint)
                    Text("\u{2014} \(over) player\(over == 1 ? "" : "s") over the \(PracticeSquadEngine.activeRosterCeiling)-man active roster")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(tint.opacity(0.4)),
                    alignment: .bottom
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(over) players over the 53-man active roster limit.")
            }

            HStack(spacing: 0) {
            summaryItem(
                label: playersLabel,
                value: playersValue,
                color: playersColor
            )

            divider

            summaryItem(
                label: "Healthy",
                value: "\(healthyCount)",
                color: .success
            )

            divider

            summaryItem(
                label: "Injured",
                value: "\(injuredCount)",
                color: injuredCount > 0 ? .danger : .textSecondary
            )

            divider

            summaryItem(
                label: "Avg OVR",
                value: "\(averageOVR)",
                color: Color.forRating(averageOVR)
            )

            divider

            // Salary cap with progress bar
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    Text(formattedCapUsed)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(capColor)
                    Text(" / ")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(formattedCapTotal)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.backgroundTertiary)
                            .frame(height: 5)
                        Capsule()
                            .fill(capColor)
                            .frame(width: geo.size.width * capUsageRatio, height: 5)
                    }
                }
                .frame(height: 5)
                .padding(.horizontal, 6)

                Text("Salary Cap")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity)

            divider

            // Roster Strength stars with OVR-based label
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: index < rosterStrength ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(index < rosterStrength ? Color.accentGold : Color.textTertiary)
                    }
                }
                Text(strengthLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.surfaceBorder),
            alignment: .bottom
        )
    }

    private func summaryItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.surfaceBorder)
            .frame(width: 1, height: 28)
    }
}

#Preview {
    VStack {
        RosterSummaryBar(players: [
            Player(
                firstName: "Patrick", lastName: "Mahomes", position: .QB,
                age: 28, yearsPro: 7,
                positionAttributes: .quarterback(QBAttributes(
                    armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                    accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                )),
                personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                contractYearsRemaining: 3, annualSalary: 45000
            ),
            Player(
                firstName: "Tyreek", lastName: "Hill", position: .WR,
                age: 29, yearsPro: 8,
                positionAttributes: .wideReceiver(WRAttributes(
                    routeRunning: 88, catching: 90, release: 92, spectacularCatch: 85
                )),
                personality: PlayerPersonality(archetype: .loneWolf, motivation: .stats),
                isInjured: true, injuryWeeksRemaining: 3
            ),
        ])
        Spacer()
    }
    .background(Color.backgroundPrimary)
}
