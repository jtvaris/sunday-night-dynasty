import Foundation
import SwiftData

@Model
final class Player {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<Player>([\.careerID])

    var firstName: String
    var lastName: String
    var position: Position
    var age: Int
    var yearsPro: Int

    var physical: PhysicalAttributes
    var mental: MentalAttributes
    var positionAttributes: PositionAttributes

    var personality: PlayerPersonality

    /// Hidden true potential ceiling (1-99). Not directly visible to the user;
    /// discovered over time through scouting and player development.
    var truePotential: Int

    /// How fast this player absorbs playbooks and schemes (25-99).
    ///
    /// Generated correlated with `awareness` (r ≈ 0.6) but deliberately NOT
    /// identical to it: `awareness` stays the in-sim game-IQ that every
    /// `PlaySimulator` formula reads, while `learning` drives scheme-install
    /// speed (`VersatilityDevelopmentEngine.learnScheme`) and a rookie's
    /// starting scheme familiarity (`DraftEngine.initializeRookieFamiliarity`).
    ///
    /// Written from `CollegeProspect.trueLearning` at draft time and by
    /// `LeagueGenerator` for generated veterans. Players from saves created
    /// before this property existed keep the 55 default until
    /// `WeekAdvancer.backfillLegacyLearning` seeds them from awareness.
    /// Default-value stored property, never in `init` → safe lightweight
    /// migration (see `docs/DRAFT_CLASS_OVERHAUL_PLAN.md` §5).
    var learning: Int = 55

    /// The `learning` value a row carries when nothing has ever written one.
    /// Doubles as the exact "unset" sentinel for the legacy backfill.
    static let defaultLearning = MentalAttributeModel.defaultLearning

    /// Normalises a generated learning rating into the 25-99 band and nudges it
    /// off `defaultLearning`, so a written value can never be mistaken for an
    /// unwritten one. The one-point gap at 55 is invisible in play and makes
    /// `WeekAdvancer.backfillLegacyLearning` provably idempotent.
    ///
    /// Phase 2 (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.2): the math moved
    /// to `MentalAttributeModel` so the three generators share one distribution;
    /// this stays as the domain-side spelling every call site already uses.
    static func storedLearning(_ value: Int) -> Int {
        MentalAttributeModel.storedLearning(value)
    }

    /// The fighter-mentality rating (25-99): how a player answers adversity —
    /// a collapsed season, a demotion, a down year — and how immune he is to
    /// post-payday complacency.
    ///
    /// Drives the phase-2 motivation state machine
    /// (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.3) and the realization
    /// factor (§2.4); it is NOT read by `PlaySimulator` (clutch stays the
    /// in-game nerve stat). Written from `CollegeProspect.trueCompetitiveness`
    /// at draft time and by `LeagueGenerator` for generated veterans; rows from
    /// older saves keep the 55 default until
    /// `WeekAdvancer.backfillLegacyCompetitiveness` seeds them.
    /// Default-value stored property, never in `init` → safe lightweight
    /// migration.
    var competitiveness: Int = 55

    /// The `competitiveness` value a row carries when nothing has ever written
    /// one. Doubles as the exact "unset" sentinel for the legacy backfill.
    static let defaultCompetitiveness = MentalAttributeModel.defaultCompetitiveness

    /// Sentinel-safe clamp for competitiveness — mirrors `storedLearning`.
    static func storedCompetitiveness(_ value: Int) -> Int {
        MentalAttributeModel.storedCompetitiveness(value)
    }

    /// Raw value of `MotivationState` — where this player's head is at going
    /// into the season, recomputed once per offseason when the league enters
    /// `.trainingCamp` (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.3).
    ///
    /// `nil` = never computed (legacy save row, or a player created mid-cycle),
    /// which the `motivationState` accessor reads as `.focused` — the neutral
    /// state, so an untouched row develops exactly as it did before phase 2.
    /// Optional stored property with a nil default → safe lightweight migration.
    var motivationStateRaw: String? = nil

