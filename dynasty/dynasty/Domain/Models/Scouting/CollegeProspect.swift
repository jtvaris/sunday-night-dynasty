import Foundation
import SwiftData
import SwiftUI

@Model
final class CollegeProspect {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<CollegeProspect>([\.careerID])

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

    /// Which instrument produced the personality read currently on the card
    /// (`PersonalitySource.rawValue`). `nil` means "unknown provenance": either
    /// nothing has read him yet, or the row predates this field.
    ///
    /// The card used to claim "From your interview" for a read that a routine
    /// scout report had quietly re-rolled on top of the interview's answer
    /// (#185). Storing the source is what lets the writer refuse a weaker
    /// instrument and lets the UI attribute the line honestly.
    ///
    /// Stored property with an INLINE default, never an `init` parameter, so the
    /// migration stays lightweight.
    var scoutedPersonalitySourceRaw: String? = nil

    /// Typed view of `scoutedPersonalitySourceRaw`. Kept here beside its storage
    /// rather than down in the computed-properties section on purpose: that
    /// section is the block the balance harness splices verbatim, and it must
    /// stay free of types the harness does not compile.
    /// `ScoutingEngine.recordPersonalityRead` is the only setter in the build.
    var scoutedPersonalitySource: PersonalitySource? {
        get { scoutedPersonalitySourceRaw.flatMap { PersonalitySource(rawValue: $0) } }
        set { scoutedPersonalitySourceRaw = newValue?.rawValue }
    }

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

    /// Who ran the meeting ("HC Mike Dawson", "Chief Scout R. Collins").
    /// The interview section used to render its findings with no attribution at
    /// all, which made a good read and a bad read look identical — the whole
    /// point of a low-quality interviewer is that you should discount him.
    /// Optional stored property with a nil default, never in `init` → safe
    /// lightweight migration (see the generator-v2 block below).
    var interviewedByName: String? = nil

    /// When it happened, in prose ("Combine \u{00B7} 2027"). `nil` on an
    /// interview conducted before attribution was recorded.
    var interviewedOnLabel: String? = nil

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

    // MARK: - Unified GM Mark
    //
    // The board used to carry FOUR parallel opinions of the same prospect —
    // `prospectFlag` (must-have / sleeper / avoid), the star in
    // `UserProspectGradeStore`, the `prospectWatchlist` bookmark set, and the
    // `UserGrade` — each with a different downstream reach: the prep card read
    // two of them, the combine table wrote a third, the pro-day screen read a
    // fourth. Marking a man on one screen therefore did nothing on the next.
    //
    // `userMarkTier` is the one verdict. Everything the user can express about
    // where a prospect sits on HIS board goes through it, and the legacy fields
    // are still written (see `setUserMark`) so nothing that has not been ported
    // yet goes blind.
    //
    // Both are stored properties with INLINE defaults and are deliberately NOT
    // `init` parameters — the project's lightweight-migration convention.

    /// The GM's own verdict: `"elite"` / `"target"` / `"depth"` / `"avoid"`.
    /// Empty means unmarked. Read through `userMark`, written through
    /// `setUserMark(_:note:)` — never assigned raw, so the legacy mirrors and
    /// the note stay in step.
    var userMarkTier: String = ""

    /// One line of the GM's own reasoning, written beside the tier on the
    /// prospect's card. Empty when he has not written one.
    var userMarkNote: String = ""

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

    // MARK: - Face

    /// Phase 4: id of this prospect's portrait in the pre-generated face
    /// library (see `FaceLibrary`). Drawn with `FaceLibrary.previewFace` at
    /// class generation — a class is 350 prospects of which a handful ever
    /// sign, so a prospect does NOT reserve his face. `DraftEngine`'s
    /// prospect → player copy claims it for real at that point, and the player
    /// keeps the face he was scouted with whenever it is still free.
    /// Optional stored property with a nil default → safe lightweight migration.
    var faceID: String? = nil

    // MARK: - Generator v2 fields
    //
    // All of the following are top-level stored properties with inline defaults
    // and are deliberately NOT part of `init` — the project's lightweight
    // migration convention (see `Player.swift`). They are written after
    // construction by `DraftClassBuilder`.

    /// How fast the player absorbs playbooks and schemes (25–99).
    /// Correlated r ≈ 0.6 with `awareness` but not identical to it: awareness
    /// stays the in-sim game-IQ, `trueLearning` drives scheme install speed.
    var trueLearning: Int = 55

    /// Fighter mentality (25–99) — how this prospect answers adversity.
    /// Generated by `DraftClassBuilder` from work ethic / clutch / personality
    /// archetype (`MentalAttributeModel.competitiveness`), surfaced to scouts as
    /// the `CMP` mental grade, and copied into `Player.competitiveness` at the
    /// draft boundary. Phase 2, `docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.1.
    var trueCompetitiveness: Int = 55

