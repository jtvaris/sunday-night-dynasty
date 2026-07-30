import Foundation
import SwiftData

/// Handles coach XP accumulation, attribute growth, aging, retirement, and potential.
enum CoachDevelopmentEngine {

    // MARK: - Potential Generation

    /// Generate potential for a new coach based on age bracket.
    static func generatePotential(forAge age: Int) -> Int {
        var rng = SystemRandomNumberGenerator()
        return generatePotential(forAge: age, using: &rng)
    }

    /// Seeded variant of `generatePotential(forAge:)` — same bands, caller-owned
    /// entropy, so the fixed-league template import produces the same staff on
    /// every run.
    static func generatePotential<G: RandomNumberGenerator>(forAge age: Int, using rng: inout G) -> Int {
        switch age {
        case ...30:   return Int.random(in: 40...99, using: &rng)
        case 31...40: return Int.random(in: 45...90, using: &rng)
        case 41...50: return Int.random(in: 50...80, using: &rng)
        case 51...60: return Int.random(in: 40...70, using: &rng)
        default:      return Int.random(in: 30...60, using: &rng)
        }
    }

    // MARK: - Weekly XP

    /// Apply XP from a single game week.
    static func applyWeeklyXP(
        coach: Coach,
        didWin: Bool,
        isPlayoff: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    ) {
        var xp = 5  // Base weekly XP
        if didWin { xp += 3 }
        else { xp += 1 }
        if isPlayoff { xp += 8 }

        // HC mentoring multiplier (0.6x–1.5x) — PRIMARY LEVER
        let hcMultiplier: Double
        if let hc = headCoach, hc.id != coach.id {
            let leadership = Double(hc.motivation + hc.playerDevelopment) / 2.0
            hcMultiplier = 0.6 + (leadership - 30.0) / 60.0 * 0.9
        } else {
            hcMultiplier = 1.0  // HC doesn't mentor themselves
        }

        // AHC secondary bonus (0–20%)
        var ahcBonus = 0.0
        if let ahc = assistantHC, ahc.id != coach.id {
            ahcBonus = Double(ahc.playerDevelopment - 50) / 50.0 * 0.20
        }

        let totalMultiplier = max(0.3, hcMultiplier + ahcBonus)
        coach.currentXP += Int(Double(xp) * totalMultiplier)
    }

    // MARK: - Seasonal Development

    /// End-of-season: convert XP to attribute growth, apply aging, check retirement.
    static func applySeasonalDevelopment(
        coach: Coach,
        teamWins: Int,
        madePlayoffs: Bool,
        wonSuperBowl: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    ) {
        // 1. Add seasonal XP bonuses
        var seasonXP = 20  // Base
        if teamWins >= 9 { seasonXP += 15 }
        if madePlayoffs { seasonXP += 20 }
        if teamWins >= 12 { seasonXP += 30 }  // Conference championship caliber
        if wonSuperBowl { seasonXP += 60 }

        // HC multiplier on seasonal XP too
        let hcMult: Double
        if let hc = headCoach, hc.id != coach.id {
            let leadership = Double(hc.motivation + hc.playerDevelopment) / 2.0
            hcMult = 0.6 + (leadership - 30.0) / 60.0 * 0.9
        } else {
            hcMult = 1.0
        }
        coach.currentXP += Int(Double(seasonXP) * hcMult)

        // 2. Convert accumulated XP to attribute growth
        convertXPToGrowth(coach: coach)

        // 3. Age-based decline
        applyAgingDecline(coach: coach)

        // 4. Age the coach
        coach.age += 1
        coach.yearsExperience += 1

        // 5. Reputation based on wins (keep existing logic)
        applyReputationChange(coach: coach, teamWins: teamWins)

        // 6. Clear the adjustment period — UNCONDITIONALLY, every offseason
        //    pass, for every coach (rostered or not). This is the only site
        //    that clears `promotedInSeason`, so anything less than
        //    unconditional would let `isInAdjustmentPeriod` stick forever on a
        //    coach who never converts XP, and the -0.05 HC / -0.03 coordinator
        //    development penalties would become permanent
        //    (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.9.3).
        //
        //    Expiry is exactly one season by construction: the offseason runs
        //    this pass BEFORE the coaching carousel stamps this year's
        //    promotions (`WeekAdvancer`, `.coachingChanges`), so a coach hired
        //    or promoted in the carousel carries the flag through the upcoming
        //    season and loses it at the next offseason's pass.
        coach.promotedInSeason = nil

        // 7. Reset XP for next season
        coach.currentXP = 0
    }

