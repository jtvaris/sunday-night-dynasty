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

    /// Annual salary in thousands (e.g. 2500 = $2.5M).
    var salary: Int

    /// Auto-generated coaching background / history blurb.
    var background: String

    var personality: PersonalityArchetype
    var teamID: UUID?
    var yearsExperience: Int

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
        self.salary = salary
        self.background = background
        self.personality = personality
        self.teamID = teamID
        self.yearsExperience = yearsExperience
    }
}
