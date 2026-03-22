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

    var scoutedOverall: Int?          // Legacy — kept for backward compat, use scoutedOverallGrade instead
    var scoutedPotential: Int?        // Legacy — use scoutedPotentialLabel instead
    var scoutedPersonality: PersonalityArchetype?
    var scoutGrade: String?           // Legacy letter grade from scoutedOverall

    // MARK: - Grade-Based Scouting (new system)

    /// Overall prospect grade as a range that narrows with more scout reports.
    var scoutedOverallGrade: GradeRange?

    /// Per-attribute mental grades keyed by abbreviation ("AWR", "DEC", "WRK", "CLT", "COA", "LDR").
    var scoutedMentalGrades: [String: GradeRange]?

    /// Per-attribute position skill grades keyed by skill name.
    var scoutedPositionGrades: [String: GradeRange]?

    /// Verbal potential assessment — accuracy depends on staff quality and scout reports.
    var scoutedPotentialLabel: PotentialLabel?

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

    // MARK: - Manual Tier Override

    /// When set, overrides the computed tier derived from scoutedOverall.
    var manualTier: Int?

    // MARK: - Prospect Flag

    var prospectFlag: ProspectFlag = ProspectFlag.none

    // MARK: - Computed Properties

    /// Always returns a grade — uses scoutedOverallGrade if available, otherwise converts
    /// from legacy scoutedOverall or scoutGrade. This ensures all views show grades, not numbers.
    var effectiveOverallGrade: GradeRange? {
        if let grade = scoutedOverallGrade { return grade }
        if let ovr = scoutedOverall {
            let lg = LetterGrade.from(numericValue: ovr)
            return GradeRange(grade: lg)
        }
        if let gradeStr = scoutGrade, let lg = LetterGrade(rawValue: gradeStr) {
            return GradeRange(grade: lg)
        }
        return nil
    }

    /// Display text for the overall grade — always a letter grade, never a number.
    var overallGradeDisplay: String {
        effectiveOverallGrade?.displayText ?? "?"
    }

    /// 6-tier scouting classification. Uses manualTier if overridden, otherwise computed from scoutedOverall.
    var scoutedTier: Int {
        if let manual = manualTier { return manual }
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

    /// Number of scout reports filed for this prospect (0-3+ scale).
    var scoutReportCount: Int {
        scoutingReports.count
    }

    /// Confidence level label based on number of scouting reports.
    var scoutConfidenceLabel: String {
        switch scoutingReports.count {
        case 0:  return "No Intel"
        case 1:  return "Low"
        case 2:  return "Medium"
        default: return "High"
        }
    }

    /// Filled/empty dot string representing scouting confidence (max 3 dots).
    var scoutConfidenceDots: String {
        let filled = min(scoutingReports.count, 3)
        let empty = 3 - filled
        return String(repeating: "\u{25CF}", count: filled) + String(repeating: "\u{25CB}", count: empty)
    }

    /// Overall rating as a weighted average of physical (60%) and mental (40%) attributes.
    var trueOverall: Int {
        let physicalAvg = truePhysical.average
        let mentalAvg = trueMental.average
        return Int((physicalAvg * 0.6 + mentalAvg * 0.4).rounded())
    }

    // MARK: - Boom/Bust Risk Indicator

    /// Risk classification based on age, position, scouting variance, personality, and potential spread.
    var riskLevel: ProspectRiskLevel {
        guard let ovr = scoutedOverall else { return .unknown }

        var riskScore = 0 // Higher = riskier

        // 1. Age-based risk — younger prospects have higher ceilings but more uncertainty
        if age <= 20 {
            riskScore += 2
        } else if age <= 21 {
            riskScore += 1
        }

        // 2. Position-based risk — some positions are inherently riskier transitions to NFL
        switch position {
        case .QB:
            riskScore += 2  // QB is the hardest transition
        case .WR, .CB:
            riskScore += 1  // Skill positions with steep learning curves
        case .LT, .LG, .C, .RG, .RT:
            break            // OL transitions are more predictable
        default:
            break
        }

        // 3. Variance between scout report grades (if multiple reports exist)
        if scoutingReports.count >= 2 {
            let grades = scoutingReports.map { $0.overallGrade }
            let maxGrade = grades.max() ?? 0
            let minGrade = grades.min() ?? 0
            let variance = maxGrade - minGrade
            if variance >= 15 { riskScore += 3 }
            else if variance >= 8 { riskScore += 2 }
            else if variance >= 4 { riskScore += 1 }
        }

        // 4. Gap between scouted overall and scouted potential — big ceiling adds risk
        let potentialGap: Int
        if let pot = scoutedPotential {
            potentialGap = pot - ovr
        } else {
            potentialGap = 0
        }
        let hasBigCeiling = potentialGap >= 15

        if hasBigCeiling {
            riskScore += 3  // Large gap = volatile prospect
        } else if potentialGap >= 8 {
            riskScore += 1
        }

        // 5. Personality-based consistency
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

        // 6. Low confidence in scouting reports
        if !scoutingReports.isEmpty {
            let avgConfidence = scoutingReports.map { $0.confidenceLevel }.reduce(0, +) / Double(scoutingReports.count)
            if avgConfidence < 0.5 { riskScore += 1 }
        }

        // Classify
        if riskScore >= 4 || (riskScore >= 3 && hasBigCeiling) {
            return .boomOrBust
        } else if riskScore >= 2 || hasBigCeiling {
            return .highCeiling
        } else {
            return .safePick
        }
    }

    // MARK: - Stock Trajectory

    /// Determines whether the prospect's stock is rising, falling, or steady
    /// based on multiple scouting reports and pre/post-combine grade changes.
    var stockTrajectory: StockTrajectory {
        // Need at least scouting data to determine trajectory
        guard scoutedOverall != nil else { return .newOnBoard }

        // Method 1: Multiple scouting reports — compare chronologically by phase weight
        if scoutingReports.count >= 2 {
            let phaseOrder: [ScoutingPhase] = [.collegeSeason, .seniorBowl, .combine, .proDay, .personalWorkout]
            let sorted = scoutingReports.sorted { a, b in
                let ai = phaseOrder.firstIndex(of: a.phase) ?? 0
                let bi = phaseOrder.firstIndex(of: b.phase) ?? 0
                return ai < bi
            }
            let earlier = sorted.prefix(sorted.count / 2)
            let later = sorted.suffix(sorted.count - sorted.count / 2)
            let earlyAvg = earlier.map(\.overallGrade).reduce(0, +) / earlier.count
            let lateAvg = later.map(\.overallGrade).reduce(0, +) / later.count
            let diff = lateAvg - earlyAvg

            if diff >= 4 { return .rising }
            if diff <= -4 { return .falling }
            return .steady
        }

        // Method 2: Pre-combine vs current grade
        if let preGrade = preCombineGrade, let currentGrade = scoutGrade, preGrade != currentGrade {
            let preRank = LetterGrade(rawValue: preGrade)?.rank ?? 0
            let curRank = LetterGrade(rawValue: currentGrade)?.rank ?? 0
            if curRank > preRank { return .rising }
            if curRank < preRank { return .falling }
            return .steady
        }

        // Single report, no pre-combine data — too early to tell
        if scoutingReports.count == 1 { return .newOnBoard }

        return .steady
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

// MARK: - Stock Trajectory

enum StockTrajectory: String {
    case rising      = "Rising"
    case falling     = "Falling"
    case steady      = "Steady"
    case newOnBoard  = "New"

    var icon: String {
        switch self {
        case .rising:     return "arrow.up.right"
        case .falling:    return "arrow.down.right"
        case .steady:     return "arrow.right"
        case .newOnBoard: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .rising:     return .success
        case .falling:    return .danger
        case .steady:     return .textSecondary
        case .newOnBoard: return .accentGold
        }
    }
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
