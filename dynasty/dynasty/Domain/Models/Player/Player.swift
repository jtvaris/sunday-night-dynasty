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
    var injuryType: InjuryType?
    var injuryWeeksOriginal: Int

    /// Position familiarity: how well this player knows each position (0-100).
    /// Primary position starts at 100. Alternate positions grow through training.
    /// Key: Position.rawValue, Value: 0-100 proficiency
    var positionFamiliarity: [String: Int] = [:]

    /// Scheme familiarity: how well this player knows each scheme (0-100).
    /// Grows through practice and games under a coordinator running that scheme.
    /// Key: scheme rawValue (e.g., "WestCoast"), Value: 0-100
    var schemeFamiliarity: [String: Int] = [:]

    /// The alternate position currently being trained (if any).
    var trainingPosition: Position?

    /// Optional relationship to a Team via its ID.
    var teamID: UUID?

    var contractYearsRemaining: Int
    /// Annual salary in thousands (e.g., 15000 = $15M).
    var annualSalary: Int

    /// Whether this player has been franchise-tagged for the current season.
    var isFranchiseTagged: Bool

    /// The overall draft pick number (1-224) if this player was drafted, nil for UDFAs/veterans.
    var draftPickNumber: Int?

    /// Coaching staff's verbal assessment of this player's development ceiling.
    /// Stored as PotentialLabel.rawValue. Accuracy depends on coach quality and time with team.
    var assessedPotential: String?

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

    /// Get familiarity for a specific position (defaults to 0, primary is always 100).
    func familiarity(at position: Position) -> Int {
        if position == self.position { return 100 }
        return positionFamiliarity[position.rawValue] ?? 0
    }

    /// Get familiarity for a specific scheme (defaults to 0).
    func schemeFam(for scheme: String) -> Int {
        return schemeFamiliarity[scheme] ?? 0
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
        injuryType: InjuryType? = nil,
        injuryWeeksOriginal: Int = 0,
        teamID: UUID? = nil,
        contractYearsRemaining: Int = 4,
        annualSalary: Int = 750,
        isFranchiseTagged: Bool = false,
        draftPickNumber: Int? = nil,
        assessedPotential: String? = nil
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
        self.injuryType = injuryType
        self.injuryWeeksOriginal = injuryWeeksOriginal
        self.teamID = teamID
        self.contractYearsRemaining = contractYearsRemaining
        self.annualSalary = annualSalary
        self.isFranchiseTagged = isFranchiseTagged
        self.draftPickNumber = draftPickNumber
        self.assessedPotential = assessedPotential
    }
}
