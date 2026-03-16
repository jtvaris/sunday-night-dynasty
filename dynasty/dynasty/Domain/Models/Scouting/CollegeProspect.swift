import Foundation
import SwiftData

@Model
final class CollegeProspect {
    var id: UUID
    var firstName: String
    var lastName: String
    var college: String
    var position: Position
    var age: Int
    var height: Int
    var weight: Int

    // MARK: - True Attributes (hidden from player)

    var truePhysical: PhysicalAttributes
    var trueMental: MentalAttributes
    var truePositionAttributes: PositionAttributes
    var truePersonality: PlayerPersonality
    var truePotential: Int

    // MARK: - Scouted Attributes (what the player sees)

    var scoutedOverall: Int?
    var scoutedPotential: Int?
    var scoutedPersonality: PersonalityArchetype?
    var scoutGrade: String?

    // MARK: - Combine Results

    var fortyTime: Double?
    var benchPress: Int?
    var verticalJump: Double?
    var broadJump: Int?
    var shuttleTime: Double?
    var coneDrill: Double?

    // MARK: - Evaluation Status

    var interviewCompleted: Bool
    var proDayCompleted: Bool
    var draftProjection: Int?
    var isDeclaringForDraft: Bool

    // MARK: - Computed Properties

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Overall rating as a weighted average of physical (60%) and mental (40%) attributes.
    var trueOverall: Int {
        let physicalAvg = truePhysical.average
        let mentalAvg = trueMental.average
        return Int((physicalAvg * 0.6 + mentalAvg * 0.4).rounded())
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        college: String,
        position: Position,
        age: Int,
        height: Int,
        weight: Int,
        truePhysical: PhysicalAttributes = .random(),
        trueMental: MentalAttributes = .random(),
        truePositionAttributes: PositionAttributes,
        truePersonality: PlayerPersonality,
        truePotential: Int = Int.random(in: 40...99),
        scoutedOverall: Int? = nil,
        scoutedPotential: Int? = nil,
        scoutedPersonality: PersonalityArchetype? = nil,
        scoutGrade: String? = nil,
        fortyTime: Double? = nil,
        benchPress: Int? = nil,
        verticalJump: Double? = nil,
        broadJump: Int? = nil,
        shuttleTime: Double? = nil,
        coneDrill: Double? = nil,
        interviewCompleted: Bool = false,
        proDayCompleted: Bool = false,
        draftProjection: Int? = nil,
        isDeclaringForDraft: Bool = true
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.college = college
        self.position = position
        self.age = age
        self.height = height
        self.weight = weight
        self.truePhysical = truePhysical
        self.trueMental = trueMental
        self.truePositionAttributes = truePositionAttributes
        self.truePersonality = truePersonality
        self.truePotential = truePotential
        self.scoutedOverall = scoutedOverall
        self.scoutedPotential = scoutedPotential
        self.scoutedPersonality = scoutedPersonality
        self.scoutGrade = scoutGrade
        self.fortyTime = fortyTime
        self.benchPress = benchPress
        self.verticalJump = verticalJump
        self.broadJump = broadJump
        self.shuttleTime = shuttleTime
        self.coneDrill = coneDrill
        self.interviewCompleted = interviewCompleted
        self.proDayCompleted = proDayCompleted
        self.draftProjection = draftProjection
        self.isDeclaringForDraft = isDeclaringForDraft
    }
}