    /// Typed accessor for the player's offseason motivation state.
    var motivationState: MotivationState {
        get { motivationStateRaw.flatMap(MotivationState.init(rawValue:)) ?? .default }
        set { motivationStateRaw = newValue.rawValue }
    }

    /// `truePotential` as it stood the day this player entered the league.
    ///
    /// Phase 2 §2.6 lets potential drift a few points with scheme fit and
    /// morale, but caps the LIFETIME drift at ±8 from the draft-time value —
    /// which requires remembering that value. `0` is the "never written"
    /// sentinel: the first offseason pass that touches a player seeds it with
    /// his current `truePotential`, so legacy saves anchor on where they are
    /// rather than snapping. Default-value stored property, never in `init`.
    var draftTruePotential: Int = 0

    var morale: Int
    var fatigue: Int
    var isInjured: Bool
    var injuryWeeksRemaining: Int
    var injuryType: InjuryType?
    var injuryWeeksOriginal: Int

    /// Position familiarity: how well this player knows each position (0-100).
    /// Primary position starts at 100. Alternate positions grow through training.
    /// Key: Position.rawValue, Value: 0-100 proficiency
    var positionFamiliarity: [String: Int] = [:]

    /// Scheme familiarity: how well this player knows each scheme (0-100).
    /// Grows through practice and games under a coordinator running that scheme.
    /// Key: scheme rawValue (e.g., "WestCoast"), Value: 0-100
    var schemeFamiliarity: [String: Int] = [:]

    /// The alternate position currently being trained (if any).
    var trainingPosition: Position?

    /// Optional relationship to a Team via its ID.
    var teamID: UUID?

    var contractYearsRemaining: Int
    /// Annual salary in thousands (e.g., 15000 = $15M).
    var annualSalary: Int

    /// Full-season base this player was on before a MIDSEASON trade prorated
    /// `annualSalary` down to the checks the buying club still owed (task #45).
    /// 0 = not carrying a prorated number.
    ///
    /// A trade at the Week 9 deadline charges the buyer 10/18 of the base, and
    /// `TradeEngine` writes that prorated figure back into `annualSalary` because
    /// `Team.currentCapUsage` is an incrementally maintained ledger — the number
    /// charged and the number later refunded have to be the same one. The cost of
    /// that is that the discount used to survive the league-year boundary: a
    /// deadline acquisition stayed booked at ~56-94 % of his real salary for the
    /// rest of his contract. This field is the receipt that lets
    /// `FreeAgencyEngine.executeNewLeagueYear` put the full base back when the
    /// new league year starts, and it is cleared in the same pass.
    ///
    /// Default-value attribute → safe lightweight migration.
    var proratedFullBaseSalary: Int = 0

    /// Whether this player has been franchise-tagged for the current season.
    var isFranchiseTagged: Bool

    /// R22: whether this player is currently holding out over their contract.
    /// A holdout player skips practice and games and does not develop until
    /// the situation is resolved or the player caves (~week 3-4).
    /// Default-value stored property → safe lightweight migration.
    var isHoldingOut: Bool = false

    /// R32: whether this player has retired from professional football.
    /// Retired players keep their row (career history / Hall of Fame reads it)
    /// but are excluded from the free-agent market, development, aging, and
    /// season-history recording. Default value → safe lightweight migration.
    var isRetired: Bool = false

    /// Phase 4: id of this player's portrait in the pre-generated face library
    /// (`face_00000`…`face_02047`, see `FaceLibrary`). Assigned once — at
    /// league generation, at the draft (carried over from the prospect), or by
    /// `WeekAdvancer.backfillLegacyFaces` for rows created before the library
    /// existed — and never rewritten, so a player's face is a stable identity
    /// anchor for his whole career.
    ///
    /// `nil` means "no face yet"; the image file may also be missing while the
    /// library is still generating. `PersonFaceView` renders a silhouette in
    /// both cases. Optional stored property with a nil default → safe
    /// lightweight migration.
    var faceID: String? = nil