    /// How ready the prospect is to contribute in the NFL on day one (25–95).
    /// Drives rookie attribute scaling and initial scheme familiarity.
    var nflReadiness: Int = 60

    /// Development archetype rawValue (`Polished` / `Balanced` / `Raw`).
    /// Read through `developmentArchetype`.
    var developmentArchetypeRaw: String? = nil

    /// Seasons started in college (1–4), generated rather than derived from age.
    /// `0` means "not generated" — `collegeYearsStarted` falls back to the
    /// legacy age-derived estimate for in-flight saves.
    var collegeYearsStartedStored: Int = 0

    /// Level of college competition rawValue (`P5` / `G5` / `FCS`).
    var collegeCompetitionLevelRaw: String? = nil

    /// Noisy college production signal (20–99). Correlates with `trueOverall`
    /// but imperfectly, so workout-warrior and production-machine profiles both
    /// exist. `0` means "not generated".
    var collegeProductionScore: Int = 0

    /// Production tier rawValue derived from `collegeProductionScore`.
    var collegeProductionTierStored: String? = nil

    /// Pre-rendered college stat line. `nil` falls back to the legacy computed line.
    var collegeStatLineStored: String? = nil

    // MARK: - Usage suppression / hidden gems (task #181)
    //
    // Two more stored properties with INLINE defaults, never `init` parameters.

    /// Why this prospect never got on the field — "sat behind a first-round
    /// pick", "lost the job in fall camp and never got it back". EMPTY is the
    /// normal case and is the single source of truth for
    /// `collegeSampleStatus`: a man with a burial reason has a production
    /// record the market cannot read, however good he actually is.
    ///
    /// The narrative hook exists because the mechanic is otherwise invisible:
    /// "89 snaps" alone reads as a bad player, and the whole point of the
    /// buried cohort is that a real minority of them are not.
    var collegeBurialReason: String = ""

    /// Snaps played in his last college season. Only meaningful on a
    /// `limitedSample` prospect (a full-season starter's snap count is not
    /// modelled and stays `0`); it is what the stat line is rendered from and
    /// what `DraftClassBuilder` derives his production SCORE from.
    var collegeSnapsPlayed: Int = 0

    /// Version of the generator that produced this prospect. `0` = legacy
    /// (pre-overhaul) class, `2` = `DraftClassBuilder`.
    var generatorVersion: Int = 0

    // MARK: - Market realism v2 (task #78)
    //
    // Three more stored properties with INLINE defaults, never `init`
    // parameters — same lightweight-migration convention as the block above.

    /// The MARKET's error on this man, in OVR points: `consensus − truth`.
    ///
    /// Drawn once at generation (`DraftClassBuilder.consensusError`) and stored,
    /// so the public board is a *wrong* board in a way that is stable across
    /// relaunches. Positive means the consensus is high on him (the top-10 bust
    /// waiting to happen), negative means the room is late on him (the day-3
    /// steal your own scouting can find). `0` on a legacy class, which reads as
    /// the old perfect-information market.
    var consensusErrorStored: Int = 0

    /// The projected round the class was BORN with, before four months of
    /// Showcase / combine / mock / pro-day drift moved it.
    ///
    /// `draftProjection − projectionAtGeneration` is the market arrow the board
    /// rows render: it is the MEDIA's own movement, distinct from
    /// `stockTrajectory`, which is what YOUR scouts have changed their mind
    /// about. `0` means "not recorded" (legacy row) and suppresses the arrow.
    var projectionAtGeneration: Int = 0

    /// Where this prospect sits in the January declaration window
    /// (`DeclarationStatus.rawValue`). Empty = the window has not been held for
    /// him yet, which for an underclassman means genuinely UNDECLARED — the
    /// autumn board used to show every underclassman as a lock because
    /// `isDeclaringForDraft` carries a model default of `true`.
    var declarationStatusRaw: String = ""

    // MARK: - Computed Properties

    /// What the MARKET believes this prospect's current level is (25–99).
    ///
    /// Public information by construction — it is the number the consensus
    /// board, the mock draft and the projected round are all built from. It is
    /// never rendered raw: every user-facing surface goes through
    /// `ProspectFog`, which turns it into a grade band.
    var consensusOverall: Int {
        min(99, max(25, trueOverall + consensusErrorStored))
    }

    /// The market's read on the ceiling. One scouting industry watching one set
    /// of tape: a consensus that is high on a man is high on both his numbers,
    /// so the same error carries (`AIDraftPerception`'s own fat-tail rule).
    var consensusPotential: Int {
        min(99, max(consensusOverall, truePotential + consensusErrorStored))
    }

    /// How far the media board has moved him since the class was generated, in
    /// rounds. Positive = risen (a lower round number), negative = slid.
    /// `nil` when the class predates the market-arrow fields.
    var marketMove: Int? {
        guard projectionAtGeneration > 0, let now = draftProjection, now > 0 else { return nil }
        return projectionAtGeneration - now
    }