    // MARK: - XP to Attribute Conversion

    private static func convertXPToGrowth(coach: Coach) {
        let ceiling = coach.attributeCeiling
        var remainingXP = coach.currentXP
        let focusAttrs = coach.role.focusAttributes

        // All 12 attribute names
        let allAttrs = [
            "playCalling", "playerDevelopment", "reputation", "adaptability",
            "gamePlanning", "scoutingAbility", "recruiting", "motivation",
            "discipline", "mediaHandling", "contractNegotiation", "moraleInfluence"
        ]

        // Build weighted pool: focus attributes get 2x weight
        var pool: [String] = []
        for attr in allAttrs {
            pool.append(attr)
            if focusAttrs.contains(attr) {
                pool.append(attr)  // Double weight
            }
        }

        // Attempt to spend XP on random attributes
        var attempts = 0
        while remainingXP > 0 && attempts < 20 {
            attempts += 1
            let attr = pool.randomElement()!
            let currentValue = coach.attributeValue(named: attr)

            guard currentValue < ceiling else { continue }

            let cost = 25 + Int(Double(currentValue) * 0.5)
            guard remainingXP >= cost else { break }

            remainingXP -= cost
            coach.setAttributeValue(named: attr, value: min(ceiling, currentValue + 1))
        }
    }

    // MARK: - Aging Decline

    static func applyAgingDecline(coach: Coach) {
        let age = coach.age
        guard age >= 50 else { return }

        let declineChance: Double
        let maxDecline: Int
        switch age {
        case 50...55: declineChance = 0.10; maxDecline = 1
        case 56...60: declineChance = 0.25; maxDecline = 2
        case 61...65: declineChance = 0.40; maxDecline = 2
        default:      declineChance = 0.60; maxDecline = 3
        }

        if Double.random(in: 0...1) < declineChance {
            let decline = Int.random(in: 1...maxDecline)
            coach.adaptability = max(1, coach.adaptability - decline)
            if age >= 56 {
                coach.playCalling = max(1, coach.playCalling - Int.random(in: 0...1))
            }
            if age >= 61 {
                coach.gamePlanning = max(1, coach.gamePlanning - Int.random(in: 0...1))
            }
        }
    }

    // MARK: - Retirement

    static func shouldRetire(coach: Coach) -> Bool {
        guard coach.age >= 65 else { return false }
        let baseChance = Double(coach.age - 64) * 0.15
        let reputationModifier = coach.reputation >= 80 ? 0.5 : 1.0
        return Double.random(in: 0...1) < (baseChance * reputationModifier)
    }

    // MARK: - Reputation

    private static func applyReputationChange(coach: Coach, teamWins: Int) {
        let change: Int
        switch teamWins {
        case 14...17: change = Int.random(in: 3...6)
        case 11...13: change = Int.random(in: 1...3)
        case 8...10:  change = Int.random(in: -1...1)
        case 5...7:   change = Int.random(in: -3...(-1))
        default:      change = Int.random(in: -6...(-3))
        }
        coach.reputation = min(99, max(1, coach.reputation + change))
    }

    // MARK: - Mentor Assignment

    static func setMentor(coach: Coach, headCoach: Coach?, teamName: String, season: Int) {
        guard let hc = headCoach, hc.id != coach.id else { return }
        if coach.mentorCoachID == nil {
            coach.mentorCoachID = hc.id
            coach.mentorshipOrigin = "\(season) \(teamName)"
        }
    }
}

// MARK: - Developer Reputation (TODO §5.7)

