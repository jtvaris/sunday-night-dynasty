import Foundation

// MARK: - CollegeProspect (HARNESS STANDALONE — assembled by sync_sources.sh)
//
// The shipped `CollegeProspect` is a SwiftData `@Model` that drags in SwiftUI
// (Color on the risk/trajectory enums), GradeRange, ScoutingReport and the whole
// scouting graph — none of which the harness can compile. But `DraftClassBuilder`
// only ever touches its STORED fields plus the production / overall MATH, and that
// math is exactly what the `draftclass` scenario validates.
//
// So this file supplies the storage (harness-owned scaffolding: plain `var`s with
// the same names and the same init labels the builder calls) and splices the math
// block VERBATIM out of the repo `Domain/Models/Scouting/CollegeProspect.swift`:
// `CollegeProductionTier` / `CollegeCompetitionLevel` / `DevelopmentArchetype`,
// `collegeYearsStarted`, `collegeProductionTier`, `productionTier(forScore:)`,
// `collegeStatLine` / `statLine(position:tier:yearsStarted:)`, and — the one that
// matters most — `trueOverall` / `overallValue(position:physical:mental:)`.
//
// That means the harness can never measure a *retyped* overall formula or a
// retyped production-tier threshold: if the repo changes one, the next sync picks
// it up (and if the repo's anchors move, the sync fails loudly). Same fail-closed
// contract as SimPlayer.harness.swift.
final class CollegeProspect {

    // MARK: Identity / body (init-carried — mirrors the repo init's argument order)
    var id: UUID
    var firstName: String
    var lastName: String
    var college: String
    var position: Position
    var age: Int
    var height: Int
    var weight: Int

    /// Phase 4 face library. The synced `DraftClassBuilder` writes it; the
    /// harness stub `FaceLibrary` always hands back `nil`, so the balance
    /// numbers are untouched (see GameModels.harness.swift).
    var faceID: String? = nil

    // MARK: True attributes
    var truePhysical: PhysicalAttributes
    var trueMental: MentalAttributes
    var truePositionAttributes: PositionAttributes
    var truePersonality: PlayerPersonality
    var truePotential: Int

    // MARK: Combine results (written by the synced ScoutingEngine combine slice)
    var fortyTime: Double?
    var benchPress: Int?
    var verticalJump: Double?
    var broadJump: Int?
    var shuttleTime: Double?
    var coneDrill: Double?
    var positionDrillGrade: String?
    var combineInvite: Bool = false

    // MARK: Anthropometrics
    var handSize: Double = 9.5
    var armLength: Double = 32.5
    var wingspan: Double = 78.0

    // MARK: Risk flags
    var medicalConcerns: [String]?
    var redFlags: [String]?

    // MARK: Hometown (written by the synced `DraftClassBuilder` via HometownGenerator)
    var hometownState: String?
    var hometownCity: String?

    // MARK: Projection
    var draftProjection: Int?

    // MARK: Declaration (read/written by the synced `generateDeclarations` slice)
    // Same default as the repo model: a prospect is declared unless the
    // declaration pass says otherwise.
    var isDeclaringForDraft: Bool = true
    var mockDraftPickNumber: Int? = nil

    var fullName: String { "\(firstName) \(lastName)" }

    // MARK: Generator v2 fields (inline defaults, never in init — repo convention)
    var trueLearning: Int = 55
    var trueCompetitiveness: Int = 55
    var nflReadiness: Int = 60
    var developmentArchetypeRaw: String? = nil
    var collegeYearsStartedStored: Int = 0
    var collegeCompetitionLevelRaw: String? = nil
    var collegeProductionScore: Int = 0
    var collegeProductionTierStored: String? = nil
    var collegeStatLineStored: String? = nil
    var generatorVersion: Int = 0

    // MARK: - Repo math (spliced verbatim on every sync)

    // @@SPLICE:PRODUCTION@@

    // MARK: - Init
    //
    // Same argument order and labels as the repo initializer for the parameters
    // `DraftClassBuilder` actually passes; everything else keeps its default.
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
        draftProjection: Int? = nil
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
        self.draftProjection = draftProjection
    }
}
