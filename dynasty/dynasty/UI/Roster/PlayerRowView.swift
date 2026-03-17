import SwiftUI

struct PlayerRowView: View {
    let player: Player

    var body: some View {
        HStack(spacing: 8) {
            positionBadge

            // Name column
            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(experienceLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(minWidth: 100, alignment: .leading)

            Spacer(minLength: 4)

            // Age
            Text("\(player.age)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .center)

            // Overall (large, color-coded)
            Text("\(player.overall)")
                .font(.callout.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .center)

            // Contract salary + years
            VStack(alignment: .trailing, spacing: 0) {
                Text(formattedSalary)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                Text("\(player.contractYearsRemaining)yr")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 48, alignment: .trailing)

            // Morale indicator
            moraleIndicator
                .frame(width: 14, alignment: .center)

            // Health status
            healthIndicator
                .frame(width: 20, alignment: .center)

            // Development trend
            developmentArrow
                .frame(width: 14, alignment: .center)
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

    private var moraleIndicator: some View {
        Circle()
            .fill(moraleColor)
            .frame(width: 8, height: 8)
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

    private var experienceLabel: String {
        player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro)yr pro"
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
            "overall \(player.overall)",
            "age \(player.age)",
            formattedSalary,
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
        ))
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
        ))
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
        ))
        PlayerRowView(player: Player(
            firstName: "Justin",
            lastName: "Tucker",
            position: .K,
            age: 34,
            yearsPro: 12,
            positionAttributes: .kicking(KickingAttributes(kickPower: 95, kickAccuracy: 98)),
            personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .loyalty),
            contractYearsRemaining: 1, annualSalary: 6000
        ))
    }
}
