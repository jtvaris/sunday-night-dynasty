import Foundation
import SwiftData
import SwiftUI

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

    /// Position drill grade (F through A+). Estimated from position-specific drills at combine.
    /// This is an imprecise evaluation — real skill may differ significantly.
    var positionDrillGrade: String?

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

    // MARK: - Pre-Combine Snapshot

    /// Scout grade captured before combine results are applied, used to show grade change arrows.
    var preCombineGrade: String?

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

    // MARK: - Boom/Bust Risk Indicator

    /// Risk classification based on scouting report variance, personality consistency, and potential spread.
    var riskLevel: ProspectRiskLevel {
        guard scoutedOverall != nil else { return .unknown }

        var riskScore = 0 // Higher = riskier

        // 1. Variance between scout report grades (if multiple reports exist)
        if scoutingReports.count >= 2 {
            let grades = scoutingReports.map { $0.overallGrade }
            let maxGrade = grades.max() ?? 0
            let minGrade = grades.min() ?? 0
            let variance = maxGrade - minGrade
            if variance >= 20 { riskScore += 3 }
            else if variance >= 12 { riskScore += 2 }
            else if variance >= 6 { riskScore += 1 }
        }

        // 2. Gap between scouted overall and scouted potential
        if let ovr = scoutedOverall, let pot = scoutedPotential {
            let gap = pot - ovr
            if gap >= 20 { riskScore += 2 }
            else if gap >= 12 { riskScore += 1 }
        }

        // 3. Personality-based consistency
        if let personality = scoutedPersonality {
            if personality == .feelPlayer || personality == .dramaQueen {
                riskScore += 2
            } else if personality == .fieryCompetitor || personality == .classClown {
                riskScore += 1
            }
            if personality == .steadyPerformer || personality == .quietProfessional {
                riskScore -= 1
            }
        }

        // 4. Low confidence in scouting reports
        if !scoutingReports.isEmpty {
            let avgConfidence = scoutingReports.map { $0.confidenceLevel }.reduce(0, +) / Double(scoutingReports.count)
            if avgConfidence < 0.5 { riskScore += 1 }
        }

        // Classify
        let hasBigCeiling = (scoutedPotential ?? 0) - (scoutedOverall ?? 0) >= 15
        if riskScore >= 4 {
            return .boomOrBust
        } else if riskScore >= 2 && hasBigCeiling {
            return .highCeiling
        } else if riskScore <= 1 {
            return .safePick
        } else {
            return .highCeiling
        }
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

// MARK: - Prospect Risk Level

enum ProspectRiskLevel: String {
    case safePick    = "Safe Pick"
    case highCeiling = "High Ceiling"
    case boomOrBust  = "Boom or Bust"
    case unknown     = "Unknown"

    var color: Color {
        switch self {
        case .safePick:    return .success
        case .highCeiling: return .accentGold
        case .boomOrBust:  return .danger
        case .unknown:     return .textTertiary
        }
    }

    var icon: String {
        switch self {
        case .safePick:    return "checkmark.shield.fill"
        case .highCeiling: return "arrow.up.right.circle.fill"
        case .boomOrBust:  return "bolt.fill"
        case .unknown:     return "questionmark.circle"
        }
    }
}
