import Foundation
import SwiftData

@Model
final class Player {
    var id: UUID
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

    /// The overall draft pick number (1-224) if this player was drafted, nil for UDFAs/veterans.
    var draftPickNumber: Int?

    /// Coaching staff's verbal assessment of this player's development ceiling.
    /// Stored as PotentialLabel.rawValue. Accuracy depends on coach quality and time with team.
    var assessedPotential: String?

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
        self.assessedPotential = assessedPotential
    }
}
