import SwiftUI
import SwiftData

// MARK: - Money

/// A coach salary (stored in thousands) as money a person reads.
///
/// Coach salaries are millions, so the raw thousands rendered as "$6 296K/yr" —
/// a grouped five-figure number in a unit nobody quotes contracts in, which
/// VoiceOver then read aloud as "six thousand two hundred ninety six thousand".
/// Everything else on these screens (budgets, candidate asks) is already in
/// millions; this brings the staff rows in line. Sub-million salaries keep the
/// K unit, ungrouped.
/// "a" or "an" for a role name. Staff roles start with O, A and I often enough
/// ("Offensive Coordinator", "Assistant Head Coach") that a hardcoded "a" was
/// audibly wrong in the spoken priority list.
func indefiniteArticle(for noun: String) -> String {
    guard let first = noun.first else { return "a" }
    return "aeiouAEIOU".contains(first) ? "an" : "a"
}

func coachSalaryText(_ thousands: Int) -> String {
    if thousands >= 1_000 {
        return String(format: "$%.1fM/yr", Double(thousands) / 1_000.0)
    }
    return "$\(thousands)K/yr"
}

// MARK: - Staff Tab Selection

enum StaffTab: String, CaseIterable {
    case staff = "Staff"
    case schemes = "Schemes"
    case review = "Review"
    case tree = "Tree"      // R30: coaching tree + legacy
}

// StaffNavDestination removed — replaced with separate state bindings to avoid
// SwiftUI navigationDestination(item:) confusion after dismiss/re-navigate cycles.

/// Unified hire sheet enum — SwiftUI only supports one reliable .sheet per view level,
/// so all hire sheets are funneled through a single .sheet(item:) binding.
enum HireSheetType: Identifiable {
    case coach(CoachRole)
    case scout(ScoutRole)
    case medical(CoachRole, [Coach])
    case offensiveScheme
    case defensiveScheme
    /// A result with no hire list behind it (wave 5b). The batch pass and the
    /// interview decision both end in a `DSResultSheet` without the user ever
    /// having opened a candidate list, so they need a slot in the ONE sheet
    /// binding rather than a second `.sheet` modifier of their own. The `UUID`
    /// is the identity: a second batch run must re-present rather than be
    /// swallowed as "same item".
    case result(UUID)
    /// The head-coach card's portrait picker. Not a hire — but it IS a modal,
    /// and it used to carry a `.sheet(isPresented:)` of its own buried in the
    /// `List`, which is a second modal point in one hierarchy.
    case portrait

    var id: String {
        switch self {
        case .coach(let r):      return "coach-\(r.rawValue)"
        case .scout(let r):      return "scout-\(r.rawValue)"
        case .medical(let r, _): return "medical-\(r.rawValue)"
        case .offensiveScheme:   return "scheme-offense"
        case .defensiveScheme:   return "scheme-defense"
        case .result(let uuid):  return "result-\(uuid.uuidString)"
        case .portrait:          return "portrait"
        }
    }

    /// Whether this face brings its own navigation chrome and dismissal, so the
    /// host must not draw a second bar or a second "Close" over it (P5's
    /// one-dismissal corollary). `ChangeUserPortraitSheet` ships its own
    /// `NavigationStack` with Cancel/Done; `DSResultSheet` ends in its own
    /// action bar and has no dismissal at all.
    var bringsOwnChrome: Bool {
        switch self {
        case .portrait, .result: return true
        default:                 return false
        }
    }
}

// MARK: - Staff outcome (wave 5b)

/// What a staff process produced, in `DSResultSheet`'s grammar.
///
/// UI_REDESIGN_VISION §2.6. This screen used to answer every commit with the
/// same top toast — a feedback metaphor unique to this file, listed in §0's
/// four — which meant a hire, a nine-man batch pass and a coordinator walking
/// out of the building all got one grey line that faded after three seconds.
/// A batch pass in particular *has* numbers: how many were signed, what it
/// spent, how many chairs stayed open, how many hires clash with the head
/// coach. The toast threw all four away.
///
/// Deliberately not `Identifiable`: it is never the sheet's item. The sheet's
/// item is ``HireSheetType``, and this rides alongside it so that a flow which
/// ENDS (a hire) swaps its content without changing the sheet's identity — the
/// dismiss-and-re-present race that every timing hack in this file existed to
/// paper over.
struct StaffOutcome {
    var tone: DSResultSheet.Tone = .good
    /// The screen ident — "STAFF HIRING", "COACHING CAROUSEL".
    var eyebrow: String
    var headline: String
    var message: String?
    var chips: [DSResultSheet.Chip] = []
    var cost: String?
    var continueTitle: String = "Continue"
}

struct CoachingStaffView: View {

    let career: Career
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var allCoachesUnscoped: [Coach]
    @Query private var allScoutsUnscoped: [Scout]