    /// Typed accessor for the January declaration window.
    var declarationStatus: DeclarationStatus {
        DeclarationStatus(rawValue: declarationStatusRaw) ?? .undecided
    }

    /// The age at which a prospect has no college eligibility left and is in the
    /// draft whether he likes it or not. Shared with
    /// `ScoutingEngine.generateDeclarations` so the board and the window agree
    /// on who is even allowed to withdraw.
    static let seniorAge = 22

    /// Whether this man still has a decision to make.
    var isUnderclassman: Bool { age < CollegeProspect.seniorAge }

    /// PUBLIC read on how likely an undeclared underclassman is to come out.
    ///
    /// Built from class year and college PRODUCTION — both things that happened
    /// on television — and deliberately NOT from `trueOverall`, which is the
    /// hidden rating the whole fog exists to keep off the screen. `nil` for a
    /// senior (no decision to make) and for anybody whose window has closed.
    var declarationLikelihood: DeclarationLikelihood? {
        guard isUnderclassman, declarationStatus == .undecided else { return nil }
        let tier = collegeProductionTier
        let starts = collegeYearsStarted
        // A junior with two years of production behind him is a lock; a
        // redshirt sophomore who has just broken out is the genuine coin flip.
        if age == CollegeProspect.seniorAge - 1 {
            switch tier {
            case .elite, .aboveAvg: return .likely
            case .average:          return starts >= 2 ? .likely : .leaning
            case .belowAvg:         return .undecided
            }
        }
        switch tier {
        case .elite:    return .leaning
        case .aboveAvg: return starts >= 2 ? .leaning : .undecided
        default:        return .undecided
        }
    }

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
    ///
    /// Cut points follow `DraftClassBuilder.talentTarget` at the band boundaries
    /// (#10 ≈ 84 · #28 ≈ 79 · #99 ≈ 72.5 · #189 ≈ 69 · #295 ≈ 65, the last two
    /// including the post-#224 taper), so a tier means the same thing here as it
    /// does in `BigBoardView.boardTier`. The old 85/75/65/55/45 cuts were tuned
    /// against the pre-overhaul class, which spanned only overall 60–69 — on the
    /// generator-v2 curve tier 3 would swallow rounds 3 through 7 and tiers 5/6
    /// were unreachable.
    var scoutedTier: Int {
        if let manual = manualTier { return manual }
        guard let ovr = scoutedOverall else { return 6 }
        switch ovr {
        case 84...99: return 1  // Blue Chip
        case 79...83: return 2  // First Rounder
        case 73...78: return 3  // Day Two (Rd 2-3)
        case 69...72: return 4  // Day Three (Rd 4-5)
        case 65...68: return 5  // Late rounds / priority FA
        default:      return 6  // Draftable
        }
    }

    // MARK: - Unified mark accessors

    /// The one verdict every scouting surface keys off.
    var userMark: ProspectMarkTier {
        ProspectMarkTier(rawValue: userMarkTier) ?? ProspectMarkTier.none
    }

    /// Whether the GM has said anything at all about this man.
    var isMarked: Bool { userMark != ProspectMarkTier.none }

    /// Sets the unified mark, and mirrors it onto the legacy systems so the
    /// screens and engines that still read `prospectFlag` or the star store
    /// agree with the board instead of contradicting it.
    ///
    /// Passing `nil` for `note` leaves an existing note alone — clearing a note
    /// is `setUserMark(tier, note: "")`. Clearing the mark itself (`.none`)
    /// also drops the note, because a note with no verdict is orphaned text.
    func setUserMark(_ tier: ProspectMarkTier, note: String? = nil) {
        userMarkTier = tier.rawValue
        if tier == ProspectMarkTier.none {
            userMarkNote = ""
        } else if let note {
            userMarkNote = String(note.prefix(200))
        }

        // Back-compat mirrors. Deliberately one-way: the unified tier is the
        // source of truth, these are written so nothing reading them goes stale.
        prospectFlag = tier.legacyFlag
        let store = UserProspectGradeStore.shared
        if store.isStarred(id) != tier.isBoardPositive {
            store.toggleStar(for: id)
        }
    }

