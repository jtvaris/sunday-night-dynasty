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

    // MARK: - Top-30 Visits

    /// UUIDs of teams that have used a Top-30 visit on this prospect.
    /// Empty by default. Filled by `ScoutingEngine.conductTop30Visit`.
    var top30VisitedByTeams: [UUID] = []

    // MARK: - Medical & Character Risk Flags

    /// Medical concerns surfaced during scouting (combine medical, top-30 visit, or generation).
    /// `nil` means no flags reported. Examples: "ACL repair 2024", "Chronic shoulder".
    var medicalConcerns: [String]?

    /// Off-field / character red flags. `nil` means no flags reported.
    /// Examples: "Off-field arrest", "Failed drug test", "Practice habits".
    var redFlags: [String]?

    // MARK: - Combine Anthropometrics

    /// Hand size in inches (8.0 - 11.5). Position-specific: QB premium.
    var handSize: Double = 9.5

    /// Arm length in inches (30 - 37). Position-specific: OL/DB premium.
    var armLength: Double = 32.5

    /// Wingspan in inches (70 - 90). Position-specific: DB/DL premium.
    var wingspan: Double = 78.0

    // MARK: - Hometown (FA Drama Storylines)

    /// Hometown state (e.g. "California"). Carried over to Player on draft for hometown storylines.
    var hometownState: String?

    /// Hometown city (e.g. "Long Beach"). Carried over to Player on draft for hometown storylines.
    var hometownCity: String?

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

    /// R27: Name of the scout who filed the most recent report, for the
    /// "scouted by X" attribution line on prospect cards.
    var latestScoutName: String? {
        scoutingReports.last?.scoutName
    }

    /// R27: Confidence of the most recent report (0.0-1.0), for the accuracy indicator.
    var latestReportConfidence: Double? {
        scoutingReports.last?.confidenceLevel
    }

    // MARK: - College Production
    //
    // Derived deterministically from `truePotential` + `truePositionAttributes`,
    // which is the same talent signal that drives `scoutedOverallGrade`. This
    // means a prospect's college production already correlates with their NFL
    // grade — flashy production reflects underlying talent, not the other way
    // around. Surfacing it here makes that pipeline visible to the GM.

    enum CollegeProductionTier: String {
        case elite       = "Elite"
        case aboveAvg    = "Above Avg"
        case average     = "Average"
        case belowAvg    = "Below Avg"
    }

    /// Number of seasons started in college (1–4). High-talent prospects start earlier.
    var collegeYearsStarted: Int {
        let base = max(1, min(3, age - 19))
        if truePotential >= 88 { return min(4, base + 1) }
        if truePotential <= 60 { return max(1, base - 1) }
        return base
    }

    /// College production tier — Elite/Above Avg/Average/Below Avg. Combines true
    /// position-attribute average (60%) and potential ceiling (40%).
    var collegeProductionTier: CollegeProductionTier {
        let attrOvr = Double(truePositionAttributes.overall)
        let combined = attrOvr * 0.6 + Double(truePotential) * 0.4
        switch combined {
        case 88...:    return .elite
        case 78..<88:  return .aboveAvg
        case 65..<78:  return .average
        default:       return .belowAvg
        }
    }

    /// Position-specific representative stat-line (e.g. "3,420 yds · 28 TD" for QB).
    /// Numbers scale with `collegeProductionTier` so they read naturally.
    var collegeStatLine: String {
        let tier = collegeProductionTier
        let yearsStarted = collegeYearsStarted
        // Per-tier multipliers applied to a position baseline.
        let tierMultiplier: Double
        switch tier {
        case .elite:    tierMultiplier = 1.30
        case .aboveAvg: tierMultiplier = 1.10
        case .average:  tierMultiplier = 0.92
        case .belowAvg: tierMultiplier = 0.72
        }

        func scaled(_ baseline: Double) -> Int {
            Int((baseline * tierMultiplier * Double(yearsStarted) / 3.0).rounded())
        }

        switch position {
        case .QB:
            return "\(scaled(3000)) pass yds · \(scaled(26)) TD · \(scaled(8)) INT"
        case .RB, .FB:
            return "\(scaled(1100)) rush yds · \(scaled(11)) TD"
        case .WR:
            return "\(scaled(1080)) rec yds · \(scaled(9)) TD"
        case .TE:
            return "\(scaled(720)) rec yds · \(scaled(7)) TD"
        case .LT, .LG, .C, .RG, .RT:
            return "\(scaled(33)) starts · \(scaled(7)) sacks allowed"
        case .DE, .DT:
            return "\(scaled(58)) tkl · \(scaled(8)) sacks · \(scaled(13)) TFL"
        case .OLB, .MLB:
            return "\(scaled(95)) tkl · \(scaled(4)) sacks · \(scaled(2)) INT"
        case .CB:
            return "\(scaled(46)) tkl · \(scaled(13)) PD · \(scaled(3)) INT"
        case .FS, .SS:
            return "\(scaled(82)) tkl · \(scaled(8)) PD · \(scaled(3)) INT"
        case .K:
            return "\(scaled(22))/\(scaled(28)) FG · \(scaled(40)) XP"
        case .P:
            return "\(scaled(43)) yd avg · \(scaled(28)) inside-20"
        }
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

        // 7. Red flags cap risk upward — character/off-field concerns make any prospect riskier.
        let redFlagCount = redFlags?.count ?? 0
        if redFlagCount > 0 {
            riskScore += 2 + redFlagCount  // 1 flag = +3, 2 flags = +4
        }

        // Classify
        // If any red flag exists, cap minimum risk at .highCeiling — never .safePick.
        if riskScore >= 4 || (riskScore >= 3 && hasBigCeiling) || redFlagCount >= 2 {
            return .boomOrBust
        } else if riskScore >= 2 || hasBigCeiling || redFlagCount >= 1 {
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