    @Query private var allPlayersUnscoped: [Player]
    @Query private var allTeamsUnscoped: [Team]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here. Without it the
    // screen mixes two careers' populations into one list.
    private var allCoaches: [Coach] { allCoachesUnscoped.filter { $0.careerID == career.id } }
    private var allScouts: [Scout] { allScoutsUnscoped.filter { $0.careerID == career.id } }
    private var allPlayers: [Player] { allPlayersUnscoped.filter { $0.careerID == career.id } }
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == career.id } }

    // MARK: - Tab State (#107)
    @State private var selectedTab: StaffTab = .staff

    /// Transient one-liner explaining why a locked tab cannot be opened.
    @State private var lockedTabHint: String?

    // MARK: - Task Confirms (#162)

    /// ``GameTask/matchKey``s this cycle has already had confirmed, read out of
    /// ``TaskProgressStore`` when the screen opens and updated in place by
    /// `confirmTask`.
    ///
    /// Held in `@State` rather than recomputed off the store on every redraw:
    /// `CareerScopedDefaults` is not observable, so a computed read would draw
    /// the pre-confirm bar forever and the tab tick would never appear until the
    /// screen was left and re-entered.
    @State private var confirmedTaskKeys: Set<String> = []

    // MARK: - Hiring Result State (#49, wave 5b)

    /// What the last staff commit produced. Non-nil replaces the sheet's flow
    /// content with a `DSResultSheet` (§2.6) — the top toast this screen used
    /// to own is gone.
    @State private var sheetOutcome: StaffOutcome?

    // Lock-in moved to Dashboard workflow (CoachingStaffReviewSheet)

    // MARK: - Collapsible Section State (#80, #274: AppStorage to survive sheet dismiss cycles)
    @AppStorage("staff_isCoordinatorsExpanded") private var isCoordinatorsExpanded: Bool = true
    @AppStorage("staff_isPositionCoachesExpanded") private var isPositionCoachesExpanded: Bool = true
    @AppStorage("staff_isMedicalExpanded") private var isMedicalExpanded: Bool = true
    @AppStorage("staff_isScoutingExpanded") private var isScoutingExpanded: Bool = true

    // MARK: - Auto-Hire State (Batch 2E)
    /// True while the bulk hiring pass is running (it generates a candidate
    /// pool per vacancy on the main actor, so the button has to show work).
    @State private var isAutoHiring = false
    /// "Hiring Defensive Coordinator…" — which vacancy the pass is on.
    @State private var autoHireStatus: String?

    // MARK: - Navigation State
    @State private var activeHireSheet: HireSheetType?  // Single sheet for all hire flows
    @State private var detailCoachID: UUID?             // Pushes CoachDetailView via navigationDestination
    // "Change portrait" on the head-coach card — the one place in a running
    // career where `Career.avatarID` can still be edited — used to own a
    // `.sheet(isPresented:)` of its own, deep inside the `List`. That is a
    // second modal point in one hierarchy, which is the recurring silent-
    // dismiss bug in this codebase, so it moved into the one sheet enum
    // (`HireSheetType.portrait`) with everything else.
    @State private var detailScoutID: UUID?             // Pushes ScoutDetailView via navigationDestination

    /// Coaches filtered to this team, derived from @Query result.
    private var coaches: [Coach] {
        guard let teamID = career.teamID else { return [] }
        return allCoaches.filter { $0.teamID == teamID }
    }

    /// Task #96 — the medical hire sheets show the league's real out-of-work
    /// staff alongside the invented field, for the same reason `HireCoachView`
    /// does: the AI clubs have been hiring out of that bench every offseason and
    /// the user could not see it. Exact title only, so nothing has to be
    /// re-priced or re-titled before he actually signs anybody.
    private func medicalHireCandidates(role: CoachRole) -> [Coach] {
        let invented = CoachingEngine.generateCoachCandidates(
            role: role,
            count: Int.random(in: 8...12),
            teamBudget: coachingBudget,
            teamWins: team?.wins ?? 8,
            teamReputation: career.reputation
        )
        let market = CoachMarketEngine.availableBench(allCoaches).filter { $0.role == role }
        return market + invented
    }

    /// Scouts filtered to this team.
    private var scouts: [Scout] {
        guard let teamID = career.teamID else { return [] }
        return allScouts.filter { $0.teamID == teamID }
    }

    /// This team's scouts read straight out of the store instead of off
    /// `@Query`.
    ///
    /// `HireScoutView.hire()` inserts the candidate, saves, and then calls
    /// `onHired` **synchronously in the same call stack** — before SwiftUI runs
    /// the view update in which `@Query` re-fetches. Anything the result sheet
    /// derives from `scouts` at that moment is the pre-insert snapshot, and
    /// `StaffOutcome` freezes it: the seat still read vacant, so the salary
    /// chip printed "$0.0M" and the scouting-left chip and the "jobs still
    /// open" count were both a hire behind. The coach path does not need this
    /// because it reports from `fullScreenCover(onDismiss:)`, i.e. a later
    /// runloop, and the batch pass yields between hires. A fetch against the
    /// same context sees the row the hire view has just saved.
    private func scoutsFromStore() -> [Scout] {
        guard let teamID = career.teamID else { return [] }
        let stored = (try? modelContext.fetch(FetchDescriptor<Scout>())) ?? []
        return stored.filter { $0.careerID == career.id && $0.teamID == teamID }
    }

    /// Players on this team's roster.
    private var rosterPlayers: [Player] {
        guard let teamID = career.teamID else { return [] }
        return allPlayers.filter { $0.teamID == teamID }
    }

    /// Offensive players on the roster.
    private var offensivePlayers: [Player] {
        rosterPlayers.filter { $0.position.side == .offense }
            .sorted { $0.position.rawValue < $1.position.rawValue }
    }

    /// Defensive players on the roster.
    private var defensivePlayers: [Player] {
        rosterPlayers.filter { $0.position.side == .defense }
            .sorted { $0.position.rawValue < $1.position.rawValue }
    }

    /// The team's owner (for budget info).
    private var owner: Owner? {
        team?.owner
    }

    /// #267: The player's team (for wins/prestige data).
    private var team: Team? {
        guard let teamID = career.teamID else { return nil }
        return allTeams.first { $0.id == teamID }
    }

    // MARK: - Budget Calculations

    /// #133: THE staff reading for this club — seats, all three pots, the
    /// required-seat list and the advance gate. Everything below is a name for
    /// a field of it.
    ///
    /// This screen used to own its own copy of each: a role filter for the
    /// medical split, a `?? 20_000` / `?? 4_000` / `?? 2_500` invented envelope
    /// per pot, and a per-ROW salary sum that charged duplicate and
    /// out-of-seat rows to a budget whose denominator excluded them. The
    /// dashboard tile, the hire flows, the review sheet and the owner's budget
    /// screen each had their own variant of the same three, which is why the
    /// four surfaces printed four numbers for one club.
    private var ledger: StaffLedger {
        StaffLedger(careerRole: career.role, coaches: coaches, scouts: scouts, owner: owner)
    }

    /// R31: Roles paid from the medical pot rather than the coaching pot.
    private static var medicalRoles: Set<CoachRole> { StaffLedger.medicalRoles }

    /// Total coaching salary currently committed (in thousands).
    /// R31: medical staff no longer draw from this pot — they have their own budget.
    private var totalCoachSalaryUsed: Int { ledger.committedCoaching }

    /// Total scouting salary currently committed (in thousands).
    private var totalScoutSalaryUsed: Int { ledger.committedScouting }

    /// R31: Total medical staff salary currently committed (in thousands).
    private var totalMedicalSalaryUsed: Int { ledger.committedMedical }

    /// Total staff salary used (coaches + medical + scouts).
    private var totalStaffSalaryUsed: Int { ledger.committedTotal }

    /// Coaching budget from the owner (in thousands).
    private var coachingBudget: Int { ledger.coachingBudget }

    /// R27: Dedicated scouting budget from the owner (in thousands).
    private var scoutingBudget: Int { ledger.scoutingBudget }

    /// R31: Dedicated medical budget from the owner (in thousands).
    private var medicalBudget: Int { ledger.medicalBudget }

    /// Remaining coaching budget available for new coach hires.
    /// R27: scouts no longer draw from this pot — they have their own budget.
    private var remainingBudget: Int { ledger.remainingCoaching }

    /// R27: Remaining scouting budget available for new scout hires.
    private var remainingScoutBudget: Int { ledger.remainingScouting }

    /// R31: Remaining medical budget available for new medical hires.
    private var remainingMedicalBudget: Int { ledger.remainingMedical }

    // MARK: - Grouped coaches

    private var headCoach: Coach? {
        coaches.first { $0.role == .headCoach }
    }

    private var assistantHeadCoach: Coach? {
        coaches.first { $0.role == .assistantHeadCoach }
    }

    private var coordinators: [Coach] {
        coaches.filter { [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    private var positionCoaches: [Coach] {
        coaches.filter { [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    // MARK: - Medical staff

    private var medicalStaff: [Coach] {
        coaches.filter { [.teamDoctor, .physio, .headTrainer].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    // MARK: - Scouting department

    private var chiefScout: Scout? {
        scouts.first { $0.scoutRole == .chiefScout }
    }

    private var regionalScouts: [Scout] {
        scouts.filter { $0.scoutRole != .chiefScout }
            .sorted { $0.scoutRole.sortOrder < $1.scoutRole.sortOrder }
    }

    // MARK: - Vacant roles

    /// #133: the seat list comes from `StaffSlots` so this screen's "23
    /// vacancies", the dashboard tile's "x / 23" and the review sheet's
    /// coaching count are three readings of ONE definition. (`StaffSlots`
    /// already drops the head-coach chair for a GM+HC career — the player is
    /// sitting in it.)
    private var vacantCoachRoles: [CoachRole] { ledger.vacantCoachRoles }

    private var vacantScoutRoles: [ScoutRole] { ledger.vacantScoutRoles }

    // MARK: - Staff Tier Headers
    //
    // Every staff section leads with the same 18pt disc so the hiring hierarchy
    // reads as one column. Numbered discs mark the 1-2-3 priority ladder; the
    // hollow variant marks a section that sits outside it (assistant HC).

    enum StaffTierBadge {
        case tier(Int)
        case optional(icon: String)
    }

    @ViewBuilder
    private func staffTierBadge(_ badge: StaffTierBadge) -> some View {
        switch badge {
        case .tier(let n):
            Text("\(n)")
                .font(.system(size: DSType.Size.micro, weight: .black))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentGold))
        case .optional(let icon):
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .frame(width: 18, height: 18)
                .background(Circle().strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1.5))
        }
    }

    private func staffTierHeader(badge: StaffTierBadge, title: String) -> some View {
        HStack(spacing: 6) {
            staffTierBadge(badge)
            Text(title)
        }
    }

    // MARK: - Hiring priority & budget helpers

    /// Whether any staff budget is over (negative remaining). (R27/R31: split pots)
    private var isBudgetOverspent: Bool { ledger.isOverspent }

    /// Required roles that must be filled before locking in staff.
    /// #158: the same list the calendar's advance gate blocks on.
    private var requiredCoachRoles: [CoachRole] { ledger.requiredCoachRoles }

    /// Whether all required coaching positions are filled.
    private var allRequiredRolesFilled: Bool { ledger.allRequiredRolesFilled }

    /// Missing required roles for display in the warning.
    private var missingRequiredRoles: [CoachRole] { ledger.missingRequiredRoles }

    /// Whether the device is in iPad portrait (regular width) for 2-column layout.
    private var isIPadPortrait: Bool {
        horizontalSizeClass == .regular
    }

    /// Whether the Schemes tab is available (requires at least one coordinator).
    private var isSchemesTabAvailable: Bool {
        coaches.contains(where: { $0.role == .offensiveCoordinator }) ||
        coaches.contains(where: { $0.role == .defensiveCoordinator })
    }

    /// Whether both offensive and defensive schemes have been set by coordinators.
    private var areSchemesSet: Bool {
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })
        return oc?.offensiveScheme != nil && dc?.defensiveScheme != nil
    }

    /// Whether the Review tab is available (requires at least one hire).
    private var isReviewTabAvailable: Bool {
        !coaches.isEmpty || !scouts.isEmpty
    }

    /// Priority level for a vacant coaching role.
    private enum HiringPriority {
        case high, recommended, normal

        var label: String {
            switch self {
            case .high:        return "High Priority"
            case .recommended: return "Recommended"
            case .normal:      return ""
            }
        }
    }

    private func hiringPriority(for role: CoachRole) -> HiringPriority {
        switch role {
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return .high
        case .qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach:
            return .recommended
        case .teamDoctor, .physio, .headTrainer:
            return .recommended
        default:
            return .normal
        }
    }

    /// Estimated salary range string for a vacant role.
    ///
    /// Derived from `CoachRole.salaryRange` — the band the candidate generator
    /// actually draws from — rather than the hand-written four-case table that
    /// used to live here. That table was a guess and it was wrong in both
    /// directions: it promised "~$2-5M/yr" for a coordinator whose top man asks
    /// $6.3M, and capped the head coach at $8M when the range runs to $32M.
    private func estimatedSalaryRange(for role: CoachRole) -> String {
        let range = role.salaryRange
        func millions(_ thousands: Int) -> String {
            let m = Double(thousands) / 1_000.0
            return m < 10 ? String(format: "%.1f", m) : String(format: "%.0f", m)
        }
        return "~$\(millions(range.min))-\(millions(range.max))M/yr"
    }

    /// Minimum salary estimate (in thousands) for a vacant coaching role.
    private func estimatedMinimumSalary(for role: CoachRole) -> Int {
        switch role {
        case .headCoach:                                          return 3_000
        case .assistantHeadCoach:                                 return 1_000
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator: return 2_000
        default:                                                  return 500
        }
    }

    /// Minimum salary estimate (in thousands) for a vacant scout role.
    private func estimatedMinimumScoutSalary(for role: ScoutRole) -> Int {
        switch role {
        case .chiefScout: return 200
        default:          return 80
        }
    }

    /// #155: Estimated minimum cost to fill all vacant positions.
    private var estimatedMinimumToFillAll: Int {
        let coachCost = vacantCoachRoles.reduce(0) { $0 + estimatedMinimumSalary(for: $1) }
        let scoutCost = vacantScoutRoles.reduce(0) { $0 + estimatedMinimumScoutSalary(for: $1) }
        return coachCost + scoutCost
    }

    // MARK: - Auto-Hire (Batch 2E)
    //
    // A fresh front office opens this screen on 21+ vacancies, each behind its
    // own full-screen hire sheet with a 25-man table in it. Filling the staff
    // by hand is a 21-sheet errand before the first snap is ever played, and
    // it is where a casual manager quits. This fills every hole in one tap
    // from the SAME candidate generator the manual sheets use — no parallel
    // pool, no invented coaches — while respecting all three budget pots.
    // Manual hiring is untouched; this is the escape hatch, not the flow.

    /// One open job, coach or scout.
    enum StaffVacancy: Identifiable, Hashable {
        case coach(CoachRole)
        case scout(ScoutRole)

        var id: String {
            switch self {
            case .coach(let role): return "coach-\(role.rawValue)"
            case .scout(let role): return "scout-\(role.rawValue)"
            }
        }

        var displayName: String {
            switch self {
            case .coach(let role): return role.displayName
            case .scout(let role): return role.displayName
            }
        }

        var abbreviation: String {
            switch self {
            case .coach(let role): return role.abbreviation
            case .scout(let role): return role.abbreviation
            }
        }
    }

    /// Which of the three budgets a job is paid from.
    private enum StaffPot: Hashable { case coaching, medical, scouting }

    private func pot(for vacancy: StaffVacancy) -> StaffPot {
        switch vacancy {
        case .coach(let role): return Self.medicalRoles.contains(role) ? .medical : .coaching
        case .scout:           return .scouting
        }
    }

    private func remaining(_ pot: StaffPot) -> Int { remaining(pot, in: ledger) }

    /// Same reading against a supplied book, so a caller holding a fresher
    /// ledger than `@Query` can ask it (see `scoutsFromStore()`).
    private func remaining(_ pot: StaffPot, in book: StaffLedger) -> Int {
        switch pot {
        case .coaching: return book.remainingCoaching
        case .medical:  return book.remainingMedical
        case .scouting: return book.remainingScouting
        }
    }

    private func total(_ pot: StaffPot) -> Int {
        switch pot {
        case .coaching: return coachingBudget
        case .medical:  return medicalBudget
        case .scouting: return scoutingBudget
        }
    }

    /// Hiring order, most decisive job first.
    ///
    /// Head coach and the two coordinators set the schemes everything else
    /// hangs off; the position coaches that drive development come next, then
    /// the medical room, and the assistant HC last because he is optional.
    private static let autoHireCoachOrder: [CoachRole] = [
        .headCoach,
        .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator,
        .qbCoach, .olCoach, .dlCoach, .dbCoach, .wrCoach, .lbCoach, .rbCoach, .strengthCoach,
        .headTrainer, .teamDoctor, .physio,
        .assistantHeadCoach
    ]

    private static let autoHireScoutOrder: [ScoutRole] = [
        .chiefScout,
        .regionalScout1, .regionalScout2, .regionalScout3, .regionalScout4, .regionalScout5,
        .extraScout1, .extraScout2
    ]

    /// Every open job in hiring order.
    private var orderedVacancies: [StaffVacancy] { orderedVacancies(in: ledger) }

    /// Same list against a supplied book (see `scoutsFromStore()`).
    private func orderedVacancies(in book: StaffLedger) -> [StaffVacancy] {
        let vacantCoaches = Set(book.vacantCoachRoles)
        let vacantScouts = Set(book.vacantScoutRoles)
        return Self.autoHireCoachOrder.filter { vacantCoaches.contains($0) }.map { StaffVacancy.coach($0) }
            + Self.autoHireScoutOrder.filter { vacantScouts.contains($0) }.map { StaffVacancy.scout($0) }
    }

    /// Planned spend band per job, in thousands.
    ///
    /// Coach figures are the authored `CoachRole.salaryRange`; the scout band
    /// mirrors the asking prices `CoachingEngine.generateScoutCandidates`
    /// actually rolls (chief 650-2000, everyone else 150-1000), so the
    /// projection in the button subtitle matches the pool the pass will read.
    private func plannedSalaryBand(for vacancy: StaffVacancy) -> (min: Int, avg: Int) {
        switch vacancy {
        case .coach(let role):
            let range = role.salaryRange
            return (range.min, range.avg)
        case .scout(let role):
            return role == .chiefScout ? (650, 1_325) : (150, 575)
        }
    }

    /// Spend target per vacancy, scaled so each pot's whole plan fits its
    /// budget. Planning the pass up front is what stops a $16M head coach from
    /// eating the money the eight position coaches need.
    private var autoHireAllocations: [String: Int] {
        var result: [String: Int] = [:]
        for pot in [StaffPot.coaching, .medical, .scouting] {
            let jobs = orderedVacancies.filter { self.pot(for: $0) == pot }
            guard !jobs.isEmpty else { continue }
            let available = max(0, remaining(pot))
            let bands = jobs.map { plannedSalaryBand(for: $0) }
            let totalAvg = bands.reduce(0) { $0 + $1.avg }
            let totalMin = bands.reduce(0) { $0 + $1.min }

            if totalAvg <= available {
                // Comfortable: everyone gets the going rate for the job.
                for (job, band) in zip(jobs, bands) { result[job.id] = band.avg }
            } else if totalMin <= available {
                // Tight: pay the floor everywhere, split what is left over the
                // floor-to-average gap proportionally.
                let slack = Double(available - totalMin) / Double(max(1, totalAvg - totalMin))
                for (job, band) in zip(jobs, bands) {
                    result[job.id] = band.min + Int((Double(band.avg - band.min) * slack).rounded())
                }
            } else {
                // Broke: fund floors in priority order until the pot runs dry —
                // the tail simply stays vacant rather than pushing it over.
                var left = available
                for (job, band) in zip(jobs, bands) {
                    let take = min(band.min, left)
                    result[job.id] = take
                    left -= take
                }
            }
        }
        return result
    }

    /// Projected spend per pot, for the button subtitle.
    private func projectedSpend(_ pot: StaffPot) -> Int {
        let allocations = autoHireAllocations
        return orderedVacancies
            .filter { self.pot(for: $0) == pot }
            .reduce(0) { $0 + (allocations[$1.id] ?? 0) }
    }

    /// "spends ~$31.0M of $38.4M coaching · ~$1.7M of $2.5M medical"
    private var autoHireSpendSubtitle: String {
        var parts: [String] = []
        for (pot, name) in [(StaffPot.coaching, "coaching"), (.medical, "medical"), (.scouting, "scouting")] {
            let projected = projectedSpend(pot)
            guard projected > 0 else { continue }
            parts.append("~$\(formatBudget(projected))M of $\(formatBudget(total(pot)))M \(name)")
        }
        return parts.isEmpty ? "" : "Spends " + parts.joined(separator: " · ")
    }

    // MARK: - Auto-Hire Execution

    /// Fills every open job with the best candidate its allocation can buy.
    ///
    /// Runs on the main actor because `generateCoachCandidates` touches
    /// SwiftData-backed models; the `Task.yield()` between jobs is what lets
    /// the progress line repaint instead of freezing for a whole second.
    @MainActor
    private func runAutoHire() async {
        guard let teamID = career.teamID, !isAutoHiring else { return }
        let plan = orderedVacancies
        guard !plan.isEmpty else { return }

        isAutoHiring = true
        let allocations = autoHireAllocations
        var wallet: [StaffPot: Int] = [
            .coaching: max(0, remainingBudget),
            .medical:  max(0, remainingMedicalBudget),
            .scouting: max(0, remainingScoutBudget)
        ]
        // Money a job did not need rolls forward to the rest of its own pot.
        var carry: [StaffPot: Int] = [.coaching: 0, .medical: 0, .scouting: 0]
        var hires = 0
        var spent = 0
        /// Task #135: seats that could only be filled by a man the staff screen
        /// will badge ✗ Conflict. Counted so the toast can say so — a hole is
        /// worse than a clash, but an unannounced clash is worse than both.
        var conflictHires = 0

        // Jobs the planned allocation could not buy, kept in priority order
        // for the second pass below.
        var unfilled: [StaffVacancy] = []

        // Task #135: who the rest of the staff is judged for fit against.
        // Tracked locally rather than re-read off `headCoach` between jobs
        // because the `@Query` behind it does not refresh inside this loop —
        // the head coach is the FIRST job in `autoHireCoachOrder` precisely so
        // everyone hired after him can be measured against him.
        var hcPersonality = autoHireReferencePersonality

        for vacancy in plan {
            autoHireStatus = "Hiring \(vacancy.displayName)…"
            await Task.yield()

            let potKey = pot(for: vacancy)
            let allocation = (allocations[vacancy.id] ?? 0) + (carry[potKey] ?? 0)
            let cap = min(wallet[potKey] ?? 0, allocation)
            guard cap > 0,
                  let result = signBest(for: vacancy, cap: cap, teamID: teamID, hcPersonality: hcPersonality)
            else {
                unfilled.append(vacancy)
                continue
            }
            if case .coach(.headCoach) = vacancy, let hired = result.hired {
                hcPersonality = hired.personality
            }
            wallet[potKey] = (wallet[potKey] ?? 0) - result.salary
            carry[potKey] = max(0, allocation - result.salary)
            spent += result.salary
            hires += 1
            if result.wasConflict { conflictHires += 1 }
        }

        // Task #106: second pass. A job whose allocation lands under every
        // asking price on the market — the assistant HC, funded off the tail
        // of the coaching plan — used to be reported "no room in the budget"
        // while his pot still held millions. Re-offer whatever the first pass
        // left in the wallet, still most decisive job first, so the only roles
        // that stay open are the ones the money genuinely cannot reach.
        var stillOpenByPot: [StaffPot: Int] = [:]
        for vacancy in unfilled { stillOpenByPot[pot(for: vacancy), default: 0] += 1 }

        for vacancy in unfilled {
            let potKey = pot(for: vacancy)
            let walletLeft = wallet[potKey] ?? 0
            let peers = max(1, stillOpenByPot[potKey] ?? 1)
            stillOpenByPot[potKey] = peers - 1
            guard walletLeft > 0 else { continue }

            // Re-offer the wallet, but not ALL of it while pot-mates still
            // wait: the first retried job gets at least its going rate and at
            // most an even share of what is left, so a $12M assistant cannot
            // eat the money two position coaches behind him need — the exact
            // failure the planned pass exists to prevent.
            let fairShare = walletLeft / peers
            let cap = min(walletLeft, max(plannedSalaryBand(for: vacancy).avg, fairShare))

            autoHireStatus = "Hiring \(vacancy.displayName)…"
            await Task.yield()

            guard let result = signBest(
                for: vacancy, cap: cap, teamID: teamID, hcPersonality: hcPersonality
            ) else { continue }
            if case .coach(.headCoach) = vacancy, let hired = result.hired {
                hcPersonality = hired.personality
            }
            wallet[potKey] = walletLeft - result.salary
            spent += result.salary
            hires += 1
            if result.wasConflict { conflictHires += 1 }
        }

        try? modelContext.save()
        autoHireStatus = nil
        isAutoHiring = false

        // Keep every section open so the newly filled rows are visible.
        isCoordinatorsExpanded = true
        isPositionCoachesExpanded = true
        isMedicalExpanded = true
        isScoutingExpanded = true

        // §2.6: a process ends in a result sheet. The batch pass is the one
        // commit on this screen with real arithmetic behind it — men signed,
        // money spent, chairs left open, fits it had to swallow — and all four
        // numbers used to be flattened into one grey line that faded after four
        // seconds.
        let stillOpen = plan.count - hires
        var message = hires == 0
            ? "Nothing in the market was affordable inside your budget."
            : "The pass worked down the ladder, most decisive job first."
        if hires > 0 && stillOpen > 0 {
            message += " **\(stillOpen)** role\(stillOpen == 1 ? "" : "s") stayed open — no room in the budget."
        }
        // Task #135: the pass refuses a Conflict fit while any workable
        // candidate is affordable. When it took one anyway, that was the whole
        // market for the chair — say so rather than let the user find the ✗
        // himself two rows down.
        if conflictHires > 0 {
            message += " **\(conflictHires)** hire\(conflictHires == 1 ? "" : "s") clash with your head coach"
                + " — nobody else was affordable for those chairs."
        }

        presentOutcome(StaffOutcome(
            tone: hires == 0 ? .bad : (stillOpen > 0 || conflictHires > 0 ? .neutral : .good),
            eyebrow: "Staff hiring \u{00B7} batch",
            headline: hires == 0
                ? "Nobody hired"
                : "\(hires) hired for $\(formatBudget(spent))M",
            message: message,
            chips: [
                .init(id: "hired", label: "Hired", value: "\(hires)", context: "of \(plan.count) jobs"),
                .init(
                    id: "spent",
                    label: "Spent",
                    value: "$\(formatBudget(spent))M",
                    context: "across three pots"
                ),
                .init(
                    id: "open",
                    label: "Still open",
                    value: "\(stillOpen)",
                    context: stillOpen > 0 ? "hire by hand" : "none",
                    valueColor: stillOpen > 0 ? .alertOrange : .textPrimary
                ),
                .init(
                    id: "clash",
                    label: "Clashes",
                    value: "\(conflictHires)",
                    context: conflictHires > 0 ? "with your HC" : "none",
                    valueColor: conflictHires > 0 ? .dangerText : .textPrimary
                )
            ],
            cost: "Leaves **$\(formatBudget(max(0, remainingBudget)))M** coaching, "
                + "**$\(formatBudget(max(0, remainingMedicalBudget)))M** medical and "
                + "**$\(formatBudget(max(0, remainingScoutBudget)))M** scouting. "
                + "You can still replace anybody by hand."
        ))
    }

    /// Signs the best candidate `cap` can buy for one open job and returns his
    /// salary (and, for a coach, the man himself); nil when nothing on that
    /// market fits the cap. Shared by both auto-hire passes so the planned offer
    /// and the leftover-wallet offer shop the exact same pool.
    private func signBest(
        for vacancy: StaffVacancy,
        cap: Int,
        teamID: UUID,
        hcPersonality: PersonalityArchetype?
    ) -> (salary: Int, hired: Coach?, wasConflict: Bool)? {
        switch vacancy {
        case .coach(let role):
            // Task #96: auto-hire shops the same market the manual sheet
            // does — real out-of-work coaches of this exact title first.
            let pool = CoachMarketEngine.availableBench(allCoaches).filter { $0.role == role }
                + CoachingEngine.generateCoachCandidates(
                    role: role,
                    count: 20,
                    teamBudget: coachingBudget,
                    teamWins: team?.wins ?? 8,
                    teamReputation: career.reputation
                )
            guard let pick = bestAffordableCoach(
                in: pool, cap: cap, role: role, hcPersonality: hcPersonality
            ) else {
                return nil
            }
            hire(coach: pick.coach, teamID: teamID)
            return (pick.coach.salary, pick.coach, pick.wasConflict)

        case .scout(let role):
            // Same seeded pool the manual sheet shows for this team/role/season.
            let pool = CoachingEngine.generateScoutCandidates(
                role: role,
                count: 20,
                seed: CoachingEngine.scoutPoolSeed(
                    teamID: teamID,
                    role: role,
                    season: career.currentSeason
                )
            )
            guard let pick = bestAffordableScout(in: pool, cap: cap) else { return nil }
            hire(scout: pick, teamID: teamID)
            return (pick.salary, nil, false)
        }
    }

    /// The personality every auto-hire is judged for fit against: the user
    /// himself when he coaches the team, otherwise whoever holds the HC chair.
    ///
    /// Deliberately the same reference `chemistryWithHC` uses to draw the
    /// ✓ / ⚠ Tension / ✗ Conflict badge on the staff rows, so the button cannot
    /// hire a man the screen then flags as a clash.
    private var autoHireReferencePersonality: PersonalityArchetype? {
        if career.role == .gmAndHeadCoach {
            return coachingStylePersonality(career.coachingStyle)
        }
        return headCoach?.personality
    }

    /// Which band the staff row for this man would wear, against the head coach
    /// he would work for. `nil` when there is nobody to judge him against.
    ///
    /// The SAME call `chemistryWithHC` makes for the ✓ / ⚠ / ✗ badge, so a
    /// candidate cannot be classified one way by the hiring pass and another by
    /// the screen it hands him to.
    private func autoHireBand(
        _ coach: Coach,
        hcPersonality: PersonalityArchetype?
    ) -> CoachingEngine.ChemistryBand? {
        guard let hcPersonality else { return nil }
        return CoachingEngine.chemistryBand(
            score: CoachingEngine.coachChemistry(coachA: hcPersonality, coachB: coach.personality)
        )
    }

    /// Ranking score for the auto-hire pass: overall rating, adjusted for how
    /// the man fits the head coach he would work for.
    ///
    /// Task #135: the button promised "the best affordable candidate for each"
    /// and delivered it on OVR alone, which is how one pass could hand a GM+HC
    /// player three coordinators the very next screen labelled ⚠ Tension and
    /// ✗ Conflict. A Tension pick is a trade-off worth paying for talent; a
    /// Conflict pick is not, so Conflict is no longer a penalty at all — it is
    /// a REFUSAL, applied in `bestAffordableCoach` before this ranking runs.
    /// Budget is untouched: the cap filter still runs first and nothing here can
    /// raise a bid.
    private func autoHireRank(
        _ coach: Coach,
        role: CoachRole?,
        hcPersonality: PersonalityArchetype?
    ) -> Int {
        // ROLE-WEIGHTED, not flat overall (QA 2026-08-21). A live run auto-hired
        // an offensive coordinator with play-calling 47 and called him "the best
        // affordable candidate": he WAS the best on the twelve-attribute mean,
        // and the mean gives a coordinator's defining skill one twelfth of the
        // say. A coordinator who cannot call plays is not a good coordinator at
        // any price. Blend rather than replace — the mean still carries the rest
        // of the man, and the specialty is only the loudest voice, not the only
        // one.
        let ovr = coachOverall(coach)
        let specialty = autoHireSpecialty(coach, role: role)
        let base = specialty.map { (ovr + $0 * 2) / 3 } ?? ovr
        switch autoHireBand(coach, hcPersonality: hcPersonality) {
        case .good:     return base + 2
        case .tension:  return base - 4
        case .conflict: return base - 9
        case nil:       return base
        }
    }

    /// The attribute a role is actually hired for, or `nil` where the twelve-way
    /// mean is already the right answer (an assistant head coach has no single
    /// defining skill; a scout is ranked by its own pass).
    private func autoHireSpecialty(_ coach: Coach, role: CoachRole?) -> Int? {
        switch role {
        case .offensiveCoordinator, .defensiveCoordinator:
            // Play-calling first, game-planning second: the two halves of a
            // coordinator's week.
            return (coach.playCalling * 2 + coach.gamePlanning) / 3
        case .qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach:
            // A position coach is hired to make his group better.
            return coach.playerDevelopment
        case .specialTeamsCoordinator:
            return (coach.playCalling + coach.discipline) / 2
        default:
            return nil
        }
    }

    /// Best man the allocation can buy: highest fit-adjusted rating inside the
    /// cap, and the cheaper of two equals.
    ///
    /// Task #135 — **a Conflict fit is refused outright.** The pass shops the
    /// non-conflicting half of the affordable pool first, and only when that
    /// half is empty does it fall back to the conflicting half, because an
    /// EMPTY seat is worse than a bad one: a vacant coordinator costs -20%
    /// offence/defence efficiency and slower development every week, where a
    /// clash costs harmony the user can fix by replacing one man. The fallback
    /// is reported (`wasConflict`) rather than taken silently — the toast names
    /// how many chairs were filled that way, so the ✗ badges the user is about
    /// to see on the staff list are ones he was told about.
    private func bestAffordableCoach(
        in pool: [Coach],
        cap: Int,
        role: CoachRole?,
        hcPersonality: PersonalityArchetype?
    ) -> (coach: Coach, wasConflict: Bool)? {
        let affordable = pool.filter { $0.salary <= cap }
        guard !affordable.isEmpty else { return nil }

        func best(_ candidates: [Coach]) -> Coach? {
            candidates.max { a, b in
                let (ra, rb) = (
                    autoHireRank(a, role: role, hcPersonality: hcPersonality),
                    autoHireRank(b, role: role, hcPersonality: hcPersonality)
                )
                if ra != rb { return ra < rb }
                return a.salary > b.salary
            }
        }

        let workable = affordable.filter {
            autoHireBand($0, hcPersonality: hcPersonality) != .conflict
        }
        if let pick = best(workable) { return (pick, false) }
        guard let pick = best(affordable) else { return nil }
        return (pick, true)
    }

    /// Scouts rank on evaluation accuracy — the hire sheet's default sort.
    private func bestAffordableScout(in pool: [Scout], cap: Int) -> Scout? {
        pool.filter { $0.salary <= cap }
            .max { a, b in
                if a.accuracy != b.accuracy { return a.accuracy < b.accuracy }
                if a.potentialRead != b.potentialRead { return a.potentialRead < b.potentialRead }
                return a.salary > b.salary
            }
    }

    /// Signs a generated coach. Mirrors `HireCoachView.hire` — including the
    /// face claim, without which the next hire in this very pass could be
    /// handed the same portrait — minus the role-clearing delete, since every
    /// job the pass touches is vacant by construction.
    private func hire(coach candidate: Coach, teamID: UUID) {
        candidate.teamID = teamID
        candidate.careerID = career.id
        candidate.hireSeasonYear = career.currentSeason
        candidate.contractYearsRemaining = 3
        // Task #133 — see `Coach.signedThisOffseason`. Without this the rival
        // poaching pass on the very next advance took ~2 of a 15-man auto-hired
        // staff back off the board before they had coached a practice.
        candidate.signedThisOffseason = true
        // Task #96 — stop the unemployment clock, and do not re-insert a coach
        // signed off the league's market (he is already a row in this store).
        candidate.unemployedSeasons = 0
        candidate.faceID = FaceLibrary.shared.claimFace(
            candidate.faceID, personID: candidate.id,
            role: .coach, age: candidate.age, position: nil,
            gender: FacePersonGender(tag: candidate.gender)
        )
        if candidate.modelContext == nil {
            modelContext.insert(candidate)
        }

        // R30: every coaching hire joins the tree (medical staff sit outside it,
        // exactly as `syncCoachingTree` treats them).
        guard !Self.medicalRoles.contains(candidate.role) else { return }
        var tree = career.coachingTree
        CoachRelationshipEngine.updateCoachingTree(
            tree: &tree.entries,
            coach: candidate,
            event: "hired",
            season: career.currentSeason
        )
        career.coachingTree = tree
    }

    /// Signs a generated scout. Mirrors `HireScoutView.hire`.
    private func hire(scout candidate: Scout, teamID: UUID) {
        candidate.teamID = teamID
        candidate.careerID = career.id
        modelContext.insert(candidate)
    }

    // MARK: - #270: Salary range summaries per section
    //
    // Shows total salary band for the group: hired coaches use actual salary,
    // vacant slots use role salary range.  As coaches are hired the range narrows.

    /// Salary range helper: returns (min, max) in thousands for a set of roles.
    private func sectionSalaryRange(roles: [CoachRole]) -> (min: Int, max: Int)? {
        var totalMin = 0
        var totalMax = 0
        for role in roles {
            if let coach = coaches.first(where: { $0.role == role }) {
                totalMin += coach.salary
                totalMax += coach.salary
            } else {
                totalMin += role.salaryRange.min
                totalMax += role.salaryRange.max
            }
        }
        guard totalMax > 0 else { return nil }
        return (totalMin, totalMax)
    }

    /// Format a salary range as a compact string.
    private func formatSalaryRange(_ range: (min: Int, max: Int)) -> String {
        if range.min == range.max {
            return "$\(formatBudget(range.min))M"
        }
        return "$\(formatBudget(range.min))M–$\(formatBudget(range.max))M"
    }

    /// Coordinator section salary range.
    private var coordinatorsSalaryRange: String? {
        let roles: [CoachRole] = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
        guard let range = sectionSalaryRange(roles: roles) else { return nil }
        return formatSalaryRange(range)
    }

    /// Position coaches section salary range.
    private var positionCoachesCostRange: String? {
        let roles: [CoachRole] = [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach]
        guard let range = sectionSalaryRange(roles: roles) else { return nil }
        return formatSalaryRange(range)
    }

    /// Medical staff section salary range.
    private var medicalCostRange: String? {
        let roles: [CoachRole] = [.teamDoctor, .physio, .headTrainer]
        guard let range = sectionSalaryRange(roles: roles) else { return nil }
        return formatSalaryRange(range)
    }

    /// Scouting section salary range.
    private var scoutingCostRange: String? {
        // Sum hired scout salaries + vacant scout role ranges
        var totalMin = 0
        var totalMax = 0
        let allRoles = ScoutRole.allCases
        for role in allRoles {
            if let scout = scouts.first(where: { $0.scoutRole == role }) {
                totalMin += scout.salary
                totalMax += scout.salary
            } else {
                totalMin += estimatedMinimumScoutSalary(for: role)
                totalMax += (role == .chiefScout ? 600 : 250)
            }
        }
        guard totalMax > 0 else { return nil }
        if totalMin == totalMax {
            return "$\(formatBudget(totalMin))M"
        }
        return "$\(formatBudget(totalMin))M–$\(formatBudget(totalMax))M"
    }

    /// Description of what position group a position coach improves.
    private func positionGroupBoost(for role: CoachRole) -> String? {
        switch role {
        case .qbCoach:        return "Improves QB development"
        case .rbCoach:        return "Improves RB development"
        case .wrCoach:        return "Improves WR development"
        case .olCoach:        return "Improves OL development"
        case .dlCoach:        return "Improves DL development"
        case .lbCoach:        return "Improves LB development"
        case .dbCoach:        return "Improves DB development"
        case .strengthCoach:  return "Improves conditioning & injury prevention"
        case .teamDoctor:     return "Reduces injury risk by up to 30%"
        case .physio:         return "Speeds recovery by up to 25%"
        case .headTrainer:    return "Runs rehab: fewer setbacks, safer returns"
        default:              return nil
        }
    }

    /// Estimated salary range for a scout role.
    private func estimatedScoutSalaryRange(for role: ScoutRole) -> String {
        switch role {
        case .chiefScout:
            return "~$200-600K/yr"
        default:
            return "~$80-250K/yr"
        }
    }

    /// Hiring impact description for a scout role.
    private func scoutHiringImpact(for role: ScoutRole) -> String {
        switch role {
        case .chiefScout:
            return "+15% draft evaluation accuracy"
        default:
            return "+5% regional prospect coverage"
        }
    }

    /// Hiring priority for a scout role.
    private func scoutHiringPriority(for role: ScoutRole) -> HiringPriority {
        switch role {
        case .chiefScout: return .high
        default: return .recommended
        }
    }

    /// Hiring impact description for a coaching role (#51).
    private func hiringImpactDescription(for role: CoachRole) -> String? {
        switch role {
        case .offensiveCoordinator:    return "+12% offensive efficiency"
        case .defensiveCoordinator:    return "+12% defensive efficiency"
        case .specialTeamsCoordinator: return "+8% special teams performance"
        case .qbCoach:                 return "+10% QB development speed"
        case .rbCoach:                 return "+10% RB development speed"
        case .wrCoach:                 return "+10% WR development speed"
        case .olCoach:                 return "+10% OL development speed"
        case .dlCoach:                 return "+10% DL development speed"
        case .lbCoach:                 return "+10% LB development speed"
        case .dbCoach:                 return "+10% DB development speed"
        case .strengthCoach:           return "-15% injury risk across roster"
        case .teamDoctor:              return "-30% injury severity"
        case .physio:                  return "+25% recovery speed"
        case .headTrainer:             return "Fewer rehab setbacks, lower re-injury risk"
        case .assistantHeadCoach:      return "+5% staff chemistry bonus"
        case .headCoach:               return "+15% overall team performance"
        }
    }

    /// Suggestion for what coordinators complement a given coaching style.
    private func coordinatorComplementNote(for style: CoachingStyle) -> String {
        switch style {
        case .tactician:
            return "Pair with creative coordinators who can execute complex schemes"
        case .playersCoach:
            return "Pair with disciplined coordinators to balance player freedom"
        case .disciplinarian:
            return "Pair with adaptable coordinators who thrive in structured systems"
        case .innovator:
            return "Pair with experienced coordinators who can ground bold ideas"
        case .motivator:
            return "Pair with detail-oriented coordinators to complement big-picture leadership"
        }
    }

    // MARK: - Chemistry helpers

    /// Returns the chemistry score between the HC (or player-as-HC) and a given coach.
    private func chemistryWithHC(coach: Coach) -> Double? {
        if career.role == .gmAndHeadCoach {
            // Use the player's coaching style personality analog
            // Map coaching style to a personality archetype for chemistry calc
            let playerPersonality = coachingStylePersonality(career.coachingStyle)
            return CoachingEngine.coachChemistry(coachA: playerPersonality, coachB: coach.personality)
        } else if let hc = headCoach {
            return CoachingEngine.coachChemistry(coachA: hc.personality, coachB: coach.personality)
        }
        return nil
    }

    /// Maps a CoachingStyle to a PersonalityArchetype for chemistry calculations.
    private func coachingStylePersonality(_ style: CoachingStyle) -> PersonalityArchetype {
        switch style {
        case .tactician:      return .quietProfessional
        case .motivator:      return .fieryCompetitor
        case .playersCoach:   return .mentor
        case .innovator:      return .feelPlayer
        case .disciplinarian: return .steadyPerformer
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Locker room background image with gradient overlay
            GeometryReader { geo in
                Image("BgLockerRoom2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.12)
            }
            .ignoresSafeArea()
                .overlay(
                    LinearGradient(
                        colors: [Color.backgroundPrimary.opacity(0.6), Color.clear, Color.backgroundPrimary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: 0) {
                // MARK: - Tab Bar (#107)
                staffTabBar

                // Tab content
                switch selectedTab {
                case .staff:
                    staffTabContent
                case .schemes:
                    schemesTabContent
                case .review:
                    reviewTabContent
                case .tree:
                    // R30: coaching tree + legacy score
                    CoachingTreeView(career: career, embedded: true)
                }

                // The tab's commit, where a commit belongs (§2.5): the foot of
                // the surface, pinned, one gold primary. Drawn only on the two
                // tabs a Coaching Changes task points at, and only while that
                // task is live (#162).
                taskConfirmBar
            }

            // The top toast that used to live here is gone (wave 5b). Every
            // staff commit now ends in a `DSResultSheet` — §2.6's one modal
            // result pattern — presented through the single sheet slot below.
        }
        .navigationTitle("Coaching Staff")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // R30: keep the coaching tree in sync with the actual staff
        // (backfills open entries for careers that predate the tree).
        .task {
            syncCoachingTree()
            // #162: what this cycle has already confirmed, and which tab the
            // rail asked for. Order matters — the hint is refused for a locked
            // tab, and `isTabLocked` reads the staff the sync above may have
            // just repaired.
            loadConfirmedTasks()
            applyPendingTabHint()
        }
        // Coach detail stays as navigation push (works correctly)
        .navigationDestination(item: $detailCoachID) { coachID in
            if let coach = allCoaches.first(where: { $0.id == coachID }) {
                CoachDetailView(coach: coach)
            }
        }
        // Scout detail as navigation push
        .navigationDestination(item: $detailScoutID) { scoutID in
            if let scout = scouts.first(where: { $0.id == scoutID }) {
                ScoutDetailView(scout: scout)
            }
        }
        // THE ONE MODAL SLOT. Every hire flow AND every staff result comes
        // through this binding — a second `.sheet` on this node is the recurring
        // silent-dismiss bug, and a result presented as its own sheet would need
        // the flow's sheet to close first, which is the dismiss-and-re-present
        // race the 0.6 s / 0.4 s timers in the hire views existed to hide.
        //
        // So a flow that ENDS does not change the sheet's identity: `onHired`
        // writes `sheetOutcome` and the content below swaps to the
        // `DSResultSheet` in place, over the same presentation (§2.6). The
        // batch pass and the interview decision, which have no flow behind
        // them, present `.result(UUID)` from nil.
        //
        // `onDismiss` clears the outcome unconditionally: a swipe-down closes
        // the sheet without going through "Continue", and a stale outcome left
        // behind would make the NEXT hire list open straight onto the last
        // hire's result.
        .sheet(item: $activeHireSheet, onDismiss: { sheetOutcome = nil }) { sheetType in
            if let teamID = career.teamID {
                NavigationStack {
                    Group {
                        if let outcome = sheetOutcome {
                            staffResultSheet(outcome)
                        } else {
                            hireFlow(sheetType, teamID: teamID)
                        }
                    }
                    .toolbar {
                        // P5's corollary: the result sheet carries the ONLY
                        // commit on the surface it covers, and the portrait
                        // picker brings its own Cancel/Done, so the host's
                        // "Close" is withdrawn for both.
                        if sheetOutcome == nil && !sheetType.bringsOwnChrome {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { activeHireSheet = nil }
                                    .foregroundStyle(Color.accentGold)
                            }
                        }
                    }
                    .toolbar(
                        sheetOutcome != nil || sheetType.bringsOwnChrome ? .hidden : .visible,
                        for: .navigationBar
                    )
                }
            }
        }
        // Lock-in alerts moved to Dashboard workflow (CoachingStaffReviewSheet)
    }

    // MARK: - The one sheet's two faces (wave 5b)

    @ViewBuilder
    private func hireFlow(_ sheetType: HireSheetType, teamID: UUID) -> some View {
        switch sheetType {
        case .coach(let role):
            HireCoachView(
                role: role,
                teamID: teamID,
                career: career,
                remainingBudget: remainingBudget,
                teamBudget: coachingBudget,
                teamWins: team?.wins ?? 8,
                teamReputation: career.reputation,
                onHired: { name, roleName, salary in
                    showHireResult(name: name, roleName: roleName, salary: salary, pot: .coaching)
                }
            )
        case .scout(let role):
            HireScoutView(
                scoutRole: role,
                teamID: teamID,
                career: career,
                remainingBudget: remainingScoutBudget,
                poolSeed: CoachingEngine.scoutPoolSeed(
                    teamID: teamID,
                    role: role,
                    season: career.currentSeason
                ),
                // `HireScoutView` keeps its two-argument callback because
                // `ScoutingHubView` shares it, so the signed man is read back
                // out of the store here. NOT off `scouts`/`ledger`: this
                // callback runs inside `hire()`'s own call stack, so `@Query`
                // is still the pre-insert snapshot and the seat reads vacant —
                // which is how the chip came out "$0.0M". `scoutsFromStore()`
                // fetches the row the hire view has just saved, and the ledger
                // built from it is what the scouting-left and jobs-open chips
                // are counted against.
                onHired: { name, roleName in
                    let signed = scoutsFromStore()
                    let salary = signed.first(where: { $0.scoutRole == role })?.salary ?? 0
                    let book = StaffLedger(
                        careerRole: career.role,
                        coaches: coaches,
                        scouts: signed,
                        owner: owner
                    )
                    showHireResult(
                        name: name,
                        roleName: roleName,
                        salary: salary,
                        pot: .scouting,
                        book: book
                    )
                }
            )
        case .medical(let role, let candidates):
            SimpleMedicalHireSheet(
                role: role,
                candidates: candidates,
                remainingBudget: remainingMedicalBudget,
                teamID: teamID,
                careerID: career.id,
                currentSeason: career.currentSeason,
                onHired: { name, roleName, salary in
                    showHireResult(name: name, roleName: roleName, salary: salary, pot: .medical)
                }
            )
        case .offensiveScheme:
            if let oc = coaches.first(where: { $0.role == .offensiveCoordinator }) {
                SchemeSelectionView(
                    coordinator: oc,
                    players: offensivePlayers,
                    isOffensive: true,
                    coaches: coaches
                )
            }
        case .defensiveScheme:
            if let dc = coaches.first(where: { $0.role == .defensiveCoordinator }) {
                SchemeSelectionView(
                    coordinator: dc,
                    players: defensivePlayers,
                    isOffensive: false,
                    coaches: coaches
                )
            }
        case .portrait:
            ChangeUserPortraitSheet(career: career)
        case .result:
            // The marker case: the sheet exists only to carry `sheetOutcome`,
            // which the branch above already drew. Reaching here means the
            // outcome was cleared without the sheet being dismissed.
            Color.clear
        }
    }

    private func staffResultSheet(_ outcome: StaffOutcome) -> some View {
        DSResultSheet(
            tone: outcome.tone,
            eyebrow: outcome.eyebrow,
            headline: outcome.headline,
            message: outcome.message,
            chips: outcome.chips,
            cost: outcome.cost,
            continueTitle: outcome.continueTitle,
            // **Dismiss only.** Clearing `sheetOutcome` here as well was the
            // flash: the `Group` above chooses its face on `sheetOutcome`, so
            // nilling it in the same runloop turn as the dismissal swapped the
            // result out for `hireFlow` — the hire list again, or the
            // `.result` marker's `Color.clear` — for the length of the
            // dismissal animation. The user saw his hire's result blink into
            // an empty sheet on the way down. The sheet's own
            // `onDismiss: { sheetOutcome = nil }` clears it once the
            // presentation is actually gone, which is also the path a
            // swipe-down already took, so there is exactly one place the
            // outcome dies.
            onContinue: { activeHireSheet = nil }
        )
    }

    /// Opens a result over a screen that has no flow sheet up.
    private func presentOutcome(_ outcome: StaffOutcome) {
        sheetOutcome = outcome
        activeHireSheet = .result(UUID())
    }

    // MARK: - Tab Bar (#107)

    /// Whether a tab refuses to open. One predicate, read by the tab bar and by
    /// the deep-link hint — a hint that opened a locked tab would land the user
    /// on a screen whose own rule says it has nothing to show yet.
    private func isTabLocked(_ tab: StaffTab) -> Bool {
        (tab == .schemes && !isSchemesTabAvailable) ||
        (tab == .review && !isReviewTabAvailable)
    }

    /// Why a locked tab is locked — shown as a one-line hint when it is tapped.
    private func lockHint(for tab: StaffTab) -> String {
        tab == .schemes
            ? "Hire a coordinator to unlock Schemes"
            : "Hire staff to unlock Review"
    }

    /// Flashes the unlock hint under the tab bar for a couple of seconds.
    private func flashLockHint(_ hint: String) {
        withAnimation(.easeInOut(duration: 0.2)) { lockedTabHint = hint }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if lockedTabHint == hint {
                withAnimation(.easeOut(duration: 0.3)) { lockedTabHint = nil }
            }
        }
    }

    /// The section strip, on the one control style (§2.2, wave 5b).
    ///
    /// This was the fourth of the five independent tab-bar implementations §0
    /// counted: a gold underline rule, a `.subheadline` label that changed
    /// weight on selection, and a 9 pt lock glyph. Two of those three break a
    /// rule by themselves — gold has exactly three jobs and "which section am I
    /// on" is none of them (P5), and 9 pt is a point under the display floor
    /// (P7's corollary). `DSLensTabs` is what the app already uses to swap what
    /// a surface is showing, so this strip is now the same capsule, the same
    /// blue selected fill and the same 44 pt target as the board's.
    ///
    /// The lock survives as the capsule's icon rather than as a fourth colour,
    /// and the refusal lives in the binding: a locked tab flashes its unlock
    /// sentence instead of switching, which is exactly what the hand-rolled bar
    /// did and the one behaviour a plain `Binding` would have dropped.
    private var tabSelection: Binding<StaffTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                guard tab != selectedTab else { return }
                if isTabLocked(tab) {
                    flashLockHint(lockHint(for: tab))
                } else {
                    selectedTab = tab
                }
            }
        )
    }

    private var staffTabBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSLensTabs(
                selection: tabSelection,
                lenses: StaffTab.allCases,
                label: { $0.rawValue },
                icon: { tab in
                    if isTabLocked(tab) { return "lock.fill" }
                    // The tick is a statement about a TASK, not about the tab:
                    // it appears only while this cycle has a live Coaching
                    // Changes row pointing here and the user has confirmed it.
                    // In every other season and phase the strip is undecorated,
                    // because there is nothing for a tick to be true of (#162).
                    if isTabTaskConfirmed(tab) { return "checkmark.circle.fill" }
                    return nil
                }
                // No `title:` line. On a screen where the strip IS the primary
                // navigation, "SECTION · STAFF" repeats the selected capsule
                // directly under it — and the staff surface has no spare
                // vertical on a portrait iPad now that the hiring band sits
                // above the list.
            )

            // Tapping a locked tab explains itself instead of doing nothing.
            if let hint = lockedTabHint {
                Text(hint)
                    .font(DSType.text(DSType.Size.footnote, .semibold, prose: true))
                    .foregroundStyle(Color.alertOrange)
                    .padding(.top, DSSpacing.xxs)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
        .padding(.bottom, DSSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Task Confirms (#162)
    //
    // The two Coaching Changes reads — "Review coaching staff" and "Review
    // coordinator schemes" — are closed here, by a button, on the tab that
    // actually carries the thing they name. They used to be closed by nothing at
    // all: their destination was the bare coaching screen, so a visit stamped
    // them `.inProgress` and no rule anywhere could ever carry them to `.done`.
    //
    // The confirm files `.done` into ``TaskProgressStore`` under the generator's
    // own title. That store is the one #138a built: career-scoped, cycle-stamped
    // `season | phase | week`, self-pruning — so the tick survives a cold launch,
    // a second save cannot inherit it, and next February's Coaching Changes opens
    // untouched. `CareerShellView.refreshTaskCompletionStatus` replays it into
    // the live task list on the way back out, which is what puts the check in the
    // rail and moves its counter. No parallel flag exists.

    /// What one tab's confirm says and which task it closes.
    private struct StaffTaskConfirm {
        /// The generator's ``GameTask/matchKey`` — the identity everything in the
        /// app matches a task on.
        let taskKey: String
        /// Action-bar explainer title, before and after.
        let title: String
        let confirmedTitle: String
        /// What confirming records, and what it has recorded once done.
        let message: String
        let confirmedMessage: String
        /// The gold primary's label.
        let buttonTitle: String
    }

    /// The confirm a tab owns, or `nil` for the tabs that close nothing.
    private func taskConfirm(for tab: StaffTab) -> StaffTaskConfirm? {
        switch tab {
        case .review:
            return StaffTaskConfirm(
                taskKey: TaskGenerator.staffReviewTaskKey,
                title: "Confirm \u{2014} Staff Review",
                confirmedTitle: "Staff Review Confirmed",
                message: "Records that you have read your staff's **ratings, budget and readiness**, and ticks **Review coaching staff** off this phase.",
                confirmedMessage: "**Review coaching staff** is ticked off this phase. You can still hire and replace anybody.",
                buttonTitle: "Confirm Staff Review"
            )
        case .schemes:
            return StaffTaskConfirm(
                taskKey: TaskGenerator.schemeReviewTaskKey,
                title: "Confirm \u{2014} Scheme Review",
                confirmedTitle: "Scheme Review Confirmed",
                message: "Records that you have read both coordinators' **schemes and roster fit**, and ticks **Review coordinator schemes** off this phase.",
                confirmedMessage: "**Review coordinator schemes** is ticked off this phase. Changing a scheme afterwards costs nothing here.",
                buttonTitle: "Confirm Scheme Review"
            )
        case .staff, .tree:
            return nil
        }
    }

    /// Whether the two review rows exist for the club right now.
    ///
    /// `TaskGenerator.coachingChangesTasks` emits them unconditionally inside
    /// `.coachingChanges` and nowhere else, so this is the exact liveness test —
    /// and it is the reason the coaching screen is undecorated for the other
    /// fourteen phases rather than carrying a tick year-round.
    private var reviewTasksAreLive: Bool {
        career.currentPhase == .coachingChanges
    }

    /// Whether `tab`'s task has been confirmed in the CURRENT cycle.
    private func isTabTaskConfirmed(_ tab: StaffTab) -> Bool {
        guard reviewTasksAreLive, let confirm = taskConfirm(for: tab) else { return false }
        return confirmedTaskKeys.contains(confirm.taskKey)
    }

    /// Replays this cycle's recorded completions into view state.
    private func loadConfirmedTasks() {
        let recorded = TaskProgressStore.statuses(in: TaskProgressStore.cycle(for: career))
        confirmedTaskKeys = Set(recorded.filter { $0.value == .done }.map(\.key))
    }

    /// Files the confirm. **Idempotent** — a second press is refused here as
    /// well as being unreachable through the disabled button, so nothing can
    /// spend twice if the bar is ever driven from somewhere else.
    private func confirmTask(_ key: String) {
        guard !confirmedTaskKeys.contains(key) else { return }
        TaskProgressStore.record(
            .done,
            for: key,
            in: TaskProgressStore.cycle(for: career),
            season: career.currentSeason
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            _ = confirmedTaskKeys.insert(key)
        }
    }

    /// Honors the one-shot tab hint `CareerShellView.handleTaskNavigation`
    /// writes, exactly as `ScoutingHubView` honors `scoutingPendingTab`. Read
    /// once and cleared, so a hint cannot outlive the navigation that set it.
    private func applyPendingTabHint() {
        guard let pending = CareerScopedDefaults.string("coachingPendingTab"),
              !pending.isEmpty else { return }
        let hinted: StaffTab? = {
            switch pending {
            case "staff":   return .staff
            case "schemes": return .schemes
            case "review":  return .review
            case "tree":    return .tree
            default:        return nil
            }
        }()
        // A locked tab is refused rather than forced: Review is locked only when
        // the club has hired nobody at all, and dropping the user on an empty
        // evaluation would be a worse answer than the hiring list plus the lock's
        // own sentence.
        if let hinted, !isTabLocked(hinted) { selectedTab = hinted }
        CareerScopedDefaults.remove("coachingPendingTab")
    }

    /// The pinned confirm bar for the selected tab, or nothing.
    @ViewBuilder
    private var taskConfirmBar: some View {
        if reviewTasksAreLive, let confirm = taskConfirm(for: selectedTab), !isTabLocked(selectedTab) {
            let isConfirmed = confirmedTaskKeys.contains(confirm.taskKey)
            DSActionBar(
                explainer: DSActionBar.Explainer(
                    title: isConfirmed ? confirm.confirmedTitle : confirm.title,
                    message: isConfirmed ? confirm.confirmedMessage : confirm.message
                ),
                primary: DSActionBar.Action(
                    // A done affirmation, not a second spend: the primary goes
                    // to the style's genuine disabled grey and says what already
                    // happened (§2.8).
                    title: isConfirmed ? "Confirmed" : confirm.buttonTitle,
                    isEnabled: !isConfirmed,
                    accessibilityLabel: isConfirmed
                        ? DSActionBar.Explainer.spoken(confirm.confirmedMessage)
                        : "\(confirm.buttonTitle). "
                            + DSActionBar.Explainer.spoken(confirm.message),
                    handler: { confirmTask(confirm.taskKey) }
                )
            )
        }
    }

    // MARK: - Staff Tab Content

    private var staffTabContent: some View {
        VStack(spacing: 0) {
            // §2.1: the process states itself at the top of the surface it owns,
            // outside the scroll. It used to be five discs inside five section
            // headers, three of them collapsed.
            hiringBand

            List {
                // MARK: - Budget Header
                Section {
                    budgetHeaderView

                    // Over-budget warning banner
                    if isBudgetOverspent {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: DSType.Size.callout))
                                .foregroundStyle(Color.danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Over Budget")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.dangerText)
                                Text(overBudgetMessage)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.danger.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.danger.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                } header: {
                    Text("Staff Budget")
                }
                .listRowBackground(Color.backgroundSecondary)

                // MARK: - Fill Your Staff (Batch 2E): the bulk escape hatch.
                // The per-job priority chips moved into the band above — one
                // component now answers "what order" and "start here".
                if !orderedVacancies.isEmpty {
                    Section {
                        autoHireButton
                    } header: {
                        Text("Fill Your Staff")
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }

                // MARK: - R30: Pending HC interview request for a user coordinator
                if let request = pendingInterview {
                    Section {
                        interviewRequestCard(request)
                    } header: {
                        Text("Interview Request")
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }

                // MARK: - R30: Offseason coaching carousel feed
                if showCarouselFeed {
                    Section {
                        ForEach(visibleCarouselMoves) { move in
                            carouselMoveRow(move)
                        }
                    } header: {
                        Text("Coaching Carousel")
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }

                // Head Coach -- prominent card
                Section {
                    if career.role == .gmAndHeadCoach {
                        playerAsHeadCoachRow
                    } else if let hc = headCoach {
                        Button {
                            detailCoachID = hc.id
                        } label: {
                            HeadCoachCardView(coach: hc, menteeCount: coaches.filter { $0.mentorCoachID == hc.id }.count)
                        }
                    } else {
                        headCoachVacantRow
                    }
                } header: {
                    staffTierHeader(badge: .tier(1), title: "Head Coach")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1.5)
                        )
                        .padding(2)
                )

                // Assistant Head Coach
                Section {
                    if let ahc = assistantHeadCoach {
                        coachRowWithChemistry(coach: ahc)
                    } else {
                        vacantRow(role: .assistantHeadCoach)
                    }
                } header: {
                    // Hollow badge, same 18pt disc as the numbered tiers: the
                    // assistant sits outside the 1-2-3 hiring ladder, but a bare
                    // inline icon made this header the odd one out in a column
                    // of otherwise identical section heads.
                    staffTierHeader(badge: .optional(icon: "person.2.fill"), title: "Assistant Head Coach")
                }
                .listRowBackground(Color.backgroundSecondary)

                // MARK: - Coordinators (#80 collapsible)
                Section {
                    DisclosureGroup(isExpanded: $isCoordinatorsExpanded) {
                        let coordRoles: [CoachRole] = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
                        ForEach(coordRoles, id: \.self) { role in
                            if let coach = coaches.first(where: { $0.role == role }) {
                                coachRowWithChemistry(coach: coach)
                            } else {
                                vacantRow(role: role)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            staffTierBadge(.tier(2))
                            Text("Coordinators")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if let range = coordinatorsSalaryRange {
                                Text(range)
                                    .font(.system(size: DSType.Size.caption, weight: .medium))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            let filledCount = coaches.filter { [CoachRole.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator].contains($0.role) }.count
                            Text("\(filledCount)/3")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(filledCount == 3 ? Color.success : Color.warning)
                        }
                    }
                    .tint(Color.accentGold)
                }
                .listRowBackground(Color.backgroundSecondary)

                // MARK: - Position Coaches (#50 compact grid, #80 collapsible)
                Section {
                    DisclosureGroup(isExpanded: $isPositionCoachesExpanded) {
                        let posRoles: [CoachRole] = [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach]
                        // #50: Compact 2-column grid of cards
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], spacing: 10) {
                            ForEach(posRoles, id: \.self) { role in
                                if let coach = coaches.first(where: { $0.role == role }) {
                                    Button {
                                        detailCoachID = coach.id
                                    } label: {
                                        compactCoachCard(coach: coach)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    compactVacantCard(role: role)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        HStack(spacing: 6) {
                            staffTierBadge(.tier(3))
                            Text("Position Coaches")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            // #270: Cost range to fill vacant slots
                            if let costRange = positionCoachesCostRange {
                                Text(costRange)
                                    .font(.system(size: DSType.Size.caption, weight: .medium))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            let filledCount = positionCoaches.count
                            Text("\(filledCount)/8")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(filledCount == 8 ? Color.success : Color.textTertiary)
                        }
                    }
                    .tint(Color.accentGold)
                }
                .listRowBackground(Color.backgroundSecondary)

                // MARK: - Medical & Scouting (#54 side-by-side on iPad, #80 collapsible)
                if isIPadPortrait {
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            // Left column: Medical Staff
                            VStack(alignment: .leading, spacing: 0) {
                                DisclosureGroup(isExpanded: $isMedicalExpanded) {
                                    let medRoles: [CoachRole] = [.teamDoctor, .physio, .headTrainer]
                                    ForEach(medRoles, id: \.self) { role in
                                        if let coach = coaches.first(where: { $0.role == role }) {
                                            Button {
                                                detailCoachID = coach.id
                                            } label: {
                                                compactCoachCard(coach: coach)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            compactVacantMedicalCard(role: role)
                                        }
                                        if role != .headTrainer {
                                            Divider().padding(.vertical, 4)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("4")
                                            .font(.system(size: DSType.Size.micro, weight: .black))
                                            .foregroundStyle(Color.backgroundPrimary)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.accentGold))
                                        Text("Medical Staff")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                        Spacer()
                                        // #270: Cost range to fill
                                        if let costRange = medicalCostRange {
                                            Text(costRange)
                                                .font(.system(size: DSType.Size.caption, weight: .medium))
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                        // #275: Filled/total count
                                        let filledCount = medicalStaff.count
                                        Text("\(filledCount)/3")
                                            .font(.caption.weight(.medium).monospacedDigit())
                                            .foregroundStyle(filledCount == 3 ? Color.success : Color.textTertiary)
                                    }
                                }
                                .tint(Color.accentGold)
                            }
                            .frame(maxWidth: .infinity)

                            Divider()

                            // Right column: Scouting Department
                            VStack(alignment: .leading, spacing: 0) {
                                DisclosureGroup(isExpanded: $isScoutingExpanded) {
                                    if let chief = chiefScout {
                                        scoutRow(scout: chief)
                                    } else {
                                        scoutVacantRow(role: .chiefScout)
                                    }
                                    let regionalRoles: [ScoutRole] = [.regionalScout1, .regionalScout2, .regionalScout3, .regionalScout4, .regionalScout5]
                                    ForEach(regionalRoles, id: \.self) { role in
                                        if let scout = scouts.first(where: { $0.scoutRole == role }) {
                                            scoutRow(scout: scout)
                                        } else {
                                            scoutVacantRow(role: role)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("5")
                                            .font(.system(size: DSType.Size.micro, weight: .black))
                                            .foregroundStyle(Color.backgroundPrimary)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.accentGold))
                                        Text("Scouting")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                        Spacer()
                                        // #270: Cost range to fill
                                        if let costRange = scoutingCostRange {
                                            Text(costRange)
                                                .font(.system(size: DSType.Size.caption, weight: .medium))
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                        // #275: Filled/total count
                                        let filledCount = scouts.count
                                        Text("\(filledCount)/6")
                                            .font(.caption.weight(.medium).monospacedDigit())
                                            .foregroundStyle(filledCount == 6 ? Color.success : Color.textTertiary)
                                    }
                                }
                                .tint(Color.accentGold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } header: {
                        Text("Support Staff")
                    }
                    .listRowBackground(Color.backgroundSecondary)
                } else {
                    // MARK: - Medical Staff (single column, collapsible)
                    Section {
                        DisclosureGroup(isExpanded: $isMedicalExpanded) {
                            let medRoles: [CoachRole] = [.teamDoctor, .physio, .headTrainer]
                            ForEach(medRoles, id: \.self) { role in
                                if let coach = coaches.first(where: { $0.role == role }) {
                                    Button {
                                        detailCoachID = coach.id
                                    } label: {
                                        compactCoachCard(coach: coach)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    compactVacantMedicalCard(role: role)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("4")
                                    .font(.system(size: DSType.Size.micro, weight: .black))
                                    .foregroundStyle(Color.backgroundPrimary)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.accentGold))
                                Text("Medical Staff")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                // #270: Cost range to fill
                                if let costRange = medicalCostRange {
                                    Text(costRange)
                                        .font(.system(size: DSType.Size.caption, weight: .medium))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                // #275: Filled/total count
                                let filledCount = medicalStaff.count
                                Text("\(filledCount)/3")
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(filledCount == 3 ? Color.success : Color.textTertiary)
                            }
                        }
                        .tint(Color.accentGold)
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    // MARK: - Scouting Department (single column, collapsible)
                    Section {
                        DisclosureGroup(isExpanded: $isScoutingExpanded) {
                            if let chief = chiefScout {
                                scoutRow(scout: chief)
                            } else {
                                scoutVacantRow(role: .chiefScout)
                            }
                            let regionalRoles: [ScoutRole] = [.regionalScout1, .regionalScout2, .regionalScout3, .regionalScout4, .regionalScout5]
                            ForEach(regionalRoles, id: \.self) { role in
                                if let scout = scouts.first(where: { $0.scoutRole == role }) {
                                    scoutRow(scout: scout)
                                } else {
                                    scoutVacantRow(role: role)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("5")
                                    .font(.system(size: DSType.Size.micro, weight: .black))
                                    .foregroundStyle(Color.backgroundPrimary)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.accentGold))
                                Text("Scouting Department")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                // #270: Cost range to fill
                                if let costRange = scoutingCostRange {
                                    Text(costRange)
                                        .font(.system(size: DSType.Size.caption, weight: .medium))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                // #275: Filled/total count
                                let filledCount = scouts.count
                                Text("\(filledCount)/6")
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(filledCount == 6 ? Color.success : Color.textTertiary)
                            }
                        }
                        .tint(Color.accentGold)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }

                // (Lock in button moved to Dashboard workflow)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)

            // Lock in button moved to Dashboard workflow (CoachingStaffReviewSheet)
        }
    }

    // MARK: - Schemes Tab Content (#107, #76)

    private var schemesTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Offensive Scheme Card (current selection)
                offensiveSchemeCard

                // Offensive Scheme Family tree (browse + see staff coverage)
                offensiveSchemeFamiliesCard

                // Offensive Roster Fit
                if let oc = coaches.first(where: { $0.role == .offensiveCoordinator }),
                   let scheme = oc.offensiveScheme {
                    schemeRosterFitSection(
                        title: "OFFENSIVE ROSTER FIT",
                        scheme: scheme.displayName,
                        coordinatorName: oc.fullName,
                        players: offensivePlayers,
                        offensiveScheme: scheme,
                        defensiveScheme: nil
                    )
                }

                // Defensive Scheme Card (current selection)
                defensiveSchemeCard

                // Defensive Scheme Family tree
                defensiveSchemeFamiliesCard

                // Defensive Roster Fit
                if let dc = coaches.first(where: { $0.role == .defensiveCoordinator }),
                   let scheme = dc.defensiveScheme {
                    schemeRosterFitSection(
                        title: "DEFENSIVE ROSTER FIT",
                        scheme: scheme.displayName,
                        coordinatorName: dc.fullName,
                        players: defensivePlayers,
                        offensiveScheme: nil,
                        defensiveScheme: scheme
                    )
                }

                // Scheme Impact Info
                schemeImpactCard
            }
            .padding(16)
        }
        // Scheme selection sheets moved to unified activeHireSheet
    }

    // MARK: - Scheme Family Trees (#schemes-page-tree)

    /// Static groupings for offensive scheme families.
    private var offensiveSchemeFamilies: [(family: String, schemes: [OffensiveScheme])] {
        [
            ("Pass-First Family", [.westCoast, .airRaid, .proPassing, .spread]),
            ("Run-First Family",  [.powerRun, .shanahan, .option, .rpo])
        ]
    }

    /// Static groupings for defensive scheme families.
    private var defensiveSchemeFamilies: [(family: String, schemes: [DefensiveScheme])] {
        [
            ("Aggressive / Man",  [.pressMan, .base43]),
            ("Zone-Heavy",        [.cover3, .tampa2, .base34]),
            ("Hybrid / Multiple", [.multiple, .hybrid])
        ]
    }

    /// Number of coaches on this team with >= 60 expertise in a given scheme.
    private func coachesKnowing(offensiveScheme scheme: OffensiveScheme) -> Int {
        coaches.filter { $0.expertise(for: scheme.rawValue) >= 60 }.count
    }

    private func coachesKnowing(defensiveScheme scheme: DefensiveScheme) -> Int {
        coaches.filter { $0.expertise(for: scheme.rawValue) >= 60 }.count
    }

    /// Offensive scheme family card -- shows families with selectable scheme cards inside.
    private var offensiveSchemeFamiliesCard: some View {
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let activeScheme = oc?.offensiveScheme
        let canChange = oc != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OFFENSIVE SCHEME FAMILIES")
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Text("Tap to apply")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
            }

            ForEach(offensiveSchemeFamilies, id: \.family) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.family.uppercased())
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Color.textSecondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 8) {
                        ForEach(group.schemes, id: \.self) { scheme in
                            offensiveSchemeFamilyCell(
                                scheme: scheme,
                                isActive: scheme == activeScheme,
                                canChange: canChange
                            )
                        }
                    }
                }
            }

            if !canChange {
                Text("Hire an Offensive Coordinator to enable scheme selection.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// One scheme cell used inside the family card.
    @ViewBuilder
    private func offensiveSchemeFamilyCell(
        scheme: OffensiveScheme,
        isActive: Bool,
        canChange: Bool
    ) -> some View {
        let count = coachesKnowing(offensiveScheme: scheme)
        Button {
            if canChange { activeHireSheet = .offensiveScheme }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isActive ? "checkmark.seal.fill" : "football")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(isActive ? Color.accentGold : Color.accentBlue.opacity(0.8))
                    Text(scheme.displayName)
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(isActive ? Color.accentGold : Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: DSType.Size.micro))
                    Text(count == 0 ? "No staff knows this" : "\(count) coach\(count == 1 ? "" : "es") know this")
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                }
                .foregroundStyle(coachCountColor(count))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentGold.opacity(0.10) : Color.backgroundTertiary.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isActive ? Color.accentGold.opacity(0.6) : Color.surfaceBorder.opacity(0.5),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canChange)
        .opacity(canChange ? 1.0 : 0.6)
    }

    /// Defensive scheme family card.
    private var defensiveSchemeFamiliesCard: some View {
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })
        let activeScheme = dc?.defensiveScheme
        let canChange = dc != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DEFENSIVE SCHEME FAMILIES")
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Text("Tap to apply")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
            }

            ForEach(defensiveSchemeFamilies, id: \.family) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.family.uppercased())
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Color.textSecondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ], spacing: 8) {
                        ForEach(group.schemes, id: \.self) { scheme in
                            defensiveSchemeFamilyCell(
                                scheme: scheme,
                                isActive: scheme == activeScheme,
                                canChange: canChange
                            )
                        }
                    }
                }
            }

            if !canChange {
                Text("Hire a Defensive Coordinator to enable scheme selection.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private func defensiveSchemeFamilyCell(
        scheme: DefensiveScheme,
        isActive: Bool,
        canChange: Bool
    ) -> some View {
        let count = coachesKnowing(defensiveScheme: scheme)
        Button {
            if canChange { activeHireSheet = .defensiveScheme }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isActive ? "checkmark.seal.fill" : "shield")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(isActive ? Color.accentGold : Color.danger.opacity(0.8))
                    Text(scheme.displayName)
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(isActive ? Color.accentGold : Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: DSType.Size.micro))
                    Text(count == 0 ? "No staff knows this" : "\(count) coach\(count == 1 ? "" : "es") know this")
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                }
                .foregroundStyle(coachCountColor(count))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentGold.opacity(0.10) : Color.backgroundTertiary.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isActive ? Color.accentGold.opacity(0.6) : Color.surfaceBorder.opacity(0.5),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canChange)
        .opacity(canChange ? 1.0 : 0.6)
    }

    /// Colour for the staff-coverage count. A headcount is not a rating — P7
    /// rule 2, status at a stated threshold, and the sentence beside it
    /// ("No staff knows this") states the threshold in words. `accentGold` left
    /// the two-coach band because this same card paints its ACTIVE state gold,
    /// so a scheme with two coaches looked selected.
    private func coachCountColor(_ count: Int) -> Color {
        if count == 0 { return .forStatus(.bad) }     // nobody knows this scheme
        if count == 1 { return .forStatus(.warn) }    // one man deep
        return .forStatus(.ok)                        // covered
    }

    // MARK: - Offensive Scheme Card

    private var offensiveSchemeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OFFENSIVE SCHEME")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if let oc = coaches.first(where: { $0.role == .offensiveCoordinator }),
               let scheme = oc.offensiveScheme {
                HStack(spacing: 12) {
                    Image(systemName: "football.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentBlue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scheme.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Set by OC \(oc.fullName)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(offensiveSchemeDescription(scheme))
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Button {
                        activeHireSheet = .offensiveScheme
                    } label: {
                        Text("Change")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "football")
                        .font(.title2)
                        .foregroundStyle(Color.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Offensive Scheme")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                        Text("Hire an Offensive Coordinator to set your offensive scheme")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Defensive Scheme Card

    private var defensiveSchemeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEFENSIVE SCHEME")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if let dc = coaches.first(where: { $0.role == .defensiveCoordinator }),
               let scheme = dc.defensiveScheme {
                HStack(spacing: 12) {
                    Image(systemName: "shield.fill")
                        .font(.title2)
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scheme.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Set by DC \(dc.fullName)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(defensiveSchemeDescription(scheme))
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Button {
                        activeHireSheet = .defensiveScheme
                    } label: {
                        Text("Change")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "shield")
                        .font(.title2)
                        .foregroundStyle(Color.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Defensive Scheme")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                        Text("Hire a Defensive Coordinator to set your defensive scheme")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Scheme Roster Fit Section

    private func schemeRosterFitSection(
        title: String,
        scheme: String,
        coordinatorName: String?,
        players: [Player],
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if players.isEmpty {
                Text("No players on roster for this side of the ball.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                // Player fit bars
                ForEach(players.prefix(15), id: \.id) { player in
                    let fitScore = CoachingEngine.schemeFit(
                        player: player,
                        offensiveScheme: offensiveScheme,
                        defensiveScheme: defensiveScheme
                    )
                    let fitPercent = Int(fitScore * 100)
                    let fitColor = schemeFitColor(fitPercent)

                    HStack(spacing: 8) {
                        Text(player.position.rawValue)
                            .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 28, alignment: .leading)

                        Text(player.fullName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(fitColor)
                                    .frame(width: max(0, geo.size.width * fitScore), height: 8)
                            }
                        }
                        .frame(width: 80, height: 8)

                        Text("\(fitPercent)%")
                            .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                            .foregroundStyle(fitColor)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                // Average fit
                Divider().overlay(Color.surfaceBorder)

                let avgFit = players.reduce(0.0) { sum, player in
                    sum + CoachingEngine.schemeFit(
                        player: player,
                        offensiveScheme: offensiveScheme,
                        defensiveScheme: defensiveScheme
                    )
                } / max(1.0, Double(players.count))
                let avgPercent = Int(avgFit * 100)
                let avgColor = schemeFitColor(avgPercent)

                HStack {
                    Text("Average Fit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(avgPercent)%")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(avgColor)
                    Text(schemeFitLabel(avgPercent))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(avgColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(avgColor.opacity(0.15))
                        )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Scheme Impact Card

    private var schemeImpactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCHEME IMPACT")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            VStack(alignment: .leading, spacing: 6) {
                schemeImpactRow(
                    icon: "sportscourt.fill",
                    text: "Your offensive scheme affects play calling tendencies during games."
                )
                schemeImpactRow(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "Players with high scheme fit perform better in game simulations."
                )
                schemeImpactRow(
                    icon: "arrow.up.forward.circle.fill",
                    text: "Players with high scheme fit develop faster in the offseason."
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func schemeImpactRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.accentGold.opacity(0.7))
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Scheme Fit Helpers

    /// Unified onto `Color.forRating(scale: .percent)` — this is exactly the
    /// case `RatingScale` was introduced for: a 62 % scheme fit painted gold
    /// here while a 62 OVR painted yellow one screen over.
    private func schemeFitColor(_ percent: Int) -> Color {
        Color.forRating(percent, scale: .percent)
    }

    private func schemeFitLabel(_ percent: Int) -> String {
        if percent >= 80 { return "Great" }
        if percent >= 60 { return "Good" }
        if percent >= 40 { return "Fair" }
        return "Poor"
    }

    // MARK: - Review Tab Content (#107)

    private var reviewTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Staff Overview
                VStack(alignment: .leading, spacing: 12) {
                    Text("STAFF OVERVIEW")
                        .font(.system(size: DSType.Size.caption, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    HStack(spacing: 20) {
                        reviewStatBadge(value: "\(ledger.filledCoachSlots)", label: "Coaches", color: .accentGold)
                        reviewStatBadge(value: "\(ledger.filledScoutSlots)", label: "Scouts", color: .accentBlue)
                        reviewStatBadge(value: "\(vacantCoachRoles.count)", label: "Vacant", color: vacantCoachRoles.isEmpty ? .success : .warning)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

                // Budget Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("BUDGET SUMMARY")
                        .font(.system(size: DSType.Size.caption, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    HStack {
                        Text("Total Budget")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("$\(formatBudget(coachingBudget))M")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack {
                        Spacer()
                        Text(budgetContext.label)
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(budgetContext.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(budgetContext.color.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(budgetContext.color.opacity(0.4), lineWidth: 1))
                    }

                    HStack {
                        Text("Coaching Salaries")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("$\(formatBudget(totalCoachSalaryUsed))M")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack {
                        Text("Scouting Salaries")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("$\(formatBudget(totalScoutSalaryUsed))M")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack {
                        Text("Medical Salaries")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("$\(formatBudget(totalMedicalSalaryUsed))M")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }

                    Divider().overlay(Color.surfaceBorder)

                    HStack {
                        Text("Remaining")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("$\(formatBudget(remainingBudget))M")
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(remainingBudget >= 0 ? Color.success : Color.dangerText)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

                // Staff Ratings
                VStack(alignment: .leading, spacing: 12) {
                    Text("STAFF RATINGS")
                        .font(.system(size: DSType.Size.caption, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    if coaches.isEmpty {
                        Text("No coaching staff hired yet.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        ForEach(coaches.sorted(by: { $0.role.sortOrder < $1.role.sortOrder })) { coach in
                            let ovr = coachOverall(coach)
                            HStack(spacing: 10) {
                                Text(coach.role.abbreviation)
                                    .font(.system(size: DSType.Size.micro, weight: .bold))
                                    .foregroundStyle(Color.backgroundPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(coach.role.badgeColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                                    .frame(width: 36)

                                Text(coach.fullName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(ovr)")
                                    .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.forRating(ovr))
                            }

                            if coach.id != coaches.sorted(by: { $0.role.sortOrder < $1.role.sortOrder }).last?.id {
                                Divider().overlay(Color.surfaceBorder.opacity(0.4))
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

                // Readiness Check
                VStack(alignment: .leading, spacing: 12) {
                    Text("READINESS CHECK")
                        .font(.system(size: DSType.Size.caption, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    readinessRow(label: "Head Coach", filled: career.role == .gmAndHeadCoach || headCoach != nil)
                    readinessRow(label: "Offensive Coordinator", filled: coaches.contains(where: { $0.role == .offensiveCoordinator }))
                    readinessRow(label: "Defensive Coordinator", filled: coaches.contains(where: { $0.role == .defensiveCoordinator }))
                    readinessRow(label: "Special Teams Coordinator", filled: coaches.contains(where: { $0.role == .specialTeamsCoordinator }))
                    readinessRow(label: "Budget Within Limits", filled: !isBudgetOverspent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
            }
            .padding(16)
        }
    }

    // Lock in staff button removed — now handled by CoachingStaffReviewSheet in Dashboard workflow

    // MARK: - Review Tab Helpers

    private func reviewStatBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: DSType.Size.title2, weight: .black).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: 72, height: 56)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func readinessRow(label: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DSType.Size.body))
                .foregroundStyle(filled ? Color.success : Color.textTertiary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(filled ? Color.textPrimary : Color.textTertiary)
            Spacer()
        }
    }

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    // MARK: - Scheme Descriptions

    private func offensiveSchemeDescription(_ scheme: OffensiveScheme) -> String {
        switch scheme {
        case .westCoast:  return "Short-to-intermediate passing with high-percentage throws and run-after-catch emphasis."
        case .airRaid:    return "Spread formations with four- and five-wide sets, emphasizing the vertical passing game."
        case .spread:     return "Space the field with spread formations, using both run and pass to exploit matchups."
        case .powerRun:   return "Downhill running attack with pulling guards and fullback leads."
        case .shanahan:   return "Outside zone running scheme with play-action boots and misdirection."
        case .proPassing: return "Pro-style balanced attack with multiple formations and under-center play-action."
        case .rpo:        return "Run-pass option plays that let the QB read the defense post-snap."
        case .option:     return "Triple-option and read-option concepts emphasizing athletic QBs."
        }
    }

    private func defensiveSchemeDescription(_ scheme: DefensiveScheme) -> String {
        switch scheme {
        case .base34:   return "3-4 base with versatile OLBs who can rush and drop into coverage."
        case .base43:   return "4-3 base with four down linemen generating the pass rush."
        case .cover3:   return "Cover 3 zone with three deep defenders and four underneath zones."
        case .pressMan: return "Aggressive press-man coverage at the line with tight man-to-man assignments."
        case .tampa2:   return "Tampa 2 zone with a fast MLB dropping into deep middle coverage."
        case .multiple: return "Multiple fronts and coverages that disguise the defense pre-snap."
        case .hybrid:   return "Hybrid defense blending 3-4 and 4-3 principles with positionless players."
        }
    }

    // MARK: - R30: Interview Request (coordinator in demand)

    /// The pending interview request, if it belongs to the current season.
    private var pendingInterview: CoachCarouselEngine.CoordinatorInterviewRequest? {
        guard let request = career.pendingInterviewRequest,
              request.season == career.currentSeason else { return nil }
        return request
    }

    /// Whether the offseason carousel feed should be shown: offseason /
    /// pre-draft phases only, and only when there is something to report.
    private var showCarouselFeed: Bool {
        let group = career.currentPhase.group
        return (group == .offseason || group == .preDraft) && !career.coachCarouselLog.isEmpty
    }

    /// Feed rows, capped so the Staff tab stays scannable.
    private var visibleCarouselMoves: [CoachCarouselEngine.CarouselMove] {
        Array(career.coachCarouselLog.prefix(12))
    }

    private func interviewRequestCard(_ request: CoachCarouselEngine.CoordinatorInterviewRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: DSType.Size.title2))
                    .foregroundStyle(Color.accentGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.requestingTeamName) want your \(request.coachRole.abbreviation)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Head coach interview request for \(request.coachName)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Text("Allow the interview and \(request.coachName) takes the job: they join your coaching tree, your reputation grows, and you receive a compensatory 3rd-round pick — but you'll need a new \(request.coachRole.displayName.lowercased()). Block it and they stay, at the cost of some motivation.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    resolveInterviewRequest(request, allow: true)
                } label: {
                    Text("Allow Interview")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentGold))
                }
                .buttonStyle(.plain)

                Button {
                    resolveInterviewRequest(request, allow: false)
                } label: {
                    Text("Block Request")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(request.canBlock ? Color.textPrimary : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.backgroundTertiary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!request.canBlock)
            }

            if !request.canBlock {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: DSType.Size.micro))
                    Text("\(request.coachName) is in the final year of their contract — the interview cannot be blocked.")
                        .font(.system(size: DSType.Size.micro, weight: .medium))
                }
                .foregroundStyle(Color.warning)
            }
        }
        .padding(.vertical, 6)
    }

    /// Resolves the pending interview request (allow → the coordinator
    /// departs to the HC job and joins the coaching tree; block → they stay
    /// with a small motivation hit).
    private func resolveInterviewRequest(
        _ request: CoachCarouselEngine.CoordinatorInterviewRequest,
        allow: Bool
    ) {
        defer {
            career.pendingInterviewRequest = nil
            try? modelContext.save()
        }
        guard let coach = allCoaches.first(where: { $0.id == request.coachID }),
              coach.teamID == career.teamID else { return }

        if allow {
            // Close out the coaching-tree entry BEFORE mutating the coach's
            // role so a backfilled entry keeps the role they held under you.
            var tree = career.coachingTree
            CoachRelationshipEngine.recordDeparture(
                tree: &tree.entries,
                coach: coach,
                event: "departed_hc",
                season: career.currentSeason,
                destination: "HC at \(request.requestingTeamName)"
            )
            career.coachingTree = tree
            career.reputation = min(99, career.reputation + 1)

            // The interview goes well — the coach takes the job.
            if let oldHC = allCoaches.first(where: {
                $0.teamID == request.requestingTeamID && $0.role == .headCoach
            }) {
                oldHC.teamID = nil
            }
            coach.teamID = request.requestingTeamID
            coach.role = .headCoach
            coach.promotedInSeason = career.currentSeason
            coach.hireSeasonYear = career.currentSeason
            coach.contractYearsRemaining = 4
            coach.salary = max(coach.salary, CoachRole.headCoach.salaryRange.min)

            career.coachCarouselLog = [CoachCarouselEngine.CarouselMove(
                season: career.currentSeason,
                kind: .departure,
                teamName: request.requestingTeamName,
                coachName: request.coachName,
                detail: "Left your staff to become head coach"
            )] + career.coachCarouselLog

            career.postNews(NewsItem(
                headline: "\(request.requestingTeamName) hire \(request.coachName) as head coach",
                body: "\(request.coachName) is leaving \(career.playerName)'s staff to take over as head coach of the \(request.requestingTeamName). Another branch grows on a coaching tree the league is starting to talk about.",
                category: .coachingChange,
                week: 0,
                season: career.currentSeason,
                relatedTeamID: request.requestingTeamID,
                sentiment: .neutral
            ))

            presentOutcome(StaffOutcome(
                tone: .neutral,
                eyebrow: "Coaching carousel",
                headline: "\(request.coachName) takes the \(request.requestingTeamName) job",
                message: "He leaves your staff as a head coach. Another branch on a coaching tree "
                    + "the league is starting to talk about — and a **vacant chair** you now have to fill.",
                chips: [
                    .init(id: "role", label: "Vacated", value: request.coachName, context: "head coach elsewhere"),
                    .init(id: "rep", label: "Reputation", value: "\(career.reputation)", context: "+1", contextColor: .success),
                    .init(id: "tree", label: "Coaching tree", value: "\(career.coachingTree.entries.count)", context: "entries")
                ],
                cost: "The seat is open from today. Nothing was charged to your budget \u{2014} his salary comes back into the pot."
            ))
        } else {
            // Blocked: the coach stays, slightly deflated.
            coach.motivation = max(1, coach.motivation - 5)

            career.coachCarouselLog = [CoachCarouselEngine.CarouselMove(
                season: career.currentSeason,
                kind: .blocked,
                teamName: request.requestingTeamName,
                coachName: request.coachName,
                detail: "Interview blocked — staying on your staff (motivation -5)"
            )] + career.coachCarouselLog

            presentOutcome(StaffOutcome(
                tone: .neutral,
                eyebrow: "Coaching carousel",
                headline: "Interview blocked",
                message: "\(request.coachName) stays on your staff. He wanted the \(request.requestingTeamName) "
                    + "job and you did not let him talk to them.",
                chips: [
                    .init(id: "coach", label: "Stays", value: request.coachName, context: "under contract"),
                    .init(
                        id: "motivation",
                        label: "Motivation",
                        value: "\(coach.motivation)",
                        context: "\u{2212}5",
                        valueColor: Color.forRating(coach.motivation),
                        contextColor: .dangerText
                    )
                ],
                cost: "Costs him **5 motivation**. A man blocked twice remembers it."
            ))
        }
    }

    // MARK: - R30: Carousel Feed Row

    private func carouselMoveRow(_ move: CoachCarouselEngine.CarouselMove) -> some View {
        let (icon, color): (String, Color) = {
            switch move.kind {
            case .firing:           return ("person.fill.xmark", .danger)
            case .hcHire:           return ("person.fill.checkmark", .success)
            case .coordinatorHire:  return ("person.fill.badge.plus", .accentBlue)
            case .interviewRequest: return ("envelope.badge.fill", .accentGold)
            case .departure:        return ("arrow.up.right.circle.fill", .accentGold)
            case .blocked:          return ("hand.raised.fill", .warning)
            }
        }()

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.body))
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(move.coachName) · \(move.teamName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(move.detail)
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(move.coachName), \(move.teamName): \(move.detail)")
    }

    // MARK: - R30: Coaching Tree Sync

    /// Backfills open coaching-tree entries for the current staff (careers
    /// started before R30 have an empty tree) and closes entries whose
    /// coaches are no longer on staff.
    private func syncCoachingTree() {
        guard career.teamID != nil else { return }
        // Never run against an unloaded/empty staff — closing every open
        // entry because the query hasn't populated yet would corrupt the tree.
        guard !coaches.isEmpty else { return }
        let medicalRoles = StaffLedger.medicalRoles
        var tree = career.coachingTree
        var changed = false

        // 1. Every current coach has an open entry.
        for coach in coaches where !medicalRoles.contains(coach.role) {
            let tracked = tree.entries.contains {
                $0.coachName == coach.fullName && $0.yearLeft == nil
            }
            if !tracked {
                let hiredYear = coach.hireSeasonYear > 0
                    ? min(coach.hireSeasonYear, career.currentSeason)
                    : career.currentSeason
                tree.entries.append(CoachRelationshipEngine.CoachingTreeEntry(
                    coachName: coach.fullName,
                    role: coach.role,
                    yearHired: hiredYear
                ))
                changed = true
            }
        }

        // 2. Open entries whose coach left (replaced, poached before R30)
        //    get closed out as alumni.
        let currentNames = Set(coaches.map(\.fullName))
        for index in tree.entries.indices where tree.entries[index].yearLeft == nil {
            if !currentNames.contains(tree.entries[index].coachName) {
                tree.entries[index].yearLeft = career.currentSeason
                if tree.entries[index].destination == nil {
                    tree.entries[index].destination = "Moved on"
                }
                changed = true
            }
        }

        if changed {
            career.coachingTree = tree
            try? modelContext.save()
        }
    }

    // MARK: - The hiring ladder (§2.1, wave 5b)
    //
    // Hiring IS a process — the screen has said so since #50 by numbering its
    // sections 1 to 5 — and until this wave the only thing that said it was five
    // gold discs buried in five section headers, three of them inside collapsed
    // `DisclosureGroup`s. So the order was invisible exactly when it mattered:
    // on the empty staff of a brand-new career, where "where do I even start" is
    // the entire question. The band states the ladder once, at the top of the
    // surface, and every slat is a hire button.
    //
    // The predecessor was `hirePriorityStrip` — "HIRE THESE FIRST", three
    // orange chips at 9 and 10 pt. It answered the same question with a sixth
    // progress metaphor, under the type floor, in a colour that means "caution"
    // (P7). The band replaces it: same three jobs reachable, one component.
    //
    // **The assistant head coach is not on the ladder**, exactly as the screen
    // already draws him: a hollow disc outside the 1-2-3 column, because the
    // chair is optional. He keeps his own section and his own hire button; the
    // band never counts him, so a club that has filled every required seat reads
    // "complete" rather than being held open by a job nobody has to fill.

    /// One rung of the ladder — the five numbered sections, as a process.
    enum StaffTier: String, CaseIterable, Identifiable {
        case headCoach, coordinators, position, medical, scouting

        var id: String { rawValue }

        /// Display voice, uppercased by the band. Kept to one or two short
        /// words so a slat never breaks a name across two lines at the 11 pt
        /// floor (`DSSlatGeometry.minSlatWidth`).
        var title: String {
            switch self {
            case .headCoach:    return "Head Coach"
            case .coordinators: return "Coordinators"
            case .position:     return "Position"
            case .medical:      return "Medical"
            case .scouting:     return "Scouting"
            }
        }

        var spokenTitle: String {
            self == .position ? "position coaches" : title.lowercased()
        }
    }

    /// Which rung a job belongs to. The assistant head coach belongs to none.
    private func tier(for vacancy: StaffVacancy) -> StaffTier? {
        switch vacancy {
        case .coach(.headCoach):          return .headCoach
        case .coach(.assistantHeadCoach): return nil
        case .coach(let role):
            if Self.medicalRoles.contains(role) { return .medical }
            let coordinatorRoles: [CoachRole] = [
                .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator
            ]
            if coordinatorRoles.contains(role) { return .coordinators }
            return .position
        case .scout:
            return .scouting
        }
    }

    /// Open jobs on one rung, still in hiring order.
    private func vacancies(in tier: StaffTier) -> [StaffVacancy] {
        orderedVacancies.filter { self.tier(for: $0) == tier }
    }

    /// Seats already filled on one rung.
    private func filledSeats(in tier: StaffTier) -> Int {
        switch tier {
        case .headCoach:
            return (career.role == .gmAndHeadCoach || headCoach != nil) ? 1 : 0
        case .coordinators:
            return coordinators.count
        case .position:
            return positionCoaches.count
        case .medical:
            return medicalStaff.count
        case .scouting:
            return scouts.count
        }
    }

    /// The rung the club is standing on: the first one with a hole in it.
    private var currentTier: StaffTier? {
        StaffTier.allCases.first { !vacancies(in: $0).isEmpty }
    }

    /// **The one place the ladder prints its count** (§2.1).
    private var hiringHeadline: String {
        guard let current = currentTier,
              let index = StaffTier.allCases.firstIndex(of: current) else {
            return "Staff complete"
        }
        return "Hiring \u{2014} tier \(index + 1) of \(StaffTier.allCases.count)"
    }

    private func hiringSlat(
        _ tier: StaffTier,
        position: Int,
        allocations: [String: Int],
        current: StaffTier?
    ) -> DSSlat {
        let open = vacancies(in: tier)
        let filled = filledSeats(in: tier)
        let state: DSSlat.State
        if open.isEmpty {
            state = .done
        } else if tier == current {
            state = .current
        } else {
            state = .future
        }

        let planned = open.reduce(0) { $0 + (allocations[$1.id] ?? 0) }
        let subcaption: String? = {
            guard state == .current else { return nil }
            let jobs = "\(open.count) open"
            return planned > 0 ? "\(jobs) \u{00B7} ~$\(formatBudget(planned))M" : jobs
        }()
        let outcome: String? = {
            guard state == .done else { return nil }
            if tier == .headCoach && career.role == .gmAndHeadCoach { return "You" }
            return filled > 0 ? "\(filled) hired" : "None needed"
        }()

        return DSSlat(
            id: tier.rawValue,
            index: "\(position)",
            title: tier.title,
            subcaption: subcaption,
            state: state,
            // Every rung is reachable by hand at any time — the ladder is
            // advice about ORDER, not a gate. A later rung the club can already
            // work in is what `isAvailable` is for.
            isAvailable: state == .future,
            outcome: outcome,
            accessibilityText: [
                "Hiring tier \(position) of \(StaffTier.allCases.count)",
                tier.spokenTitle,
                open.isEmpty
                    ? "filled"
                    : "\(open.count) open, \(filled) hired",
                open.isEmpty ? nil : "opens the hire list for \(open[0].displayName)"
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    /// The ladder, pinned at the top of the staff surface.
    ///
    /// `autoHireAllocations` is read ONCE per render and handed down: it is an
    /// O(vacancies) plan over three budget pots, and letting each slat reach for
    /// it would rebuild the whole plan five times a frame.
    private var hiringBand: some View {
        let allocations = autoHireAllocations
        let current = currentTier
        return DSSlatBand(
            slats: StaffTier.allCases.enumerated().map { index, tier in
                hiringSlat(tier, position: index + 1, allocations: allocations, current: current)
            },
            headline: hiringHeadline,
            // Demoted to the 44 pt variant once every seat is filled: the
            // ladder is still the truth of the screen, but it stops being the
            // thing the screen is about.
            isCompact: current == nil,
            selectedID: current?.rawValue,
            onSelect: { id in
                guard !isAutoHiring, let tier = StaffTier(rawValue: id) else { return }
                if let next = vacancies(in: tier).first {
                    openHireSheet(for: next)
                } else {
                    expandSection(for: tier)
                }
            }
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }

    /// A rung with nothing left to hire opens the section it names instead.
    private func expandSection(for tier: StaffTier) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch tier {
            case .headCoach:    break
            case .coordinators: isCoordinatorsExpanded = true
            case .position:     isPositionCoachesExpanded = true
            case .medical:      isMedicalExpanded = true
            case .scouting:     isScoutingExpanded = true
            }
        }
    }

    // MARK: - Auto-Hire UI (Batch 2E)

    /// Routes a vacancy to the hire flow it already had — coordinators and
    /// position coaches to the negotiation table, medical to the simple sheet,
    /// scouts to the scouting board.
    private func openHireSheet(for vacancy: StaffVacancy) {
        switch vacancy {
        case .coach(let role) where Self.medicalRoles.contains(role):
            activeHireSheet = .medical(role, medicalHireCandidates(role: role))
        case .coach(let role):
            activeHireSheet = .coach(role)
        case .scout(let role):
            activeHireSheet = .scout(role)
        }
    }

    private var autoHireButton: some View {
        Button {
            Task { await runAutoHire() }
        } label: {
            HStack(spacing: 12) {
                if isAutoHiring {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.accentGold)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: DSType.Size.callout, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                        .frame(width: 22, height: 22)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isAutoHiring ? "Hiring…" : "Auto-Hire Recommended Staff")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(isAutoHiring
                         ? (autoHireStatus ?? "Working through the vacancies…")
                         : "Fills all \(orderedVacancies.count) vacant roles with the best affordable candidate who fits your staff.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if !isAutoHiring && !autoHireSpendSubtitle.isEmpty {
                        Text(autoHireSpendSubtitle)
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.accentGold)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                if !isAutoHiring {
                    Image(systemName: "chevron.right")
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentGold.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentGold.opacity(0.45), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAutoHiring)
        .accessibilityLabel("Auto-hire recommended staff")
        .accessibilityHint("Fills all \(orderedVacancies.count) vacant roles. \(autoHireSpendSubtitle). You can still hire or replace anyone by hand afterwards.")
    }

    // MARK: - How one hire ends (#49, wave 5b)

    /// The ending of a single hire, in `DSResultSheet`'s grammar (§2.6).
    ///
    /// The old toast said `"<name> hired as <role>!"` and faded after three
    /// seconds. It never said what the man cost or what was left in the pot —
    /// which is the only question a user has after signing anybody, and the
    /// reason the pre-wave flow made him close the sheet and hunt the budget
    /// header for the answer.
    ///
    /// Writing `sheetOutcome` swaps the content of the sheet the hire list was
    /// already living in. The sheet's identity does not change, so nothing is
    /// dismissed and nothing is re-presented — which is why the 0.6 s / 0.4 s /
    /// 0.8 s timers the three hire views used to carry could all be deleted.
    /// - Parameter book: the staff reading the chips are composed from. Defaults
    ///   to this screen's `ledger`; the scout path passes a freshly fetched one
    ///   because its callback fires before `@Query` has seen the hire.
    private func showHireResult(
        name: String,
        roleName: String,
        salary: Int,
        pot: StaffPot,
        book: StaffLedger? = nil
    ) {
        let book = book ?? ledger
        // Keep every section open so the newly filled row is visible behind the
        // result.
        isCoordinatorsExpanded = true
        isPositionCoachesExpanded = true
        isMedicalExpanded = true
        isScoutingExpanded = true

        let left = remaining(pot, in: book)
        let stillOpen = orderedVacancies(in: book).count
        sheetOutcome = StaffOutcome(
            tone: .good,
            eyebrow: "Staff hiring",
            headline: "\(name) is your \(roleName)",
            message: stillOpen == 0
                ? "Every chair on your staff is filled."
                : "**\(stillOpen)** job\(stillOpen == 1 ? "" : "s") still open on the staff.",
            chips: [
                .init(id: "role", label: "Role", value: roleName),
                .init(id: "salary", label: "Salary", value: coachSalaryText(salary)),
                .init(
                    id: "left",
                    label: "\(potName(pot)) left",
                    value: "$\(formatBudget(max(0, left)))M",
                    context: left < 0 ? "over budget" : "this season",
                    valueColor: left < 0 ? .dangerText : .textPrimary
                )
            ],
            cost: "Charges **\(coachSalaryText(salary))** against your \(potName(pot).lowercased()) budget "
                + "for \(pot == .scouting ? "as long as he is on staff" : "the length of his deal")."
        )
    }

    private func potName(_ pot: StaffPot) -> String {
        switch pot {
        case .coaching: return "Coaching"
        case .medical:  return "Medical"
        case .scouting: return "Scouting"
        }
    }

    // MARK: - Budget Header

    /// Budget change from previous season (in thousands).
    ///
    /// Only meaningful once this front office has actually worked a season.
    /// At career bootstrap `WeekAdvancer.startNewSeason` stamps
    /// `previousCoachingBudget` with the authored `LeagueTeamData` figure and then
    /// replaces `coachingBudget` with the `BudgetEngine` formula output, so week 0
    /// of season 1 would otherwise show a phantom year-over-year delta
    /// (BAL: $46.0M authored → $38.4M formula = a bogus "-$7.6M").
    private var budgetChange: Int? {
        guard career.totalWins + career.totalLosses > 0 else { return nil }
        guard let prev = owner?.previousCoachingBudget, prev > 0 else { return nil }
        let delta = coachingBudget - prev
        return delta == 0 ? nil : delta
    }

    /// League-average coaching budget in thousands. Used for context indicator.
    /// Hardcoded to $35M for now — see `LeagueGenerator.swift` (default 35) and `LeagueTeamData.swift`.
    private static let leagueAverageCoachingBudget: Int = 35_000

    /// Context for the team's coaching budget vs the league average.
    private var budgetContext: (label: String, color: Color) {
        let avg = Self.leagueAverageCoachingBudget
        let lowerThreshold = Int(Double(avg) * 0.9)   // within 10% = league avg
        let upperThreshold = Int(Double(avg) * 1.1)
        let avgM = avg / 1_000

        if coachingBudget < lowerThreshold {
            return ("Below league avg (~$\(avgM)M)", Color.warning)
        } else if coachingBudget > upperThreshold {
            return ("Above league avg (~$\(avgM)M)", Color.success)
        } else {
            return ("League avg (~$\(avgM)M)", Color.textTertiary)
        }
    }

    /// R27/R31: names the pot(s) that are overspent now that the budgets are split.
    ///
    /// No `@ViewBuilder`: this returns a String, and the attribute it used to
    /// carry was disabled by the explicit return anyway.
    private var overBudgetMessage: String {
        var overs: [String] = []
        if remainingBudget < 0 {
            overs.append("$\(formatBudget(abs(remainingBudget)))M over the coaching budget")
        }
        if remainingScoutBudget < 0 {
            overs.append("$\(formatBudget(abs(remainingScoutBudget)))M over the scouting budget")
        }
        if remainingMedicalBudget < 0 {
            overs.append("$\(formatBudget(abs(remainingMedicalBudget)))M over the medical budget")
        }
        let list = overs.isEmpty ? "over budget" : overs.joined(separator: " and ")
        return "You are \(list). Release staff, reduce salaries, or reallocate the budget in Owner Relations to proceed."
    }

    private var budgetHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coaching Budget")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 4) {
                        Text("Used $\(formatBudget(totalCoachSalaryUsed))M of $\(formatBudget(coachingBudget))M")
                            .font(.caption)
                            .foregroundStyle(remainingBudget >= 0 ? Color.textSecondary : Color.dangerText)

                        // Budget change from last season (#80) — spelled out, so a
                        // year-over-year cut can never read as an overspend.
                        if let change = budgetChange {
                            Text(change > 0
                                 ? "(+$\(formatBudget(change))M vs last season)"
                                 : "(-$\(formatBudget(abs(change)))M vs last season)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(change > 0 ? Color.success : Color.warning)
                        }
                    }

                    // League-average context indicator
                    Text(budgetContext.label)
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(budgetContext.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(budgetContext.color.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(budgetContext.color.opacity(0.4), lineWidth: 1))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(formatBudget(remainingBudget))M")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(remainingBudget >= 0 ? Color.success : Color.dangerText)
                    Text("remaining")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Progress bar (coaches)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(remainingBudget >= 0 ? Color.accentGold : Color.danger)
                        .frame(width: geo.size.width * min(1.0, Double(totalCoachSalaryUsed) / max(1.0, Double(coachingBudget))))
                }
            }
            .frame(height: 6)

            // R27: separate scouting budget line + bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "binoculars")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.accentBlue)
                    Text("Scouting Budget")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Used $\(formatBudget(totalScoutSalaryUsed))M of $\(formatBudget(scoutingBudget))M")
                        .font(.caption)
                        .foregroundStyle(remainingScoutBudget >= 0 ? Color.textSecondary : Color.dangerText)
                }
                Spacer()
                Text("$\(formatBudget(remainingScoutBudget))M left")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingScoutBudget >= 0 ? Color.success : Color.dangerText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(remainingScoutBudget >= 0 ? Color.accentBlue : Color.danger)
                        .frame(width: geo.size.width * min(1.0, Double(totalScoutSalaryUsed) / max(1.0, Double(scoutingBudget))))
                }
            }
            .frame(height: 6)

            // R31: separate medical budget line + bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cross.case")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.success)
                    Text("Medical Budget")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Used $\(formatBudget(totalMedicalSalaryUsed))M of $\(formatBudget(medicalBudget))M")
                        .font(.caption)
                        .foregroundStyle(remainingMedicalBudget >= 0 ? Color.textSecondary : Color.dangerText)
                }
                Spacer()
                Text("$\(formatBudget(remainingMedicalBudget))M left")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingMedicalBudget >= 0 ? Color.success : Color.dangerText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(remainingMedicalBudget >= 0 ? Color.success : Color.danger)
                        .frame(width: geo.size.width * min(1.0, Double(totalMedicalSalaryUsed) / max(1.0, Double(medicalBudget))))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    /// Formats a budget value (in thousands) to a display string like "25.0".
    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    // MARK: - Player as HC row (GM+HC career)

    @ViewBuilder
    private var playerAsHeadCoachRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // HC badge
                Text("HC")
                    .font(.system(size: DSType.Size.callout, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 6))

                // The user's own portrait — the photograph picked in the
                // new-career wizard — MOVED here from the row's trailing edge.
                // It was the only face on the staff screen that did not sit
                // right after the role badge (`HeadCoachCardView`, `CoachRowView`
                // and `CoachRowWithDescriptionView` all lead with it), which read
                // as the head-coach card missing the portrait every row under
                // it had. Same styling as the AI rows, so the gold ring and
                // diameter match. Tapping it re-opens the picker: this card is
                // the only place a running career can change its face.
                Button {
                    activeHireSheet = .portrait
                } label: {
                    UserPortraitView(career: career, size: .medium)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: DSType.Size.callout))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.backgroundPrimary, Color.accentGold)
                                .offset(x: 2, y: 2)
                        }
                }
                .buttonStyle(.plain)
                // Distinct from the labelled twin further down the card, which
                // also says "Change portrait" — two controls reading identically
                // in the same card is a VoiceOver dead end.
                .accessibilityLabel("Your portrait. Double tap to change it")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("You")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.accentGold)
                        Text("(\(career.playerName))")
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack(spacing: 6) {
                        Text(career.coachingStyle.displayName)
                            .foregroundStyle(Color.accentBlue)
                        Text("\u{00B7}")
                        Text("GM & Head Coach")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .font(.caption)
                }

                Spacer()
            }

            Text("Sets the team's vision, manages coordinators, and makes key game-day decisions")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            // Fix #36: Coaching style bonus for player-as-HC
            HStack(spacing: 4) {
                Text("+\(career.coachingStyle.bonusValue) \(career.coachingStyle.bonusAttribute)")
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.success)
            }

            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: DSType.Size.micro))
                Text(coordinatorComplementNote(for: career.coachingStyle))
                    .font(.system(size: DSType.Size.micro, weight: .medium))
            }
            .foregroundStyle(Color.accentGold.opacity(0.8))

            // Discoverable twin of the tap target on the portrait itself — a
            // pencil badge alone is easy to miss on a card this dense.
            Button {
                activeHireSheet = .portrait
            } label: {
                Label("Change portrait", systemImage: "person.crop.circle")
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Coach Row with Chemistry Indicator

    @ViewBuilder
    private func coachRowWithChemistry(coach: Coach) -> some View {
        Button {
            detailCoachID = coach.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CoachRowWithDescriptionView(coach: coach)

                // Chemistry indicator
                if let chemistry = chemistryWithHC(coach: coach) {
                    HStack(spacing: 4) {
                        Text(CoachingEngine.chemistrySymbol(score: chemistry))
                            .font(.caption)
                        Text(CoachingEngine.chemistryLabel(score: chemistry))
                            .font(.system(size: DSType.Size.micro, weight: .medium))
                    }
                    .foregroundStyle(chemistryColor(for: chemistry))
                    .padding(.leading, 56) // align with name after badge
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact Coach Card (#50)

    @ViewBuilder
    private func compactCoachCard(coach: Coach) -> some View {
        let keyAttr: (name: String, value: Int) = {
            switch coach.role {
            case .headCoach, .assistantHeadCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
                return ("PC", coach.playCalling)
            default:
                return ("Dev", coach.playerDevelopment)
            }
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(coach.role.abbreviation)
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(coach.role.badgeColor, in: RoundedRectangle(cornerRadius: 3))

                Spacer()

                Text("\(keyAttr.value)")
                    .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(keyAttr.value))
            }

            HStack(spacing: 4) {
                Text(coach.fullName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if coach.isInAdjustmentPeriod {
                    Text("Adjusting")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            HStack(spacing: 4) {
                Text("\(coach.yearsExperience)yr")
                    .font(.system(size: DSType.Size.caption).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                Text("\u{00B7}")
                    .foregroundStyle(Color.textTertiary)
                Text("$\(coach.salary)K")
                    .font(.system(size: DSType.Size.caption).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)

                // Chemistry pip vs HC (small inline checkmark / warning / X)
                if coach.role != .headCoach, let chem = chemistryWithHC(coach: coach) {
                    Spacer(minLength: 2)
                    Text(CoachingEngine.chemistrySymbol(score: chem))
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(chemistryColor(for: chem))
                        .accessibilityLabel("Chemistry with head coach: \(CoachingEngine.chemistryLabel(score: chem))")
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.surfaceBorder.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - Compact Vacant Card (#50)

    @ViewBuilder
    private func compactVacantCard(role: CoachRole) -> some View {
        Button {
            activeHireSheet = .coach(role)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(role.abbreviation)
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    Image(systemName: "plus.circle")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.accentGold)
                }

                Text(role.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                // #51: Impact hint in compact card
                if let impact = hiringImpactDescription(for: role) {
                    Text(impact)
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                        .foregroundStyle(Color.success)
                        .lineLimit(1)
                }

                Text(estimatedSalaryRange(for: role))
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentGold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - #276: Compact Vacant Medical Card (simple hire flow)

    @ViewBuilder
    private func compactVacantMedicalCard(role: CoachRole) -> some View {
        Button {
            activeHireSheet = .medical(role, medicalHireCandidates(role: role))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(role.abbreviation)
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    Image(systemName: "plus.circle")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.accentGold)
                }

                Text(role.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                if let impact = hiringImpactDescription(for: role) {
                    Text(impact)
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                        .foregroundStyle(Color.success)
                        .lineLimit(1)
                }

                Text(estimatedSalaryRange(for: role))
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentGold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Staff chemistry is a SIGNED −1…1 relationship score, not a 0–100 rating,
    /// so P7 rule 2 applies: status at a stated threshold. The threshold is not
    /// restated here — `CoachingEngine.chemistryBand` owns it, and the symbol
    /// and word printed beside this colour already come from that same band, so
    /// a copy in the view could only ever drift out of step with them.
    private func chemistryColor(for score: Double) -> Color {
        switch CoachingEngine.chemistryBand(score: score) {
        case .good:     return .forStatus(.ok)
        case .tension:  return .forStatus(.warn)
        case .conflict: return .forStatus(.bad)
        }
    }

    // MARK: - HC Vacant Row (prominent)

    @ViewBuilder
    private var headCoachVacantRow: some View {
        Button {
            activeHireSheet = .coach(.headCoach)
        } label: {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Head Coach")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.textTertiary)
                            Text("Sets the team's vision, manages coordinators, and makes key game-day decisions")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentGold)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                        Text("HIRE FIRST")
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                    }
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentGold.opacity(0.12))
                    )
                }
                .padding(.vertical, 6)
            }
        }


    // MARK: - Vacant row

    @ViewBuilder
    private func vacantRow(role: CoachRole) -> some View {
        Button {
            activeHireSheet = .coach(role)
        } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(role.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textTertiary)

                            // Fix #32: Hiring priority indicator
                            switch hiringPriority(for: role) {
                            case .high:
                                Text("High Priority")
                                    .font(.system(size: DSType.Size.caption, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.danger, in: Capsule())
                            case .recommended:
                                Text("Recommended")
                                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                                    .foregroundStyle(Color.warning)
                            case .normal:
                                EmptyView()
                            }
                        }

                        Text("Vacant \u{2014} Tap to hire")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)

                        // Fix #35: Estimated salary range
                        Text(estimatedSalaryRange(for: role))
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)

                        // Fix #32: Position group boost description
                        if let boost = positionGroupBoost(for: role) {
                            Text(boost)
                                .font(.system(size: DSType.Size.micro, weight: .medium))
                                .foregroundStyle(Color.accentBlue.opacity(0.8))
                        }

                        // #51: Hiring impact on team performance
                        if let impact = hiringImpactDescription(for: role) {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: DSType.Size.micro))
                                Text(impact)
                                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                            }
                            .foregroundStyle(Color.success)
                        }
                    }
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentGold)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        .buttonStyle(.plain)
        }

    // MARK: - Scout Row

    @ViewBuilder
    private func scoutRow(scout: Scout) -> some View {
        Button {
            detailScoutID = scout.id
        } label: {
        HStack(spacing: 12) {
            // Role badge
            Text(scout.scoutRole.abbreviation)
                .font(.system(size: DSType.Size.footnote, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(scout.scoutRole.isChief ? Color.accentGold : Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                .frame(width: 44)

            // Name + meta
            VStack(alignment: .leading, spacing: 2) {
                Text(scout.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text("\(scout.experience) yr\(scout.experience == 1 ? "" : "s") exp")
                    if let spec = scout.positionSpecialization {
                        Text("\u{00B7}")
                        Text(spec.rawValue)
                            .foregroundStyle(Color.accentBlue)
                    }
                    Text("\u{00B7}")
                    Text("$\(scout.salary)K")
                        .foregroundStyle(Color.textTertiary)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Accuracy rating
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(scout.accuracy)")
                    .font(.system(size: DSType.Size.title3, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(scout.accuracy))
                Text("Accuracy")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scout Vacant Row

    @ViewBuilder
    private func scoutVacantRow(role: ScoutRole) -> some View {
        // IMPORTANT: Use onTapGesture + contentShape instead of Button.
        // Button inside DisclosureGroup causes tap to target the last rendered
        // item instead of the tapped one — a known SwiftUI hit-testing bug.
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(role.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textTertiary)

                    // #53: Priority badge consistent with coach vacant rows
                    switch scoutHiringPriority(for: role) {
                    case .high:
                        Text("High Priority")
                            .font(.system(size: DSType.Size.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.danger, in: Capsule())
                    case .recommended:
                        Text("Recommended")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.warning)
                    case .normal:
                        EmptyView()
                    }
                }

                Text("Vacant \u{2014} Tap to hire")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)

                // #53: Salary range
                Text(estimatedScoutSalaryRange(for: role))
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)

                // #53: Hiring impact
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: DSType.Size.micro))
                    Text(scoutHiringImpact(for: role))
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                }
                .foregroundStyle(Color.success)
            }
            Spacer()
            Image(systemName: "plus.circle")
                .foregroundStyle(Color.accentGold)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            activeHireSheet = .scout(role)
        }
    }
}

// MARK: - Head Coach Card (Prominent)

private struct HeadCoachCardView: View {
    let coach: Coach
    var menteeCount: Int = 0

    private var schemeText: String? {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return nil
    }

    /// The HC's strongest attribute and its value.
    private var topAttribute: (name: String, value: Int) {
        let attributes: [(String, Int)] = [
            ("Play Calling", coach.playCalling),
            ("Player Dev", coach.playerDevelopment),
            ("Game Planning", coach.gamePlanning),
            ("Motivation", coach.motivation),
            ("Adaptability", coach.adaptability),
            ("Discipline", coach.discipline)
        ]
        return attributes.max(by: { $0.1 < $1.1 }) ?? ("Play Calling", coach.playCalling)
    }

    /// Coordinator complement note based on HC personality.
    private var coordinatorNote: String {
        switch coach.personality {
        case .teamLeader:
            return "Pair with strong-willed coordinators who bring tactical depth"
        case .quietProfessional:
            return "Pair with creative coordinators who can execute complex schemes"
        case .fieryCompetitor:
            return "Pair with calm, detail-oriented coordinators for balance"
        case .mentor:
            return "Pair with disciplined coordinators to balance player freedom"
        case .steadyPerformer:
            return "Pair with innovative coordinators who push boundaries"
        case .feelPlayer:
            return "Pair with experienced coordinators who can ground bold ideas"
        case .loneWolf:
            return "Pair with collaborative coordinators who bridge communication gaps"
        case .dramaQueen:
            return "Pair with steady, low-drama coordinators for stability"
        case .classClown:
            return "Pair with structured coordinators to complement loose leadership"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // Head coach portrait — the staff card is the one place a
                // coach gets more than a row, so it carries the bigger size.
                PersonFaceView(coach: coach, size: .medium, ringColor: .accentGold)

                // HC badge -- larger
                Text("HC")
                    .font(.system(size: DSType.Size.callout, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.fullName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text("Age \(coach.age)")
                        Text("\u{00B7}")
                        Text("\(coach.yearsExperience) yr\(coach.yearsExperience == 1 ? "" : "s") exp")
                        if let scheme = schemeText {
                            Text("\u{00B7}")
                            Text(scheme)
                                .foregroundStyle(Color.accentBlue)
                        }
                        Text("\u{00B7}")
                        Text(coachSalaryText(coach.salary))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                    // Fix #36: Coaching style bonus
                    HStack(spacing: 4) {
                        Text("+\(topAttribute.value) \(topAttribute.name)")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.success)
                        Text("\u{00B7}")
                            .foregroundStyle(Color.textTertiary)
                        Text(coach.personality.displayName)
                            .font(.system(size: DSType.Size.caption, weight: .medium))
                            .foregroundStyle(Color.accentBlue)
                    }
                }

                Spacer()

                // Play calling rating -- larger
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(coach.playCalling)")
                        .font(.system(size: DSType.Size.title2, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(coach.playCalling))
                    Text("Play Calling")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Role description
            Text("Sets the team's vision, manages coordinators, and makes key game-day decisions")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            // Fix #36: Coordinator complement note
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: DSType.Size.micro))
                Text(coordinatorNote)
                    .font(.system(size: DSType.Size.micro, weight: .medium))
            }
            .foregroundStyle(Color.accentGold.opacity(0.8))

            // Coaching Tree badge
            if menteeCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: DSType.Size.micro))
                    Text("Coaching Tree: \(menteeCount)")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                }
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coach.fullName), Head Coach, age \(coach.age), Play Calling \(coach.playCalling)")
    }
}

// MARK: - Coach Row with Description

private struct CoachRowWithDescriptionView: View {
    let coach: Coach

    private var keyAttribute: (name: String, value: Int) {
        switch coach.role {
        case .headCoach, .assistantHeadCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return ("Play Calling", coach.playCalling)
        default:
            return ("Development", coach.playerDevelopment)
        }
    }

    private var schemeText: String? {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return nil
    }

    /// The coach's primary strength -- highest attribute name.
    private var primaryStrength: String {
        let attributes: [(String, Int)] = [
            ("Play Calling", coach.playCalling),
            ("Player Dev", coach.playerDevelopment),
            ("Reputation", coach.reputation),
            ("Adaptability", coach.adaptability),
            ("Game Planning", coach.gamePlanning),
            ("Scouting", coach.scoutingAbility),
            ("Recruiting", coach.recruiting),
            ("Motivation", coach.motivation),
            ("Discipline", coach.discipline),
            ("Media", coach.mediaHandling),
            ("Negotiation", coach.contractNegotiation),
            ("Morale", coach.moraleInfluence)
        ]
        return attributes.max(by: { $0.1 < $1.1 })?.0 ?? "Play Calling"
    }

    /// Average of all coach attributes, used for mini star rating.
    private var averageAttribute: Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.reputation +
                  coach.adaptability + coach.gamePlanning + coach.scoutingAbility +
                  coach.recruiting + coach.motivation + coach.discipline +
                  coach.mediaHandling + coach.contractNegotiation + coach.moraleInfluence
        return sum / 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Role badge
                Text(coach.role.abbreviation)
                    .font(.system(size: DSType.Size.footnote, weight: .bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(coach.role.badgeColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                    .frame(width: 44)

                PersonFaceView(coach: coach, size: .small)

                // Name + meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text("Age \(coach.age)")
                        Text("\u{00B7}")
                        Text("\(coach.yearsExperience) yr\(coach.yearsExperience == 1 ? "" : "s") exp")
                        if let scheme = schemeText {
                            Text("\u{00B7}")
                            Text(scheme)
                                .foregroundStyle(Color.accentBlue)
                        }
                        Text("\u{00B7}")
                        Text(coachSalaryText(coach.salary))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                    // Mini star rating + primary strength
                    HStack(spacing: 6) {
                        Text(CoachingEngine.starString(for: averageAttribute))
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.accentGold)
                        Text(primaryStrength)
                            .font(.system(size: DSType.Size.micro, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                // Key attribute
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(keyAttribute.value)")
                        .font(.system(size: DSType.Size.title3, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(keyAttribute.value))
                    Text(keyAttribute.name)
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Role description
            Text(coach.role.roleDescription)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coach.fullName), \(coach.role.displayName), age \(coach.age), \(keyAttribute.name) \(keyAttribute.value)")
    }
}

// MARK: - Coach Row View

private struct CoachRowView: View {
    let coach: Coach

    /// The key attribute to surface depends on role tier.
    private var keyAttribute: (name: String, value: Int) {
        switch coach.role {
        case .headCoach, .assistantHeadCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return ("Play Calling", coach.playCalling)
        default:
            return ("Development", coach.playerDevelopment)
        }
    }

    private var schemeText: String? {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            // Role badge
            Text(coach.role.abbreviation)
                .font(.system(size: DSType.Size.footnote, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(coach.role.badgeColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                .frame(width: 44)

            PersonFaceView(coach: coach, size: .small)

            // Name + meta
            VStack(alignment: .leading, spacing: 2) {
                Text(coach.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text("Age \(coach.age)")
                    Text("\u{00B7}")
                    Text("\(coach.yearsExperience) yr\(coach.yearsExperience == 1 ? "" : "s") exp")
                    if let scheme = schemeText {
                        Text("\u{00B7}")
                        Text(scheme)
                            .foregroundStyle(Color.accentBlue)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Key attribute
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(keyAttribute.value)")
                    .font(.system(size: DSType.Size.title3, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(keyAttribute.value))
                Text(keyAttribute.name)
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coach.fullName), \(coach.role.displayName), age \(coach.age), \(keyAttribute.name) \(keyAttribute.value)")
    }
}

// MARK: - CoachRole helpers

extension CoachRole {
    var displayName: String {
        switch self {
        case .headCoach:               return "Head Coach"
        case .assistantHeadCoach:      return "Assistant Head Coach"
        case .offensiveCoordinator:    return "Offensive Coordinator"
        case .defensiveCoordinator:    return "Defensive Coordinator"
        case .specialTeamsCoordinator: return "Special Teams Coordinator"
        case .qbCoach:                 return "QB Coach"
        case .rbCoach:                 return "RB Coach"
        case .wrCoach:                 return "WR Coach"
        case .olCoach:                 return "OL Coach"
        case .dlCoach:                 return "DL Coach"
        case .lbCoach:                 return "LB Coach"
        case .dbCoach:                 return "DB Coach"
        case .strengthCoach:           return "Strength & Conditioning"
        case .teamDoctor:              return "Team Doctor"
        case .physio:                  return "Physiotherapist"
        case .headTrainer:             return "Head Trainer"
        }
    }

    var abbreviation: String {
        switch self {
        case .headCoach:               return "HC"
        case .assistantHeadCoach:      return "AHC"
        case .offensiveCoordinator:    return "OC"
        case .defensiveCoordinator:    return "DC"
        case .specialTeamsCoordinator: return "STC"
        case .qbCoach:                 return "QB"
        case .rbCoach:                 return "RB"
        case .wrCoach:                 return "WR"
        case .olCoach:                 return "OL"
        case .dlCoach:                 return "DL"
        case .lbCoach:                 return "LB"
        case .dbCoach:                 return "DB"
        case .strengthCoach:           return "S&C"
        case .teamDoctor:              return "DOC"
        case .physio:                  return "PHY"
        case .headTrainer:             return "TRN"
        }
    }

    var sortOrder: Int {
        switch self {
        case .headCoach:               return 0
        case .assistantHeadCoach:      return 1
        case .offensiveCoordinator:    return 2
        case .defensiveCoordinator:    return 3
        case .specialTeamsCoordinator: return 4
        case .qbCoach:                 return 5
        case .rbCoach:                 return 6
        case .wrCoach:                 return 7
        case .olCoach:                 return 8
        case .dlCoach:                 return 9
        case .lbCoach:                 return 10
        case .dbCoach:                 return 11
        case .strengthCoach:           return 12
        case .teamDoctor:              return 13
        case .physio:                  return 14
        case .headTrainer:             return 15
        }
    }

    var roleDescription: String {
        switch self {
        case .headCoach:               return "Sets the team's vision, manages coordinators, and makes key game-day decisions"
        case .assistantHeadCoach:      return "Supports the HC, bridges communication between coordinators, and fills in on game day"
        case .offensiveCoordinator:    return "Manages the offense and calls plays"
        case .defensiveCoordinator:    return "Manages the defense and calls coverage schemes"
        case .specialTeamsCoordinator: return "Oversees kicking, punting, and return units"
        case .qbCoach:                 return "Develops quarterbacks and refines passing mechanics"
        case .rbCoach:                 return "Develops running backs and blocking technique"
        case .wrCoach:                 return "Develops receivers and route running"
        case .olCoach:                 return "Develops offensive linemen and pass protection"
        case .dlCoach:                 return "Develops defensive linemen and pass rush technique"
        case .lbCoach:                 return "Develops linebackers and run-fit assignments"
        case .dbCoach:                 return "Develops defensive backs and coverage skills"
        case .strengthCoach:           return "Manages conditioning, injury prevention, and recovery"
        case .teamDoctor:              return "Reduces injury risk and speeds diagnosis for faster return to play"
        case .physio:                  return "Speeds injury recovery and improves weekly fatigue management"
        case .headTrainer:             return "Leads rehab programs — fewer setbacks and safer early returns"
        }
    }

    var badgeColor: Color {
        switch self {
        case .headCoach:               return .accentGold
        case .assistantHeadCoach:      return .accentGold.opacity(0.7)
        case .offensiveCoordinator:    return .accentBlue
        case .defensiveCoordinator:    return .danger
        case .specialTeamsCoordinator: return .success
        case .teamDoctor, .physio, .headTrainer: return .accentBlue.opacity(0.7)
        default:                       return .backgroundTertiary
        }
    }
}

// MARK: - Scheme display helpers

extension OffensiveScheme {
    var displayName: String {
        switch self {
        case .westCoast:  return "West Coast"
        case .airRaid:    return "Air Raid"
        case .spread:     return "Spread"
        case .powerRun:   return "Power Run"
        case .shanahan:   return "Shanahan"
        case .proPassing: return "Pro Passing"
        case .rpo:        return "RPO"
        case .option:     return "Option"
        }
    }
}

extension DefensiveScheme {
    var displayName: String {
        switch self {
        case .base34:   return "3-4 Base"
        case .base43:   return "4-3 Base"
        case .cover3:   return "Cover 3"
        case .pressMan: return "Press Man"
        case .tampa2:   return "Tampa 2"
        case .multiple: return "Multiple"
        case .hybrid:   return "Hybrid"
        }
    }
}

// MARK: - #276: Simple Medical Hire Sheet (no negotiation)

private struct SimpleMedicalHireSheet: View {
    let role: CoachRole
    let candidates: [Coach]
    let remainingBudget: Int
    let teamID: UUID
    /// The save being played — every medical hire is stamped with it.
    let careerID: UUID
    /// The league year the hire is signed in (#143b).
    ///
    /// Every other hiring path stamps `Coach.hireSeasonYear` (`HireCoachView`
    /// line 1094, the auto-hire pass line 843, `CoachCarouselEngine`), and both
    /// tenure readouts in `CoachDetailView` are `currentSeason - hireSeasonYear
    /// + 1`. This sheet never stamped it, so a doctor/physio/trainer kept
    /// `hireSeasonYear == 0`, the `> 0` guard failed, and the card fell back to
    /// "1" forever.
    let currentSeason: Int
    /// `(name, role, salary in thousands)` — wave 5b: the ending is a
    /// `DSResultSheet`, whose third beat is what the hire cost.
    var onHired: ((String, String, Int) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var hiredID: UUID?

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    VStack(spacing: 4) {
                        Text("Hire \(role.displayName)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Select a candidate to hire at their listed salary. No negotiation needed.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    ForEach(candidates.sorted(by: { coachOverall($0) > coachOverall($1) })) { candidate in
                        let ovr = coachOverall(candidate)
                        let isOverBudget = candidate.salary > remainingBudget
                        let isHired = hiredID == candidate.id

                        HStack(spacing: 12) {
                            // OVR badge
                            Text("\(ovr)")
                                .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.forRating(ovr))
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.fullName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)
                                HStack(spacing: 6) {
                                    Text("Age \(candidate.age)")
                                    Text("\u{00B7}")
                                    Text("\(candidate.yearsExperience) yrs exp")
                                    Text("\u{00B7}")
                                    Text(candidate.personality.shortLabel)
                                        .foregroundStyle(Color.accentBlue)
                                }
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            }

                            Spacer()

                            if isHired {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.success)
                                    Text("Hired")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.success)
                                }
                            } else {
                                Button {
                                    hireMedical(candidate)
                                } label: {
                                    VStack(spacing: 1) {
                                        Text("Hire")
                                            .font(.caption.weight(.bold))
                                        Text("$\(String(format: "%.1f", Double(candidate.salary) / 1000.0))M/yr")
                                            .font(.system(size: DSType.Size.caption).monospacedDigit())
                                    }
                                    .foregroundStyle(isOverBudget ? Color.textTertiary : Color.backgroundPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isOverBudget ? Color.backgroundTertiary : Color.accentGold)
                                    )
                                }
                                .disabled(isOverBudget || hiredID != nil)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isHired ? Color.success.opacity(0.06) : Color.backgroundSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(isHired ? Color.success.opacity(0.3) : Color.surfaceBorder.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .opacity(isOverBudget && !isHired ? 0.6 : 1.0)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Hire \(role.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func hireMedical(_ candidate: Coach) {
        guard candidate.salary <= remainingBudget else { return }

        // Release the incumbent — never delete him. Same rule as
        // `HireCoachView.hire`: the row is permanent (archived `LeagueEvent`s
        // fetch coaches by id and render their portrait) and the man belongs on
        // the unemployed bench, not in the void. See `CoachMarketEngine`.
        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            for outgoing in existing where outgoing.role == role && outgoing.id != candidate.id {
                outgoing.teamID = nil
                outgoing.contractYearsRemaining = 0
                outgoing.unemployedSeasons = 0
            }
        }

        candidate.teamID = teamID
        // #143b: stamp the hire year like every other hiring path does, or the
        // staff card reads "Tenure 1" for the rest of his career.
        candidate.hireSeasonYear = currentSeason
        // Back in work — stop the unemployment clock (task #96). No-op for an
        // invented candidate.
        candidate.unemployedSeasons = 0
        // Phase 4 faces: turn the candidate's non-reserving preview portrait
        // into a real reservation (same reason as `HireCoachView.hire`). A coach
        // signed off the market already holds his, and `claimFace` hands the
        // same id back when the registry names him as its holder.
        candidate.faceID = FaceLibrary.shared.claimFace(
            candidate.faceID, personID: candidate.id,
            role: .coach, age: candidate.age, position: nil,
            gender: FacePersonGender(tag: candidate.gender)
        )
        candidate.careerID = careerID
        if candidate.modelContext == nil {
            modelContext.insert(candidate)
        }
        hiredID = candidate.id
        try? modelContext.save()

        // Wave 5b: no 0.8 s deadline and no `dismiss()` — the host swaps this
        // sheet's content to a `DSResultSheet` (§2.6).
        onHired?(candidate.fullName, role.displayName, candidate.salary)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachingStaffView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Coach.self, Scout.self, Owner.self, Player.self], inMemory: true)
}
