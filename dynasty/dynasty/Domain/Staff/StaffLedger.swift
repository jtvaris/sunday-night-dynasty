import Foundation

// MARK: - AdvanceBlocker

/// A non-task reason the calendar advance is refused, in one sentence plus a
/// remedy.
///
/// Lives here rather than on the panel that draws it because two different
/// surfaces draw it (the left rail and the Season Guide sheet) and exactly one
/// place is allowed to decide it — see ``StaffLedger/advanceBlocker(phase:)``.
struct AdvanceBlocker: Equatable {
    /// Headline, e.g. "Resolve staff budget overage first".
    let title: String
    /// What to do about it, in one sentence.
    let detail: String
}

// MARK: - StaffLedger

/// ONE reading of a club's staff: which seats exist, which are filled, and what
/// each of the three pots has committed against its envelope.
///
/// Task #133. The same two questions — "how many staff do I have" and "how much
/// of the budget is gone" — were answered independently by the dashboard staff
/// tile, the Staff screen, the hire flows, the offseason task rail, the staff
/// review sheet and the owner's budget screen. ``StaffSlots`` already unified
/// the SEAT half; this unifies the MONEY half onto the same seat list and
/// deletes the remaining copies. Three defects fell out of the duplication:
///
/// 1. **Seats were counted, salaries were summed per ROW.** ``StaffSlots``
///    exists because duplicate rows for one seat (and the stray head-coach row
///    a GM+HC save can carry) had pushed the tile to "24 / 23". Those same rows
///    were still charged to the coaching pot, so "23 / 23 filled" and "used
///    $x of $y" described different populations — and the money one moved
///    whenever a rogue row appeared or was cleaned up between sessions.
/// 2. **Every surface invented its own budget when the owner had not
///    resolved** — `?? 20_000` on the Staff screen, `?? 0` on the dashboard
///    tile, `25_000` as the hire sheet's default parameter. Which figure a
///    launch printed depended on which copy ran first.
/// 3. **The advance gate re-derived the overage a third time**, so the sidebar
///    and the rail could disagree about whether the week could be left (#158).
///
/// Cheap to build (two array passes) and deliberately a value type: hand it
/// down, never re-derive it per call site.
struct StaffLedger {

    /// Coaching roles paid from the medical pot rather than the coaching pot.
    /// R31 split the envelope; this is the one list that says which side of it
    /// a title falls on.
    static let medicalRoles: Set<CoachRole> = [.teamDoctor, .physio, .headTrainer]

    /// Coaching seats this career is responsible for filling.
    let coachRoles: [CoachRole]
    /// Scouting seats. Every career fills all of them.
    let scoutRoles: [ScoutRole]

    /// Occupied coaching seats (seats, never rows).
    let filledCoachRoles: Set<CoachRole>
    /// Occupied scouting seats.
    let filledScoutRoles: Set<ScoutRole>

    /// Owner envelopes, in thousands. Zero when no owner has resolved — the one
    /// honest answer, and the reason `isResolved` exists instead of a per-screen
    /// invented default.
    let coachingBudget: Int
    let medicalBudget: Int
    let scoutingBudget: Int

    /// Salary committed against each pot, in thousands, counted ONE ROW PER
    /// SEAT over `coachRoles` / `scoutRoles`.
    let committedCoaching: Int
    let committedMedical: Int
    let committedScouting: Int

    /// False when the club's owner row could not be reached, i.e. every budget
    /// figure here is a zero rather than a number. Callers hide the money
    /// entirely in that state; nobody prints a fabricated envelope.
    let isResolved: Bool

    /// The career's own role, kept so the required-seat list can be answered
    /// without the caller re-deriving it.
    let careerRole: CareerRole

    // MARK: - Init