    /// The overall draft pick number (1-224) if this player was drafted, nil for UDFAs/veterans.
    /// Doubles as the "draft pick overall" of record.
    var draftPickNumber: Int?

    /// #40 Draft provenance. Written once at draft time (`DraftEngine.convertToPlayer`)
    /// and never mutated afterward. All three stay nil for UDFAs, generated
    /// veterans, and legacy players created before this field existed — such
    /// players are treated as "undrafted/legacy" by the draft-grade pipeline.
    /// Optional stored properties with a nil default → safe lightweight migration.
    ///
    /// The team that drafted this player (the pick's owning team at selection).
    var draftedByTeamID: UUID? = nil

    /// The season (calendar year) in which this player was drafted.
    var draftSeason: Int? = nil

    /// The draft round (1-7) derived from the overall pick number at draft time.
    var draftRound: Int? = nil

    /// Coaching staff's verbal assessment of this player's development ceiling.
    /// Stored as PotentialLabel.rawValue. Accuracy depends on coach quality and time with team.
    var assessedPotential: String?

    // MARK: - Biography (fixed-league template import)

    /// Uniform number (0-99). Written only by `LeagueTemplateImporter` — the
    /// random `LeagueGenerator` path never assigned numbers, and the match view
    /// still paints its own decal numbers, so this is roster/profile data only.
    /// Unique per roster at import: the template resolves its own collisions and
    /// the importer re-checks, keeping the first holder and reassigning the
    /// second to the lowest free number in the position's legal NFL band.
    /// Optional stored property with a nil default → safe lightweight migration.
    var jerseyNumber: Int? = nil

    /// School of record. Real and factual — colleges are deliberately NOT
    /// anonymized away, only swapped within tier (`docs/ANONYMIZATION_SPEC.md`
    /// §2). `nil` for every randomly generated player.
    var college: String? = nil

    /// Listed height in inches. Bio-jittered in the publish profile (§2).
    var heightInches: Int? = nil

    /// Listed weight in pounds. Bio-jittered in the publish profile (§2).
    var weightPounds: Int? = nil

    // MARK: - FA Drama / Storylines

    /// Hometown state (e.g. "California"). Used by HometownDetector for storyline matching.
    var hometownState: String?

    /// Hometown city (e.g. "Long Beach"). Used by HometownDetector for storyline matching.
    var hometownCity: String?

    /// If non-nil, the team that previously cut this player. Drives Revenge Tour grudge flag.
    var cutByTeamID: UUID?

    /// Timestamp of the cut event used to age out the grudge over time.
    var cutAt: Date?

    /// Number of consecutive seasons the player has been on the current team.
    /// Used by LoyaltyEngine to compute hometown-discount eligibility.
    var loyaltyYears: Int = 0

    /// #33: regular-season games the player has appeared in during the current
    /// season. Incremented by `WeekAdvancer` each week the player's team plays
    /// and the player was AVAILABLE (active roster, healthy, not holding out,
    /// not retired) — the only participation signal available league-wide,
    /// since AI games are score-only. Snapshotted into
    /// `PlayerSeasonHistory.gamesPlayed` at week 18 and reset to 0 in
    /// `startNewSeason`. Default value → safe lightweight migration.
    var gamesPlayedThisSeason: Int = 0

    /// #40: regular-season games the player STARTED during the current season.
    /// A "start" is credited by `WeekAdvancer` each week the player's team plays
    /// and the player is in his team's projected starting lineup — i.e. he ranks
    /// within the starter-slot count at his position among AVAILABLE teammates
    /// (healthy, not holding out, not retired), mirroring the best-available
    /// `MatchupResolver.FieldUnit` selection that puts 11 offense + 11 defense +
    /// K + P on the field. This is the only starter signal available league-wide
    /// (AI games are score-only). Snapshotted into
    /// `PlayerSeasonHistory.gamesStarted` at week 18 and reset to 0 in
    /// `startNewSeason`. Always ≤ `gamesPlayedThisSeason`. Default value →
    /// safe lightweight migration.
    var gamesStartedThisSeason: Int = 0

