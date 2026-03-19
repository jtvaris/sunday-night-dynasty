import Foundation
import SwiftData

@Model
final class Coach {
    var id: UUID
    var firstName: String
    var lastName: String
    var age: Int
    var role: CoachRole
    var offensiveScheme: OffensiveScheme?
    var defensiveScheme: DefensiveScheme?

    // Core Attributes (1-99)
    var playCalling: Int
    var playerDevelopment: Int
    var reputation: Int
    var adaptability: Int

    // Expanded Attributes (1-99)
    var gamePlanning: Int
    var scoutingAbility: Int
    var recruiting: Int
    var motivation: Int
    var discipline: Int
    var mediaHandling: Int
    var contractNegotiation: Int
    var moraleInfluence: Int

    // Coach Development System
    var potential: Int = 50
    var currentXP: Int = 0
    var promotedInSeason: Int?
    var mentorCoachID: UUID?
    var mentorshipOrigin: String?

    /// Annual salary in thousands (e.g. 2500 = $2.5M).
    var salary: Int

    /// Auto-generated coaching background / history blurb.
    var background: String

    /// Scheme expertise: how well this coach knows/teaches each scheme (0-100).
    /// Primary scheme starts at 80-95. Related schemes start at 40-60.
    /// Key: scheme rawValue, Value: 0-100
    var schemeExpertise: [String: Int] = [:]

    var personality: PersonalityArchetype
    var teamID: UUID?
    var yearsExperience: Int

    /// Get expertise for a specific scheme (baseline 20 for unknown schemes).
    func expertise(for scheme: String) -> Int {
        return schemeExpertise[scheme] ?? 20
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        age: Int,
        role: CoachRole,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        playCalling: Int = 50,
        playerDevelopment: Int = 50,
        reputation: Int = 50,
        adaptability: Int = 50,
        gamePlanning: Int = 50,
        scoutingAbility: Int = 50,
        recruiting: Int = 50,
        motivation: Int = 50,
        discipline: Int = 50,
        mediaHandling: Int = 50,
        contractNegotiation: Int = 50,
        moraleInfluence: Int = 50,
        potential: Int = 50,
        salary: Int = 500,
        background: String = "",
        personality: PersonalityArchetype = .quietProfessional,
        teamID: UUID? = nil,
        yearsExperience: Int = 0
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.age = age
        self.role = role
        self.offensiveScheme = offensiveScheme
        self.defensiveScheme = defensiveScheme
        self.playCalling = playCalling
        self.playerDevelopment = playerDevelopment
        self.reputation = reputation
        self.adaptability = adaptability
        self.gamePlanning = gamePlanning
        self.scoutingAbility = scoutingAbility
        self.recruiting = recruiting
        self.motivation = motivation
        self.discipline = discipline
        self.mediaHandling = mediaHandling
        self.contractNegotiation = contractNegotiation
        self.moraleInfluence = moraleInfluence
        self.potential = potential
        self.salary = salary
        self.background = background
        self.personality = personality
        self.teamID = teamID
        self.yearsExperience = yearsExperience
    }

    // MARK: - Coach Development Computed Properties

    /// Attribute ceiling derived from potential
    var attributeCeiling: Int {
        Int(Double(potential) * 0.65 + 35)
    }

    /// Whether coach is in adjustment period after promotion
    var isInAdjustmentPeriod: Bool {
        promotedInSeason != nil
    }

    /// Fuzzy potential label for UI
    func potentialLabel(seasonsOnTeam: Int) -> String {
        let noise = seasonsOnTeam >= 2 ? Int.random(in: -3...3) : Int.random(in: -10...10)
        let displayed = min(99, max(1, potential + noise))
        switch displayed {
        case 85...99: return "Elite Ceiling"
        case 70...84: return "High Ceiling"
        case 55...69: return "Solid Ceiling"
        case 40...54: return "Limited Upside"
        default:      return "Low Ceiling"
        }
    }

    // MARK: - Attribute Access Helpers

    func attributeValue(named name: String) -> Int {
        switch name {
        case "playCalling": return playCalling
        case "playerDevelopment": return playerDevelopment
        case "reputation": return reputation
        case "adaptability": return adaptability
        case "gamePlanning": return gamePlanning
        case "scoutingAbility": return scoutingAbility
        case "recruiting": return recruiting
        case "motivation": return motivation
        case "discipline": return discipline
        case "mediaHandling": return mediaHandling
        case "contractNegotiation": return contractNegotiation
        case "moraleInfluence": return moraleInfluence
        default: return 50
        }
    }

    func setAttributeValue(named name: String, value: Int) {
        switch name {
        case "playCalling": playCalling = value
        case "playerDevelopment": playerDevelopment = value
        case "reputation": reputation = value
        case "adaptability": adaptability = value
        case "gamePlanning": gamePlanning = value
        case "scoutingAbility": scoutingAbility = value
        case "recruiting": recruiting = value
        case "motivation": motivation = value
        case "discipline": discipline = value
        case "mediaHandling": mediaHandling = value
        case "contractNegotiation": contractNegotiation = value
        case "moraleInfluence": moraleInfluence = value
        default: break
        }
    }
}
