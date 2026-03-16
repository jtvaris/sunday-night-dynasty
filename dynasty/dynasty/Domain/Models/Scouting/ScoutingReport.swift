import Foundation

struct ScoutingReport: Codable {
    var prospectID: UUID
    var scoutID: UUID
    var scoutName: String
    var date: String
    var overallGrade: Int
    var potentialGrade: Int
    var strengthNotes: String
    var weaknessNotes: String
    var personalityNotes: String?
    var confidenceLevel: Double
}