    /// JSON-encoded `SeasonStatLine` — the production the SIM actually recorded
    /// for this player so far this regular season, accumulated game by game.
    ///
    /// Only the user's own games produce a box score (the other 31 teams are
    /// score-only), so this stays `nil` for most of the league; `WeekAdvancer`
    /// then synthesizes those seasons at week 18. Snapshotted into
    /// `PlayerSeasonHistory` at week 18 and cleared in `startNewSeason`, the same
    /// lifecycle as `gamesPlayedThisSeason` (#33).
    /// Optional new attribute → lightweight migration.
    var seasonStatLineData: Data? = nil

    /// Pair partner — when this veteran is signed, the protégé rookie may be brought in at a discount.
    var mentorOfPlayerID: UUID?

    /// Community-engagement level (0-3). Higher tier players generate more
    /// CommunityImpact storyline events and city-loyalty modifiers.
    var civicTier: Int = 0

    /// Career milestone enum raw value (e.g. "hofPush", "comeback"). Drives MilestoneTracker.
    var milestoneRaw: String?

    // MARK: - Camp / Workload

    /// Accumulated training-load points across the current camp/season week.
    /// Reset by `WorkloadEngine` after recovery is applied.
    var cumulativeLoad: Int = 0

    /// Raw value of `WorkloadStatus`. Defaults to `.healthy` when nil/unknown.
    var workloadStatusRaw: String?

    /// Raw value of `CampGrade`. nil until camp evaluation has run.
    var campGradeRaw: String?

    /// Typed accessor for the player's current workload state.
    var workloadStatus: WorkloadStatus {
        get { WorkloadStatus(rawValue: workloadStatusRaw ?? "") ?? .healthy }
        set { workloadStatusRaw = newValue.rawValue }
    }

    /// Typed accessor for the player's current camp grade (nil before evaluation).
    var campGrade: CampGrade? {
        get { campGradeRaw.flatMap(CampGrade.init(rawValue:)) }
        set { campGradeRaw = newValue?.rawValue }
    }

    // MARK: - Training Focus (R26)

    /// Raw value of `TrainingFocusArea` — the weekly training emphasis the
    /// coaching staff has put on this player. `nil` = no focus. At most 3
    /// players per team hold a focus slot (enforced by UI and AI logic).
    /// Optional new attribute → safe lightweight migration.
    var trainingFocusAreaRaw: String? = nil

    /// Typed accessor for the player's weekly training focus.
    var trainingFocusArea: TrainingFocusArea? {
        get { trainingFocusAreaRaw.flatMap(TrainingFocusArea.init(rawValue:)) }
        set { trainingFocusAreaRaw = newValue?.rawValue }
    }

    // MARK: - Injuries & Medical 2.0 (R28)

    /// JSON-encoded `[InjuryRecord]` — permanent injury history, newest last.
    /// Optional new attribute → safe lightweight migration.
    var injuryHistoryData: Data? = nil

    /// Raw value of `RehabStatus` for the current injury (nil when healthy).
    /// Optional new attribute → safe lightweight migration.
    var rehabStatusRaw: String? = nil

    /// Weeks of elevated re-injury risk remaining after the player rushed
    /// back from an injury one week early. Decremented weekly; 0 = no risk.
    /// Default-value attribute → safe lightweight migration.
    var rushBackWeeksRemaining: Int = 0

    /// Typed accessor for the current rehab trajectory.
    var rehabStatus: RehabStatus? {
        get { rehabStatusRaw.flatMap(RehabStatus.init(rawValue:)) }
        set { rehabStatusRaw = newValue?.rawValue }
    }

