import SwiftUI

struct PlayerDetailView: View {
    let player: Player

    var body: some View {
        List {
            overviewSection
            physicalSection
            mentalSection
            personalitySection
            contractSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(player.fullName)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sections

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent("Position") {
                positionLabel
            }
            LabeledContent("Age", value: "\(player.age)")
            LabeledContent("Experience") {
                Text(player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro) year\(player.yearsPro == 1 ? "" : "s") pro")
                    .foregroundStyle(.secondary)
            }
            AttributeRow(name: "Overall", value: player.overall)
            LabeledContent("Morale") {
                HStack(spacing: 6) {
                    moraleIcon
                    Text(moraleLabel)
                        .foregroundStyle(moraleColor)
                }
            }
            if player.isInjured {
                LabeledContent("Status") {
                    Label("Injured – \(player.injuryWeeksRemaining) wk\(player.injuryWeeksRemaining == 1 ? "" : "s")", systemImage: "cross.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var physicalSection: some View {
        Section("Physical Attributes") {
            AttributeRow(name: "Speed",        value: player.physical.speed)
            AttributeRow(name: "Acceleration", value: player.physical.acceleration)
            AttributeRow(name: "Strength",     value: player.physical.strength)
            AttributeRow(name: "Agility",      value: player.physical.agility)
            AttributeRow(name: "Stamina",      value: player.physical.stamina)
            AttributeRow(name: "Durability",   value: player.physical.durability)
        }
    }

    private var mentalSection: some View {
        Section("Mental Attributes") {
            AttributeRow(name: "Awareness",       value: player.mental.awareness)
            AttributeRow(name: "Decision Making",  value: player.mental.decisionMaking)
            AttributeRow(name: "Clutch",           value: player.mental.clutch)
            AttributeRow(name: "Work Ethic",       value: player.mental.workEthic)
            AttributeRow(name: "Coachability",     value: player.mental.coachability)
            AttributeRow(name: "Leadership",       value: player.mental.leadership)
        }
    }

    private var personalitySection: some View {
        Section("Personality") {
            LabeledContent("Archetype", value: archetypeDisplayName)
            LabeledContent("Motivation", value: player.personality.motivation.rawValue)
            if player.personality.isMentor {
                Label("Mentor influence on team", systemImage: "person.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if player.personality.isDramaticInMedia {
                Label("Can generate media drama", systemImage: "exclamationmark.bubble.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var contractSection: some View {
        Section("Contract") {
            LabeledContent("Years Remaining", value: "\(player.contractYearsRemaining)")
            LabeledContent("Annual Salary") {
                Text(formattedSalary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var positionLabel: some View {
        HStack(spacing: 6) {
            Text(player.position.rawValue)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(positionSideColor, in: RoundedRectangle(cornerRadius: 4))
            Text(player.position.side.rawValue)
                .foregroundStyle(.secondary)
        }
    }

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .blue
        case .defense:      return .red
        case .specialTeams: return Color(red: 0.75, green: 0.55, blue: 0.0)
        }
    }

    private var moraleLabel: String {
        switch player.morale {
        case 85...: return "Excellent (\(player.morale))"
        case 70..<85: return "Good (\(player.morale))"
        case 55..<70: return "Neutral (\(player.morale))"
        default:    return "Low (\(player.morale))"
        }
    }

    private var moraleColor: Color {
        overallColor(for: player.morale)
    }

    private var moraleIcon: some View {
        Image(systemName: moraleSystemImage)
            .foregroundStyle(moraleColor)
    }

    private var moraleSystemImage: String {
        switch player.morale {
        case 85...: return "face.smiling.fill"
        case 70..<85: return "face.smiling"
        case 55..<70: return "face.dashed"
        default:    return "face.dashed.fill"
        }
    }

    private var archetypeDisplayName: String {
        switch player.personality.archetype {
        case .teamLeader:        return "Team Leader"
        case .loneWolf:          return "Lone Wolf"
        case .feelPlayer:        return "Feel Player"
        case .steadyPerformer:   return "Steady Performer"
        case .dramaQueen:        return "Drama Queen"
        case .quietProfessional: return "Quiet Professional"
        case .mentor:            return "Mentor"
        case .fieryCompetitor:   return "Fiery Competitor"
        case .classClown:        return "Class Clown"
        }
    }

    private var formattedSalary: String {
        let millions = Double(player.annualSalary) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.2fM", millions)
        } else {
            return "$\(player.annualSalary)K"
        }
    }
}

// MARK: - AttributeRow

struct AttributeRow: View {
    let name: String
    let value: Int

    var body: some View {
        LabeledContent(name) {
            Text("\(value)")
                .fontWeight(.semibold)
                .foregroundStyle(overallColor(for: value))
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerDetailView(player: Player(
            firstName: "Patrick",
            lastName: "Mahomes",
            position: .QB,
            age: 28,
            yearsPro: 7,
            physical: PhysicalAttributes(
                speed: 72, acceleration: 78, strength: 65,
                agility: 80, stamina: 85, durability: 88
            ),
            mental: MentalAttributes(
                awareness: 94, decisionMaking: 92, clutch: 96,
                workEthic: 88, coachability: 82, leadership: 90
            ),
            positionAttributes: .quarterback(QBAttributes(
                armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                accuracyDeep: 87, pocketPresence: 92, scrambling: 80
            )),
            personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            morale: 90,
            contractYearsRemaining: 3,
            annualSalary: 45000
        ))
    }
}
