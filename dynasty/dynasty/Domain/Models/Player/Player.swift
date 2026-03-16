import Foundation
import SwiftData

@Model
final class Player {
    var id: UUID
    var firstName: String
    var lastName: String
    var position: Position
    var age: Int
    var yearsPro: Int

    var physical: PhysicalAttributes
    var mental: MentalAttributes
    var positionAttributes: PositionAttributes

    var personality: PlayerPersonality

    /// Hidden true potential ceiling (1-99). Not directly visible to the user;
    /// discovered over time through scouting and player development.
    var truePotential: Int

    var morale: Int
    var fatigue: Int
    var isInjured: Bool
    var injuryWeeksRemaining: Int

    /// Optional relationship to a Team via its ID.
    var teamID: UUID?

    var contractYearsRemaining: Int
    /// Annual salary in thousands (e.g., 15000 = $15M).
    var annualSalary: Int

    // MARK: - Computed Properties

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Overall rating as a weighted average of physical (60%) and mental (40%) attributes.
    var overall: Int {
        let physicalAvg = physical.average
        let mentalAvg = mental.average
        return Int((physicalAvg * 0.6 + mentalAvg * 0.4).rounded())
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        position: Position,
        age: Int,
        yearsPro: Int = 0,
        physical: PhysicalAttributes = .random(),
        mental: MentalAttributes = .random(),
        positionAttributes: PositionAttributes,
        personality: PlayerPersonality,
        truePotential: Int = Int.random(in: 50...99),
        morale: Int = 70,
        fatigue: Int = 0,
        isInjured: Bool = false,
        injuryWeeksRemaining: Int = 0,
        teamID: UUID? = nil,
        contractYearsRemaining: Int = 4,
        annualSalary: Int = 750
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.position = position
        self.age = age
        self.yearsPro = yearsPro
        self.physical = physical
        self.mental = mental
        self.positionAttributes = positionAttributes
        self.personality = personality
        self.truePotential = truePotential
        self.morale = morale
        self.fatigue = fatigue
        self.isInjured = isInjured
        self.injuryWeeksRemaining = injuryWeeksRemaining
        self.teamID = teamID
        self.contractYearsRemaining = contractYearsRemaining
        self.annualSalary = annualSalary
    }
}
