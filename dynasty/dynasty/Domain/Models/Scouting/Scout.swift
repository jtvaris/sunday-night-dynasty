import Foundation
import SwiftData

@Model
final class Scout {
    var id: UUID
    var firstName: String
    var lastName: String
    var teamID: UUID?
    var positionSpecialization: Position?
    var accuracy: Int
    var personalityRead: Int
    var potentialRead: Int
    var experience: Int

    /// Annual salary in thousands (e.g. 200 = $200K).
    var salary: Int

    /// The scout's role in the scouting department hierarchy.
    var scoutRole: ScoutRole

    /// Number of Pro Days attended this year (max 5 per scout).
    var proDaysAttended: Int = 0

    /// How many seasons this scout has been in their current role/region.
    /// Scouts with 2+ seasons get a familiarity accuracy bonus.
    var seasonsInRole: Int = 0

    // MARK: - Computed Properties

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        teamID: UUID? = nil,
        positionSpecialization: Position? = nil,
        accuracy: Int = 50,
        personalityRead: Int = 50,
        potentialRead: Int = 50,
        experience: Int = 1,
        salary: Int = 100,
        scoutRole: ScoutRole = .regionalScout1
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.teamID = teamID
        self.positionSpecialization = positionSpecialization
        self.accuracy = accuracy
        self.personalityRead = personalityRead
        self.potentialRead = potentialRead
        self.experience = experience
        self.salary = salary
        self.scoutRole = scoutRole
    }
}