/// A coach's reputation as a DEVELOPER, as distinct from `Coach.reputation`,
/// which is a win-loss reputation and nothing else (`applyReputationChange`
/// moves it purely on the team's record). A 5-12 season under a staff that
/// turned three rookies into starters is a good year for a developer and a bad
/// one for `reputation` — the game had no way to say so, which is why free
/// agents could not care about it and coach cards could not show it.
///
/// ## The measurement
///
/// The only ground truth for "did players get better here" is
/// `PlayerSeasonHistory`: one row per player per completed season, carrying
/// `overallAtEndOfSeason` and the team he finished on. A player who was on the
/// same team in consecutive seasons contributes the difference between the two
/// snapshots to that team's ledger for the later season.
///
/// Two deliberate restrictions keep the number meaning what it says:
///
/// - **Same team both seasons.** A player who arrived in March did not develop
///   under this staff last year, so his gain is not theirs to claim.
/// - **Development-age only** (`developmentAgeCeiling`). Past that age the
///   overall curve is dominated by decline that no position coach causes, so
///   including it would rank every staff by the average age of its roster
///   instead of by its coaching.
///
/// ## Blending with attributes
///
/// A brand-new league has no completed seasons, so a pure track record would
/// rate all 32 staffs identically at zero — and a coach's FIRST job would be
/// decided by a coin flip. The score therefore starts from the coach's
/// development attributes and shifts toward the measured record as seasons
/// accumulate (`measuredWeightPerSeason`, capped at
/// `maxMeasuredWeight`): reputation is a promise early and a record later.
extension CoachDevelopmentEngine {

    /// Oldest a player can be at season's end and still count as "developed".
    static let developmentAgeCeiling = 27

    /// Completed seasons the record looks back over.
    static let developerWindowSeasons = 5

    /// How much of the score the measured record claims per season on the job.
    private static let measuredWeightPerSeason = 0.22

    /// Ceiling on that claim — the attributes never stop mattering entirely,
    /// because a staff is re-hired and re-shuffled constantly and the ledger is
    /// per TEAM, not per person.
    private static let maxMeasuredWeight = 0.65

    // MARK: - Types

    /// One team-season of development outcomes.
    struct SeasonDevelopment: Equatable {
        /// Player-seasons that could be compared against the prior year.
        var evaluated: Int = 0
        /// Of those, how many gained at least one overall point.
        var improved: Int = 0
        /// Sum of the overall deltas (negative when the young core regressed).
        var netDelta: Int = 0
    }

    /// A coach's developer track record over his tenure, plus the 1-99 score
    /// the UI and the free-agency multiplier read.
    struct DeveloperRecord: Equatable {
        /// Completed seasons of this coach's tenure that could be measured.
        let seasonsMeasured: Int
        let playersEvaluated: Int
        let playersImproved: Int
        let netOverallGained: Int
        /// 1-99. Blends the coach's development attributes with the measured
        /// record; see the type note for the blend.
        let score: Int

        /// True once at least one completed season under this coach has been
        /// measured — i.e. the score is a record and not just a projection.
        var isMeasured: Bool { seasonsMeasured > 0 && playersEvaluated > 0 }

        /// Average overall gained per young player-season.
        var averageGain: Double {
            playersEvaluated > 0 ? Double(netOverallGained) / Double(playersEvaluated) : 0
        }

        /// Share of measured young players who improved (0-1).
        var improvementRate: Double {
            playersEvaluated > 0 ? Double(playersImproved) / Double(playersEvaluated) : 0
        }

        var tier: String {
            switch score {
            case 85...:  return "Elite Developer"
            case 72..<85: return "Strong Developer"
            case 58..<72: return "Solid Developer"
            case 45..<58: return "Average Developer"
            case 32..<45: return "Weak Developer"
            default:      return "Poor Developer"
            }
        }

        /// One line for a coach card: what the number is built on.
        var detail: String {
            guard isMeasured else { return "Projected — no completed season yet" }
            let gain = String(format: "%+.1f", averageGain)
            return "\(playersImproved)/\(playersEvaluated) young players improved · \(gain) OVR avg"
        }
    }

