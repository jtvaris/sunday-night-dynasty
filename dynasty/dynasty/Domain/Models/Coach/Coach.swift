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

    // Attributes (1-99)
    var playCalling: Int
    var playerDevelopment: Int
    var reputation: Int
    var adaptability: Int

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
        self.personality = personality
        self.teamID = teamID
        self.yearsExperience = yearsExperience
    }
}
