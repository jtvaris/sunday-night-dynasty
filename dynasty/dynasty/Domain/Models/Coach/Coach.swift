import Foundation
import SwiftData

@Model
final class Coach {
    var id: UUID
    var firstName: String
    var lastName: String
    var age: Int
    var role: CoachRole
    var offensiveScheme: OffensiveScheme?
    var defensiveScheme: DefensiveScheme?

    // Core Attributes (1-99)
    var playCalling: Int
    var playerDevelopment: Int
    var reputation: Int
    var adaptability: Int

    // Expanded Attributes (1-99)
    var gamePlanning: Int
    var scoutingAbility: Int
    var recruiting: Int
    var motivation: Int
    var discipline: Int
    var mediaHandling: Int
    var contractNegotiation: Int
    var moraleInfluence: Int

    // Coach Development System
    var potential: Int = 50
    var currentXP: Int = 0
    var promotedInSeason: Int?
    var mentorCoachID: UUID?
    var mentorshipOrigin: String?

    /// The season year when this coach was hired onto the current team.
    /// Used to calculate seasons on team. Defaults to 0 (unknown/legacy data).
    var hireSeasonYear: Int = 0

    /// Remaining years on the coach's contract. Decremented each offseason.
    /// Defaults to 3 for newly hired coaches.
    var contractYearsRemaining: Int = 3

    /// Annual salary in thousands (e.g. 2500 = $2.5M).
    var salary: Int

    /// Auto-generated coaching background / history blurb.
    var background: String

    /// Scheme expertise: how well this coach knows/teaches each scheme (0-100).
    /// Primary scheme starts at 80-95. Related schemes start at 40-60.
    /// Key: scheme rawValue, Value: 0-100
    var schemeExpertise: [String: Int] = [:]

    var personality: PersonalityArchetype
    var teamID: UUID?
    var yearsExperience: Int

    /// Players this coach previously coached on other teams. Used by CoachReunionMatcher
    /// during free agency to surface reunion-discount storylines.
    var coacheePlayerIDs: [UUID] = []

    /// Phase 4: id of this coach's portrait in the pre-generated face library
    /// (`face_00000`…`face_03583`, see `FaceLibrary`). Coaches draw from the
    /// coach-age half of the pool — and, per `gender` below, from the matching
    /// gender half of that. Assigned at league generation, when a candidate is
    /// hired, or by `WeekAdvancer.backfillLegacyFaces`; stays `nil` when no face
    /// of this coach's gender is available, which renders the placeholder photo.
    /// Optional stored property with a nil default → safe lightweight migration.
    var faceID: String? = nil

    /// `true` once the coach has left coaching for good (the 65+ retirement in
    /// `WeekAdvancer`). The row is kept forever — coaching trees, history and
    /// portraits still read it — exactly like a retired player's row.
    ///
    /// It exists because "unemployed" and "gone" used to be the same state
    /// (`teamID == nil`), which made the coach half of the face pool leak: a
    /// retired coach can never coach again, yet `FaceLibrary.backfill` re-claimed
    /// his portrait on every advance, so a career accumulated hundreds of dead
    /// rows holding faces. Now retirement releases the face and this flag keeps
    /// the reconciliation pass from taking it back.
    /// Stored property with an inline default → safe lightweight migration.
    var isRetired: Bool = false

    /// `"male"` | `"female"` — the same two-value vocabulary `FaceBucket.gender`
    /// uses, because portrait matching is gender-strict: a female coach may only
    /// ever be handed a face out of the female half of the library.
    ///
    /// The male default is load-bearing, not laziness. Every row written before
    /// this field existed is male — the game had no female coaches at all — and
    /// the same convention holds one layer down, where a face bucket generated
    /// before the female range simply has no `gender` key and decodes as male.
    /// Template HC/OC/DC and support staff stay male by construction too: they
    /// anonymize real male coaches (`ANONYMIZATION_SPEC.md`).
    /// Stored property with an inline default → safe lightweight migration.
    var gender: String = "male"