    // MARK: - Pure measurement

    /// Per-team, per-season development ledger derived from season snapshots.
    /// PURE: no fetches, no globals — hand it the rows and it counts.
    ///
    /// - Parameter history: `PlayerSeasonHistory` rows for ONE career, any
    ///   number of seasons. Rows without a team are ignored (a free agent
    ///   developed under nobody).
    static func developmentLedger(history: [PlayerSeasonHistory]) -> [UUID: [Int: SeasonDevelopment]] {
        var byPlayer: [UUID: [PlayerSeasonHistory]] = [:]
        for row in history {
            byPlayer[row.playerID, default: []].append(row)
        }

        var ledger: [UUID: [Int: SeasonDevelopment]] = [:]
        for (_, rows) in byPlayer {
            let seasons = rows.sorted { $0.season < $1.season }
            guard seasons.count >= 2 else { continue }
            for index in 1..<seasons.count {
                let previous = seasons[index - 1]
                let current = seasons[index]
                // Consecutive seasons only: a gap means a season nobody here
                // coached him through.
                guard current.season == previous.season + 1 else { continue }
                // Same staff both years, or the gain is not theirs.
                guard let teamID = current.teamID, previous.teamID == teamID else { continue }
                guard current.ageAtEndOfSeason <= developmentAgeCeiling else { continue }

                let delta = current.overallAtEndOfSeason - previous.overallAtEndOfSeason
                var entry = ledger[teamID]?[current.season] ?? SeasonDevelopment()
                entry.evaluated += 1
                if delta > 0 { entry.improved += 1 }
                entry.netDelta += delta
                ledger[teamID, default: [:]][current.season] = entry
            }
        }
        return ledger
    }

    /// Builds one coach's record from a pre-computed ledger. PURE.
    ///
    /// - Parameters:
    ///   - coach: The coach being rated.
    ///   - ledger: Output of ``developmentLedger(history:)``.
    ///   - currentSeason: The season in progress (its own year is not
    ///     measurable yet — nothing has been snapshotted for it).
    static func developerRecord(
        coach: Coach,
        ledger: [UUID: [Int: SeasonDevelopment]],
        currentSeason: Int
    ) -> DeveloperRecord {
        var totals = SeasonDevelopment()
        var seasons = 0

        if let teamID = coach.teamID, let byYear = ledger[teamID] {
            // Tenure window: from the hire (when known) but never further back
            // than the window, and never into the unfinished current season.
            let oldest = max(
                coach.hireSeasonYear > 0 ? coach.hireSeasonYear : currentSeason - developerWindowSeasons,
                currentSeason - developerWindowSeasons
            )
            for (season, entry) in byYear where season >= oldest && season < currentSeason {
                guard entry.evaluated > 0 else { continue }
                totals.evaluated += entry.evaluated
                totals.improved += entry.improved
                totals.netDelta += entry.netDelta
                seasons += 1
            }
        }

        return DeveloperRecord(
            seasonsMeasured: seasons,
            playersEvaluated: totals.evaluated,
            playersImproved: totals.improved,
            netOverallGained: totals.netDelta,
            score: score(coach: coach, totals: totals, seasons: seasons)
        )
    }

    /// The 1-99 blend. `+1.0` average OVR gained per young player-season is a
    /// genuinely good developer, `+2.0` is a factory, `-1.0` is a staff whose
    /// young players went backwards.
    private static func score(coach: Coach, totals: SeasonDevelopment, seasons: Int) -> Int {
        let attributeBaseline =
            0.55 * Double(coach.playerDevelopment)
            + 0.25 * Double(coach.motivation)
            + 0.20 * Double(coach.reputation)

        guard seasons > 0, totals.evaluated > 0 else {
            return clampScore(attributeBaseline)
        }

        let averageGain = Double(totals.netDelta) / Double(totals.evaluated)
        let measured = 50.0 + averageGain * 22.0
        let weight = min(maxMeasuredWeight, measuredWeightPerSeason * Double(seasons))
        return clampScore((1.0 - weight) * attributeBaseline + weight * measured)
    }

