import Foundation

// MARK: - Locker Room State

struct LockerRoomState: Codable {
    /// Overall team chemistry rating from 0 to 100.
    var teamChemistry: Int
    /// Sum of positive leader contributions to chemistry.
    var leadershipScore: Int
    /// Sum of negative toxic contributions dragging chemistry down.
    var toxicityScore: Int
    /// Human-readable log of recent events that affected chemistry.
    var recentEvents: [String]
}

// MARK: - Locker Room Engine

enum LockerRoomEngine {

    // MARK: - Calculate Chemistry

    /// Evaluates the full team chemistry based on player personalities, motivations,
    /// and how well players complement each other in the locker room.
    static func calculateChemistry(players: [Player]) -> LockerRoomState {
        var leadershipScore = 0
        var toxicityScore = 0
        var events: [String] = []

        for player in players {
            let archetype = player.personality.archetype

            switch archetype {
            case .teamLeader:
                // High-morale leaders give a strong chemistry boost
                let contribution = player.morale >= 70 ? 8 : 4
                leadershipScore += contribution
                if contribution >= 8 {
                    events.append("\(player.fullName) is leading the team with great energy.")
                }

            case .mentor:
                // Mentors uplift younger players; solid chemistry contributors
                let contribution = player.morale >= 60 ? 6 : 3
                leadershipScore += contribution
                if contribution >= 6 {
                    events.append("\(player.fullName) is mentoring teammates and building trust.")
                }

            case .dramaQueen:
                // Drama Queens create friction, especially when unhappy
                let penalty = player.morale < 50 ? 8 : 4
                toxicityScore += penalty
                if penalty >= 8 {
                    events.append("\(player.fullName) is stirring up drama in the locker room.")
                }

            case .fieryCompetitor:
                // Can be volatile — hurts chemistry when morale drops
                let penalty = player.morale < 45 ? 5 : 2
                toxicityScore += penalty
                if penalty >= 5 {
                    events.append("\(player.fullName)'s intensity is creating locker room tension.")
                }

            case .loneWolf:
                // Lone Wolves neither help nor hurt; they stay in their lane
                break

            case .feelPlayer:
                // Feel Players amplify the current mood — good when happy, bad when not
                if player.morale >= 75 {
                    leadershipScore += 3
                    events.append("\(player.fullName)'s high energy is lifting the room.")
                } else if player.morale < 45 {
                    toxicityScore += 3
                    events.append("\(player.fullName)'s low mood is bringing others down.")
                }

            case .steadyPerformer, .quietProfessional:
                // Stable presences that provide a small passive boost
                leadershipScore += 1

            case .classClown:
                // Keeps spirits up but can be a mild distraction
                leadershipScore += 2
                if player.morale < 40 {
                    toxicityScore += 2
                }
            }
        }

        // Motivation alignment: players with matching motivations bond better
        let motivationGroups = Dictionary(grouping: players, by: { $0.personality.motivation })
        for (motivation, group) in motivationGroups where group.count >= 3 {
            leadershipScore += 2
            events.append("Several \(motivation.rawValue.lowercased())-motivated players are bonding well.")
        }

        // Raw chemistry: base 50, add leadership, subtract toxicity
        let rawChemistry = 50 + leadershipScore - toxicityScore
        let teamChemistry = max(0, min(100, rawChemistry))

        return LockerRoomState(
            teamChemistry: teamChemistry,
            leadershipScore: leadershipScore,
            toxicityScore: toxicityScore,
            recentEvents: Array(events.prefix(8)) // cap log to 8 entries
        )
    }

    // MARK: - Apply Morale Effects

