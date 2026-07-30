import Foundation
import SwiftData

@Model
final class Owner {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    var name: String
    var avatarID: String

    /// How many bad seasons the owner will tolerate before firing the coach (scale 1–10).
    var patience: Int

    /// Willingness to spend money (scale 1–99).
    var spendingWillingness: Int

    /// How much the owner interferes with football decisions (scale 1–99).
    var meddling: Int

    /// Whether the owner prioritises winning immediately over rebuilding.
    var prefersWinNow: Bool

    /// Current owner satisfaction with the franchise (0–100).
    var satisfaction: Int

    /// Total coaching & scouting staff budget in thousands (e.g. 25000 = $25M).
    /// Derived from spendingWillingness when the owner is created.
    var coachingBudget: Int

    /// Previous season's coaching budget in thousands, for showing budget change in UI.
    var previousCoachingBudget: Int

    /// R27: Dedicated scouting department budget in thousands (e.g. 4000 = $4M).
    /// Separate pot from `coachingBudget` — scout salaries draw from this one.
    /// Default keeps old saves valid (lightweight migration).
    var scoutingBudget: Int = 4_000

    /// R27: Previous season's scouting budget, for showing change in UI.
    var previousScoutingBudget: Int = 0

    /// R31: Dedicated medical department budget in thousands (e.g. 2500 = $2.5M).
    /// Team doctor, physio, and head trainer salaries draw from this pot.
    /// Default keeps old saves valid (lightweight migration).
    var medicalBudget: Int = 2_500

    /// R31: Previous season's medical budget, for showing change in UI.
    var previousMedicalBudget: Int = 0

    // MARK: - Facilities (§5.4)

    /// The club this owner runs (`Team.id`).
    ///
    /// `Team.owner` is a one-way relationship with no inverse, so an `Owner`
    /// row could not name its own franchise — which is exactly what
    /// `FacilityEngine.developmentMultiplier(teamID:owners:)` needs, since the
    /// offseason development pass holds a team id and a flat owner list, not a
    /// `Team`. `FacilityEngine.linkOwners` stamps this from the team side (and
    /// the medical resolver back-fills it lazily), so legacy saves heal
    /// themselves on the first pass. `nil` reads as "not linked yet" and every
    /// facility effect falls back to neutral. Default-value stored property,
    /// never in `init` -> safe lightweight migration.
    var teamID: UUID? = nil

    /// Training complex tier, 1-3 (`FacilityEngine.Tier`). Weight room, indoor
    /// field, sports-science staff — drives the development multiplier.
    ///
    /// **2 = league standard = every multiplier exactly 1.0**, which is why the
    /// default is 2 and not 1: an existing save loads at standard and behaves
    /// bit-for-bit as it did before facilities existed. Only a club that
    /// deliberately lets the building rot (1) or pays for the best in the
    /// league (3) moves off neutral. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var trainingFacilityLevel: Int = 2

    /// Medical wing tier, 1-3. Imaging, surgeons on call, load monitoring —
    /// drives injury FREQUENCY (`MedicalEngine.injuryCheck`). 2 = neutral.
    var medicalFacilityLevel: Int = 2

    /// Recovery centre tier, 1-3. Cryo, hydrotherapy, sleep programme — drives
    /// recovery SPEED (rehab weeks, rehab roll, weekly fatigue) and adds a
    /// small share of the development multiplier. 2 = neutral.
    var recoveryFacilityLevel: Int = 2

    /// `"male"` | `"female"` — the same two-value vocabulary `Coach.gender` and
    /// `FaceBucket.gender` use, because portrait matching is gender-strict here
    /// too: a female owner may only ever be handed one of the 12 female owner
    /// portraits, and `avatarID` may only ever be one of the `owner_f*`
    /// illustrations.
    ///
    /// The male default is load-bearing, not laziness. Every row written before
    /// this field existed was drawn from a male-only name pool, so reading an old
    /// save as male is not a guess — it is what the name says. Anything that is
    /// not `"female"` reads as male, exactly like `FacePersonGender(tag:)`.
    /// Stored property with an inline default → safe lightweight migration.
    var gender: String = "male"

    /// Id of this owner's AI portrait in the extras library
    /// (`owner_00000`…`owner_00095`, see `ExtrasCatalog`). Assigned once, at
    /// league generation / template import, as a deterministic function of
    /// (`id`, `gender`), or by `ExtrasCatalog.backfillOwnerFaces` on load for
    /// careers that predate the field. Stays `nil` when the extras did not ship,
    /// which renders the illustrated `avatarID` portrait instead.
    /// Optional stored property with a nil default → safe lightweight migration.
    var faceID: String? = nil

    init(
        id: UUID = UUID(),
        name: String,
        avatarID: String = "owner_m1",
        patience: Int = 5,
        spendingWillingness: Int = 50,
        meddling: Int = 30,
        prefersWinNow: Bool = false,
        satisfaction: Int = 70,
        coachingBudget: Int = 20_000,
        previousCoachingBudget: Int = 0,
        scoutingBudget: Int = 4_000,
        previousScoutingBudget: Int = 0,
        medicalBudget: Int = 2_500,
        previousMedicalBudget: Int = 0,
        gender: String = "male",
        faceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarID = avatarID
        self.patience = patience
        self.spendingWillingness = spendingWillingness
        self.meddling = meddling
        self.prefersWinNow = prefersWinNow
        self.satisfaction = satisfaction
        self.coachingBudget = coachingBudget
        self.previousCoachingBudget = previousCoachingBudget
        self.scoutingBudget = scoutingBudget
        self.previousScoutingBudget = previousScoutingBudget
        self.medicalBudget = medicalBudget
        self.previousMedicalBudget = previousMedicalBudget
        self.gender = gender
        self.faceID = faceID
    }
}
