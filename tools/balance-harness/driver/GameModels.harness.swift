import Foundation

// MARK: - SwiftData-model stubs (HARNESS-OWNED SCAFFOLDING)
//
// The shipped full-game pipeline — GameSimulator / DriveSimulator / CoachingModifiers,
// all synced VERBATIM (sha-verified) by sync_sources.sh — is written against three
// SwiftData `@Model` types (`Player`, `Team`, `Coach`) that cannot compile outside the
// iOS app (they pull in SwiftData, the whole Domain graph, etc.). None of those three
// carries any balance MATH: they are pure data holders. So the harness supplies its own
// plain shells exposing EXACTLY the members the synced engine reads — the same technique
// the existing `CoachingEngine` / `VersatilityDevelopmentEngine` stubs in
// SimPlayer.harness.swift use. Every tuning constant still flows from the verbatim
// engine sources; these stubs never touch a number.
//
// `Player` MUST be a reference type: `GameSimulator.finalizeGameResult` writes fatigue
// back through `let livePlayerByID: [UUID: Player]` via `dict[id]?.fatigue = …`, which
// only compiles (mutating through a `let` dictionary) when the value is a class.
//
// This file is copied verbatim into build/src/GameModels.swift on every sync and
// compiled alongside the engine sources.

/// Minimal mirror of the shipped `CoachRole`. The four roles the sim's coaching
/// path (`CoachingModifiers.ratings`) inspects, plus the position-coach roles the
/// staged development stack reads through `CoachingEngine.positionRoleMatch`
/// (the `career` scenario), plus a catch-all. No verbatim engine source switches
/// exhaustively over this enum, so the extra cases are additive.
enum CoachRole {
    case headCoach
    case assistantHeadCoach
    case offensiveCoordinator
    case defensiveCoordinator
    case specialTeamsCoordinator
    case qbCoach
    case rbCoach
    case wrCoach
    case olCoach
    case dlCoach
    case lbCoach
    case dbCoach
    case strengthCoach
    case other
}

/// Data-holder for the handful of coach attributes `CoachingModifiers` and the
/// development stack consume. A grade-70 coach on every field produces ~zero
/// coaching effect (each mechanic is centered at 70 / 50), so neutral coaches can
/// carry a scheme without moving the balance.
final class Coach {
    /// Phase 4 face library (written by the synced `CoachingEngine`).
    var faceID: String? = nil

    /// `"male"` | `"female"` — mirrors `Coach.gender` in the app so the synced
    /// `CoachingEngine` compiles here. The harness never reads it; portraits do
    /// not exist in a headless sim.
    var gender: String = "male"

    var role: CoachRole
    var offensiveScheme: OffensiveScheme?
    var defensiveScheme: DefensiveScheme?
    var playCalling: Int
    var adaptability: Int
    var gamePlanning: Int
    var discipline: Int
    var moraleInfluence: Int
    var motivation: Int
    var schemeExpertise: [String: Int]

    // --- Development-stack fields (read by the staged CoachingEngine /
    //     PlayerDevelopmentEngine / TrainingFocusEngine slices) -----------------

    /// `Coach.playerDevelopment` — the teaching rating every development layer
    /// (position coach ±15 %, coordinator ±10 %, AHC ±4 %, strength bonus) reads.
    var playerDevelopment: Int = 50

    /// First season in the building: the shipped stack docks the multiplier
    /// (−0.05 HC / −0.03 coordinator) while a new hire installs his system.
    var isInAdjustmentPeriod: Bool = false

    /// Consecutive completed seasons on this team — drives the §2.9.3 continuity
    /// reward (3+ seasons, unchanged scheme).
    var seasonsOnTeam: Int = 0

    init(role: CoachRole,
         offensiveScheme: OffensiveScheme? = nil,
         defensiveScheme: DefensiveScheme? = nil,
         playCalling: Int = 70,
         adaptability: Int = 70,
         gamePlanning: Int = 70,
         discipline: Int = 70,
         moraleInfluence: Int = 70,
         motivation: Int = 70,
         schemeExpertise: [String: Int] = [:],
         playerDevelopment: Int = 50) {
        self.role = role
        self.offensiveScheme = offensiveScheme
        self.defensiveScheme = defensiveScheme
        self.playCalling = playCalling
        self.adaptability = adaptability
        self.gamePlanning = gamePlanning
        self.discipline = discipline
        self.moraleInfluence = moraleInfluence
        self.motivation = motivation
        self.schemeExpertise = schemeExpertise
        self.playerDevelopment = playerDevelopment
    }