    /// First-read migration of the legacy marks onto `userMarkTier`.
    ///
    /// Only ever fills a row that has no unified mark yet, so it cannot undo a
    /// verdict the user has since given. Mapping (per the draft-flow contract):
    /// an avoid flag wins over everything, a must-have flag / star / watchlist
    /// bookmark becomes `target`, and the old "sleeper" flag — a man you are
    /// tracking but do not rate as a target — becomes `depth`.
    ///
    /// Returns the number of rows changed so the caller knows whether to save.
    @discardableResult
    static func migrateLegacyMarks(
        in prospects: [CollegeProspect],
        watchlistIDs: Set<String> = []
    ) -> Int {
        let store = UserProspectGradeStore.shared
        var changed = 0
        for prospect in prospects where prospect.userMarkTier.isEmpty {
            let migrated: ProspectMarkTier
            switch prospect.prospectFlag {
            case .avoid:
                migrated = .avoid
            case .mustHave:
                migrated = .target
            case .sleeper:
                migrated = .depth
            case .none:
                let starred = store.isStarred(prospect.id)
                    || watchlistIDs.contains(prospect.id.uuidString)
                migrated = starred ? .target : ProspectMarkTier.none
            }
            guard migrated != ProspectMarkTier.none else { continue }
            // Write the raw fields rather than `setUserMark`: the legacy values
            // are the SOURCE here, so mirroring them back would be a no-op at
            // best and a star toggle race at worst.
            prospect.userMarkTier = migrated.rawValue
            prospect.prospectFlag = migrated.legacyFlag
            changed += 1
        }
        return changed
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

    /// #184: the raw-tally trio that used to live here — `scoutReportCount`,
    /// `scoutConfidenceLabel`, `scoutConfidenceDots` — is retired. All three
    /// counted `scoutingReports.count`, which includes the inherited
    /// `Previous Staff` row `applyPreScoutedData` stamps on the top of every
    /// class, so every screen that picked one up told the user this building
    /// had watched ~250 men it had never seen, and disagreed with the prospect
    /// card next to it. The counters the UI is allowed to show are
    /// `ProspectFog.ownReportCount` (number) and `ProspectFog.confidenceDots`
    /// (glyphs), both capped by `ScoutEvaluationBudget.maxReportsPerProspect`.
    /// Read `scoutingReports` directly only when you mean every piece of paper
    /// on file, the previous regime's included.

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
    // Generator v2 stores production as a *noisy signal* (`collegeProductionScore`)
    // written by `DraftClassBuilder`: real information about the prospect, but
    // imperfect, so workout-warrior (high talent / low production) and
    // production-machine (inverse) profiles both occur. The computed properties
    // below fall back to the legacy `truePotential`-derived estimate whenever the
    // stored fields are unset (in-flight saves with a pre-overhaul class).

    enum CollegeProductionTier: String {
        case elite       = "Elite"
        case aboveAvg    = "Above Avg"
        case average     = "Average"
        case belowAvg    = "Below Avg"
    }

    /// Whether the production record is a season of football or a handful of
    /// snaps (task #181, "hidden gems").
    ///
    /// Deliberately a SEPARATE enum rather than a fifth `CollegeProductionTier`
    /// case: a tier answers "how good was he when he played", and a buried
    /// prospect has a perfectly real (low) answer to that — the extra thing the
    /// board needs to say is that the answer is drawn from 89 snaps. Folding it
    /// into the tier would also have collapsed the two axes into one column on
    /// every board that renders a tier chip.
    enum CollegeSampleStatus: String {
        case full          = ""
        case limitedSample = "Limited Sample"
    }

    /// Level of college competition faced. Easier competition inflates production.
    enum CollegeCompetitionLevel: String {
        case powerFive = "P5"
        case groupOfFive = "G5"
        case fcs = "FCS"
    }

    /// Development archetype — how far the prospect's technique has come.
    enum DevelopmentArchetype: String {
        case polished = "Polished"
        case balanced = "Balanced"
        case raw      = "Raw"
    }

    var collegeCompetitionLevel: CollegeCompetitionLevel? {
        collegeCompetitionLevelRaw.flatMap { CollegeCompetitionLevel(rawValue: $0) }
    }

    var developmentArchetype: DevelopmentArchetype? {
        developmentArchetypeRaw.flatMap { DevelopmentArchetype(rawValue: $0) }
    }

    /// Whether this row was written by the generator that owns the college
    /// production fields. Everything below branches on THIS rather than on a
    /// `0`/`nil` sentinel in an individual field, because `0` is now a legal
    /// generated value for `collegeYearsStartedStored` (a buried prospect who
    /// never started a game).
    var hasGeneratedProduction: Bool { generatorVersion >= 2 }

    /// Number of seasons started in college (0–4). `0` only occurs on a
    /// `limitedSample` prospect.
    var collegeYearsStarted: Int {
        if hasGeneratedProduction { return max(0, min(4, collegeYearsStartedStored)) }
        if collegeYearsStartedStored > 0 { return collegeYearsStartedStored }
        // LEGACY (generatorVersion < 2) — NEUTRAL, not derived.
        //
        // This branch used to read `truePotential`, i.e. the hidden ceiling the
        // entire fog exists to keep off the screen, and leak it into a field
        // rendered unfogged on the prospect card: an 88-potential prospect
        // printed one more year of starts than an identical 60-potential one,
        // for free, before a single scout was spent. The public surface is now
        // a flat age-derived estimate that knows nothing it should not.
        // Migration: task #171 backfills these rows, after which the branch is
        // dead (see docs/SWIFTDATA_MIGRATION_PLAN.md).
        return max(1, min(3, age - 19))
    }

    /// College production tier — Elite/Above Avg/Average/Below Avg.
    var collegeProductionTier: CollegeProductionTier {
        if let stored = collegeProductionTierStored,
           let tier = CollegeProductionTier(rawValue: stored) {
            return tier
        }
        // LEGACY (generatorVersion < 2) — NEUTRAL, not derived. Same leak as
        // above and a worse one: the old fallback was 60 % true position
        // attributes + 40 % `truePotential`, which made the production chip a
        // near-direct readout of the hidden grade on every pre-overhaul save.
        // A legacy row now reads "Average" and says nothing at all, which is
        // the honest answer for a row that never recorded a production number.
        // Migration: task #171.
        return .average
    }

    /// Whether the production record is a handful of snaps rather than a
    /// season. Derived from the burial reason so there is exactly one field
    /// that can turn it on.
    var collegeSampleStatus: CollegeSampleStatus {
        collegeBurialReason.isEmpty ? .full : .limitedSample
    }

    /// Convenience for board rows: `true` when the production tier below is
    /// drawn from `collegeSnapsPlayed` snaps and should be read as such.
    var hasLimitedCollegeSample: Bool { collegeSampleStatus == .limitedSample }

    /// Maps a 20–99 production score onto a tier. Shared with the generator so
    /// stored and fallback tiers use one threshold table.
    static func productionTier(forScore score: Int) -> CollegeProductionTier {
        switch score {
        case 85...:   return .elite
        case 74..<85: return .aboveAvg
        case 60..<74: return .average
        default:      return .belowAvg
        }
    }

    /// Position-specific representative stat-line (e.g. "3,420 yds · 28 TD" for QB).
    ///
    /// SEMANTICS (task #181). The tier is a RATE — "how good was he when he
    /// played" — so the line it renders is his BEST SEASON, not a career total,
    /// and per-season numbers therefore do NOT scale with years started. Only
    /// genuinely cumulative quantities (an offensive lineman's career starts)
    /// carry the year count, and they say "career" on the line so the two
    /// cannot be misread as the same thing.
    var collegeStatLine: String {
        if let stored = collegeStatLineStored { return stored }
        return CollegeProspect.statLine(
            position: position,
            tier: collegeProductionTier,
            yearsStarted: collegeYearsStarted,
            seed: CollegeProspect.productionSeed(id),
            limitedSampleSnaps: hasLimitedCollegeSample ? collegeSnapsPlayed : 0
        )
    }

    /// Stable 64-bit fold of a prospect UUID (FNV-1a). `hashValue` is seeded per
    /// process, so it would re-roll the stat line on every launch.
    static func productionSeed(_ id: UUID) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: id.uuid) { raw in
            for byte in raw {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return hash
    }

    /// Deterministic scatter in −1…+1 for one number of one prospect's stat
    /// line. `productionSpread` turns it into a percentage.
    ///
    /// Without it a (position, tier, years) triple has exactly one printable
    /// line, so the whole game shipped 16 stat lines per position and a board
    /// of 350 read as a lookup table rather than as football. SplitMix64 over
    /// `(seed, index)` — same input, same line, forever, which is what lets the
    /// generator pre-render into `collegeStatLineStored` and the fallback path
    /// agree.
    static func productionJitter(seed: UInt64, index: Int) -> Double {
        var z = seed &+ (UInt64(bitPattern: Int64(index) &+ 1) &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= (z >> 31)
        return Double(z % 2001) / 1000.0 - 1.0   // −1.000 … +1.000
    }

    /// Half-width of the scatter window around a stat, as a fraction.
    ///
    /// 8 % is the headline number and it is what a yardage total gets. It
    /// cannot be the whole rule, though: 8 % of an Elite corner's 3.9
    /// interceptions is 0.31, which rounds away to a constant, and a class of
    /// 35 corners then prints "4 INT" 35 times. The window therefore widens on
    /// small counting stats to whatever spans ±2 whole units — which is also
    /// the more honest model, because interception and sack totals genuinely
    /// swing far harder season-to-season than yardage does.
    static func productionSpread(_ scaledBaseline: Double) -> Double {
        max(0.08, 2.0 / max(1.0, scaledBaseline))
    }

    /// Renders the stat line for a tier/position/years combination. Static so the
    /// generator can pre-render it into `collegeStatLineStored`.
    ///
    /// - Parameters:
    ///   - seed: `productionSeed(prospect.id)`. `0` renders the unjittered
    ///     baseline line and is only for previews.
    ///   - limitedSampleSnaps: non-zero switches to the usage line of a
    ///     prospect who never got on the field (task #181).
    static func statLine(
        position: Position,
        tier: CollegeProductionTier,
        yearsStarted: Int,
        seed: UInt64 = 0,
        limitedSampleSnaps: Int = 0
    ) -> String {
        if limitedSampleSnaps > 0 {
            return usageLine(
                position: position,
                snaps: limitedSampleSnaps,
                starts: max(0, min(4, yearsStarted)),
                seed: seed
            )
        }

        // Per-tier multiplier on a position baseline. The baselines are
        // one-season figures for a starter at that position.
        let tierMultiplier: Double
        switch tier {
        case .elite:    tierMultiplier = 1.30
        case .aboveAvg: tierMultiplier = 1.10
        case .average:  tierMultiplier = 0.92
        case .belowAvg: tierMultiplier = 0.72
        }

        var jitterIndex = 0
        func jitter() -> Double {
            jitterIndex += 1
            return productionJitter(seed: seed, index: jitterIndex)
        }
        /// Applies the per-prospect scatter to an already tier-scaled figure.
        func scatter(_ value: Double) -> Int {
            max(0, Int((value * (1.0 + jitter() * productionSpread(value))).rounded()))
        }

        /// A per-season rate where MORE is better.
        func rate(_ baseline: Double) -> Int { scatter(baseline * tierMultiplier) }

        /// A pure USAGE quantity that carries no tier information at all —
        /// field-goal attempts, punts, extra points. Spread across its real
        /// per-season range instead of scattered around one baseline, because
        /// these are the only numbers on a specialist's line.
        func usage(_ low: Double, _ high: Double) -> Int {
            Int((low + (high - low) * (jitter() + 1.0) / 2.0).rounded())
        }

        /// A per-season rate where LESS is better — interceptions thrown, sacks
        /// surrendered. These used to be multiplied by the same tier factor as
        /// the good numbers, which printed the Elite quarterback as the most
        /// careless passer in the class and the Elite tackle as the worst pass
        /// protector. Dividing is the correct direction and keeps one knob.
        func negRate(_ baseline: Double) -> Int { scatter(baseline / tierMultiplier) }

        /// The share of his team's games a starter at this tier actually
        /// started — benchings and knocks, not talent. Scales the ONE genuinely
        /// cumulative stat on the board.
        let availability: Double
        switch tier {
        case .elite:    availability = 1.00
        case .aboveAvg: availability = 0.98
        case .average:  availability = 0.95
        case .belowAvg: availability = 0.90
        }
        /// Career starts: 12 games a season, capped at the four years of
        /// eligibility. A four-year Elite starter prints 48, not the 57 the
        /// old `years/3` scaling produced for a man who cannot have played
        /// more than ~50 college games.
        func careerStarts() -> Int {
            let seasons = Double(max(1, min(4, yearsStarted)))
            return max(1, scatter(seasons * 12.0 * availability))
        }

        switch position {
        case .QB:
            return "\(rate(3000)) pass yds · \(rate(26)) TD · \(negRate(8)) INT"
        case .RB, .FB:
            return "\(rate(1100)) rush yds · \(rate(11)) TD"
        case .WR:
            return "\(rate(1080)) rec yds · \(rate(9)) TD"
        case .TE:
            return "\(rate(720)) rec yds · \(rate(7)) TD"
        case .LT, .LG, .C, .RG, .RT:
            // Pressures allowed is the stat that actually separates college
            // linemen (sacks allowed is a 4–11 integer and starts is a count of
            // games), so the line carries all three.
            return "\(careerStarts()) career starts · \(negRate(7)) sacks · \(negRate(24)) pressures"
        case .DE, .DT:
            return "\(rate(58)) tkl · \(rate(8)) sacks · \(rate(13)) TFL"
        case .OLB, .MLB:
            return "\(rate(95)) tkl · \(rate(4)) sacks · \(rate(2)) INT"
        case .CB:
            return "\(rate(46)) tkl · \(rate(13)) PD · \(rate(3)) INT"
        case .FS, .SS:
            return "\(rate(82)) tkl · \(rate(8)) PD · \(rate(3)) INT"
        case .K:
            // Attempts are USAGE and carry no tier information; the make rate
            // is the whole skill. The old line scaled makes and attempts by the
            // same factor, so every kicker in the game printed 79 % whatever
            // his tier was — and a four-year Elite kicker printed 38/49, which
            // is not a season and not a career.
            let makeRate: Double
            switch tier {
            case .elite:    makeRate = 0.88
            case .aboveAvg: makeRate = 0.82
            case .average:  makeRate = 0.75
            case .belowAvg: makeRate = 0.66
            }
            let attempts = usage(16, 32)
            let makes = Int((Double(attempts) * makeRate).rounded())
            return "\(makes)/\(attempts) FG · \(usage(30, 52)) XP"
        case .P:
            // Gross average lives in a 39–48 yd band in the real world, so it
            // is drawn from a per-tier LEVEL rather than a multiplier: 46.5 ×
            // 1.30 × 4/3 was printing 80-yard punt averages.
            let grossAverage: Double
            switch tier {
            case .elite:    grossAverage = 46.5
            case .aboveAvg: grossAverage = 44.5
            case .average:  grossAverage = 42.5
            case .belowAvg: grossAverage = 40.0
            }
            // A percentage window is wrong for this one number: 8 % of a punt
            // average is ±3.7 yd, which is the whole league spread. It gets an
            // absolute ±1.2 yd instead.
            let average = grossAverage + jitter() * 1.2
            return String(format: "%.1f yd avg · %d punts · %d inside-20",
                          average, usage(44, 78), rate(24))
        }
    }

    /// The stat line of a prospect who never got on the field (task #181).
    ///
    /// Everything here is driven by SNAPS, not by a tier: the number the board
    /// is being shown is how little tape exists, and the small counting stats
    /// that fall out of it are what a rotational player produces. The tier is
    /// still rendered beside it and is still low — that is the trap the
    /// mechanic is built on.
    private static func usageLine(
        position: Position,
        snaps: Int,
        starts: Int,
        seed: UInt64
    ) -> String {
        var jitterIndex = 100
        func jitter() -> Double {
            jitterIndex += 1
            return productionJitter(seed: seed, index: jitterIndex)
        }
        func scatter(_ value: Double) -> Int {
            max(0, Int((value * (1.0 + jitter() * productionSpread(value))).rounded()))
        }
        func per(_ ratePerSnap: Double) -> Int { scatter(Double(snaps) * ratePerSnap) }
        let prefix = starts > 0 ? "\(snaps) snaps · 1 start" : "\(snaps) snaps"

        switch position {
        case .QB:
            return "\(prefix) · \(per(4.6)) pass yds · \(per(0.030)) TD"
        case .RB, .FB:
            let carries = per(0.32)
            return "\(prefix) · \(carries) car, \(scatter(Double(carries) * 5.1)) yds"
        case .WR:
            let catches = per(0.095)
            return "\(prefix) · \(catches) rec, \(scatter(Double(catches) * 12.8)) yds"
        case .TE:
            let catches = per(0.070)
            return "\(prefix) · \(catches) rec, \(scatter(Double(catches) * 11.0)) yds"
        case .LT, .LG, .C, .RG, .RT:
            return "\(prefix) · rotational duty"
        case .DE, .DT:
            return "\(prefix) · \(per(0.085)) tkl · \(per(0.012)) sacks"
        case .OLB, .MLB:
            return "\(prefix) · \(per(0.140)) tkl · \(per(0.008)) sacks"
        case .CB:
            return "\(prefix) · \(per(0.070)) tkl · \(per(0.020)) PD"
        case .FS, .SS:
            return "\(prefix) · \(per(0.100)) tkl · \(per(0.015)) PD"
        case .K, .P:
            // Specialists are excluded from the buried cohort by the generator;
            // this branch exists so the switch stays exhaustive.
            return "\(prefix) · backup duty"
        }
    }

    /// Overall rating using the **same weights as `Player.overall`**: position
    /// skills 50 %, physical 30 %, mental 20 %. Excluding position skills (the
    /// old 60/40 physical/mental blend) meant a drafted prospect's rating jumped
    /// the moment he became a Player, and it collapsed the class into a 60–69
    /// band because position skills carried all of the real variance.
    var trueOverall: Int {
        Int(CollegeProspect.overallValue(
            position: truePositionAttributes,
            physical: truePhysical,
            mental: trueMental
        ).rounded())
    }

    /// Unrounded overall for the attribute solver — mirrors `Player.overall`.
    static func overallValue(
        position: PositionAttributes,
        physical: PhysicalAttributes,
        mental: MentalAttributes
    ) -> Double {
        position.overall * 0.5 + physical.average * 0.3 + mental.average * 0.2
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

// MARK: - Personality read provenance (task #185)

/// Which instrument produced the personality read on a prospect's card.
///
/// The cases are ordered by how much of a man's character the instrument can
/// actually see, and `strength` is that order made explicit: the inherited
/// league consensus is hearsay, a filed scout report is tape, a private workout
/// is a day in your own facility, and an interview is forty minutes across a
/// table. A read may only be replaced by an instrument at least as strong, so a
/// routine weekly report can never quietly overwrite what the user learned by
/// spending an interview slot — and an interview read is replaceable only by
/// another interview.
enum PersonalitySource: String, Codable, CaseIterable {
    case leagueConsensus
    case report
    case interview
    case workout

    /// Higher sees more. Used by `ScoutingEngine.recordPersonalityRead`.
    var strength: Int {
        switch self {
        case .leagueConsensus: return 0
        case .report:          return 1
        case .workout:         return 2
        case .interview:       return 3
        }
    }

    /// How the read should be attributed on the prospect card.
    var attributionLabel: String {
        switch self {
        case .leagueConsensus: return "League consensus"
        case .report:          return "From scouting reports"
        case .interview:       return "From your interview"
        case .workout:         return "From the private workout"
        }
    }
}

// MARK: - Declaration window (task #78, finding S11)

/// Where a prospect sits in the January declaration window.
///
/// The board used to have no vocabulary for this at all: `isDeclaringForDraft`
/// defaults to `true` on the model, so from September to January every
/// underclassman in the class read as a lock to come out — including the ~100
/// who never declare and the one who pulls his name back off the top of the
/// board every year.
enum DeclarationStatus: String {
    /// The window has not been held for him. For an underclassman that means
    /// genuinely undecided; a senior is moved to `.declared` at generation
    /// because he has no eligibility left to keep.
    case undecided = ""
    case declared  = "Declared"
    case withdrawn = "Withdrawn"

    /// Row-badge text. Empty for the undecided case, which renders the public
    /// `DeclarationLikelihood` chip instead.
    var shortLabel: String {
        switch self {
        case .undecided: return ""
        case .declared:  return "IN"
        case .withdrawn: return "OUT"
        }
    }
}

/// The PUBLIC read on whether an undeclared underclassman comes out.
///
/// Built from class year and college production only — see
/// `CollegeProspect.declarationLikelihood` for why `trueOverall` may not enter
/// into it.
enum DeclarationLikelihood: String {
    case likely    = "Likely"
    case leaning   = "Leaning"
    case undecided = "Undecided"

    /// Four characters or fewer so it fits a board row.
    var shortLabel: String {
        switch self {
        case .likely:    return "LIKELY"
        case .leaning:   return "LEAN"
        case .undecided: return "UNDEC"
        }
    }

    var color: Color {
        switch self {
        case .likely:    return .success
        case .leaning:   return .warning
        case .undecided: return .textTertiary
        }
    }
}

// MARK: - Unified GM Mark Tier

/// The GM's verdict on a prospect — the single mark system every scouting
/// screen reads and writes.
///
/// It is deliberately a *tier*, not a flag: the tier is the tier-break
/// primitive the board groups on in "My Board" mode, so a verdict written on
/// the deep-dive card is visible as structure on the board two taps later.
/// `avoid` sorts BELOW unmarked on purpose — a man you have actively crossed
/// off should sit under the men you simply have not looked at yet.
enum ProspectMarkTier: String, CaseIterable, Identifiable {
    case none   = ""
    case elite  = "elite"
    case target = "target"
    case depth  = "depth"
    case avoid  = "avoid"

    var id: String { rawValue }

    /// The four tiers a user can actually pick, in board order.
    static var choices: [ProspectMarkTier] { [.elite, .target, .depth, .avoid] }

    var label: String {
        switch self {
        case .none:   return "Unmarked"
        case .elite:  return "Elite"
        case .target: return "Target"
        case .depth:  return "Depth"
        case .avoid:  return "Avoid"
        }
    }

    /// Row-badge form — four characters or fewer so it fits a board row.
    var shortLabel: String {
        switch self {
        case .none:   return ""
        case .elite:  return "ELITE"
        case .target: return "TGT"
        case .depth:  return "DPTH"
        case .avoid:  return "AVD"
        }
    }

    /// What picking this tier means, shown under the choice in the mark menu.
    var blurb: String {
        switch self {
        case .none:   return "No verdict yet"
        case .elite:  return "Take him wherever you pick"
        case .target: return "Want him at the right value"
        case .depth:  return "Late-round / roster filler"
        case .avoid:  return "Off your board"
        }
    }

    var icon: String {
        switch self {
        case .none:   return "circle.dashed"
        case .elite:  return "star.circle.fill"
        case .target: return "target"
        case .depth:  return "square.stack.3d.down.right.fill"
        case .avoid:  return "nosign"
        }
    }

    var color: Color {
        switch self {
        case .none:   return .textTertiary
        case .elite:  return .accentGold
        case .target: return .success
        case .depth:  return .accentBlue
        case .avoid:  return .danger
        }
    }

    /// Board grouping order. Unmarked sits above `avoid` deliberately.
    var sortRank: Int {
        switch self {
        case .elite:  return 0
        case .target: return 1
        case .depth:  return 2
        case .none:   return 3
        case .avoid:  return 4
        }
    }

    /// Elite and Target are the two tiers that mean "I want this man" — the
    /// bar the prep card's "on your board, never interviewed" nag uses, and
    /// what the legacy star mirrors.
    var isBoardPositive: Bool { self == .elite || self == .target }

    /// The legacy `ProspectFlag` this tier is mirrored onto.
    var legacyFlag: ProspectFlag {
        switch self {
        case .none:   return .none
        case .elite:  return .mustHave
        case .target: return .mustHave
        case .depth:  return .sleeper
        case .avoid:  return .avoid
        }
    }
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