    /// Updates each player's morale based on team record, chemistry, contract situation,
    /// and their personality archetype.
    static func applyMoraleEffects(
        players: [Player],
        teamWins: Int,
        teamLosses: Int,
        chemistry: Int
    ) {
        let totalGames = teamWins + teamLosses
        let winRate = totalGames > 0 ? Double(teamWins) / Double(totalGames) : 0.5

        for player in players {
            var delta = 0

            // --- Team record impact ---
            if winRate >= 0.7 {
                delta += 5
            } else if winRate >= 0.5 {
                delta += 2
            } else if winRate < 0.35 {
                delta -= 4
            } else {
                delta -= 1
            }

            // --- Chemistry impact ---
            if chemistry >= 75 {
                delta += 3
            } else if chemistry >= 50 {
                delta += 1
            } else if chemistry < 35 {
                delta -= 3
            } else {
                delta -= 1
            }

            // --- Contract situation: underpaid players lose morale ---
            let marketValue = ContractEngine.estimateMarketValue(player: player)
            let payRatio = marketValue > 0 ? Double(player.annualSalary) / Double(marketValue) : 1.0
            if payRatio < 0.65 {
                // Significantly underpaid
                let contractPenalty = player.personality.motivation == .money ? -6 : -3
                delta += contractPenalty
            } else if payRatio >= 1.1 {
                // Overpaid or on a great deal
                let contractBonus = player.personality.motivation == .money ? 4 : 2
                delta += contractBonus
            }

            // --- Contract years remaining: upcoming free agency creates anxiety ---
            if player.contractYearsRemaining == 1 {
                if player.personality.motivation == .money {
                    delta -= 3 // Money-motivated players want security
                } else if player.personality.motivation == .loyalty {
                    delta -= 1
                }
            }

            // --- Personality modifiers ---
            switch player.personality.archetype {
            case .feelPlayer:
                // Feel Players swing more dramatically in both directions
                delta = Int((Double(delta) * 1.5).rounded())

            case .dramaQueen:
                // Drama Queens amplify the swing and react to bad situations harder
                if delta < 0 {
                    delta = Int((Double(delta) * 1.4).rounded())
                }

            case .steadyPerformer, .quietProfessional:
                // Stable archetypes absorb volatility
                delta = Int((Double(delta) * 0.6).rounded())

            case .loneWolf:
                // Lone Wolves are less affected by team morale dynamics
                delta = Int((Double(delta) * 0.7).rounded())

            default:
                break
            }

            // Apply clamped morale update
            player.morale = max(1, min(100, player.morale + delta))
        }
    }

    // MARK: - Weekly Morale Update

    /// Small weekly morale adjustments tied to the most recent game result.
    /// Streaks compound these effects for feel players.
    static func weeklyMoraleUpdate(
        players: [Player],
        wonLastGame: Bool,
        chemistry: Int
    ) {
        for player in players {
            var delta = 0

            // Base shift from win/loss
            if wonLastGame {
                delta += 3
            } else {
                delta -= 3
            }

            // Chemistry still has a mild weekly influence
            if chemistry >= 70 {
                delta += 1
            } else if chemistry < 40 {
                delta -= 1
            }

            // Personality-based weekly variance
            switch player.personality.archetype {
            case .feelPlayer:
                // Feel Players ride the emotional rollercoaster week to week
                delta = wonLastGame ? delta + 3 : delta - 3

            case .dramaQueen:
                // Drama Queens are extra volatile — swings are steeper
                delta = wonLastGame ? delta + 2 : delta - 4

            case .steadyPerformer, .quietProfessional:
                // Dampen the weekly swing significantly
                delta = Int((Double(delta) * 0.4).rounded())

            case .teamLeader, .mentor:
                // Leaders stay grounded; winning gives a small extra lift
                delta = wonLastGame ? delta + 1 : delta - 1

            case .fieryCompetitor:
                // Competitors hate losing more than they love winning
                delta = wonLastGame ? delta + 1 : delta - 3

            default:
                break
            }

            // Money-motivated players on expiring contracts feel losses more
            if player.personality.motivation == .money && player.contractYearsRemaining <= 1 {
                if !wonLastGame { delta -= 2 }
            }

            // Winning-motivated players get an extra morale kick from victories
            if player.personality.motivation == .winning {
                delta = wonLastGame ? delta + 2 : delta - 2
            }

            // Apply clamped morale update
            player.morale = max(1, min(100, player.morale + delta))
        }
    }

    // MARK: - Chemistry Color Helper

    /// Returns a string label for the chemistry level, used for display.
    static func chemistryLabel(_ chemistry: Int) -> String {
        switch chemistry {
        case 80...100: return "Elite"
        case 65..<80:  return "Strong"
        case 50..<65:  return "Average"
        case 35..<50:  return "Shaky"
        default:       return "Toxic"
        }
    }

    /// Bucketed morale tier for a single player.
    static func moraleTier(_ morale: Int) -> MoraleTier {
        switch morale {
        case 75...100: return .high
        case 45..<75:  return .medium
        default:       return .low
        }
    }

    enum MoraleTier: String {
        case high   = "High"
        case medium = "Medium"
        case low    = "Low"
    }
}