    /// Matches the shipped `Coach.expertise(for:)` (baseline 20 for unknown schemes).
    func expertise(for scheme: String) -> Int { schemeExpertise[scheme] ?? 20 }
}

/// Which roster a player occupies. Stub of the shipped `RosterStatus`, which
/// lives in `Domain/Models/Player/Player.swift` — a `@Model` file the harness
/// cannot compile, so only its `overall` body is spliced (below). The three
/// cases and their raw values are the shipped ones because they are PERSISTED
/// raw values in the app; the display strings are left behind.
enum RosterStatus: String, Codable, CaseIterable {
    case active
    case practiceSquad
    case campBody
}

/// Carrier for the SHIPPED `Player.overall` blend, spliced VERBATIM from the repo
/// `Domain/Models/Player/Player.swift` on every sync.
///
/// The stub `Player` below cannot host the spliced property directly: the round-5
/// tier-roster generator PINS an explicit grade (`overall: 88` for an "elite"
/// cell) and every per-play band in this harness is calibrated against that
/// pinning, while the `career` scenario needs the real formula because
/// development moves attributes, not a stored number. So the repo's own body
/// lives here and `Player.overall` falls through to it whenever no pin is set —
/// no weight (0.5 / 0.3 / 0.2) is ever retyped in the harness.
struct ShippedOverall {
    let positionAttributes: PositionAttributes
    let physical: PhysicalAttributes
    let mental: MentalAttributes

    // @@SPLICE:PLAYEROVERALL@@
}

/// Reference-type player shell. Two audiences share it, because the harness is a
/// single swiftc module and there can only be one `Player`:
///
/// 1. the round-5 full-game pipeline, which reads `SimPlayer.init(from:)`'s
///    members plus `isHoldingOut` / `morale` / `fatigue`; and
/// 2. the phase-2 development stack (`PlayerDevelopmentEngine`,
///    `PlayerRetirementEngine`, `TrainingFocusEngine`, `ContractEngine` — all
///    synced from the repo), which reads the career fields below.
///
/// Every career field is an inline-default stored property, exactly like the
/// shipped `@Model Player`, so the fullgame roster builder is untouched. No
/// SwiftData, no @Model, and no balance math — the one formula this type needs
/// (`overall`) is spliced from the repo above.
final class Player {
    let id: UUID
    var fullName: String
    var position: Position
    var physical: PhysicalAttributes
    var mental: MentalAttributes
    var positionAttributes: PositionAttributes
    var isMoodDependent: Bool
    var personalityArchetype: PersonalityArchetype
    var morale: Int
    var schemeFamiliarity: [String: Int]
    var fatigue: Int
    var isHoldingOut: Bool

    /// Round-5 seam: when set, `overall` reports this grade verbatim (the tier
    /// rosters are built "a 90 is a 90"). `nil` → the shipped blend.
    var pinnedOverall: Int?

    var overall: Int {
        pinnedOverall ?? ShippedOverall(
            positionAttributes: positionAttributes,
            physical: physical,
            mental: mental
        ).overall
    }

    // MARK: - Career fields (development stack)