    /// `gender` as the enum the bundled placeholder photographs are tagged with
    /// (`CoachAvatars.maleAvatars` / `femaleAvatars`).
    ///
    /// A shim on the model rather than a string comparison in the view layer:
    /// `PersonFaceView.init(coach:)` is where a nil `faceID` turns into a
    /// `coach_m*`/`coach_f*` photo, and it should not be the place that decides
    /// what an unrecognised gender string means. Anything that is not
    /// `"female"` reads as male, exactly like `FacePersonGender(tag:)`.
    var avatarGender: CoachAvatarInfo.Gender {
        gender == "female" ? .female : .male
    }

    /// Get expertise for a specific scheme (baseline 20 for unknown schemes).
    func expertise(for scheme: String) -> Int {
        return schemeExpertise[scheme] ?? 20
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        age: Int,
        role: CoachRole,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        playCalling: Int = 50,
        playerDevelopment: Int = 50,
        reputation: Int = 50,
        adaptability: Int = 50,
        gamePlanning: Int = 50,
        scoutingAbility: Int = 50,
        recruiting: Int = 50,
        motivation: Int = 50,
        discipline: Int = 50,
        mediaHandling: Int = 50,
        contractNegotiation: Int = 50,
        moraleInfluence: Int = 50,
        potential: Int = 50,
        salary: Int = 500,
        background: String = "",
        personality: PersonalityArchetype = .quietProfessional,
        teamID: UUID? = nil,
        yearsExperience: Int = 0
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.age = age
        self.role = role
        self.offensiveScheme = offensiveScheme
        self.defensiveScheme = defensiveScheme
        self.playCalling = playCalling
        self.playerDevelopment = playerDevelopment
        self.reputation = reputation
        self.adaptability = adaptability
        self.gamePlanning = gamePlanning
        self.scoutingAbility = scoutingAbility
        self.recruiting = recruiting
        self.motivation = motivation
        self.discipline = discipline
        self.mediaHandling = mediaHandling
        self.contractNegotiation = contractNegotiation
        self.moraleInfluence = moraleInfluence
        self.potential = potential
        self.salary = salary
        self.background = background
        self.personality = personality
        self.teamID = teamID
        self.yearsExperience = yearsExperience
    }

    // MARK: - Coach Development Computed Properties

    /// Attribute ceiling derived from potential
    var attributeCeiling: Int {
        Int(Double(potential) * 0.65 + 35)
    }

    /// Whether coach is in adjustment period after promotion
    var isInAdjustmentPeriod: Bool {
        promotedInSeason != nil
    }

    /// Fuzzy potential label for UI
    func potentialLabel(seasonsOnTeam: Int) -> String {
        let noise = seasonsOnTeam >= 2 ? Int.random(in: -3...3) : Int.random(in: -10...10)
        let displayed = min(99, max(1, potential + noise))
        switch displayed {
        case 85...99: return "Elite Ceiling"
        case 70...84: return "High Ceiling"
        case 55...69: return "Solid Ceiling"
        case 40...54: return "Limited Upside"
        default:      return "Low Ceiling"
        }
    }

    // MARK: - Attribute Access Helpers

    func attributeValue(named name: String) -> Int {
        switch name {
        case "playCalling": return playCalling
        case "playerDevelopment": return playerDevelopment
        case "reputation": return reputation
        case "adaptability": return adaptability
        case "gamePlanning": return gamePlanning
        case "scoutingAbility": return scoutingAbility
        case "recruiting": return recruiting
        case "motivation": return motivation
        case "discipline": return discipline
        case "mediaHandling": return mediaHandling
        case "contractNegotiation": return contractNegotiation
        case "moraleInfluence": return moraleInfluence
        default: return 50
        }
    }

    func setAttributeValue(named name: String, value: Int) {
        switch name {
        case "playCalling": playCalling = value
        case "playerDevelopment": playerDevelopment = value
        case "reputation": reputation = value
        case "adaptability": adaptability = value
        case "gamePlanning": gamePlanning = value
        case "scoutingAbility": scoutingAbility = value
        case "recruiting": recruiting = value
        case "motivation": motivation = value
        case "discipline": discipline = value
        case "mediaHandling": mediaHandling = value
        case "contractNegotiation": contractNegotiation = value
        case "moraleInfluence": moraleInfluence = value
        default: break
        }
    }
}