    /// - Parameters:
    ///   - careerRole: decides whether the head-coach chair is a seat at all.
    ///   - coaches: the club's coaching rows (already scoped to this save).
    ///   - scouts: the club's scouting rows.
    ///   - owner: the club's owner, for the three envelopes.
    init(careerRole: CareerRole, coaches: [Coach], scouts: [Scout], owner: Owner?) {
        self.careerRole = careerRole
        self.coachRoles = StaffSlots.coachRoles(for: careerRole)
        self.scoutRoles = StaffSlots.scoutRoles

        let ownedCoachSeats = Set(coachRoles)
        let ownedScoutSeats = Set(scoutRoles)

        // One occupant per seat. A second row for a seat the club already fills
        // is a data artefact, not a second salary; a row for a seat this career
        // does not own (the GM+HC's own head-coach chair) is not charged at all,
        // because it is not in any denominator either. Where duplicates exist
        // the dearer man wins, so the pot is never understated.
        var coachBySeat: [CoachRole: Coach] = [:]
        for coach in coaches where ownedCoachSeats.contains(coach.role) {
            if let sitting = coachBySeat[coach.role], sitting.salary >= coach.salary { continue }
            coachBySeat[coach.role] = coach
        }
        var scoutBySeat: [ScoutRole: Scout] = [:]
        for scout in scouts where ownedScoutSeats.contains(scout.scoutRole) {
            if let sitting = scoutBySeat[scout.scoutRole], sitting.salary >= scout.salary { continue }
            scoutBySeat[scout.scoutRole] = scout
        }

        self.filledCoachRoles = Set(coachBySeat.keys)
        self.filledScoutRoles = Set(scoutBySeat.keys)

        self.committedCoaching = coachBySeat.values
            .filter { !Self.medicalRoles.contains($0.role) }
            .reduce(0) { $0 + $1.salary }
        self.committedMedical = coachBySeat.values
            .filter { Self.medicalRoles.contains($0.role) }
            .reduce(0) { $0 + $1.salary }
        self.committedScouting = scoutBySeat.values.reduce(0) { $0 + $1.salary }

        self.isResolved = owner != nil
        self.coachingBudget = owner?.coachingBudget ?? 0
        self.medicalBudget = owner?.medicalBudget ?? 0
        self.scoutingBudget = owner?.scoutingBudget ?? 0
    }

    // MARK: - Seats

    var totalCoachSlots: Int { coachRoles.count }
    var totalScoutSlots: Int { scoutRoles.count }
    var totalSlots: Int { totalCoachSlots + totalScoutSlots }

    var filledCoachSlots: Int { filledCoachRoles.count }
    var filledScoutSlots: Int { filledScoutRoles.count }
    var filledSlots: Int { filledCoachSlots + filledScoutSlots }

    var isFullyStaffed: Bool { filledSlots >= totalSlots }

    /// Open coaching seats, in the enum's own order.
    var vacantCoachRoles: [CoachRole] { coachRoles.filter { !filledCoachRoles.contains($0) } }
    /// Open scouting seats, in the enum's own order.
    var vacantScoutRoles: [ScoutRole] { scoutRoles.filter { !filledScoutRoles.contains($0) } }

    // MARK: - Required seats (the staff-completeness gate)

    /// Seats a club must fill before the calendar is allowed to leave Coaching
    /// Changes. A GM+HC career already occupies the head-coach chair.
    ///
    /// #158: this was written out a third time inside the Staff screen and a
    /// fourth inside the review sheet, and the calendar sidebar consulted
    /// neither — so its button offered an advance the real path then argued
    /// with. One list.
    var requiredCoachRoles: [CoachRole] {
        careerRole == .gmAndHeadCoach
            ? [.offensiveCoordinator, .defensiveCoordinator]
            : [.headCoach, .offensiveCoordinator, .defensiveCoordinator]
    }

    var missingRequiredRoles: [CoachRole] {
        requiredCoachRoles.filter { !filledCoachRoles.contains($0) }
    }

    var allRequiredRolesFilled: Bool { missingRequiredRoles.isEmpty }

    // MARK: - The first scout (the zero-scout gate)

    /// The DEAREST asking price the hire sheet can roll for a scout seat, in
    /// thousands — the top of the band `CoachingEngine.generateScoutCandidates`
    /// draws its salaries from (chief 650-2000, everyone else 150-1000).
    ///
    /// The ceiling and not the floor, deliberately. Salaries are rolled per
    /// pool, so "the pot covers the cheapest man the band allows" is a hope,
    /// not a guarantee: a twenty-man pool can easily open at $190K. The pot
    /// covering the DEAREST man the band allows is a guarantee — every
    /// candidate the sheet can offer for that seat is then signable, and
    /// `HireScoutView` refuses a hire above the remaining budget outright
    /// (`guard candidate.salary <= remainingBudget`), which is the exact edge a
    /// hard gate strands a career on.
    static func dearestScoutAsk(for role: ScoutRole) -> Int {
        role.isChief ? 2_000 : 1_000
    }