    var age: Int = 22
    /// Phase 4 face library (written by the synced `DraftEngine`, read by the
    /// synced `PlayerRetirementEngine`).
    var faceID: String? = nil
    var yearsPro: Int = 0
    var personality: PlayerPersonality = PlayerPersonality(archetype: .steadyPerformer, motivation: .winning)
    var truePotential: Int = 75
    var learning: Int = MentalAttributeModel.defaultLearning
    var competitiveness: Int = MentalAttributeModel.defaultCompetitiveness
    var motivationStateRaw: String? = nil
    var draftTruePotential: Int = 0
    var isInjured: Bool = false
    var injuryWeeksRemaining: Int = 0
    var injuryType: InjuryType? = nil
    var injuryWeeksOriginal: Int = 0
    var positionFamiliarity: [String: Int] = [:]
    var trainingPosition: Position? = nil
    var teamID: UUID? = nil
    /// --- Roster status (task #157: the practice-squad diagnostic) -----------
    /// The three fields `PracticeSquadEngine.isSquadEligible` and
    /// `squadSigningScore` read, with the shipped spellings and the shipped
    /// meanings: a squad man carries `teamID == nil` and
    /// `practiceSquadTeamID == <club>`, and `cutByTeamID` is the release stamp
    /// the own-cuts-first ranking turns on.
    var rosterStatusRaw: String = RosterStatus.active.rawValue
    var practiceSquadTeamID: UUID? = nil
    var cutByTeamID: UUID? = nil
    var contractYearsRemaining: Int = 4
    var annualSalary: Int = 750
    var isFranchiseTagged: Bool = false
    var isRetired: Bool = false
    var draftPickNumber: Int? = nil
    var draftedByTeamID: UUID? = nil
    var draftSeason: Int? = nil
    var draftRound: Int? = nil
    var assessedPotential: String? = nil
    var loyaltyYears: Int = 0
    var gamesPlayedThisSeason: Int = 0
    var gamesStartedThisSeason: Int = 0
    var cumulativeLoad: Int = 0
    var workloadStatusRaw: String? = nil
    var campGradeRaw: String? = nil
    var trainingFocusAreaRaw: String? = nil
    var injuryHistoryData: Data? = nil
    var rehabStatusRaw: String? = nil
    var rushBackWeeksRemaining: Int = 0

    // MARK: Typed accessors (same spellings as the shipped model)

    /// Both halves are checked, exactly as the shipped model does it, so a
    /// half-written row never reads as a squad member.
    var rosterStatus: RosterStatus {
        get { RosterStatus(rawValue: rosterStatusRaw) ?? .active }
        set { rosterStatusRaw = newValue.rawValue }
    }
    var isOnPracticeSquad: Bool {
        rosterStatus == .practiceSquad && practiceSquadTeamID != nil
    }
    var motivationState: MotivationState {
        get { motivationStateRaw.flatMap(MotivationState.init(rawValue:)) ?? .default }
        set { motivationStateRaw = newValue.rawValue }
    }
    var workloadStatus: WorkloadStatus {
        get { WorkloadStatus(rawValue: workloadStatusRaw ?? "") ?? .healthy }
        set { workloadStatusRaw = newValue.rawValue }
    }
    var campGrade: CampGrade? {
        get { campGradeRaw.flatMap(CampGrade.init(rawValue:)) }
        set { campGradeRaw = newValue?.rawValue }
    }
    var trainingFocusArea: TrainingFocusArea? {
        get { trainingFocusAreaRaw.flatMap(TrainingFocusArea.init(rawValue:)) }
        set { trainingFocusAreaRaw = newValue?.rawValue }
    }
    var rehabStatus: RehabStatus? {
        get { rehabStatusRaw.flatMap(RehabStatus.init(rawValue:)) }
        set { rehabStatusRaw = newValue?.rawValue }
    }
    var injuryHistory: [InjuryRecord] {
        get {
            guard let data = injuryHistoryData,
                  let records = try? JSONDecoder().decode([InjuryRecord].self, from: data) else {
                return []
            }
            return records
        }
        set { injuryHistoryData = try? JSONEncoder().encode(newValue) }
    }
    func priorInjuryCount(of type: InjuryType) -> Int {
        injuryHistory.filter { $0.injuryTypeRaw == type.rawValue }.count
    }
    func familiarity(at position: Position) -> Int {
        if position == self.position { return 100 }
        return positionFamiliarity[position.rawValue] ?? 0
    }
    func schemeFam(for scheme: String) -> Int { schemeFamiliarity[scheme] ?? 0 }

    /// Domain-side spellings the shipped code (`DraftEngine.copyProspectMetadata`,
    /// the backfills) uses — both forward to the verbatim `MentalAttributeModel`.
    static let defaultLearning = MentalAttributeModel.defaultLearning
    static let defaultCompetitiveness = MentalAttributeModel.defaultCompetitiveness
    static func storedLearning(_ value: Int) -> Int { MentalAttributeModel.storedLearning(value) }
    static func storedCompetitiveness(_ value: Int) -> Int { MentalAttributeModel.storedCompetitiveness(value) }

