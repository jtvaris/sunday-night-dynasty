import SwiftUI

struct PlayerRowView: View {
    let player: Player
    /// Depth chart index: 0 = starter, 1 = backup, 2+ = 3rd string. nil = unknown.
    var depthIndex: Int? = nil
    /// Optional detailed contract for cap hit display.
    var contract: Contract? = nil
    /// Analysis view mode that determines which columns to show.
    var analysisMode: RosterAnalysisMode = .overview
    /// Total number of players at this position (used for promote/demote bounds).
    var positionGroupCount: Int = 0
    /// Called when the user requests a depth change. Parameter is the new depth index.
    var onDepthChange: ((Int) -> Void)? = nil
    /// Called when the user taps the position badge to change position (#175).
    var onPositionBadgeTap: (() -> Void)? = nil
    /// Called when the user taps the starter badge to pick a new starter (#198).
    var onStarterBadgeTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            // Always show: Position badge + Depth + Avatar + Name
            positionBadge

            depthIndicator
                .frame(width: 14, alignment: .center)

            PlayerAvatarView(player: player, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // Status badges — full text for clarity (#171, #172)
                HStack(spacing: 4) {
                    if isExpiringContract {
                        Text("Trade Watch")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.warning)
                    }
                    if isHighCapInvestment {
                        Text("Invested")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                    }
                    if player.isFranchiseTagged {
                        Text("Franchise")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.danger)
                    }
                }
            }
            .frame(minWidth: 80, alignment: .leading)

            Spacer(minLength: 2)

            // Mode-specific columns
            switch analysisMode {
            case .overview:
                overviewColumns
            case .contracts:
                contractColumns
            case .development:
                developmentColumns
            case .physical:
                physicalColumns
            case .attributes:
                attributeColumns
            case .depth:
                depthColumns
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Overview Columns (default)

    private var overviewColumns: some View {
        Group {
            // Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, alignment: .center)

            // Form indicator (#97)
            formColumn

            // OVR (large, color-coded)
            Text("\(player.overall)")
                .font(.callout.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 40, alignment: .center)

            // Development arrow
            developmentArrow
                .frame(width: 20, alignment: .center)

            // Cap Hit
            VStack(alignment: .trailing, spacing: 0) {
                Text(formattedCapHit)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                if showsSeparateCapHit {
                    Text("cap")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(width: 52, alignment: .trailing)

            // Contract years remaining
            contractYearsLabel
                .frame(width: 30, alignment: .center)

            // Morale icon
            moraleIndicator
                .frame(width: 24, alignment: .center)

            // Health status
            healthIndicator
                .frame(width: 28, alignment: .center)
        }
    }

    // MARK: - Contract Columns

    private var contractColumns: some View {
        Group {
            // Base Salary
            Text(formattedSalary)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 52, alignment: .trailing)

            // Cap Hit
            VStack(alignment: .trailing, spacing: 0) {
                Text(formattedCapHit)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentGold)
                Text("cap")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 52, alignment: .trailing)

            // Years remaining
            contractYearsLabel
                .frame(width: 34, alignment: .center)

            // Free agent year estimate
            Text("FA \(player.age + player.contractYearsRemaining)")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(player.contractYearsRemaining <= 1 ? Color.warning : Color.textTertiary)
                .frame(width: 40, alignment: .center)

            // OVR for context
            Text("\(player.overall)")
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .center)
        }
    }

    // MARK: - Development Columns

    private var developmentColumns: some View {
        Group {
            // Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, alignment: .center)

            // OVR
            Text("\(player.overall)")
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .center)

            // Potential (hidden value shown as fuzzy label)
            Text(potentialLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.accentGold)
                .frame(width: 40, alignment: .center)

            // Development arrow
            developmentArrow
                .frame(width: 20, alignment: .center)

            // Phase label
            Text(developmentPhaseLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(developmentTrend.color)
                .frame(width: 48, alignment: .center)

            // Form
            formColumn

            // Work ethic indicator
            colorCodedMiniAttribute(value: player.mental.workEthic, label: "WE")
                .frame(width: 32, alignment: .center)
        }
    }

    // MARK: - Physical Columns

    private var physicalColumns: some View {
        Group {
            colorCodedMiniAttribute(value: player.physical.speed, label: "SPD")
                .frame(width: 34, alignment: .center)
            colorCodedMiniAttribute(value: player.physical.strength, label: "STR")
                .frame(width: 34, alignment: .center)
            colorCodedMiniAttribute(value: player.physical.stamina, label: "STA")
                .frame(width: 34, alignment: .center)
            colorCodedMiniAttribute(value: player.physical.durability, label: "DUR")
                .frame(width: 34, alignment: .center)

            // Health
            healthIndicator
                .frame(width: 28, alignment: .center)

            // OVR
            Text("\(player.overall)")
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .center)
        }
    }

    // MARK: - Position Skills Columns (#280)

    /// Returns position-specific attribute tuples: (value, label).
    private var positionSkillAttributes: [(value: Int, label: String)] {
        switch player.positionAttributes {
        case .quarterback(let a):
            return [(a.armStrength, "ARM"), (a.accuracyShort, "SHT"), (a.accuracyDeep, "DEP"), (a.pocketPresence, "POC")]
        case .wideReceiver(let a):
            return [(a.routeRunning, "RTE"), (a.catching, "CTH"), (a.release, "REL")]
        case .runningBack(let a):
            return [(a.vision, "VIS"), (a.elusiveness, "ELU"), (a.breakTackle, "TRK")]
        case .tightEnd(let a):
            return [(a.blocking, "BLK"), (a.catching, "CTH"), (a.routeRunning, "RTE")]
        case .offensiveLine(let a):
            return [(a.passBlock, "PBK"), (a.runBlock, "RBK"), (a.anchor, "ANC")]
        case .defensiveLine(let a):
            return [(a.passRush, "PRU"), (a.blockShedding, "RST"), (a.powerMoves, "PWR")]
        case .linebacker(let a):
            return [(a.tackling, "TKL"), (a.zoneCoverage, "ZCV"), (a.manCoverage, "MCV")]
        case .defensiveBack(let a):
            if player.position == .CB {
                return [(a.manCoverage, "MAN"), (a.zoneCoverage, "ZON"), (a.press, "PRS")]
            } else {
                // Safeties: range (zone), tackle-oriented, ball skills
                return [(a.zoneCoverage, "RNG"), (a.ballSkills, "BAL"), (a.manCoverage, "MCV")]
            }
        case .kicking(let a):
            return [(a.kickPower, "PWR"), (a.kickAccuracy, "ACC")]
        }
    }

    private var attributeColumns: some View {
        Group {
            let skills = positionSkillAttributes
            ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                colorCodedMiniAttribute(value: skill.value, label: skill.label)
                    .frame(width: 32, alignment: .center)
            }
            // Pad to 4 columns if fewer attributes
            if skills.count < 4 {
                ForEach(0..<(4 - skills.count), id: \.self) { _ in
                    Spacer().frame(width: 32)
                }
            }

            // OVR
            Text("\(player.overall)")
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .center)
        }
    }

    // MARK: - Depth Columns

    private var depthColumns: some View {
        Group {
            // Starter/Backup badge (larger) — tappable to pick starter (#198)
            Group {
                if depthIndex == 0, let onStarterBadgeTap {
                    Button {
                        onStarterBadgeTap()
                    } label: {
                        starterBadgeContent
                    }
                    .buttonStyle(.plain)
                } else {
                    starterBadgeContent
                }
            }

            // Depth label
            Text(depthLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(depthColor)
                .frame(width: 52, alignment: .leading)

            // OVR
            Text("\(player.overall)")
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .center)

            // Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .center)

            // Health
            healthIndicator
                .frame(width: 28, alignment: .center)

            // Form
            formColumn
        }
    }

    // MARK: - Starter Badge Content (#198)

    private var starterBadgeContent: some View {
        Text(depthBadgeText)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(depthIndex == 0 ? Color.backgroundPrimary : depthColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                depthIndex == 0
                    ? AnyShapeStyle(depthColor)
                    : AnyShapeStyle(depthColor.opacity(0.2)),
                in: RoundedRectangle(cornerRadius: 3)
            )
    }

    // MARK: - Form Column (#97)

    private var formColumn: some View {
        let form = playerFormIndicator(for: player)
        return Text(form.symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(form.color)
            .frame(width: 24, alignment: .center)
            .accessibilityLabel("Form \(formAccessibilityLabel)")
    }

    private var formAccessibilityLabel: String {
        let form = playerFormIndicator(for: player)
        switch form.symbol {
        case "\u{2191}": return "hot"
        case "\u{2192}": return "steady"
        default:         return "cold"
        }
    }

    // MARK: - Mini Attribute Helper

    private func colorCodedMiniAttribute(value: Int, label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(analysisAttributeColor(for: value))
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    /// Color coding for attribute columns: 90+ gold, 80+ green, 70+ blue, below 70 orange/red.
    private func analysisAttributeColor(for value: Int) -> Color {
        switch value {
        case 90...:   return .accentGold
        case 80..<90: return .success
        case 70..<80: return .accentBlue
        default:      return .warning
        }
    }

    // MARK: - Subviews

    private var positionBadge: some View {
        Group {
            if let onPositionBadgeTap {
                Button {
                    onPositionBadgeTap()
                } label: {
                    positionBadgeContent
                }
                .buttonStyle(.plain)
            } else {
                positionBadgeContent
            }
        }
    }

    private var positionBadgeContent: some View {
        Text(player.position.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 24)
            .background(positionColor, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                onPositionBadgeTap != nil
                    ? RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.textTertiary.opacity(0.5), lineWidth: 1)
                    : nil
            )
            .accessibilityLabel("\(player.position.rawValue), \(player.position.side.rawValue)\(onPositionBadgeTap != nil ? ", tap to change" : "")")
    }

    @ViewBuilder
    private var depthIndicator: some View {
        if let onDepthChange, let currentIndex = depthIndex, positionGroupCount > 1 {
            Menu {
                if currentIndex > 0 {
                    Button {
                        onDepthChange(currentIndex - 1)
                    } label: {
                        Label("Promote to \(depthRoleLabel(for: currentIndex - 1))", systemImage: "arrow.up")
                    }
                }
                if currentIndex < positionGroupCount - 1 {
                    Button {
                        onDepthChange(currentIndex + 1)
                    } label: {
                        Label("Demote to \(depthRoleLabel(for: currentIndex + 1))", systemImage: "arrow.down")
                    }
                }
            } label: {
                Text(depthBadgeText)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(depthIndex == 0 ? Color.backgroundPrimary : depthColor)
                    .frame(width: 14, height: 14)
                    .background(
                        depthIndex == 0
                            ? AnyShapeStyle(depthColor)
                            : AnyShapeStyle(depthColor.opacity(0.2)),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
            }
            .accessibilityLabel("\(depthLabel), tap to change")
        } else {
            Text(depthBadgeText)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(depthIndex == 0 ? Color.backgroundPrimary : depthColor)
                .frame(width: 14, height: 14)
                .background(
                    depthIndex == 0
                        ? AnyShapeStyle(depthColor)
                        : AnyShapeStyle(depthColor.opacity(0.2)),
                    in: RoundedRectangle(cornerRadius: 3)
                )
                .accessibilityLabel(depthLabel)
        }
    }

    private var depthBadgeText: String {
        switch depthIndex {
        case 0:         return "S"
        case 1:         return "B"
        case let n?:    return "\(min(n + 1, 9))"
        case nil:       return "-"
        }
    }

    private var isExpiringContract: Bool {
        player.contractYearsRemaining <= 1
    }

    /// True when the player has a high cap commitment ($15M+ annual salary).
    private var isHighCapInvestment: Bool {
        player.annualSalary >= 15000
    }

    private var contractYearsLabel: some View {
        Text("\(player.contractYearsRemaining)yr")
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(isExpiringContract ? Color.backgroundPrimary : Color.textTertiary)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                isExpiringContract
                    ? Color.warning
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 3)
            )
            .overlay(
                isExpiringContract
                    ? RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.warning.opacity(0.6), lineWidth: 1)
                    : nil
            )
    }

    private var moraleIndicator: some View {
        Image(systemName: moraleSystemImage)
            .font(.system(size: 16))
            .foregroundStyle(moraleColor)
            .accessibilityLabel("Morale \(moraleLabel)")
    }

    private var healthIndicator: some View {
        Group {
            if player.isInjured {
                HStack(spacing: 2) {
                    Image(systemName: "cross.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.danger)
                    Text("\(player.injuryWeeksRemaining)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.danger)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.success)
            }
        }
        .accessibilityLabel(player.isInjured ? "Injured, \(player.injuryWeeksRemaining) weeks" : "Healthy")
    }

    private var developmentArrow: some View {
        Group {
            let trend = developmentTrend
            Image(systemName: trend.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(trend.color)
        }
        .accessibilityLabel("Development \(developmentTrend.label)")
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var depthColor: Color {
        switch depthIndex {
        case 0:     return .success   // starter = green
        case 1:     return .accentBlue // backup = blue
        default:    return .textTertiary // 3rd string or unknown = gray
        }
    }

    private var depthLabel: String {
        switch depthIndex {
        case 0:     return "Starter"
        case 1:     return "Backup"
        case 2:     return "Third string"
        default:    return "Reserve"
        }
    }

    private func depthRoleLabel(for index: Int) -> String {
        switch index {
        case 0:  return "Starter"
        case 1:  return "Backup"
        case 2:  return "3rd String"
        default: return "#\(index + 1)"
        }
    }

    /// Cap hit from the detailed Contract model (if available), otherwise falls back to annualSalary.
    private var capHitValue: Int {
        contract?.capHit ?? player.annualSalary
    }

    private var formattedCapHit: String {
        formatSalary(capHitValue)
    }

    private var formattedSalary: String {
        formatSalary(player.annualSalary)
    }

    /// Returns true when the contract provides a distinct cap hit that differs from base salary.
    private var showsSeparateCapHit: Bool {
        guard let contract else { return false }
        return contract.capHit != player.annualSalary
    }

    private func formatSalary(_ value: Int) -> String {
        let millions = Double(value) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(value)K"
        }
    }

    private var moraleColor: Color {
        switch player.morale {
        case 85...:   return .success
        case 70..<85: return .accentGold
        case 55..<70: return .warning
        default:      return .danger
        }
    }

    private var moraleLabel: String {
        switch player.morale {
        case 85...:   return "excellent"
        case 70..<85: return "good"
        case 55..<70: return "neutral"
        default:      return "low"
        }
    }

    private var moraleSystemImage: String {
        switch player.morale {
        case 85...:   return "face.smiling.fill"
        case 70..<85: return "face.smiling"
        case 55..<70: return "face.dashed"
        default:      return "face.dashed.fill"
        }
    }

    private var developmentTrend: DevelopmentTrend {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return .improving
        } else if peak.contains(player.age) {
            return .stable
        } else {
            return .declining
        }
    }

    private var potentialLabel: String {
        let pot = player.truePotential
        switch pot {
        case 90...:   return "Elite"
        case 80..<90: return "Star"
        case 70..<80: return "Good"
        case 60..<70: return "Avg"
        default:      return "Low"
        }
    }

    private var developmentPhaseLabel: String {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return "Rising"
        } else if peak.contains(player.age) {
            return "Prime"
        } else {
            return "Decline"
        }
    }

    private var accessibilityText: String {
        var parts = [
            player.fullName,
            player.position.rawValue,
            depthLabel,
            "overall \(player.overall)",
            "age \(player.age)",
            formattedSalary,
            "\(player.contractYearsRemaining) year\(player.contractYearsRemaining == 1 ? "" : "s") remaining",
        ]
        if player.isInjured {
            parts.append("injured \(player.injuryWeeksRemaining) weeks")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Roster Analysis Mode (#96, #98)

/// Analysis view modes for the roster list. Each mode adjusts which columns
/// PlayerRowView displays, enabling different analytical perspectives.
enum RosterAnalysisMode: String, CaseIterable, Identifiable {
    case overview
    case contracts
    case development
    case physical
    case attributes
    case depth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview:    return "Overview"
        case .contracts:   return "Contracts"
        case .development: return "Development"
        case .physical:    return "Physical"
        case .attributes:  return "Position Skills"
        case .depth:       return "Depth"
        }
    }

    var icon: String {
        switch self {
        case .overview:    return "list.bullet"
        case .contracts:   return "dollarsign.circle"
        case .development: return "chart.line.uptrend.xyaxis"
        case .physical:    return "figure.run"
        case .attributes:  return "figure.american.football"
        case .depth:       return "person.3.sequence"
        }
    }
}

// MARK: - Development Trend

enum DevelopmentTrend {
    case improving, stable, declining

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable:    return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .success
        case .stable:    return .accentGold
        case .declining: return .danger
        }
    }

    var label: String {
        switch self {
        case .improving: return "improving"
        case .stable:    return "stable"
        case .declining: return "declining"
        }
    }
}

// MARK: - Overall Color Helper (package-level for reuse)

func overallColor(for value: Int) -> Color {
    Color.forRating(value)
}

// MARK: - Preview

#Preview {
    List {
        PlayerRowView(player: Player(
            firstName: "Patrick",
            lastName: "Mahomes",
            position: .QB,
            age: 28,
            yearsPro: 7,
            positionAttributes: .quarterback(QBAttributes(
                armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                accuracyDeep: 87, pocketPresence: 92, scrambling: 80
            )),
            personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            morale: 85, contractYearsRemaining: 3, annualSalary: 45000
        ), depthIndex: 0)
        PlayerRowView(player: Player(
            firstName: "Tyreek",
            lastName: "Hill",
            position: .WR,
            age: 29,
            yearsPro: 8,
            positionAttributes: .wideReceiver(WRAttributes(
                routeRunning: 88, catching: 90, release: 92, spectacularCatch: 85
            )),
            personality: PlayerPersonality(archetype: .loneWolf, motivation: .stats),
            isInjured: true, injuryWeeksRemaining: 4, contractYearsRemaining: 2, annualSalary: 30000
        ), depthIndex: 1, analysisMode: .contracts)
        PlayerRowView(player: Player(
            firstName: "Myles",
            lastName: "Garrett",
            position: .DE,
            age: 28,
            yearsPro: 7,
            positionAttributes: .defensiveLine(DLAttributes(
                passRush: 96, blockShedding: 90, powerMoves: 88, finesseMoves: 91
            )),
            personality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
            contractYearsRemaining: 4, annualSalary: 25000
        ), depthIndex: 2, analysisMode: .attributes)
        PlayerRowView(player: Player(
            firstName: "Justin",
            lastName: "Tucker",
            position: .K,
            age: 34,
            yearsPro: 12,
            positionAttributes: .kicking(KickingAttributes(kickPower: 95, kickAccuracy: 98)),
            personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .loyalty),
            contractYearsRemaining: 1, annualSalary: 6000
        ), depthIndex: 0, analysisMode: .physical)
    }
}
