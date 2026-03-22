import Foundation

struct ScoutingReport: Codable {
    var prospectID: UUID
    var scoutID: UUID
    var scoutName: String
    var date: String
    var phase: ScoutingPhase = .combine
    var overallGrade: Int
    var potentialGrade: Int
    var strengthNotes: String
    var weaknessNotes: String
    var personalityNotes: String?
    var confidenceLevel: Double
    /// College production notes (e.g. "22 TDs this season", "3 INTs in last 4 games")
    var productionNotes: String?

    // MARK: - Grade-Based Evaluations (new system)

    /// Scout's letter grade assessment of each mental attribute.
    var mentalGrades: [String: LetterGrade]?

    /// Scout's letter grade assessment of each position skill.
    var positionSkillGrades: [String: LetterGrade]?

    /// Scout's overall grade for this prospect.
    var overallLetterGrade: LetterGrade?

    /// Scout's verbal potential assessment.
    var potentialLabel: PotentialLabel?
}