    init(id: UUID = UUID(),
         fullName: String,
         position: Position,
         physical: PhysicalAttributes,
         mental: MentalAttributes,
         positionAttributes: PositionAttributes,
         isMoodDependent: Bool = false,
         personalityArchetype: PersonalityArchetype = .steadyPerformer,
         morale: Int = 70,
         overall: Int? = nil,
         schemeFamiliarity: [String: Int] = [:],
         fatigue: Int = 0,
         isHoldingOut: Bool = false) {
        self.id = id
        self.fullName = fullName
        self.position = position
        self.physical = physical
        self.mental = mental
        self.positionAttributes = positionAttributes
        self.isMoodDependent = isMoodDependent
        self.personalityArchetype = personalityArchetype
        self.morale = morale
        self.pinnedOverall = overall
        self.schemeFamiliarity = schemeFamiliarity
        self.fatigue = fatigue
        self.isHoldingOut = isHoldingOut
    }
}

/// A team is its roster + a stable id (the two members the sim touches) plus the
/// cap counter `PlayerRetirementEngine.retire` decrements.
final class Team {
    let id: UUID
    var players: [Player]
    var currentCapUsage: Int = 0
    init(id: UUID = UUID(), players: [Player]) {
        self.id = id
        self.players = players
    }

    /// Mirror of the shipped `Team.currentRoster()`. The shipped version fetches
    /// `Player` rows by `teamID` and documents its own fallback: "falls back to
    /// `players` only when the team has no model context: a league that was
    /// generated in memory and never inserted (the DEBUG balance harness)."
    /// That fallback IS this harness's situation, so returning `players` here is
    /// the shipped behaviour, not an approximation.
    func currentRoster() -> [Player] { players }
}

// MARK: - Position-versatility stubs (UNREACHABLE in this harness)
//
// `PlayerDevelopmentEngine.developPlayer` trains an alternate position only when
// `player.trainingPosition != nil`. No harness scenario ever sets one (position
// conversions are explicitly out of scope in development plan §3), so these two
// exist purely so the verbatim engine links. Their shipped counterparts hang off
// `VersatilityEngine.rate`, a positional-fit grader the harness does not compile.
// Both fail LOUD rather than quietly returning a plausible number: if a scenario
// ever does set a training position, the run stops instead of measuring a stub.
extension VersatilityDevelopmentEngine {
    static func trainPosition(
        player: Player,
        targetPosition: Position,
        positionCoach: Coach?,
        practiceIntensity: Double = 1.0
    ) -> Int {
        fatalError("harness: VersatilityDevelopmentEngine.trainPosition is not staged — no scenario sets trainingPosition")
    }

    static func versatilityCeiling(player: Player, at position: Position) -> Int {
        fatalError("harness: VersatilityDevelopmentEngine.versatilityCeiling is not staged — no scenario sets trainingPosition")
    }

    /// A completed position switch. Field-for-field the shipped shape, so the
    /// synced `TrainingFocusEngine.applyWeeklyFocusTick` signature compiles
    /// unchanged; nothing here ever constructs one.
    struct CompletedConversion {
        let playerID: UUID
        let playerName: String
        let from: Position
        let to: Position
        let overallBefore: Int
        let overallAfter: Int
    }

    /// The §5.3 conversion tick the weekly focus pass opens with.
    ///
    /// Unlike the two above this one IS called — once per club per week by the
    /// synced `applyWeeklyFocusTick` — so it cannot fail loud. It returns the
    /// empty list, which is EXACTLY what the shipped function returns here: a
    /// conversion only exists for a player with `trainingPosition != nil`, and
    /// no harness scenario ever sets one. The stub is the shipped behaviour for
    /// this input, not an approximation of it.
    static func tickConversions(roster: [Player], coaches: [Coach]) -> [CompletedConversion] {
        []
    }

    /// A conversion the staff would sign off on. Opaque here — the harness only
    /// needs the TYPE so `aiConsiderConversion`'s signature compiles.
    struct ConversionOffer {}