    /// The cheapest vacant scouting seat this club is CERTAIN to be able to
    /// fill out of what is left in the scouting pot, or `nil` when no such
    /// certainty exists.
    ///
    /// `remainingScouting` is the same figure the Staff screen hands
    /// `HireScoutView` as its ceiling (`ledger.remainingScouting`), so a seat
    /// named here can always be filled from that sheet — and filling it inside
    /// the remaining pot cannot create an overage, so clearing this gate cannot
    /// raise the one below it.
    var guaranteedAffordableScoutSeat: ScoutRole? {
        guard isResolved else { return nil }
        return vacantScoutRoles
            .filter { remainingScouting >= Self.dearestScoutAsk(for: $0) }
            .min { Self.dearestScoutAsk(for: $0) < Self.dearestScoutAsk(for: $1) }
    }

    /// True when the club is about to walk into draft prep with nobody scouting
    /// it AND can demonstrably do something about it. Both halves matter — see
    /// `advanceBlocker`.
    var isBlockedOnFirstScout: Bool {
        filledScoutSlots == 0 && guaranteedAffordableScoutSeat != nil
    }

    // MARK: - Money

    var remainingCoaching: Int { coachingBudget - committedCoaching }
    var remainingMedical: Int { medicalBudget - committedMedical }
    var remainingScouting: Int { scoutingBudget - committedScouting }

    /// Total staff salary across all three pots.
    var committedTotal: Int { committedCoaching + committedMedical + committedScouting }

    /// How far every pot is over its envelope, summed. Zero when the books are
    /// legal — or when no owner has resolved, because an unknown envelope is
    /// not an overspend.
    var overage: Int {
        guard isResolved else { return 0 }
        return max(0, -remainingCoaching) + max(0, -remainingMedical) + max(0, -remainingScouting)
    }

    var isOverspent: Bool { overage > 0 }

    // MARK: - Advance gate

    /// The staff reason this phase cannot be left, or `nil` when staff are not
    /// what is holding it.
    ///
    /// #158: the ONE predicate. `CareerDashboardView` gates its advance button
    /// on it, `CalendarSidebarView` gates its own on the same value, and
    /// `CareerShellView.performShellAdvance` refuses on it — so the sidebar can
    /// no longer offer a week the shell will decline, and the blocked-state copy
    /// names the actual reason instead of counting tasks that are all ticked.
    func advanceBlocker(phase: SeasonPhase) -> AdvanceBlocker? {
        guard phase == .coachingChanges else { return nil }

        if !missingRequiredRoles.isEmpty {
            let names = missingRequiredRoles.map(\.displayName).joined(separator: ", ")
            return AdvanceBlocker(
                title: "Fill your required staff first",
                detail: "\(names) \(missingRequiredRoles.count == 1 ? "is" : "are") still vacant. "
                    + "Hire from the Staff screen to advance."
            )
        }

        if isOverspent {
            return AdvanceBlocker(
                title: "Resolve staff budget overage first",
                detail: "You are \(StaffLedger.money(overage)) over the staff budget. "
                    + "Release staff or reduce salaries to advance."
            )
        }

        // The draft-prep pipeline behind this phase — the Big Board, film
        // study, pro days, the combine trip — is screen after screen that needs
        // a scout, and a career could walk the whole way through it with an
        // empty scouting department. It is asked LAST of the three because
        // the remedy is a hire, and a club that is over its budget or short a
        // coordinator has a cheaper thing to fix first.
        //
        // The condition is not "no scouts": it is "no scouts, and a seat this
        // club can certainly fill". A gate with no clearing move is a stranded
        // career, and this repo already paid for that lesson once — the
        // combine-trip task had to be de-required because a club that had spent
        // its scouting pot on salaries could not afford the flight, leaving a
        // red Required chip no action in the app could clear. So when the pot
        // cannot guarantee a signing, the calendar moves and the hub's
        // zero-scout empty states are what say so.
        if filledScoutSlots == 0, let seat = guaranteedAffordableScoutSeat {
            return AdvanceBlocker(
                title: "Hire your first scout",
                detail: "Nobody is scouting the draft class. \(seat.displayName) can be signed out of the "
                    + "\(StaffLedger.money(remainingScouting)) left in your scouting budget — "
                    + "hire from the Staff screen to advance."
            )
        }

        return nil
    }

    // MARK: - Formatting

    /// Thousands as the money these screens quote. Shared so the blocker
    /// sentence and the banner beside it cannot round differently.
    static func money(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if abs(millions) >= 1.0 { return String(format: "$%.1fM", millions) }
        return "$\(thousands)K"
    }
}
