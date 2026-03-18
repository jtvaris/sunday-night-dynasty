import SwiftUI

struct PlayerRowView: View {
    let player: Player
    /// Depth chart index: 0 = starter, 1 = backup, 2+ = 3rd string. nil = unknown.
    var depthIndex: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            // 1. Position badge
            positionBadge

            // 2. Depth indicator
            depthIndicator
                .frame(width: 10, alignment: .center)

            // 3. Name
            Text(player.fullName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .leading)

            Spacer(minLength: 2)

            // 4. Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24, alignment: .center)

            // 5. Cap Hit (salary)
            Text(formattedCapHit)
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .trailing)

            // 6. Contract years remaining (final year highlighted)
            contractYearsLabel
                .frame(width: 26, alignment: .center)

            // 7. OVR (large, color-coded)
            Text("\(player.overall)")
                .font(.callout.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .center)

            // 8. Development arrow
            developmentArrow
                .frame(width: 14, alignment: .center)

            // 9. Salary
            Text(formattedSalary)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(Color.textTertiary)
                .frame(width: 40, alignment: .trailing)

            // 10. Morale icon
            moraleIndicator
                .frame(width: 14, alignment: .center)

            // 11. Health status
            healthIndicator
                .frame(width: 20, alignment: .center)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Subviews

    private var positionBadge: some View {
        Text(player.position.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 24)
            .background(positionColor, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("\(player.position.rawValue), \(player.position.side.rawValue)")
    }

    private var depthIndicator: some View {
        Circle()
            .fill(depthColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel(depthLabel)
    }

    private var contractYearsLabel: some View {
        Text("\(player.contractYearsRemaining)yr")
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(player.contractYearsRemaining <= 1 ? Color.warning : Color.textTertiary)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(
                player.contractYearsRemaining <= 1
                    ? Color.warning.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 3)
            )
    }

    private var moraleIndicator: some View {
        Image(systemName: moraleSystemImage)
            .font(.system(size: 10))
            .foregroundStyle(moraleColor)
            .accessibilityLabel("Morale \(moraleLabel)")
    }

    private var healthIndicator: some View {
        Group {
            if player.isInjured {
                HStack(spacing: 1) {
                    Image(systemName: "cross.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.danger)
                    Text("\(player.injuryWeeksRemaining)")
                        .font(.system(size: 8))
                        .monospacedDigit()
                        .foregroundStyle(Color.danger)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.success)
            }
        }
        .accessibilityLabel(player.isInjured ? "Injured, \(player.injuryWeeksRemaining) weeks" : "Healthy")
    }

    private var developmentArrow: some View {
        Group {
            let trend = developmentTrend
            Image(systemName: trend.icon)
                .font(.system(size: 10, weight: .bold))
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

    private var formattedCapHit: String {
        let millions = Double(player.annualSalary) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(player.annualSalary)K"
        }
    }

    private var formattedSalary: String {
        let millions = Double(player.annualSalary) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(player.annualSalary)K"
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
        ), depthIndex: 1)
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
        ), depthIndex: 2)
        PlayerRowView(player: Player(
            firstName: "Justin",
            lastName: "Tucker",
            position: .K,
            age: 34,
            yearsPro: 12,
            positionAttributes: .kicking(KickingAttributes(kickPower: 95, kickAccuracy: 98)),
            personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .loyalty),
            contractYearsRemaining: 1, annualSalary: 6000
        ), depthIndex: 0)
    }
}