    private static func clampScore(_ value: Double) -> Int {
        min(99, max(1, Int(value.rounded())))
    }

    // MARK: - Context-driven convenience

    /// A coach's developer record, resolved off the row's own model context.
    ///
    /// The ledger is fetched and derived ONCE per (career, season) and memoised
    /// — the free-agency multiplier asks for it per signing decision, which
    /// would otherwise be a full `PlayerSeasonHistory` scan per free agent.
    /// The cache key carries the career id and the season, so a career switch
    /// or a rollover invalidates it without anyone having to remember to reset
    /// it (the cached value is plain numbers, never a live model reference).
    static func developerRecord(coach: Coach, currentSeason: Int? = nil) -> DeveloperRecord {
        guard let context = coach.modelContext, let careerID = coach.careerID else {
            return DeveloperRecord(
                seasonsMeasured: 0, playersEvaluated: 0, playersImproved: 0,
                netOverallGained: 0,
                score: score(coach: coach, totals: SeasonDevelopment(), seasons: 0)
            )
        }
        let season = currentSeason ?? resolveCurrentSeason(careerID: careerID, context: context)
        let ledger = cachedLedger(careerID: careerID, season: season, context: context)
        // The per-coach result is memoised too: free agency asks for the same
        // staff once per candidate, and re-walking the ledger for an answer
        // that cannot have changed is pure waste. The key is the complete input
        // set of the calculation, so a carousel move or an offseason attribute
        // bump invalidates the entry by construction rather than by hoping
        // somebody remembers to clear it.
        let coachKey = recordCacheKey(coach)
        if let cached = recordCache[coachKey] { return cached }
        let record = developerRecord(coach: coach, ledger: ledger, currentSeason: season)
        recordCache[coachKey] = record
        return record
    }

    /// The season the store believes is in progress for this coach's save, or
    /// `nil` when the row is not attached to one. Callers rating a whole staff
    /// should resolve it ONCE and thread it into `developerRecord`, rather than
    /// paying a `Career` lookup per coach.
    static func activeSeason(for coach: Coach) -> Int? {
        guard let context = coach.modelContext, let careerID = coach.careerID else { return nil }
        return resolveCurrentSeason(careerID: careerID, context: context)
    }

    private static var ledgerCacheKey: String?
    private static var ledgerCache: [UUID: [Int: SeasonDevelopment]] = [:]
    private static var recordCache: [String: DeveloperRecord] = [:]

    /// Every input `developerRecord` and `score` read, in one string. Anything
    /// that can move the answer moves the key.
    private static func recordCacheKey(_ coach: Coach) -> String {
        "\(coach.id.uuidString)|\(coach.teamID?.uuidString ?? "-")|\(coach.hireSeasonYear)"
            + "|\(coach.playerDevelopment)|\(coach.motivation)|\(coach.reputation)"
    }

    private static func cachedLedger(
        careerID: UUID,
        season: Int,
        context: ModelContext
    ) -> [UUID: [Int: SeasonDevelopment]] {
        let key = "\(careerID.uuidString)#\(season)"
        if ledgerCacheKey == key { return ledgerCache }

        // One season deeper than the window: a delta needs the PRIOR year's
        // snapshot, so the oldest measurable season needs the one before it in
        // the fetch or it silently drops out of the record.
        let floor = season - developerWindowSeasons - 2
        let descriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate<PlayerSeasonHistory> {
                $0.careerID == careerID && $0.season > floor && $0.season < season
            }
        )
        let history = (try? context.fetch(descriptor)) ?? []
        ledgerCache = developmentLedger(history: history)
        // Both caches live and die on the same key — a per-coach record derived
        // from the old ledger would outlive the ledger that produced it.
        recordCache = [:]
        ledgerCacheKey = key
        return ledgerCache
    }

    private static func resolveCurrentSeason(careerID: UUID, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Career>(
            predicate: #Predicate<Career> { $0.id == careerID }
        )
        return (try? context.fetch(descriptor))?.first?.currentSeason ?? 0
    }
}