    /// The AI club's weekly "should we move somebody?" roll, called by the
    /// synced `TrainingFocusEngine.autoAssignFocus`.
    ///
    /// Returns `nil` — no club ever starts a conversion in a harness run. That
    /// is a deliberate scope exclusion, not an oversight: the shipped decision
    /// runs through `conversionOffers` → `VersatilityEngine.rate`, the
    /// positional-fit grader the harness does not compile (same reason
    /// `versatilityCeiling` above fails loud), and development plan §3 puts
    /// position conversions out of scope for the balance measurements. Every
    /// player therefore stays at his drafted position for the whole run.
    @discardableResult
    static func aiConsiderConversion(roster: [Player], coaches: [Coach]) -> ConversionOffer? {
        nil
    }
}

// MARK: - Incentive-package stub (UNREACHABLE in this harness)
//
// `MotivationState.incentiveChaseScore` — trigger 5b of the §2.3 table, and part
// of the verbatim `MotivationState.swift` the `career` scenario compiles — asks
// whether a player is carrying live incentive clauses. The real registry
// (`Domain/Models/Contract/Contract.swift`) keeps those packages in
// career-scoped `UserDefaults`, written only by the contract-negotiation screen,
// and depends on `CareerScopedDefaults` / SwiftData `Player.careerID`, none of
// which the harness has.
//
// Same argument as the `FaceLibrary` stub above: a package can only exist
// because a user negotiated one, so in a harness run every player has none. The
// stub returns the empty package for everybody, which makes `incentiveChaseScore`
// return 0 — byte-identical to what the shipped code returns for a synthetic
// league — and the synced source stays verbatim.
struct ContractIncentive {}

enum ContractIncentiveRegistry {
    static func incentives(for player: Player) -> [ContractIncentive] { [] }
    static func hasIncentives(for player: Player) -> Bool { false }
}

// MARK: - SimPlayer.init(from:) — harness overload
//
// The repo `SimPlayer` builds from a SwiftData `@Model Player` via `init(from:)`; the
// harness never splices that initializer (it owns a plain memberwise init instead). But
// the synced `GameSimulator.simulate` calls `homeRoster.map(SimPlayer.init(from:))`, so
// the harness supplies its own overload against the stub `Player` above. It preserves
// the player's UUID (delegating through the memberwise init's `id:` seam) so heat
// attribution and the fatigue/morale write-back key correctly.
extension SimPlayer {
    init(from p: Player) {
        self.init(
            fullName: p.fullName,
            position: p.position,
            physical: p.physical,
            mental: p.mental,
            positionAttributes: p.positionAttributes,
            overall: p.overall,
            morale: p.morale,
            isMoodDependent: p.isMoodDependent,
            personalityArchetype: p.personalityArchetype,
            schemeFamiliarity: p.schemeFamiliarity,
            fatigue: p.fatigue,
            id: p.id
        )
    }
}

// ---------------------------------------------------------------------------
// FaceLibrary stub (phase 4)
// ---------------------------------------------------------------------------
//
// The synced engine sources — `DraftClassBuilder` (prospect previews),
// `CoachingEngine` (candidate previews), `DraftEngine.copyProspectMetadata`
// (claim on signing) and `PlayerRetirementEngine.retire` (release) — all talk
// to `FaceLibrary.shared`. The real one lives in
// `Domain/Models/Faces/FaceLibrary.swift` and depends on `Career`, SwiftData
// `Player`/`Coach` and a 2 048-entry catalog, none of which the harness has or
// wants: portraits are decorative and cannot move a single balance number.
//
// So the harness owns a no-op stand-in that always reports "no face". Every
// call site tolerates `nil` (that is the shipped "images not generated yet"
// path), so the synced sources stay byte-identical to the repo.
enum FacePersonRole { case player, coach }

final class FaceLibrary {
    static let shared = FaceLibrary()
    private init() {}

    @discardableResult
    func assignFace(personID: UUID, role: FacePersonRole, age: Int, position: Position?) -> String? { nil }

    func previewFace(personID: UUID, role: FacePersonRole, age: Int, position: Position?) -> String? { nil }

    @discardableResult
    func claimFace(_ preferred: String?, personID: UUID, role: FacePersonRole,
                   age: Int, position: Position?) -> String? { nil }

    func releaseFace(_ faceID: String?, heldBy personID: UUID? = nil) {}
}
