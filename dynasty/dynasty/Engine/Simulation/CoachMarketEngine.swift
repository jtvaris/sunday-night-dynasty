import Foundation

// MARK: - CoachMarketEngine (task #96)

/// The supply side of the coaching profession: who is available when a seat
/// opens, and when a man who cannot find a seat stops being available at all.
///
/// ## Why this exists
///
/// Before this engine the league had an inflow and no outflow. Three passes in
/// `WeekAdvancer.coachingChanges` detach coaches every offseason —
/// `CoachingEngine.checkCoordinatorPoaching` (every non-HC seat on all 32
/// staffs), `checkHCPromotionPoaching`, and Black Monday's firings — and all of
/// them express "left the team" as `teamID = nil`. Nothing then looked at those
/// rows again: `refillAIStaffVacancies` generated a brand-new coach for every
/// hole it found, so a poached receivers coach was replaced by an invented one
/// and joined a bench that only ever grew. Measured over two 8-season runs:
/// **575 → 1147 living coaches (+82/season)** against 512 seeded, while the only
/// exit door in the game — retirement at 65 — took ~17 a season. Every one of
/// those men holds a face reservation, so the 3 712-image catalog drained ~100
/// portraits a season and would have been empty around season 9-10.
///
/// ## The two halves of the fix
///
/// * `hireFromBench` — a vacancy is offered to the out-of-work first. This is
///   what makes poaching mean "hired away by another organization" (which is the
///   text the game already showed) instead of "evaporated".
/// * `settleUnemployment` — a man who cannot get back in eventually leaves the
///   profession, quickly if he is old or unknown, slowly if he is young and hot.
///
/// Both run once per offseason from `.coachingChanges`, in that order.
enum CoachMarketEngine {

    // MARK: - Availability

    /// Everyone who could take a job right now: unattached, not gone for good,
    /// and not so old that a club would rather hire someone with a future.
    ///
    /// The age ceiling matches the carousel's own recycling filters
    /// (`CoachCarouselEngine.runBlackMonday`), so a 64-year-old is not offered a
    /// coordinator seat by one pass and refused it by the next.
    static func availableBench(_ coaches: [Coach]) -> [Coach] {
        coaches.filter { $0.teamID == nil && !$0.isRetired && $0.age < 64 }
    }

    /// The best available man for `role`, or `nil` when the market has nobody
    /// plausible and the caller has to invent one.
    ///
    /// Ranking is by exact-title first, then by the role's `hiringFamilies`
    /// ladder, and inside a tier by overall rating. A club therefore always
    /// prefers a real receivers coach to a demoted coordinator, and prefers
    /// either to a stranger — but it does not wait forever: a seat whose ladder
    /// comes up empty falls through to a fresh hire on the same advance, which is
    /// what keeps every staff filled (the gate the smoke asserts).
    ///
    /// - Parameter excluding: ids already promised to another seat in this same
    ///   pass. The caller holds the bench array across many vacancies and the
    ///   store is not written until the end, so without this two teams would hire
    ///   the same man.
    static func hireFromBench(
        role: CoachRole,
        bench: [Coach],
        excluding taken: Set<UUID>
    ) -> Coach? {
        let pool = bench.filter { !taken.contains($0.id) }
        guard !pool.isEmpty else { return nil }

        if let exact = best(pool.filter { $0.role == role }) { return exact }
        for family in role.hiringFamilies {
            if let pick = best(pool.filter { $0.role.family == family }) { return pick }
        }
        return nil
    }

    /// Who a club takes out of a tier of the bench.
    ///
    /// Deliberately NOT `max(by: ovr)`. Recycling made the bench the league's
    /// main source of coaches — generation collapsed from ~37 a season to single
    /// digits — so whatever this function prefers, the league becomes. Strict
    /// max-OVR prefers the most experienced man in every tier for every seat, and
    /// experience here is a monotone function of age (`CoachDevelopmentEngine`
    /// converts XP every offseason and only starts decline at 50), so it is a
    /// ratchet: the oldest available man wins every hire, the young stay
    /// unemployed until attrition takes them, and the mean staff age climbs
    /// season on season with no counter-force until a 65+ retirement boom.
    ///
    /// Two things break the ratchet:
    ///
    /// * a late-career discount — a 58-year-old position coach and a 40-year-old
    ///   of the same rating are not the same hire, and clubs know it;
    /// * a shortlist rather than a winner. The carousel already models a hiring
    ///   decision this way (`CoachCarouselEngine`: `pool.prefix(3).randomElement()`),
    ///   and it is the honest shape — a search that ends in an interview, not in
    ///   a sort.
    private static func best(_ candidates: [Coach]) -> Coach? {
        guard !candidates.isEmpty else { return nil }
        let ranked = candidates
            .map { (coach: $0, score: hiringScore($0)) }
            .sorted { $0.score > $1.score }
        return ranked.prefix(3).randomElement()?.coach
    }

    /// Overall rating, discounted for how little of a career is left.
    ///
    /// The steps line up with the two age gates the rest of the system already
    /// uses: 64 is the bench's own ceiling (`availableBench`) and 65 is where
    /// `CoachDevelopmentEngine.shouldRetire` starts rolling, so a man at 60 is
    /// being hired for two or three more seasons and is priced accordingly.
    static func hiringScore(_ coach: Coach) -> Double {
        let ovr = Double(CoachingEngine.coachOverallRating(coach))
        let agePenalty: Double
        switch coach.age {
        case 60...: agePenalty = 6
        case 55...: agePenalty = 3
        case 50...: agePenalty = 1
        default:    agePenalty = 0
        }
        return ovr - agePenalty
    }

