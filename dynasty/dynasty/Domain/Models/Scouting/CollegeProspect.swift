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

    // MARK: - Scouting Reports

    var scoutingReports: [ScoutingReport]

    // MARK: - Interview Results

    var interviewNotes: String?
    var interviewFootballIQ: Int?
    var interviewCharacterNotes: [String]?

    // MARK: - Evaluation Status

    var combineInvite: Bool
    var interviewCompleted: Bool
    var proDayCompleted: Bool
    var draftProjection: Int?
    var isDeclaringForDraft: Bool

    // MARK: - Team Interest & Mock Draft

    /// UUIDs of teams that have shown interest based on positional need matching.
    var teamInterest: [UUID]

    /// The pick number this prospect is projected to go in the latest mock draft (nil if undrafted).
    var mockDraftPickNumber: Int?

    /// The team abbreviation projected to draft this prospect in the latest mock.
    var mockDraftTeam: String?

    // MARK: - Combine Media

    /// Headline text if this prospect was mentioned in combine media coverage.
    var combineMediaMention: String?

    // MARK: - Prospect Flag

    var prospectFlag: ProspectFlag = ProspectFlag.none

    // MARK: - Computed Properties

    /// 6-tier scouting classification based on scouted overall rating.
    var scoutedTier: Int {
        guard let ovr = scoutedOverall else { return 6 }
        switch ovr {
        case 85...99: return 1  // Blue Chip
        case 75...84: return 2  // First Rounder
        case 65...74: return 3  // Day Two
        case 55...64: return 4  // Day Three
        case 45...54: return 5  // Priority FA
        default:      return 6  // Draftable
        }
    }

    /// Interest level based on how many teams have shown interest.
    var interestLevel: String {
        switch teamInterest.count {
        case 0: return "Unknown"
        case 1...2: return "Cold"
        case 3...4: return "Warm"
        default: return "Hot"
        }
    }

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
        scoutingReports: [ScoutingReport] = [],
        interviewNotes: String? = nil,
        interviewFootballIQ: Int? = nil,
        interviewCharacterNotes: [String]? = nil,
        combineInvite: Bool = false,
        interviewCompleted: Bool = false,
        proDayCompleted: Bool = false,
        draftProjection: Int? = nil,
        isDeclaringForDraft: Bool = true,
        teamInterest: [UUID] = [],
        mockDraftPickNumber: Int? = nil,
        mockDraftTeam: String? = nil
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
        self.scoutingReports = scoutingReports
        self.interviewNotes = interviewNotes
        self.interviewFootballIQ = interviewFootballIQ
        self.interviewCharacterNotes = interviewCharacterNotes
        self.combineInvite = combineInvite
        self.interviewCompleted = interviewCompleted
        self.proDayCompleted = proDayCompleted
        self.draftProjection = draftProjection
        self.isDeclaringForDraft = isDeclaringForDraft
        self.teamInterest = teamInterest
        self.mockDraftPickNumber = mockDraftPickNumber
        self.mockDraftTeam = mockDraftTeam
    }
}

// MARK: - Prospect Flag

enum ProspectFlag: String, Codable {
    case none, mustHave, sleeper, avoid
}