    /// Permanent injury history (newest last). Writing encodes and stores the
    /// list; the caller saves the context.
    var injuryHistory: [InjuryRecord] {
        get {
            guard let data = injuryHistoryData,
                  let records = try? JSONDecoder().decode([InjuryRecord].self, from: data) else {
                return []
            }
            return records
        }
        set {
            injuryHistoryData = try? JSONEncoder().encode(newValue)
        }
    }

    /// How many times this player has previously suffered the given injury type.
    func priorInjuryCount(of type: InjuryType) -> Int {
        injuryHistory.filter { $0.injuryTypeRaw == type.rawValue }.count
    }

    // MARK: - Computed Properties

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Overall rating as a weighted blend of position-specific skills (50%),
    /// physical (30%), and mental (20%) attributes. Position skills dominate
    /// because they reflect what a player actually does on the field.
    var overall: Int {
        let positionAvg = positionAttributes.overall
        let physicalAvg = physical.average
        let mentalAvg = mental.average
        return Int((positionAvg * 0.5 + physicalAvg * 0.3 + mentalAvg * 0.2).rounded())
    }

    /// Get familiarity for a specific position (defaults to 0, primary is always 100).
    func familiarity(at position: Position) -> Int {
        if position == self.position { return 100 }
        return positionFamiliarity[position.rawValue] ?? 0
    }

    /// Get familiarity for a specific scheme (defaults to 0).
    func schemeFam(for scheme: String) -> Int {
        return schemeFamiliarity[scheme] ?? 0
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        position: Position,
        age: Int,
        yearsPro: Int = 0,
        physical: PhysicalAttributes = .random(),
        mental: MentalAttributes = .random(),
        positionAttributes: PositionAttributes,
        personality: PlayerPersonality,
        truePotential: Int = Int.random(in: 50...99),
        morale: Int = 70,
        fatigue: Int = 0,
        isInjured: Bool = false,
        injuryWeeksRemaining: Int = 0,
        injuryType: InjuryType? = nil,
        injuryWeeksOriginal: Int = 0,
        teamID: UUID? = nil,
        contractYearsRemaining: Int = 4,
        annualSalary: Int = 750,
        isFranchiseTagged: Bool = false,
        draftPickNumber: Int? = nil,
        draftedByTeamID: UUID? = nil,
        draftSeason: Int? = nil,
        draftRound: Int? = nil,
        assessedPotential: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.position = position
        self.age = age
        self.yearsPro = yearsPro
        self.physical = physical
        self.mental = mental
        self.positionAttributes = positionAttributes
        self.personality = personality
        self.truePotential = truePotential
        self.morale = morale
        self.fatigue = fatigue
        self.isInjured = isInjured
        self.injuryWeeksRemaining = injuryWeeksRemaining
        self.injuryType = injuryType
        self.injuryWeeksOriginal = injuryWeeksOriginal
        self.teamID = teamID
        self.contractYearsRemaining = contractYearsRemaining
        self.annualSalary = annualSalary
        self.isFranchiseTagged = isFranchiseTagged
        self.draftPickNumber = draftPickNumber
        self.draftedByTeamID = draftedByTeamID
        self.draftSeason = draftSeason
        self.draftRound = draftRound
        self.assessedPotential = assessedPotential
    }
}

// MARK: - Season Stat Line Codable Bridge

extension Player {

    /// The production the sim has recorded for this player so far this regular
    /// season, JSON-decoded from `seasonStatLineData`. Reading an untouched
    /// player returns an all-zero line; writing encodes it (caller saves the
    /// context). `SeasonStatLine` decodes leniently, so a payload written by an
    /// older build survives a new stat category.
    var seasonStatLine: SeasonStatLine {
        get {
            guard let data = seasonStatLineData,
                  let line = try? JSONDecoder().decode(SeasonStatLine.self, from: data) else {
                return SeasonStatLine()
            }
            return line
        }
        set {
            seasonStatLineData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Folds one game's box score into the running season line.
    func accumulateSeasonStats(_ game: PlayerGameStats) {
        var line = seasonStatLine
        line.add(game)
        seasonStatLine = line
    }
}