    // MARK: - Attrition

    /// Odds a coach who has now spent `years` consecutive offseasons out of work
    /// gives up on the league this year.
    ///
    /// Shape: one year out is normal (a tenth leave), two is a warning, and by
    /// four nearly everyone has taken the college job, the booth, or the front
    /// office. Age accelerates it — a 60-year-old position coach nobody called
    /// back is done — and reputation slows it, because a hot young name can sit
    /// out a cycle and still be wanted.
    static func attritionChance(age: Int, reputation: Int, years: Int) -> Double {
        let base: Double
        switch years {
        case ...0:  return 0
        case 1:     base = 0.10
        case 2:     base = 0.35
        case 3:     base = 0.60
        default:    base = 0.85
        }

        let ageFactor: Double
        switch age {
        case 60...: ageFactor = 1.7
        case 55...: ageFactor = 1.3
        case 45...: ageFactor = 1.0
        case 35...: ageFactor = 0.8
        default:    ageFactor = 0.6
        }

        let reputationFactor: Double
        switch reputation {
        case 80...: reputationFactor = 0.45
        case 70...: reputationFactor = 0.70
        case 55...: reputationFactor = 0.90
        default:    reputationFactor = 1.0
        }

        return min(0.95, base * ageFactor * reputationFactor)
    }

    /// One season's bookkeeping on the unemployed bench. Call ONCE per offseason,
    /// after every hiring pass has run, so a man hired this cycle is counted as
    /// employed and not charged a year out of work.
    ///
    /// Employed coaches reset to zero. Everyone else ages a year on the bench and
    /// rolls against `attritionChance`; whoever fails leaves the profession for
    /// good.
    ///
    /// ## Face reclamation, and why deleting the row would be wrong
    ///
    /// A departure releases the portrait back to `FaceLibrary` — that is the
    /// whole point of the task — but the ROW STAYS, exactly as retirement has
    /// always handled it. Three persisted surfaces can still show a coach who is
    /// no longer employed anywhere, and they behave differently:
    ///
    /// * `CoachingTreeData` / `Career.coachCarouselLog` — name snapshots with no
    ///   portrait and no id back into `Coach`, so they are safe either way.
    /// * `LeagueEvent.coachID` → `EventAlertView.loadRelatedNames` — a live fetch
    ///   by id that reads `coach.faceID`. Deleting the row would blank an
    ///   archived event's subject; keeping it renders him exactly as before.
    ///
    /// So the rule is: **release the reservation, keep the row and its `faceID`.**
    /// The id may later be re-issued to a living person after its cooldown, which
    /// means a years-old news item can share a portrait with somebody current —
    /// the same trade retired players and 65+ retirements already make, and the
    /// reason `FaceLibrary.backfill` keys reclamation on `isRetired` rather than
    /// on `faceID == nil`.
    ///
    /// - Returns: the coaches who left the league this offseason.
    @discardableResult
    static func settleUnemployment(coaches: [Coach], season: Int) -> [Coach] {
        var departed: [Coach] = []

        for coach in coaches {
            guard !coach.isRetired else { continue }

            guard coach.teamID == nil else {
                coach.unemployedSeasons = 0
                continue
            }

            coach.unemployedSeasons += 1
            let chance = attritionChance(
                age: coach.age,
                reputation: coach.reputation,
                years: coach.unemployedSeasons
            )
            guard Double.random(in: 0...1) < chance else { continue }

            coach.isRetired = true
            coach.departureReason = "leftLeague"
            FaceLibrary.shared.releaseFace(coach.faceID, heldBy: coach.id)
            CoachChurnDiag.record(CoachChurnDiag.leftLeague)
            departed.append(coach)
        }

        return departed
    }
}

// MARK: - CoachChurnDiag

/// The coach-population counterpart of `ChurnDiag`: how many men entered and
/// left the profession this offseason, and through which door.
///
/// One line a season is enough to see the plateau task #96 is about — a healthy
/// league recycles far more seats than it invents, and `generated` should sit
/// near the number of seats no bench candidate existed for.
enum CoachChurnDiag {

    // MARK: - Doors

    /// A vacancy filled by an out-of-work coach (`CoachMarketEngine.hireFromBench`).
    static let recycled = "recycled"
    /// A vacancy that had to invent a coach — `CoachingEngine.generateCoachCandidates`
    /// out of `refillAIStaffVacancies` or the carousel's outside-hire fallbacks.
    static let generated = "generated"
    /// Detached from a staff this offseason (poaching, firing, retirement).
    static let detached = "detached"
    /// Left coaching at 65+ (`WeekAdvancer`'s retirement roll).
    static let retiredAge = "retiredAge"
    /// Left coaching after too long out of work (`settleUnemployment`).
    static let leftLeague = "leftLeague"

#if DEBUG

    private static let doorOrder = [recycled, generated, detached, retiredAge, leftLeague]

    /// Master switch. `record` is a no-op while this is false.
    static var isEnabled = false

    private static var counts: [String: Int] = [:]

    static func record(_ door: String, _ n: Int = 1) {
        guard isEnabled else { return }
        counts[door, default: 0] += n
    }

    /// One line per season, then clears the ledger.
    static func report(seasonLabel: Int) -> String? {
        guard isEnabled else { return nil }
        let parts = doorOrder.map { "\($0)=\(counts[$0] ?? 0)" }
        counts.removeAll(keepingCapacity: true)
        return "SMOKE: diag coachChurn season=\(seasonLabel) " + parts.joined(separator: " ")
    }

    static func reset() { counts.removeAll() }

#else

    @inline(__always) static func record(_ door: String, _ n: Int = 1) {}

#endif
}
