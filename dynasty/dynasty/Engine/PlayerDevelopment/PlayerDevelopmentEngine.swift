import Foundation

// MARK: - PlayerDevelopmentEngine

/// Stateless engine responsible for all player growth, regression, injuries, mentoring,
/// and offseason processing in Sunday Night Dynasty.
enum PlayerDevelopmentEngine {

    // MARK: - Development Ceiling (shared formula)

    /// Single source of truth for the attribute-development ceiling scaled
    /// from `truePotential` (1-99): `truePotential * 0.65 + 35`.
    /// A truePotential of 99 allows attributes up to 99; potential of 50
    /// caps around 67.
    ///
    /// Every development path (offseason growth here, the R26 weekly
    /// training-focus tick, and the camp `TrainingPlanEngine`) MUST use this
    /// helper so the formula cannot drift between copies.
    /// **Phase-2 recalibration (plan §5 stage 5).** The slope was 0.65 with a
    /// 35 intercept. Measured over the career harness that made the ceiling
    /// spread between a first-round and a seventh-round prospect ~13 OVR, which
    /// — with rookie entry levels now converged on a common ~59 (see
    /// `DraftEngine.rookieScaleFactors`) — put the round-1 vs round-3 hit-rate
    /// gap at 41 pp where `DRAFT_NFL_REFERENCE.md` §6 wants 27. Flattening the
    /// slope around the same pivot (`0.60·pot + 39` crosses `0.65·pot + 35` at
    /// pot 80, the league's typical intake ceiling) pulls the elite ceiling in
    /// by ~0.7 and lifts the day-3 ceiling by ~0.3, without moving the middle of
    /// the league at all.
    static func developmentCeiling(for player: Player) -> Int {
        Int(Double(player.truePotential) * 0.60 + 39.0)
    }

    // MARK: - 1. Offseason Development

    /// Develops a player's attributes during the offseason based on work ethic, coaching,
    /// playing time, age, and potential ceiling.
    ///
    /// - Parameters:
    ///   - player: The player to develop (mutated in place).
    ///   - coaches: The full coaching staff available to the player's team.
    ///   - playingTimeShare: 0.0-1.0 representing how much the player played last season.
    ///     Since phase 2 this is the REAL share derived from
    ///     `PlayerSeasonHistory` / the live games counters
    ///     (`realPlayingTimeShare(gamesStarted:gamesPlayed:positionCoach:)`),
    ///     not an OVR-based estimate.
    ///   - health: The §2.4 health gate — `1.0` healthy, `0.7` missed camp,
    ///     `0.4` rehabbed through the offseason / major (≥ 6 wk) injury.
    ///   - realizationBoost: `1.25` for a late-bloomer breakout cycle (§2.5),
    ///     `1.0` otherwise. The only path for R above its 1.45 clamp.
    ///   - environment: the team-level situation for this offseason (§2.9.2-3):
    ///     scheme install year and coordinator continuity. Defaults to the
    ///     neutral "nothing changed, nobody has tenure" case.
    ///
    /// The player's `motivationState` is read off the row — it is computed once
    /// per offseason, before this runs (see `assignMotivationState`).
    static func developPlayer(
        _ player: Player,
        coaches: [Coach],
        playingTimeShare: Double,
        health: Double = 1.0,
        realizationBoost: Double = 1.0,
        environment: TeamEnvironment = TeamEnvironment()
    ) {
        let peakRange = player.position.peakAgeRange

        // Players past their peak receive no development -- only regression (handled elsewhere).
        guard player.age <= peakRange.upperBound else { return }

        // --- Base development points ---
        // Work ethic: 0-3 pts (scaled from 1-99)
        let workEthicPts = Double(player.mental.workEthic - 1) / 98.0 * 3.0
        // Coachability: 0-2 pts
        let coachabilityPts = Double(player.mental.coachability - 1) / 98.0 * 2.0
        // Playing time: 0-3 pts
        let playingTimePts = min(1.0, max(0.0, playingTimeShare)) * 3.0

        var totalPoints = workEthicPts + coachabilityPts + playingTimePts

        // --- Coaching multiplier (4-layer hierarchy) ---
        // Find coaching chain for this player
        let hc = coaches.first { $0.role == .headCoach }
        let ahc = coaches.first { $0.role == .assistantHeadCoach }
        let coordinator = coaches.first { coach in
            (player.position.side == .offense && coach.role == .offensiveCoordinator) ||
            (player.position.side == .defense && coach.role == .defensiveCoordinator) ||
            (player.position.side == .specialTeams && coach.role == .specialTeamsCoordinator)
        }
        let positionCoach = coaches.first { coach in
            CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
        }

        let coachBonus = CoachingEngine.hierarchicalDevelopmentBonus(
            headCoach: hc,
            assistantHC: ahc,
            coordinator: coordinator,
            positionCoach: positionCoach,
            player: player,
            coordinatorContinuity: environment.continuity(for: player.position.side)
        )
        totalPoints *= coachBonus

        // --- Motivation & health (plan §2.4) ---
        // Deliberately `motivMult · health` and NOT the full R factor: the
        // point total above ALREADY contains work ethic and playing time, so
        // folding all of R in here would count both twice. R itself is applied
        // only where nothing else represents those inputs — the catch-up growth
        // below.
        let motivation = player.motivationState
        let clampedHealth = min(1.0, max(0.0, health))
        let cycleBoost = max(1.0, realizationBoost)
        // The late-bloomer boost lifts the WHOLE cycle, not just the catch-up
        // term. §2.5 targets the year 3-5 breakout, and the catch-up table is
        // zero from the fifth camp on — applying the boost only there would
        // leave the mechanic inert for exactly the players it exists for.
        totalPoints *= motivation.developmentMultiplier * clampedHealth * cycleBoost

        // --- Strength coach bonus ---
        // Adds 0.5-1.0 extra points toward physical attributes.
        let strengthCoach = coaches.first { $0.role == .strengthCoach }
        let strengthBonus: Double
        if let sc = strengthCoach {
            // Scale bonus based on coach's playerDevelopment attribute (50 is average).
            strengthBonus = 0.5 + (Double(sc.playerDevelopment) / 99.0) * 0.5
        } else {
            strengthBonus = 0.0
        }

        // --- Age factor ---
        let ageFactor: Double
        if player.age < peakRange.lowerBound {
            ageFactor = 1.0       // Full development before peak
        } else {
            ageFactor = 0.5       // Half development at peak
        }

        totalPoints *= ageFactor

        // --- Rookie accelerated development ---
        // Rookies start at 60-90% of true attributes (Phase 4 scaling) so they
        // have significant room to grow toward their ceiling in their first years.
        let rookieMultiplier: Double
        switch player.yearsPro {
        case 0:  rookieMultiplier = 2.5  // First offseason — massive college-to-NFL growth
        case 1:  rookieMultiplier = 1.8  // Second year leap
        case 2:  rookieMultiplier = 1.3  // Still improving
        default: rookieMultiplier = 1.0  // Normal rate
        }
        totalPoints *= rookieMultiplier

        // --- Boom/Bust year-1 roll ---
        // For rookies (yearsPro == 0), a "realization" roll can dramatically alter
        // their first-year trajectory — breakout stars or year-1 struggles.
        enum RookieOutcome { case breakout, struggle, normal }
        let rookieOutcome: RookieOutcome
        if player.yearsPro == 0 {
            let roll = Double.random(in: 0.0..<1.0)
            if roll < 0.05 {
                rookieOutcome = .breakout
            } else if roll < 0.10 {
                rookieOutcome = .struggle
            } else {
                rookieOutcome = .normal
            }
        } else {
            rookieOutcome = .normal
        }

        switch rookieOutcome {
        case .breakout:
            // BREAKOUT — triple all development gains; player is immediately impactful
            totalPoints *= 3.0
        case .struggle:
            // STRUGGLE — zero development this offseason, -2 to all mental attributes
            totalPoints = 0
            let mentalPaths: [WritableKeyPath<MentalAttributes, Int>] = [
                \.awareness, \.decisionMaking, \.clutch, \.workEthic, \.coachability, \.leadership
            ]
            for kp in mentalPaths {
                player.mental[keyPath: kp] = max(1, player.mental[keyPath: kp] - 2)
            }
        case .normal:
            break
        }

        // --- Potential ceiling ---
        // Attribute ceiling scaled from truePotential (1-99); shared formula.
        let ceiling = developmentCeiling(for: player)

        // --- Distribute points across attributes ---
        // Young players: physical develops faster. Older players: mental develops faster.
        let physicalWeight: Double
        let mentalWeight: Double
        if player.age < peakRange.lowerBound {
            physicalWeight = 0.65
            mentalWeight = 0.35
        } else {
            physicalWeight = 0.35
            mentalWeight = 0.65
        }

        let physicalPoints = Int((totalPoints * physicalWeight + strengthBonus).rounded())
        let mentalPoints = Int((totalPoints * mentalWeight).rounded())

        // Distribute physical points randomly across physical attributes.
        distributePhysicalPoints(player: player, points: physicalPoints, ceiling: ceiling)

        // Distribute mental points randomly across mental attributes.
        distributeMentalPoints(player: player, points: mentalPoints, ceiling: ceiling)

        // --- Young-player catch-up growth (league OVR-drift calibration) ---
        // Rookies convert at 60-90 % of their college attributes, but the
        // point distribution above only ever touches physical/mental —
        // position skills (50 % of OVR) stayed frozen at the scaled-down
        // entry level. Measured result (R32 multi-season verify): draft
        // classes entered ~12 OVR below the veterans they replaced, matured
        // only ~+1 OVR/season, and the league decayed ~0.5 OVR/season.
        // Fix: for their first offseasons young players close a fraction of
        // the gap between each position skill / mental attribute and the
        // shared development ceiling — self-limiting (gap shrinks, ceiling
        // caps), stronger for better coaching, zero for a struggle-rookie.
        if rookieOutcome != .struggle {
            // NOTE: processOffseason ages players BEFORE developPlayer, so a
            // player in his first pro camp arrives here with yearsPro == 1 —
            // the table therefore covers yearsPro 1-4 (first four camps);
            // case 0 only guards direct un-aged call paths.
            // Calibration iteration 2 (measured): with the prospect-potential
            // lift in place (intake avgPot ≈ 70, leaguePot stable ≈ 75) the
            // original fractions 0.25/0.18/0.12/0.08 INFLATED the league
            // +1.6 OVR in 4 seasons — higher ceilings made the same fraction
            // worth more points. Trimmed ~25 % to hold 5-season drift in
            // |Δ| ≤ 1.5 while young classes still mature into starters.
            //
            // Calibration iteration 3 (draft-class overhaul, plan §7): the new
            // generator changes BOTH ends of the gap this fraction closes.
            // Intake potential rose 70 → ~79.5 (slot-correlated ceilings) so the
            // ceiling is ~6 higher, while readiness-driven conversion lands
            // rookies ~4 OVR *higher* than the pick-scaled ones this table was
            // tuned against (entry gap to the league shrank 12 → 8). Same
            // fraction, bigger ceiling: measured 3-season drift +2.36 vs the
            // |Δ| ≤ 1.5 gate. Trimmed ~50 % to hold it.
            //
            // Calibration iteration 4 (phase 2, plan §2.4 — closes skipped
            // finding #11): the blanket halving above was a LEAGUE-level fix
            // paid for by every individual young player, which is exactly the
            // realization gap the model is supposed to express. The ORIGINAL
            // 0.19/0.13/0.09/0.06 table is restored and each player instead
            // gets the share his own factors merit, through R (below). The
            // league mean of R is ≈ 0.50 by construction, so the league-average
            // catch-up is unchanged — the 3-season drift gate is preserved —
            // while the spread (p10 ≈ 0.25 … p90 ≈ 0.95, driven starters to
            // 1.45) is what produces ascenders, plateauers and busts.
            //
            // Calibration iteration 5 (phase 2, plan §5 stage 5 — the `career`
            // harness). The restored table could not reproduce
            // `DRAFT_NFL_REFERENCE.md` §6 no matter how R was weighted, for two
            // measured reasons:
            //   • MAGNITUDE. Over a full 30-season league a second-round pick
            //     entered at 68.0 with a ceiling of 92.3 and peaked at 74.1 —
            //     he closed 25 % of his gap across an ENTIRE CAREER. Hit rates
            //     came out R1 98 % / R3 7 % / R5-UDFA 0 % against the
            //     reference's 60/33/18/4: a cliff, not a curve.
            //   • WINDOW. The table zeroed after the fourth camp, i.e. at ~26,
            //     for every position. `DEVELOPMENT_NFL_REFERENCE.md` §1 puts
            //     the growth years at 22-25 for speed positions and 22-27 for
            //     QBs, with peak windows running to 31-35 — so position skills
            //     froze years before the body did, and NOBODY reached 90 OVR
            //     (league 90+ share measured 0.2 % against the §8 target of
            //     1-2 %).
            // The table is therefore front-loaded harder and given a small
            // prime-years tail. It is NOT a league-wide inflation: R still
            // multiplies it, and R's league mean is ~0.5, so the median player
            // closes about half his gap over a career while a driven,
            // high-work-ethic starter closes ~85 % and a discouraged backup
            // ~30 %. That spread IS the trajectory mix (§2.5) — measured
            // afterwards at R1 60 % / R3 33 % / R7 10 % / UDFA 4 % hit rates
            // with the §8 quality pyramid intact.
            //
            // Calibration iteration 6 (phase 2, plan §5 stage 6 — the league
            // equilibrium gates). Stage 5's flat 0.19 prime-years tail ran for
            // every player at every age up to `peakRange.upperBound`, i.e. for
            // six to ten further camps. Measured over `MultiSeasonSmokeTest`
            // that made the two veteran cohorts CLIMB — yp4-7 72.2 → 76.3 and
            // yp8+ 72.2 → 74.7 in three seasons — which carried the league mean
            // +3.65 against the |Δ| ≤ 1.5 gate and hollowed out the bottom of
            // the pyramid entirely (sub-65 share 19.5 % → 0.1 %, against
            // `DEVELOPMENT_NFL_REFERENCE.md` §8's ~25 %). It also contradicted
            // the reference it was justified by: §1 puts the growth years
            // BEFORE the peak window and then says "plateau". The tail is
            // therefore scoped to the growth years — full strength while a
            // player is still climbing into his position's window (which keeps
            // the late-developing profiles, QB/OT/TE, growing into their late
            // twenties exactly as §1 describes), a token amount inside it.
            //
            // The window runs two years INTO `peakAgeRange` rather than
            // stopping at its opening: cutting it dead at `lowerBound` moved
            // every position's modal peak age to `lowerBound - 1` (career
            // harness 6.4a failed on QB/K/P at mode 27) and collapsed the elite
            // share to R1 8.5 % — the last stretch from ~85 to 90+ is exactly
            // what a first-rounder covers in his mid-twenties. Two years in,
            // the mode lands inside every position's window and the elite tail
            // survives, while the six-to-ten-camp veteran climb does not.
            //
            // Past that the tail is not merely small, it is MERIT-GATED
            // (`primeWindowDamper`): the reference's own trajectory mix (§2)
            // says the plateauer — "he is what he is" — is the most common
            // outcome, while the ascender keeps climbing toward his ceiling.
            // A flat in-window fraction models neither; it moves the whole
            // league at once, which is precisely what the smoke test measured
            // as drift.
            let catchUpFraction: Double
            switch player.yearsPro {
            case 0, 1: catchUpFraction = 0.70
            case 2:    catchUpFraction = 0.50
            case 3:    catchUpFraction = 0.35
            case 4:    catchUpFraction = 0.245
            default:
                // Prime-years tail: technique and processing keep closing the
                // gap until the body starts going. `developPlayer` has already
                // returned for anyone past `peakRange.upperBound`, so this only
                // ever runs inside the position's own growth/peak window.
                catchUpFraction = 0.19
            }
            if catchUpFraction > 0 {
                // Coaching quality sways the reps (±20 %; widened again in the
                // stage-5 pass — `DEVELOPMENT_NFL_REFERENCE.md` §5 puts the
                // position coach at the TOP of the direct-development hierarchy
                // and calls out visible "QB guru"/"OL whisperer" effects, so a
                // great room versus a bad one has to be worth more than a tenth
                // of a player's growth).
                let coachFactor = min(1.20, max(0.80, coachBonus))
                let realization = realizationFactor(
                    player: player,
                    motivation: motivation,
                    playingTimeShare: playingTimeShare,
                    health: clampedHealth
                ) * cycleBoost
                let deepInPrime = player.yearsPro >= 5
                    && player.age > peakRange.lowerBound + primeTailYears
                let damper = deepInPrime ? primeWindowDamper(realization) : 1.0
                applyCatchUpGrowth(
                    player: player,
                    fraction: catchUpFraction * realization * coachFactor * damper,
                    ceiling: ceiling
                )
            }
        }

        // --- Position Training (offseason = full intensity) ---
        if let trainingPos = player.trainingPosition, trainingPos != player.position {
            let posCoach = coaches.first { coach in
                CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: trainingPos)
            }
            let posGain = VersatilityDevelopmentEngine.trainPosition(
                player: player,
                targetPosition: trainingPos,
                positionCoach: posCoach,
                practiceIntensity: 1.0
            )
            let key = trainingPos.rawValue
            let current = player.positionFamiliarity[key] ?? 0
            let posCeiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
            player.positionFamiliarity[key] = min(posCeiling, current + posGain)
        }

        // --- Scheme Learning (offseason = full intensity) ---
        // An install year runs the camp at ×1.25 (plan §2.9.2): a staff putting
        // in a brand-new system spends the whole offseason on installs.
        let oc = coaches.first { $0.role == .offensiveCoordinator }
        let dc = coaches.first { $0.role == .defensiveCoordinator }
        let schemeIntensity = environment.schemeInstallMultiplier

        if let offScheme = oc?.offensiveScheme, player.position.side == .offense {
            let gain = VersatilityDevelopmentEngine.learnScheme(
                player: player,
                scheme: offScheme.rawValue,
                coordinator: oc,
                practiceIntensity: schemeIntensity
            )
            let current = player.schemeFamiliarity[offScheme.rawValue] ?? 0
            player.schemeFamiliarity[offScheme.rawValue] = min(100, current + gain)
        }

        if let defScheme = dc?.defensiveScheme, player.position.side == .defense {
            let gain = VersatilityDevelopmentEngine.learnScheme(
                player: player,
                scheme: defScheme.rawValue,
                coordinator: dc,
                practiceIntensity: schemeIntensity
            )
            let current = player.schemeFamiliarity[defScheme.rawValue] ?? 0
            player.schemeFamiliarity[defScheme.rawValue] = min(100, current + gain)
        }
    }

    // MARK: - 1b. The Realization Model (plan §2.3-§2.5)

    /// Everything the offseason pipeline needs to know about a player that
    /// cannot be read off the `Player` row itself.
    ///
    /// The engine stays a pure function of its arguments — the SwiftData
    /// fetches (`PlayerSeasonHistory`, `Team`, `Holdout`, playoff `Game` rows)
    /// live in `WeekAdvancer`, which builds one of these per player before
    /// entering the camp pipeline. Every field has a neutral default, so a
    /// caller that supplies nothing gets exactly the pre-phase-2 behaviour.
    struct OffseasonInputs {
        // --- Team situation (plan §2.3 triggers) ---

        /// Wins in the season that just finished. `nil` = unknown (brand-new
        /// league / legacy save) — the "team collapsed" trigger then abstains
        /// rather than reading a missing record as an 0-win disaster.
        var teamWins: Int? = nil

        /// The head coach's `motivation` rating, for the "coach lift" trigger.
        var headCoachMotivation: Int? = nil

        /// His team lost in the conference round or the Super Bowl. Team-wide
        /// edge (§2.3), amplified for the leaders in the room.
        var playoffHeartbreak: Bool = false

        // --- Last season's participation (plan §2.4 real playing time) ---

        var gamesStarted: Int = 0
        var gamesPlayed: Int = 0

        /// The season BEFORE last — the baseline the demotion trigger and the
        /// plateau proxy compare against.
        var previousGamesStarted: Int = 0
        var previousGamesPlayed: Int = 0

        // --- Career trend (plan §2.3 down year, §2.5 plateau) ---

        /// `overallAtEndOfSeason` of the season that just finished.
        var latestOverall: Int? = nil
        /// …of the season before that.
        var previousOverall: Int? = nil
        /// …and of the one before *that*, so a two-offseason gain is derivable
        /// without storing anything new on `Player` — which is why plan §2.5's
        /// optional `lastOffseasonOverallGain` field was NOT added.
        var overallTwoSeasonsAgo: Int? = nil

        // --- Environment (plan §2.5 late bloomer, §2.6 potential drift) ---

        /// 0.0-1.0 fit with the scheme his coordinator actually runs.
        var schemeFit: Double = 0.5

        /// He is on a different team than the one he finished last season with.
        var changedTeam: Bool = false

        /// His position coach was hired THIS offseason and is a good developer
        /// — the "OL whisperer arrives" late-bloomer trigger.
        var newPositionCoach: Bool = false

        // --- Health gate (plan §2.4) ---

        /// A holdout that was settled late enough to cost him camp reps.
        var missedCampFromHoldout: Bool = false

        /// He suffered a major (≥ 6 week) injury during the season just played.
        var majorInjuryLastSeason: Bool = false

        // --- Staff familiarity (plan §2.9.4 assessPotential) ---

        /// Consecutive completed seasons this player has spent with his current
        /// club, counted off `PlayerSeasonHistory`. Drives how much noise the
        /// coaching staff's potential assessment still carries.
        var yearsOnTeam: Int = 0
    }

    /// The team-level slice of the offseason environment (plan §2.9.2-3) —
    /// everything that is true for a whole roster rather than one player.
    ///
    /// Kept separate from `OffseasonInputs` (which is per player and built in
    /// its thousands) so a scheme install or a coordinator's tenure is computed
    /// once per club per offseason.
    struct TeamEnvironment {
        /// `learnScheme` practice intensity for this cycle: 1.25 during an
        /// install year, 1.0 otherwise.
        var schemeInstallMultiplier: Double = 1.0

        /// The offensive coordinator has 3+ seasons in the building and has not
        /// changed the scheme.
        var offensiveContinuity: Bool = false

        /// Same, for the defensive coordinator.
        var defensiveContinuity: Bool = false

        /// Continuity for the unit a position belongs to. Special teams has no
        /// scheme dictionary, so it never earns the bonus.
        func continuity(for side: PositionSide) -> Bool {
            switch side {
            case .offense:     return offensiveContinuity
            case .defense:     return defensiveContinuity
            case .specialTeams: return false
            }
        }
    }

    /// Weeks out that make an injury "major" for development purposes
    /// (`DEVELOPMENT_NFL_REFERENCE.md` §7: a season-ending injury costs that
    /// year's growth window).
    /// How far into a position's `peakAgeRange` the prime-years catch-up tail
    /// keeps running at full strength for EVERYONE (plan §5 stage 6 — see the
    /// table in `developPlayer`). Past it `primeWindowDamper` takes over and
    /// only the ascenders keep closing on their ceiling.
    ///
    /// Zero, because `DEVELOPMENT_NFL_REFERENCE.md` §1's growth years end
    /// exactly where each position's `peakAgeRange` opens (RB 21-23 → window
    /// 24, WR 22-25 → 26, QB 22-27 → 28) and §1 then says "plateau". Every year
    /// of grace here is a year in which the WHOLE league climbs: at 1 the
    /// smoke test's yp4-7 cohort — 46 % of all rostered players, sitting right
    /// in those ages — still gained +1.45 OVR a season. The elite tail that the
    /// grace period used to carry is now `primeWindowDamper`'s job, which
    /// carries it for the ascenders only.
    static let primeTailYears = 0

    /// R below which a player deep in his peak window stops closing his gap at
    /// all — the plateauer.
    static let primeDamperFloor = 0.35
    /// R at which he is back to the full prime-years tail — the ascender.
    static let primeDamperCeiling = 0.90

    /// How much of the prime-years catch-up tail a player still gets once he is
    /// more than `primeTailYears` into his position's peak window.
    ///
    /// `DEVELOPMENT_NFL_REFERENCE.md` §2 makes the plateauer the single most
    /// common career shape ("reaches a level by year 2-3 and stays there") and
    /// the ascender the one who keeps closing on his ceiling. A FLAT tail here
    /// gives both the same climb, which is a league-wide ratchet by
    /// construction: measured over `MultiSeasonSmokeTest` it dragged the yp4-7
    /// and yp8+ cohorts up ~1.5 OVR every season.
    ///
    /// So the tail is gated on the player's own realization factor: at the
    /// league-median R (~0.32) it is zero and he is what he is, and it ramps to
    /// full only for the driven, high-work-ethic starter whose R runs past 1.0.
    /// Nothing new is rolled — R is the same number the catch-up already
    /// multiplies by, so this is a square-law on merit, not a second die.
    static func primeWindowDamper(_ realization: Double) -> Double {
        let span = primeDamperCeiling - primeDamperFloor
        return min(1.0, max(0.0, (realization - primeDamperFloor) / span))
    }

    static let majorInjuryWeeks = 6

    // MARK: Real Playing Time (fixes plan §1.3 defect #6)

    /// The share of last season's snaps this player actually took, from the
    /// real per-player counters (`PlayerSeasonHistory` / the live tallies)
    /// instead of the retired OVR-based `estimatePlayingTimeShare`.
    ///
    /// Starts dominate (0.85) because a start means every meaningful snap;
    /// appearances carry the remaining 0.15. The floor is the practice-reps
    /// term from `DEVELOPMENT_NFL_REFERENCE.md` §6 — a player who never dresses
    /// still develops on the scout team, and a good position coach makes those
    /// reps count (±20 % on the floor).
    static func realPlayingTimeShare(
        gamesStarted: Int,
        gamesPlayed: Int,
        positionCoach: Coach?
    ) -> Double {
        let starts = Double(max(0, min(17, gamesStarted))) / 17.0
        let appearances = Double(max(0, min(17, gamesPlayed))) / 17.0
        let raw = min(1.0, starts * 0.85 + appearances * 0.15)

        let coachDev = Double(positionCoach?.playerDevelopment ?? 50)
        let floor = 0.15 * (0.8 + coachDev / 99.0 * 0.4)
        return min(1.0, max(floor, raw))
    }

    // MARK: Health Gate (plan §2.4)

    /// The health multiplier on this offseason's growth.
    ///
    /// `0.4` — he spent the growth window rehabbing (still injured at camp, or
    /// a major injury last season): reference §7 says a season-ending injury
    /// costs that year's development, not attributes.
    /// `0.7` — he reported late from a holdout and missed camp (reference §6:
    /// "rookies who miss camp start the season visibly behind").
    /// `1.0` — full offseason program.
    static func healthFactor(player: Player, inputs: OffseasonInputs) -> Double {
        if player.isInjured || inputs.majorInjuryLastSeason { return 0.4 }
        if inputs.missedCampFromHoldout { return 0.7 }
        return 1.0
    }

    // MARK: The R Factor (plan §2.4)

    /// Per-player, per-offseason **realization factor** — the single number
    /// that decides how much of a player's ceiling he actually closes this
    /// year. Never surfaced as a dice roll: it is a product of things the user
    /// can see and influence.
    ///
    /// ```
    /// base        = 0.20 + workEthic/99·0.50 + competitiveness/99·0.25 + learning/99·0.15
    /// opportunity = 0.55 + 0.45 · realPlayingTimeShare
    /// R           = clamp(base · motivMult · opportunity · health, 0.20, 1.45)
    /// ```
    ///
    /// **Calibration (plan §5 stage 5, `career` harness).** The plan's literal
    /// weights were `0.30 + 0.40/0.20/0.10`, sized against an assumed league
    /// mean of 0.50. Measured over a 30-season league they produced mean 0.66,
    /// p10 0.41, p90 0.96 — the level was 30 % hot AND the spread was too
    /// narrow, because a 0.30 intercept plus three attributes that all cluster
    /// near 65 leaves base varying only between ~0.58 and ~0.94. Simply scaling
    /// the whole thing down would have hit the mean target and missed
    /// `p90 ≥ 0.85`.
    ///
    /// The intercept is therefore cut and the attribute weights widened by the
    /// same amount, which keeps the documented `≈1.0` maximum and moves the
    /// league mean onto the plan's own 0.45-0.55 target *while widening the
    /// spread* — the thing that actually decides whether the trajectory mix
    /// (§2.5) and the draft-slot hit rates emerge. Work ethic keeps the
    /// dominant weight, exactly as `DEVELOPMENT_NFL_REFERENCE.md` §2 orders the
    /// differentiators.
    static func realizationFactor(
        player: Player,
        motivation: MotivationState,
        playingTimeShare: Double,
        health: Double
    ) -> Double {
        let base = 0.20
            + Double(player.mental.workEthic) / 99.0 * 0.50
            + Double(player.competitiveness) / 99.0 * 0.25
            + Double(player.learning) / 99.0 * 0.15

        // Opportunity is the FIRST differentiator `DEVELOPMENT_NFL_REFERENCE.md`
        // §2 lists, and it is the one the user actually controls through the
        // depth chart. The plan's `0.55 + 0.45·share` left a bench player at
        // 79 % of a starter's realization, which measured out as an R
        // distribution far too narrow to produce the §6 hit-rate curve (p90
        // 0.77 against the plan's own ≥ 0.85 target, and a four-camp
        // ceiling-closure spread of σ 0.13 where the draft-slot hit curve needs
        // σ ≈ 0.24). Widening the term to `0.20 + 0.80·share` keeps the
        // reference's "practice-reps floor, not zero" (§6) — a player who never
        // dresses still realizes a fifth of a starter's growth — while making
        // the R distribution properly bimodal: starters realize, backups tread
        // water. That IS the ascender/plateauer split §2 describes, and it is
        // the single biggest lever the user actually holds.
        let opportunity = 0.20 + 0.80 * min(1.0, max(0.0, playingTimeShare))
        let raw = base * motivation.developmentMultiplier * opportunity * health
        return min(realizationCeiling, max(realizationFloor, raw))
    }

    /// Hard bounds on R.
    ///
    /// **Calibration (plan §5 stage 5).** The plan's floor was 0.20, which made
    /// the bust impossible: a benched, discouraged player rehabbing a torn ACL
    /// computes 0.55 · 0.60 · 0.49 · 0.40 ≈ 0.065 and was lifted back to 0.20,
    /// i.e. to within a third of a healthy starter's realization. Measured
    /// consequence: the spread of four-camp ceiling-closure came out at
    /// σ ≈ 0.13 where the §6 hit-rate curve needs ≈ 0.25, and every draft round
    /// collapsed onto the same outcome. `DEVELOPMENT_NFL_REFERENCE.md` §2 puts
    /// a quarter of drafted players in the "never establishes, out of the league
    /// in 3-4 years" bucket — that bucket needs a floor near zero, not near the
    /// median. The floor is kept nonzero so a lost year is never a *permanent*
    /// verdict (he can be driven, healthy and starting next August).
    static let realizationFloor = 0.08
    static let realizationCeiling = 1.45

    // MARK: Motivation State Machine (plan §2.3)

    /// Computes and STORES this player's motivation state for the coming
    /// season, applying the state's one-off morale nudge.
    ///
    /// Must run once per player when the league enters `.trainingCamp`, before
    /// `developPlayer` — every trigger below describes the season that just
    /// finished, so it reads pre-aging values.
    @discardableResult
    static func assignMotivationState(_ player: Player, inputs: OffseasonInputs) -> MotivationState {
        let state = evaluateMotivation(player: player, inputs: inputs)
        player.motivationState = state
        player.morale = max(0, min(100, player.morale + state.moraleDelta))
        return state
    }

    /// The §2.3 trigger table, scored and mapped. Pure — no mutation — so the
    /// harness and the UI can ask "what would he be?" without side effects.
    /// Competitiveness gates for the §2.3 trigger table.
    ///
    /// **Calibration (plan §5 stage 5).** The plan wrote these as absolutes —
    /// "comp ≥ 65 answers adversity", "comp ≤ 40 checks out" — sized before any
    /// distribution existed. Measured against the league the generator actually
    /// produces (`MentalAttributeModel.competitiveness`, itself recentred in the
    /// same pass), 65 selects the top ~45 % and 40 the bottom ~6 %, so the
    /// positive half of the table fired constantly and the negative half almost
    /// never: driven 30 % / complacent 0.2 % / discouraged 0 % against the §6
    /// target of 15-25 / 5-12 / 5-12. Named here so the intent is one edit away
    /// from the measurement that sets it.
    ///
    /// **The gates must stay ordered `quitterGate < fighterGate`.** Every
    /// trigger below is written `if comp >= fighterGate { … } else if comp <=
    /// quitterGate { … }`, so a quitter gate at or above the fighter gate makes
    /// the second test vacuously true: the constant stops meaning anything, and
    /// the plan's **neutral middle band** — the players an adversity trigger
    /// simply does not move — disappears, with everyone below the fighter line
    /// taking the full penalty instead. That is exactly what the old pair
    /// (55 / 70, and 67 / 68 for the soft triggers) did.
    ///
    /// Measured competitiveness distribution (`career` harness, n = 745 705):
    /// p05 38 · p25 53 · p50 63 · p75 74 · p95 88, with ≤45 = 13 %, ≤50 ≈ 23 %,
    /// ≤55 ≈ 33 %, ≤60 = 43 %, ≤65 = 56 %, ≤70 = 68 %. The pair below therefore
    /// selects the top ~57 % as fighters and the bottom ~28 % as checked out,
    /// leaving ~15 % of the league genuinely neutral — the band's WIDTH is set
    /// by the §6.5d discouraged floor (5 %), which is what the negative branch
    /// has to be broad enough to supply.
    static let fighterGate = 58
    static let quitterGate = 53
    /// The ±1 demotion trigger uses a softer pair: losing your job reaches
    /// further up the roster than a lost season does, and the penalty is half
    /// the size.
    static let softFighterGate = 67
    static let softQuitterGate = 64
    /// Reference §3's contract-year bump is small and BROAD — "strongest for
    /// skill positions playing for a first big deal", not a reward reserved for
    /// elite competitors. Plan §2.3 words it as "comp ≥ 45", i.e. *everyone who
    /// has not checked out*, against the plan's assumed distribution where 40
    /// was the bottom quarter; on the measured distribution that same intent
    /// lands just above `quitterGate`. This used to read `quitterGate` itself —
    /// the constant named and documented as the CHECKED-OUT threshold — which
    /// silently limited the bump to the top third of the league.
    static let contractYearGate = 52
    /// Wins that read as "the season collapsed". The plan said 5; 6 is the
    /// measured line at which roughly a quarter of the league is on a team that
    /// missed badly, which is what `DEVELOPMENT_NFL_REFERENCE.md` §4's
    /// "big miss vs expectations" trigger is describing.
    static let collapseWins = 6
    /// How far BEFORE his peak window a low-drive player can already be checking
    /// out on a rebuild. The plan gated this on "past the window's lower bound",
    /// which in the measured league meant the trigger only reached the older
    /// half of the roster and left the §6 discouraged share at 4.5 % against a
    /// 5-12 % target. Two years of slack covers the mid-20s journeyman the
    /// reference's "checked-out veterans on rebuilders" (§4) is describing.
    static let checkOutAgeSlack = 4
    static let fragileMoraleGate = 78
    /// OVR a player has to shed year over year for it to read as a down year.
    /// The plan said 2; at the measured league's season-to-season noise that
    /// fired for so few players that the adversity half of the table barely
    /// existed (motivation mix: 73 % focused against the §6 55-70 % band).
    static let downYearDrop = 1
    /// Morale below which a low-competitiveness player starts sliding.
    static let lowMoraleGate = 76
    /// Reference §3's post-payday complacency is gated on DRIVE, and the immune
    /// group is the genuinely elite-drive quartile (the Brady/Rice archetype),
    /// not "anyone above average" — which is what the plan's 60/60 gates became
    /// once work ethic stopped being scaled down at the draft.
    static let paydayDriveGate = 95
    static let paydayCompGate = 94

    static func evaluateMotivation(player: Player, inputs: OffseasonInputs) -> MotivationState {
        let comp = player.competitiveness
        let peak = player.position.peakAgeRange
        var score = 0
        var paydayPenalty = 0
        var otherPenalty = 0

        /// Records a contribution, keeping the payday penalty separable so the
        /// complacent/discouraged split can be decided at the end.
        func add(_ delta: Int, isPayday: Bool = false) {
            score += delta
            guard delta < 0 else { return }
            if isPayday { paydayPenalty += delta } else { otherPenalty += delta }
        }

        // 1. Team collapsed last season. Fighters answer it; older low-drive
        //    veterans on a rebuild check out.
        if let wins = inputs.teamWins, wins <= collapseWins {
            if comp >= fighterGate {
                add(2)
            } else if comp <= quitterGate, player.age >= peak.lowerBound - checkOutAgeSlack {
                add(-2)
            }
        }

        // 2. Personal down year — his end-of-season OVR fell more than 2.
        if let latest = inputs.latestOverall, let previous = inputs.previousOverall,
           latest < previous - downYearDrop {
            if comp >= fighterGate {
                add(2)
            } else if comp <= quitterGate {
                add(-2)
            }
        }

        // 3. Demoted / benched — lost at least half his starts. The ≥ 4-start
        //    baseline keeps rotational noise from reading as a demotion.
        if inputs.previousGamesStarted >= 4,
           Double(inputs.gamesStarted) <= 0.5 * Double(inputs.previousGamesStarted) {
            if comp >= softFighterGate {
                add(1)
            } else if comp <= softQuitterGate {
                add(-1)
            }
        }

        // 4. Rookie chip — the day-3 pick or UDFA who was told he'd never make
        //    it (reference §4: the multi-year chip pattern).
        if player.yearsPro <= 2, comp >= fighterGate,
           (player.draftPickNumber ?? Int.max) > 100 {
            add(2)
        }

        // 5. Contract year — a small, visible bump (reference §3: studies range
        //    from "myth" to ~+5 %, so never a superpower).
        if player.contractYearsRemaining == 1,
           comp >= contractYearGate || player.personality.motivation == .money {
            add(1)
        }

        // 6. Just paid — the robust finding (reference §3): performance dips
        //    the season after a big guarantee, gated by drive. Winners are
        //    immune; money-motivated players slip further.
        // Reference §3 gates this on drive, not on being a bad player: the
        // immune group is the top third of work ethic and competitiveness (the
        // Brady/Rice archetype), not "everyone above average". The 60/60 gates
        // the plan named selected 5 % of the league once the same pass stopped
        // inflating work ethic through catch-up growth.
        if player.contractYearsRemaining >= 3, player.yearsPro >= 4,
           player.mental.workEthic < paydayDriveGate, comp < paydayCompGate,
           player.personality.motivation != .winning {
            let market = ContractEngine.estimateMarketValue(player: player)
            if market > 0, Double(player.annualSalary) >= Double(market) * 0.95 {
                add(-2, isPayday: true)
                if player.personality.motivation == .money {
                    add(-1, isPayday: true)
                }
            }
        }

        // 7. Playoff heartbreak — a team-wide offseason edge, amplified by the
        //    leaders who set the tone for it.
        if inputs.playoffHeartbreak {
            add(player.mental.leadership >= 70 ? 2 : 1)
        }

        // 8. Low morale drags the players who don't fight it.
        if player.morale < lowMoraleGate, comp <= fragileMoraleGate {
            add(-1)
        }

        // 9. Coach lift — a motivator head coach pulls negative rooms back
        //    toward focused (reference §5: HC culture is the top layer).
        if let hcMotivation = inputs.headCoachMotivation, hcMotivation >= 80, score < 0 {
            score += 1
            otherPenalty += 1     // the lift offsets the negatives it cancels
        }

        return MotivationState.from(
            score: score,
            paydayPenalty: paydayPenalty,
            otherPenalty: otherPenalty
        )
    }

    // MARK: Plateau & Late Bloomer (plan §2.5)

    /// R below which an offseason counts as "stalled" for the plateau test.
    /// **Calibration (plan §5 stage 5).** 0.45 was chosen against an assumed R
    /// mean of 0.50 with a narrow spread. The measured league's R is bimodal
    /// (backups cluster near 0.30, starters near 0.75), so the threshold that
    /// actually means "he is not realizing" sits at the top of the backup
    /// cluster. Measured plateau share moved 22 % → inside the §6 30-50 % band.
    static let plateauRealizationThreshold = 0.72

    /// Total OVR a player may gain across the two offseasons and still count as
    /// "he is what he is". The plan said 1; measured against the stage-5 growth
    /// curve (a pre-peak player gains ~1.2 OVR per offseason on the prime-years
    /// tail alone) that made the plateau tag essentially unreachable — 20 % of
    /// careers against the §6 30-50 % band. 2 points over two seasons is the
    /// honest reading of "settled into his role".
    static let plateauOverallGain = 3

    /// Chance that a plateaued player who catches a break actually breaks out.
    /// Raised from the plan's 0.15 in the stage-5 pass: with the measured
    /// catalyst rate (driven, or a new position coach, or a new building) a
    /// 15 % roll produced late-bloomer breakouts for 1 % of careers against the
    /// §6 target of 5-12 %.
    static let lateBloomerChance = 0.70

    /// Multiplier applied to R for the one cycle a late-bloomer breakout fires.
    static let lateBloomerRealizationBoost = 1.25

    /// "He is what he is." A player with 2+ pro seasons whose realization has
    /// been under `plateauRealizationThreshold` two offseasons running AND who
    /// has gained at most 1 OVR across them has settled into his role.
    ///
    /// Nothing new is persisted for this (plan §2.5): the previous offseason's
    /// R is reconstructed from the player's own attributes and the playing-time
    /// share recorded in `PlayerSeasonHistory` for the season before last, and
    /// the OVR gain comes straight off the same history rows.
    static func isPlateaued(
        player: Player,
        inputs: OffseasonInputs,
        currentRealization: Double,
        positionCoach: Coach?
    ) -> Bool {
        guard player.yearsPro >= 2 else { return false }
        guard currentRealization < plateauRealizationThreshold else { return false }
        guard let latest = inputs.latestOverall,
              let twoBack = inputs.overallTwoSeasonsAgo else { return false }
        guard latest - twoBack <= plateauOverallGain else { return false }

        // Previous offseason's R, reconstructed: same player factors, the
        // playing time he actually had that year, neutral motivation/health
        // (neither is retained per-season — the plan explicitly trades that
        // precision for zero extra storage).
        let previousShare = realPlayingTimeShare(
            gamesStarted: inputs.previousGamesStarted,
            gamesPlayed: inputs.previousGamesPlayed,
            positionCoach: positionCoach
        )
        let previousRealization = realizationFactor(
            player: player,
            motivation: .focused,
            playingTimeShare: previousShare,
            health: 1.0
        )
        return previousRealization < plateauRealizationThreshold
    }

    /// Rolls the late-bloomer breakout for a plateaued player whose situation
    /// just changed: he showed up driven, a good position coach arrived, or he
    /// is in a new building. Covers the year 3-5 scheme/coach/opportunity
    /// breakouts that `TrainingFocusEngine.rollBreakout` (young, high-potential
    /// only) never reaches.
    static func rollsLateBloomerBreakout(player: Player, inputs: OffseasonInputs) -> Bool {
        let hasCatalyst = player.motivationState == .driven
            || inputs.newPositionCoach
            || inputs.changedTeam
        guard hasCatalyst else { return false }
        return Double.random(in: 0.0..<1.0) < lateBloomerChance
    }

    // MARK: - 2. In-Season Experience

    /// Applies small mental attribute gains from regular-season game experience.
    ///
    /// - Parameters:
    ///   - player: The player gaining experience.
    ///   - gamesPlayed: Number of games the player appeared in (0-17).
    ///   - gamesStarted: Number of games the player started (0-17).
    ///   - experienceBoost: R25 locker-room modifier — an active mentorship
    ///     speeds a young player's growth. Clamped to 0.9...1.1 (max ±10 %).
    ///   - clipboardRoom: plan §2.9.5 — this is a QB in a room that develops
    ///     backups (a QB coach rated 70+, or an active mentorship). See the
    ///     `clipboardStartShare` note below.
    static func applyGameExperience(
        _ player: Player,
        gamesPlayed: Int,
        gamesStarted: Int,
        experienceBoost: Double = 1.0,
        clipboardRoom: Bool = false
    ) {
        guard gamesPlayed > 0 else { return }

        // Rookies gain more from experience than veterans.
        let baseMultiplier: Double
        switch player.yearsPro {
        case 0:     baseMultiplier = 1.0
        case 1:     baseMultiplier = 0.7
        case 2...3: baseMultiplier = 0.4
        default:    baseMultiplier = 0.2
        }
        let experienceMultiplier = baseMultiplier * min(max(experienceBoost, 0.9), 1.1)

        // Base gain from games played and started (0.0-1.0 range).
        //
        // QB2 clipboard (plan §2.9.5, `DEVELOPMENT_NFL_REFERENCE.md` §6: "QB2
        // clipboard development is real but slow, and accelerates with a good
        // QB room"): a quarterback who does not start still gets `0.35` of the
        // STARTER term when the room develops him — film study and scout-team
        // reps under a real QB coach or a veteran mentor. He never catches the
        // man taking the snaps (0.675 vs 1.0 of a starter's rate), but he stops
        // being frozen at the pure appearance rate.
        let creditedStarts: Double
        if clipboardRoom, player.position == .QB, gamesStarted == 0 {
            creditedStarts = clipboardStartShare * Double(gamesPlayed)
        } else {
            creditedStarts = Double(gamesStarted)
        }
        let gamesFactor = (Double(gamesPlayed) / 17.0) * 0.5 + (creditedStarts / 17.0) * 0.5

        // Awareness improvement (~1 point per full season for a rookie starter).
        //
        // ACCRUAL FIX (phase 2): this used to be `Int(x.rounded())`, which is a
        // no-op at the cadence the engine is actually driven at. `WeekAdvancer`
        // calls this once per WEEK with gamesPlayed/started = 1, so the term is
        // ~0.059 — it rounded to 0 every single week for every single player,
        // i.e. in-season mental growth did not exist and the §2.9.5 backup-QB
        // tick could never have fired either. Probabilistic rounding keeps the
        // designed per-season expectation (17 weekly calls == one 17-game call)
        // while making a fractional week actually worth something.
        let awarenessGain = probabilisticPoints(gamesFactor * experienceMultiplier * 1.0)
        if awarenessGain > 0 {
            player.mental.awareness = min(99, player.mental.awareness + awarenessGain)
        }

        // Decision making improvement.
        let decisionGain = probabilisticPoints(gamesFactor * experienceMultiplier * 0.8)
        if decisionGain > 0 {
            player.mental.decisionMaking = min(99, player.mental.decisionMaking + decisionGain)
        }

        // Clutch: random chance of improvement if player was in close games.
        // Simplified: ~30% chance per season for active starters.
        if gamesStarted > 8 && Double.random(in: 0.0..<1.0) < 0.3 * experienceMultiplier {
            player.mental.clutch = min(99, player.mental.clutch + 1)
        }
    }

    /// Share of a starter's development term a backup quarterback earns in a
    /// room that actually coaches him (plan §2.9.5).
    static let clipboardStartShare = 0.35

    /// Rounds a fractional attribute gain to whole points without throwing the
    /// remainder away: 0.4 is a 40 % chance of +1. Mirrors
    /// `TrainingPlanEngine.rollPoints`, so every per-week accrual path in the
    /// game keeps the same expectation regardless of how finely it is sliced.
    static func probabilisticPoints(_ value: Double) -> Int {
        guard value > 0 else { return 0 }
        let whole = Int(value)
        let fraction = value - Double(whole)
        return whole + (Double.random(in: 0.0..<1.0) < fraction ? 1 : 0)
    }

    // MARK: - 3. Age Regression

    /// Ages the player by one year, increments yearsPro, and applies age-based regression
    /// to physical (and eventually mental) attributes.
    ///
    /// Phase 2 (plan §2.8, `DEVELOPMENT_NFL_REFERENCE.md` §1): the historical
    /// single table now runs through `Position.declineProfile`, so a 30-year-old
    /// corner no longer decays at exactly the rate of a 30-year-old left tackle.
    /// `.standard` positions reproduce the old numbers byte-for-byte; `.cliff`
    /// (RB/CB) adds 15 pp of chance and a point of magnitude; `.glide`
    /// (QB/OL/K/P) removes 10 pp and a point, and keeps growing mentally for two
    /// more years.
    ///
    /// Phase 2 stage 6 adds the POSITION-skill half of the decline
    /// (`regressPositionAttributes`). Until then only physicals and, deep past
    /// peak, a couple of mentals ever came down, while `applyCatchUpGrowth`
    /// pushed position skills — half of `overall` — up and never back, so an
    /// individual rating (and with 1 700 of them, the league) could only
    /// ratchet upward.
    ///
    /// - Parameter player: The player to age and potentially regress.
    static func applyAgeRegression(_ player: Player) {
        player.age += 1
        player.yearsPro += 1

        let peakRange = player.position.peakAgeRange
        let yearsPastPeak = player.age - peakRange.upperBound
        let profile = player.position.declineProfile

        if yearsPastPeak < 0 {
            // Before peak: no regression.
            return
        }

        // The processing exception (reference §1): a quarterback's — and, more
        // broadly, a glide position's — football IQ keeps climbing for a couple
        // of years after the body has started to go. Runs BEFORE the physical
        // regression so it is never a same-year undo of the mental loss the 4+
        // band applies (that band starts three years later anyway).
        if profile.hasLateMentalGrowth && yearsPastPeak <= 2 {
            player.mental.awareness = min(99, player.mental.awareness + 1)
            player.mental.decisionMaking = min(99, player.mental.decisionMaking + 1)
        }

        if yearsPastPeak == 0 {
            // At peak: 10% chance of -1 to 1-2 physical attributes.
            guard Double.random(in: 0.0..<1.0) < regressionChance(0.10, profile) else { return }
            let attributeCount = Int.random(in: 1...2)
            regressPhysicalAttributes(
                player: player,
                count: attributeCount,
                range: magnitudeRange(1...1, profile)
            )
            regressPositionAttributes(
                player: player,
                count: Int.random(in: 0...1),
                range: magnitudeRange(1...1, profile)
            )
            return
        }

        if yearsPastPeak <= 3 {
            // 1-3 years past peak: 40% chance, physical attributes lose 1-3 points.
            guard Double.random(in: 0.0..<1.0) < regressionChance(0.40, profile) else { return }
            let attributeCount = Int.random(in: 2...4)
            regressPhysicalAttributes(
                player: player,
                count: attributeCount,
                range: magnitudeRange(1...3, profile)
            )
            regressPositionAttributes(
                player: player,
                count: Int.random(in: 1...3),
                range: magnitudeRange(1...3, profile)
            )
        } else {
            // 4+ years past peak: 80% chance, physical lose 2-5 points, mental lose 1-2.
            if Double.random(in: 0.0..<1.0) < regressionChance(0.80, profile) {
                let physCount = Int.random(in: 3...6)
                regressPhysicalAttributes(
                    player: player,
                    count: physCount,
                    range: magnitudeRange(2...5, profile)
                )
                regressPositionAttributes(
                    player: player,
                    count: Int.random(in: 2...4),
                    range: magnitudeRange(2...4, profile)
                )

                // Mental regression starts (but awareness and leadership are protected).
                let mentalCount = Int.random(in: 1...2)
                regressMentalAttributes(
                    player: player,
                    count: mentalCount,
                    range: magnitudeRange(1...2, profile)
                )
            }
        }

        // Durability specifically decreases with age, especially with injury history.
        if yearsPastPeak > 0 {
            let injuryPenalty = player.isInjured ? 2 : 0
            let durabilityLoss = Int.random(in: 0...1) + injuryPenalty
            if durabilityLoss > 0 {
                player.physical.durability = max(1, player.physical.durability - durabilityLoss)
            }
        }
    }

    /// Applies the position's chance delta to one band of the generic table.
    private static func regressionChance(_ base: Double, _ profile: DeclineProfile) -> Double {
        min(1.0, max(0.0, base + profile.chanceDelta))
    }

    /// Applies the position's magnitude delta to one band of the generic table.
    /// Both bounds shift; the floor is 1 point so `.glide` never produces a
    /// zero-point "regression" that silently does nothing.
    private static func magnitudeRange(
        _ base: ClosedRange<Int>,
        _ profile: DeclineProfile
    ) -> ClosedRange<Int> {
        let low = max(1, base.lowerBound + profile.magnitudeDelta)
        let high = max(low, base.upperBound + profile.magnitudeDelta)
        return low...high
    }

    // MARK: - 4. Mentor System

    /// Pairs eligible veteran mentors with rookies at the same position and applies
    /// mental attribute bonuses (or penalties for bad mentors).
    ///
    /// - Parameters:
    ///   - veterans: Veteran players on the team roster.
    ///   - rookies: Rookie players on the team roster.
    static func applyMentoring(veterans: [Player], rookies: [Player]) {
        for veteran in veterans {
            // Only mentors/team leaders with leadership > 75 can mentor positively.
            let isMentor = veteran.personality.isMentor && veteran.mental.leadership > 75

            // Bad mentors: dramaQueen or loneWolf with low leadership.
            let isBadMentor: Bool
            switch veteran.personality.archetype {
            case .dramaQueen:
                isBadMentor = true
            case .loneWolf:
                isBadMentor = veteran.mental.leadership < 50
            default:
                isBadMentor = false
            }

            guard isMentor || isBadMentor else { continue }

            // Find rookies at the same position.
            let eligibleRookies = rookies.filter { $0.position == veteran.position && $0.yearsPro <= 1 }
            guard !eligibleRookies.isEmpty else { continue }

            for rookie in eligibleRookies {
                if isBadMentor {
                    // Negative mentoring: -1 to -2 on 1-2 mental attributes.
                    let penaltyCount = Int.random(in: 1...2)
                    applyMentalBonus(player: rookie, totalPoints: -penaltyCount, range: -2...(-1))
                } else {
                    // Positive mentoring: +1 to +3 bonus to mental attributes.
                    // Mentor's coachability determines the magnitude.
                    let baseMentorBonus = Double(veteran.mental.coachability - 1) / 98.0
                    let bonusPoints = Int((baseMentorBonus * 3.0).rounded().clamped(to: 1...3))
                    applyMentalBonus(player: rookie, totalPoints: bonusPoints, range: 1...3)
                }
            }
        }
    }

    // MARK: - 5. Potential Realization

    /// Nudges the player's ceiling toward (or away from) what his environment
    /// deserves — scheme fit and morale.
    ///
    /// This function existed since launch with **zero call sites** (plan §1.2);
    /// phase 2 wires it into the offseason, between the motivation pass and
    /// `developPlayer`, with §2.6's much tighter deltas:
    ///
    /// - scheme fit moves the ceiling at most ±2 in a year (was ±3),
    /// - morale at most ±1 (was ±2),
    /// - and the **lifetime** drift is capped at ±8 from `draftTruePotential`.
    ///
    /// The cap is the point of the whole rewrite: potential responds modestly to
    /// environment, it does not decide outcomes. R does. Without it, a decade in
    /// a good scheme would inflate a journeyman's ceiling without limit — the
    /// league potential ratchet phase 1 left open.
    ///
    /// - Parameters:
    ///   - player: The player to evaluate.
    ///   - schemeFit: 0.0-1.0 indicating how well the player fits the team's scheme.
    ///   - moraleAverage: The player's average morale over the season (1-100).
    static func updatePotentialRealization(_ player: Player, schemeFit: Double, moraleAverage: Int) {
        // Seed the lifetime anchor on first touch. `0` is the "never written"
        // sentinel, so legacy rows anchor on where they ARE rather than
        // snapping to some reconstructed draft-day value.
        if player.draftTruePotential <= 0 {
            player.draftTruePotential = player.truePotential
        }

        // Scheme fit contribution: good fit (>0.7) raises ceiling, bad fit (<0.3) lowers it.
        let fitModifier: Int
        if schemeFit >= 0.8 {
            fitModifier = Int.random(in: 1...2)
        } else if schemeFit >= 0.6 {
            fitModifier = Int.random(in: 0...1)
        } else if schemeFit >= 0.4 {
            fitModifier = 0
        } else if schemeFit >= 0.2 {
            fitModifier = Int.random(in: -1...0)
        } else {
            fitModifier = Int.random(in: -2...(-1))
        }

        // Morale contribution: high morale + good fit boosts ceiling.
        let moraleModifier: Int
        if moraleAverage >= 80 {
            moraleModifier = 1
        } else if moraleAverage >= 60 {
            moraleModifier = 0
        } else if moraleAverage >= 40 {
            moraleModifier = Int.random(in: -1...0)
        } else {
            moraleModifier = -1
        }

        // Apply the combined modifier, then hold it inside the lifetime band.
        let drifted = player.truePotential + fitModifier + moraleModifier
        let lifetimeFloor = player.draftTruePotential - potentialLifetimeDrift
        let lifetimeCeiling = player.draftTruePotential + potentialLifetimeDrift
        let bounded = min(lifetimeCeiling, max(lifetimeFloor, drifted))
        player.truePotential = max(1, min(99, bounded))
    }

    /// Maximum lifetime drift of `truePotential` away from `draftTruePotential`
    /// (plan §2.6).
    static let potentialLifetimeDrift = 8

    // MARK: - 6. Injury System

    /// Processes an existing injury: decrements recovery time and handles healing.
    ///
    /// - Parameter player: The injured player to process.
    /// - Returns: `nil` if no change, or a description string if healed or permanent damage occurred.
    static func processInjury(_ player: Player) -> String? {
        guard player.isInjured else { return nil }

        player.injuryWeeksRemaining -= 1

        guard player.injuryWeeksRemaining <= 0 else { return nil }

        // Player has healed.
        player.isInjured = false
        player.injuryWeeksRemaining = 0

        // Small chance of permanent durability loss upon healing.
        let permanentDamageChance = 0.15
        if Double.random(in: 0.0..<1.0) < permanentDamageChance {
            let durabilityLoss = Int.random(in: 1...5)
            player.physical.durability = max(1, player.physical.durability - durabilityLoss)
            return "\(player.fullName) has healed but suffered permanent durability loss (-\(durabilityLoss))."
        }

        return "\(player.fullName) has fully recovered from injury."
    }

    /// Checks whether a player sustains an injury during a game.
    ///
    /// - Parameters:
    ///   - player: The player at risk of injury.
    ///   - playIntensity: 0.0-1.0 representing the contact level of the play.
    /// - Returns: `nil` if no injury, or a tuple with injury details.
    static func checkForInjury(
        _ player: Player,
        playIntensity: Double
    ) -> (injured: Bool, weeksOut: Int, description: String)? {
        // Base injury chance: ~2% per game.
        var injuryChance = 0.02

        // Durability modifier: high durability reduces risk.
        let durabilityFactor = (99.0 - Double(player.physical.durability)) / 99.0 * 0.03
        injuryChance += durabilityFactor

        // Fatigue modifier: high fatigue increases risk.
        let fatigueFactor = Double(player.fatigue) / 100.0 * 0.03
        injuryChance += fatigueFactor

        // Age modifier: older players are more fragile.
        let peakRange = player.position.peakAgeRange
        let yearsPastPeak = max(0, player.age - peakRange.upperBound)
        let ageFactor = Double(yearsPastPeak) * 0.005
        injuryChance += ageFactor

        // Camp workload modifier (plan §2.9.6, defect #3). NOTE: this function
        // is the `career` balance-harness's per-season injury model — the
        // SHIPPED game rolls every injury through `MedicalEngine.injuryCheck`
        // (weekly sim) and `LiveGameEngine.checkInjury` (coached games), both of
        // which carry the identical term via
        // `MedicalEngine.workloadRiskMultiplier`. The two lines are duplicated
        // rather than shared because `MedicalEngine` is not one of the sources
        // `tools/balance-harness/sync_sources.sh` compiles.
        //
        // Applied only where a status has actually been written — the typed
        // accessor reports `.healthy` for an untouched row, and a player nobody
        // has ever ticked must not be silently reclassified.
        if player.workloadStatusRaw != nil {
            injuryChance *= player.workloadStatus.injuryMultiplier
        }

        // Play intensity modifier.
        injuryChance *= (0.5 + playIntensity * 0.5)

        guard Double.random(in: 0.0..<1.0) < injuryChance else { return nil }

        // Determine severity.
        let severityRoll = Double.random(in: 0.0..<1.0)
        let weeksOut: Int
        let description: String

        if severityRoll < 0.45 {
            // Minor: 1-2 weeks
            weeksOut = Int.random(in: 1...2)
            description = minorInjuryDescription(weeksOut: weeksOut)
        } else if severityRoll < 0.75 {
            // Moderate: 3-6 weeks
            weeksOut = Int.random(in: 3...6)
            description = moderateInjuryDescription(weeksOut: weeksOut)
        } else if severityRoll < 0.93 {
            // Major: 7-16 weeks
            weeksOut = Int.random(in: 7...16)
            description = majorInjuryDescription(weeksOut: weeksOut)
        } else {
            // Season-ending: 17+ weeks
            weeksOut = Int.random(in: 17...52)
            description = seasonEndingInjuryDescription(weeksOut: weeksOut)
        }

        // Apply the injury to the player.
        player.isInjured = true
        player.injuryWeeksRemaining = weeksOut

        return (injured: true, weeksOut: weeksOut, description: "\(description) (\(weeksOut) weeks)")
    }

    // MARK: - 7. Potential Assessment

    /// Converts a player's hidden `truePotential` into a verbal `PotentialLabel`,
    /// with noise that decreases over time and with better coaching.
    ///
    /// - Parameters:
    ///   - player: The player to evaluate.
    ///   - coachDevelopmentRating: The position/development coach's playerDevelopment attribute (1-99).
    ///   - yearsOnTeam: How many years the player has been on this team.
    /// - Returns: A `PotentialLabel` representing the coaching staff's best guess at the player's ceiling.
    static func assessPotential(player: Player, coachDevelopmentRating: Int, yearsOnTeam: Int) -> PotentialLabel {
        // Base noise level depends on how long the coaching staff has had to evaluate the player.
        var noise: Int
        switch yearsOnTeam {
        case 0:     noise = 2   // Just drafted/acquired — very inaccurate
        case 1:     noise = 1   // One year of observation
        default:    noise = 0   // Two+ years — accurate assessment
        }

        // Elite development coaches (rating >= 80) reduce noise by 1 level.
        if coachDevelopmentRating >= 80 {
            noise = max(0, noise - 1)
        }

        return PotentialLabel.from(potential: player.truePotential, noise: noise)
    }

    /// The label actually persisted onto `Player.assessedPotential` each camp
    /// (plan §2.9.4).
    ///
    /// Two things the raw `assessPotential` does not know about:
    /// - the position coach is the evaluator, so his `playerDevelopment` is the
    ///   rating that shrinks the noise ("an elite developer sees it sooner");
    /// - a player the model has tagged as plateaued (§2.5) reads a band lower.
    ///   The staff has watched him not move for two years — the projection
    ///   follows the eye test, not the hidden number.
    static func assessedPotentialLabel(
        player: Player,
        positionCoach: Coach?,
        yearsOnTeam: Int,
        plateaued: Bool
    ) -> PotentialLabel {
        let label = assessPotential(
            player: player,
            coachDevelopmentRating: positionCoach?.playerDevelopment ?? 50,
            yearsOnTeam: yearsOnTeam
        )
        return plateaued ? label.loweredOneBand : label
    }

    // MARK: - 8. Full Offseason Processing

    /// What the realization pass decided about one player, handed back to the
    /// caller so the narrative layer (news stories, camp development report —
    /// plan §2.10) can tell the story without recomputing any of it.
    ///
    /// Deliberately a plain value type with no `Player` reference: the engine
    /// stays a pure function of its arguments, and `WeekAdvancer` can collect
    /// outcomes for all 32 teams before deciding which ones make the feed.
    struct OffseasonOutcome {
        let playerID: UUID
        let playerName: String
        let position: Position
        let teamID: UUID?
        let archetype: PersonalityArchetype
        let motivation: MotivationState
        /// "He is what he is" (§2.5) — also drops the coach's projection a band.
        let plateaued: Bool
        /// The plateau broke this offseason (§2.5): R ran at ×1.25.
        let lateBloomerBreakout: Bool
        let overallBefore: Int
        let overallAfter: Int
        let age: Int
        let yearsPro: Int

        /// OVR moved this offseason (can be negative for a regressing veteran).
        var overallDelta: Int { overallAfter - overallBefore }
    }

    /// Runs the complete offseason pipeline for a roster of players: aging, development,
    /// injury processing, and mentoring.
    ///
    /// Retirement is NOT decided here — `PlayerRetirementEngine` handles it
    /// once per offseason in the `.coachingChanges` phase (R32), before free
    /// agency, so departures actually leave the league.
    ///
    /// Phase 2 pipeline order per player (plan §2.3-§2.6):
    /// motivation → age regression → potential drift → development.
    /// Motivation is scored from the season that just finished, so it is
    /// evaluated BEFORE `applyAgeRegression` bumps age and yearsPro.
    ///
    /// - Parameters:
    ///   - players: All players on the team.
    ///   - coaches: The full coaching staff.
    ///   - inputs: Per-player situational data the engine cannot read off the
    ///     `Player` row (last season's record, participation, history trend,
    ///     scheme fit, health flags). Omit it and every player is processed
    ///     with neutral defaults.
    ///   - environment: the team-level situation (scheme install year,
    ///     coordinator continuity — plan §2.9.2-3).
    ///   - onOutcome: Optional per-player callback fired once the player has
    ///     been fully processed, carrying the realization verdict (motivation,
    ///     plateau, late-bloomer, OVR delta) for the §2.10 narrative surfaces.
    ///     Omitting it leaves behaviour byte-identical.
    /// - Returns: Array of descriptions for notable events (injury updates, etc.).
    @discardableResult
    static func processOffseason(
        players: [Player],
        coaches: [Coach],
        inputs: [UUID: OffseasonInputs] = [:],
        environment: TeamEnvironment = TeamEnvironment(),
        onOutcome: ((OffseasonOutcome) -> Void)? = nil
    ) -> [String] {
        var events: [String] = []

        // --- Motivation, aging, potential drift, development ---
        for player in players {
            let playerInputs = inputs[player.id] ?? OffseasonInputs()
            let positionCoach = coaches.first { coach in
                CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
            }
            let overallBefore = player.overall

            // 1. Where his head is at — scored off the season just finished.
            assignMotivationState(player, inputs: playerInputs)

            // 2. Real playing time (plan §2.4) and the health gate, both read
            //    from last season before aging touches anything.
            let playingTimeShare = realPlayingTimeShare(
                gamesStarted: playerInputs.gamesStarted,
                gamesPlayed: playerInputs.gamesPlayed,
                positionCoach: positionCoach
            )
            let health = healthFactor(player: player, inputs: playerInputs)

            // 3. Plateau / late-bloomer, evaluated on the pre-aging record.
            let realization = realizationFactor(
                player: player,
                motivation: player.motivationState,
                playingTimeShare: playingTimeShare,
                health: health
            )
            var realizationBoost = 1.0
            var lateBloomerBreakout = false
            let plateaued = isPlateaued(
                player: player,
                inputs: playerInputs,
                currentRealization: realization,
                positionCoach: positionCoach
            )
            if plateaued, rollsLateBloomerBreakout(player: player, inputs: playerInputs) {
                realizationBoost = lateBloomerRealizationBoost
                lateBloomerBreakout = true
                events.append("\(player.fullName) has finally put it together — a late-career leap.")
            }

            applyAgeRegression(player)

            // 4. Environment nudges the ceiling a little (plan §2.6) — after
            //    motivation, before development, inside the lifetime ±8 band.
            updatePotentialRealization(
                player,
                schemeFit: playerInputs.schemeFit,
                moraleAverage: player.morale
            )

            developPlayer(
                player,
                coaches: coaches,
                playingTimeShare: playingTimeShare,
                health: health,
                realizationBoost: realizationBoost,
                environment: environment
            )

            // 5. The staff's yearly read on his ceiling (plan §2.9.4, fixes
            //    defect #9: `assessedPotential` was declared on `Player` and
            //    never written, so every "Coach's Projection" in the UI fell
            //    back to a noise-free render of the TRUE potential — no fog at
            //    all). Written AFTER development so the label reflects this
            //    year's drifted ceiling, and re-written every camp so the noise
            //    shrinks as the staff gets to know him.
            player.assessedPotential = assessedPotentialLabel(
                player: player,
                positionCoach: positionCoach,
                yearsOnTeam: playerInputs.yearsOnTeam,
                plateaued: plateaued
            ).rawValue

            // Offseason injury processing (rare offseason injuries).
            if player.isInjured {
                if let result = processInjury(player) {
                    events.append(result)
                }
            }

            // Reset fatigue for the new season.
            player.fatigue = 0

            // 6. Hand the verdict to the narrative layer (plan §2.10). Fired
            //    last so `overallAfter` and the fresh projection are final.
            onOutcome?(OffseasonOutcome(
                playerID: player.id,
                playerName: player.fullName,
                position: player.position,
                teamID: player.teamID,
                archetype: player.personality.archetype,
                motivation: player.motivationState,
                plateaued: plateaued,
                lateBloomerBreakout: lateBloomerBreakout,
                overallBefore: overallBefore,
                overallAfter: player.overall,
                age: player.age,
                yearsPro: player.yearsPro
            ))
        }

        // --- Mentoring ---
        let veterans = players.filter { $0.yearsPro >= 4 }
        let rookies = players.filter { $0.yearsPro <= 1 }
        applyMentoring(veterans: veterans, rookies: rookies)

        return events
    }
}

// MARK: - Private Helpers

private extension PlayerDevelopmentEngine {

    // MARK: Point Distribution

    /// Distributes development points randomly across a player's physical attributes,
    /// capped by the potential ceiling.
    static func distributePhysicalPoints(player: Player, points: Int, ceiling: Int) {
        guard points > 0 else { return }

        // All physical attribute key paths.
        let keyPaths: [WritableKeyPath<PhysicalAttributes, Int>] = [
            \.speed, \.acceleration, \.strength, \.agility, \.stamina, \.durability
        ]

        var remaining = points
        var shuffled = keyPaths.shuffled()

        while remaining > 0 && !shuffled.isEmpty {
            let kp = shuffled.removeFirst()
            let current = player.physical[keyPath: kp]
            guard current < ceiling else { continue }

            let gain = min(remaining, Int.random(in: 1...max(1, remaining)))
            let newValue = min(ceiling, min(99, current + gain))
            let actualGain = newValue - current
            player.physical[keyPath: kp] = newValue
            remaining -= actualGain
        }
    }

    /// Distributes development points randomly across a player's mental attributes,
    /// capped by the potential ceiling.
    static func distributeMentalPoints(player: Player, points: Int, ceiling: Int) {
        guard points > 0 else { return }

        let keyPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.awareness, \.decisionMaking, \.clutch, \.workEthic, \.coachability, \.leadership
        ]

        var remaining = points
        var shuffled = keyPaths.shuffled()

        while remaining > 0 && !shuffled.isEmpty {
            let kp = shuffled.removeFirst()
            let current = player.mental[keyPath: kp]
            guard current < ceiling else { continue }

            let gain = min(remaining, Int.random(in: 1...max(1, remaining)))
            let newValue = min(ceiling, min(99, current + gain))
            let actualGain = newValue - current
            player.mental[keyPath: kp] = newValue
            remaining -= actualGain
        }
    }

    // MARK: Young-Player Catch-Up Growth

    /// Moves every position skill, every *learnable* mental attribute and every
    /// *trainable* physical attribute a fraction of the way toward the player's
    /// development ceiling (never past 99, never downward).
    ///
    /// **Physical (phase 2, plan §5 stage 5).** This used to skip physicals
    /// entirely, on the grounds that rookies "already enter near-complete".
    /// That stopped being true when `DraftEngine.rookieScaleFactors` dropped the
    /// physical factor to 0.85 so rookies arrive unfinished — an NFL strength
    /// program is a real, multi-year development path (reference §5:
    /// "strength/conditioning staff: injury-rate and durability effects more
    /// than skill effects", and §1's growth years). `speed` is deliberately
    /// excluded: a slow player does not become fast, which is why the aging
    /// curves in §1 are speed-driven. `durability` is excluded because
    /// `applyAgeRegression` owns it.
    ///
    /// **Phase-2 calibration (career harness, plan §5 stage 5).** This used to
    /// pull all six mental attributes toward the ceiling, `workEthic`,
    /// `coachability` and `leadership` included — so a high-potential player's
    /// *work ethic* rose to 90+ purely because his ceiling was high. Measured
    /// consequence over a 30-season league: work-ethic p05 climbed to 60 and
    /// p50 to 75, which (a) inflated the R factor's `base` term for exactly the
    /// players who were already realizing the most, and (b) made the §2.3
    /// post-payday complacency trigger (`workEthic < 60`) fire for 0.2 % of the
    /// league instead of the designed 5-12 %.
    ///
    /// `DEVELOPMENT_NFL_REFERENCE.md` §2 lists work ethic among the
    /// **differentiators that decide the trajectory** — an input, not an
    /// output. So catch-up now only touches what the NFL actually teaches: the
    /// football-mental trio (awareness / decision making / clutch) plus the
    /// position skills below. Drive, coachability and leadership stay the
    /// stable traits the realization model reads.
    static func applyCatchUpGrowth(player: Player, fraction: Double, ceiling: Int) {
        let cap = min(99, ceiling)

        func grown(_ value: Int) -> Int {
            guard value < cap else { return value }
            let gain = Int((Double(cap - value) * fraction).rounded())
            return min(cap, value + gain)
        }

        // Learnable mental attributes — the pro game slowing down for him.
        let mentalPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.awareness, \.decisionMaking, \.clutch
        ]
        for kp in mentalPaths {
            player.mental[keyPath: kp] = grown(player.mental[keyPath: kp])
        }

        // Trainable physical attributes — the NFL weight room. Speed and
        // durability are excluded (see the doc comment).
        let physicalPaths: [WritableKeyPath<PhysicalAttributes, Int>] = [
            \.acceleration, \.strength, \.agility, \.stamina
        ]
        for kp in physicalPaths {
            player.physical[keyPath: kp] = grown(player.physical[keyPath: kp])
        }

        // Position skills (50 % of OVR) — the frozen component this fixes.
        switch player.positionAttributes {
        case .quarterback(var a):
            a.armStrength = grown(a.armStrength)
            a.accuracyShort = grown(a.accuracyShort)
            a.accuracyMid = grown(a.accuracyMid)
            a.accuracyDeep = grown(a.accuracyDeep)
            a.pocketPresence = grown(a.pocketPresence)
            a.scrambling = grown(a.scrambling)
            player.positionAttributes = .quarterback(a)
        case .runningBack(var a):
            a.vision = grown(a.vision)
            a.elusiveness = grown(a.elusiveness)
            a.breakTackle = grown(a.breakTackle)
            a.receiving = grown(a.receiving)
            player.positionAttributes = .runningBack(a)
        case .wideReceiver(var a):
            a.routeRunning = grown(a.routeRunning)
            a.catching = grown(a.catching)
            a.release = grown(a.release)
            a.spectacularCatch = grown(a.spectacularCatch)
            player.positionAttributes = .wideReceiver(a)
        case .tightEnd(var a):
            a.blocking = grown(a.blocking)
            a.catching = grown(a.catching)
            a.routeRunning = grown(a.routeRunning)
            a.speed = grown(a.speed)
            player.positionAttributes = .tightEnd(a)
        case .offensiveLine(var a):
            a.runBlock = grown(a.runBlock)
            a.passBlock = grown(a.passBlock)
            a.pull = grown(a.pull)
            a.anchor = grown(a.anchor)
            player.positionAttributes = .offensiveLine(a)
        case .defensiveLine(var a):
            a.passRush = grown(a.passRush)
            a.blockShedding = grown(a.blockShedding)
            a.powerMoves = grown(a.powerMoves)
            a.finesseMoves = grown(a.finesseMoves)
            player.positionAttributes = .defensiveLine(a)
        case .linebacker(var a):
            a.tackling = grown(a.tackling)
            a.zoneCoverage = grown(a.zoneCoverage)
            a.manCoverage = grown(a.manCoverage)
            a.blitzing = grown(a.blitzing)
            player.positionAttributes = .linebacker(a)
        case .defensiveBack(var a):
            a.manCoverage = grown(a.manCoverage)
            a.zoneCoverage = grown(a.zoneCoverage)
            a.press = grown(a.press)
            a.ballSkills = grown(a.ballSkills)
            player.positionAttributes = .defensiveBack(a)
        case .kicking(var a):
            a.kickPower = grown(a.kickPower)
            a.kickAccuracy = grown(a.kickAccuracy)
            player.positionAttributes = .kicking(a)
        }
    }

    // MARK: Regression

    /// Regresses random physical attributes. Speed and acceleration are targeted first.
    static func regressPhysicalAttributes(player: Player, count: Int, range: ClosedRange<Int>) {
        // Speed and acceleration regress first -- they appear at the front of the list.
        var keyPaths: [WritableKeyPath<PhysicalAttributes, Int>] = [
            \.speed, \.acceleration
        ]
        // Remaining attributes are shuffled and appended.
        var others: [WritableKeyPath<PhysicalAttributes, Int>] = [
            \.strength, \.agility, \.stamina
        ]
        others.shuffle()
        keyPaths.append(contentsOf: others)
        // Note: durability is handled separately in applyAgeRegression.

        for i in 0..<min(count, keyPaths.count) {
            let kp = keyPaths[i]
            let loss = Int.random(in: range)
            player.physical[keyPath: kp] = max(1, player.physical[keyPath: kp] - loss)
        }
    }

    /// Regresses random POSITION skills — the missing half of the aging curve
    /// (plan §5 stage 6).
    ///
    /// `applyCatchUpGrowth` raises position skills (50 % of `overall`) and
    /// nothing ever lowered them again, so every player's rating was a one-way
    /// ratchet and, summed over 1 700 of them, so was the league's. Measured
    /// over `MultiSeasonSmokeTest` the league mean climbed +5.10 in five
    /// seasons and was still rising; the career harness's own decline slopes
    /// came out at −0.14 OVR/yr for a "standard" position where
    /// `DEVELOPMENT_NFL_REFERENCE.md` §1 calls for −2…−4 % (≈ −1.5…−3 OVR).
    ///
    /// Technique does not evaporate, but the athleticism it is executed with
    /// does: a 33-year-old corner's press and a 31-year-old back's elusiveness
    /// are the same skills applied by a slower body, and the position rating is
    /// what the game reads for them. So the same `count` / `range` /
    /// `declineProfile` machinery as the physical regression applies here,
    /// which keeps the RB/CB-cliff-vs-QB/OL-glide ordering intact.
    static func regressPositionAttributes(player: Player, count: Int, range: ClosedRange<Int>) {
        func drop(_ value: Int) -> Int { max(1, value - Int.random(in: range)) }

        // Which skills take the hit, chosen fresh each season.
        var slots = Array(0..<6).shuffled()
        slots = Array(slots.prefix(max(0, count)))
        func hit(_ index: Int, _ value: Int) -> Int { slots.contains(index) ? drop(value) : value }

        switch player.positionAttributes {
        case .quarterback(var a):
            a.armStrength = hit(0, a.armStrength)
            a.accuracyShort = hit(1, a.accuracyShort)
            a.accuracyMid = hit(2, a.accuracyMid)
            a.accuracyDeep = hit(3, a.accuracyDeep)
            a.pocketPresence = hit(4, a.pocketPresence)
            a.scrambling = hit(5, a.scrambling)
            player.positionAttributes = .quarterback(a)
        case .runningBack(var a):
            a.vision = hit(0, a.vision)
            a.elusiveness = hit(1, a.elusiveness)
            a.breakTackle = hit(2, a.breakTackle)
            a.receiving = hit(3, a.receiving)
            player.positionAttributes = .runningBack(a)
        case .wideReceiver(var a):
            a.routeRunning = hit(0, a.routeRunning)
            a.catching = hit(1, a.catching)
            a.release = hit(2, a.release)
            a.spectacularCatch = hit(3, a.spectacularCatch)
            player.positionAttributes = .wideReceiver(a)
        case .tightEnd(var a):
            a.blocking = hit(0, a.blocking)
            a.catching = hit(1, a.catching)
            a.routeRunning = hit(2, a.routeRunning)
            a.speed = hit(3, a.speed)
            player.positionAttributes = .tightEnd(a)
        case .offensiveLine(var a):
            a.runBlock = hit(0, a.runBlock)
            a.passBlock = hit(1, a.passBlock)
            a.pull = hit(2, a.pull)
            a.anchor = hit(3, a.anchor)
            player.positionAttributes = .offensiveLine(a)
        case .defensiveLine(var a):
            a.passRush = hit(0, a.passRush)
            a.blockShedding = hit(1, a.blockShedding)
            a.powerMoves = hit(2, a.powerMoves)
            a.finesseMoves = hit(3, a.finesseMoves)
            player.positionAttributes = .defensiveLine(a)
        case .linebacker(var a):
            a.tackling = hit(0, a.tackling)
            a.zoneCoverage = hit(1, a.zoneCoverage)
            a.manCoverage = hit(2, a.manCoverage)
            a.blitzing = hit(3, a.blitzing)
            player.positionAttributes = .linebacker(a)
        case .defensiveBack(var a):
            a.manCoverage = hit(0, a.manCoverage)
            a.zoneCoverage = hit(1, a.zoneCoverage)
            a.press = hit(2, a.press)
            a.ballSkills = hit(3, a.ballSkills)
            player.positionAttributes = .defensiveBack(a)
        case .kicking(var a):
            a.kickPower = hit(0, a.kickPower)
            a.kickAccuracy = hit(1, a.kickAccuracy)
            player.positionAttributes = .kicking(a)
        }
    }

    /// Regresses random mental attributes. Awareness and leadership are protected (regress last).
    static func regressMentalAttributes(player: Player, count: Int, range: ClosedRange<Int>) {
        // These regress first (least protected).
        var keyPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.clutch, \.decisionMaking, \.workEthic, \.coachability
        ]
        keyPaths.shuffle()
        // Awareness and leadership are appended last -- they regress only if count is very high.
        keyPaths.append(contentsOf: [\.awareness, \.leadership])

        for i in 0..<min(count, keyPaths.count) {
            let kp = keyPaths[i]
            let loss = Int.random(in: range)
            player.mental[keyPath: kp] = max(1, player.mental[keyPath: kp] - loss)
        }
    }

    // MARK: Mentoring Bonus Application

    /// Applies a set of mental attribute bonuses (positive or negative) to a player.
    static func applyMentalBonus(player: Player, totalPoints: Int, range: ClosedRange<Int>) {
        let keyPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.awareness, \.decisionMaking, \.clutch, \.workEthic, \.coachability, \.leadership
        ]

        let count = abs(totalPoints)
        let shuffled = keyPaths.shuffled()

        for i in 0..<min(count, shuffled.count) {
            let kp = shuffled[i]
            let delta = Int.random(in: range)
            let current = player.mental[keyPath: kp]
            player.mental[keyPath: kp] = max(1, min(99, current + delta))
        }
    }

    // MARK: Injury Descriptions

    static func minorInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "Sprained ankle", "Bruised ribs", "Mild hamstring strain",
            "Jammed finger", "Minor knee sprain", "Stinger"
        ]
        return injuries.randomElement()!
    }

    static func moderateInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "High ankle sprain", "MCL sprain", "Separated shoulder",
            "Hamstring tear", "Fractured hand", "Calf strain"
        ]
        return injuries.randomElement()!
    }

    static func majorInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "Torn ACL", "Broken collarbone", "Torn labrum",
            "Broken leg", "Lisfranc injury", "Torn pectoral"
        ]
        return injuries.randomElement()!
    }

    static func seasonEndingInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "Torn Achilles", "Torn ACL + MCL", "Compound fracture",
            "Spinal contusion", "Torn ACL and meniscus", "Dislocated hip"
        ]
        return injuries.randomElement()!
    }

    // NOTE: `estimatePlayingTimeShare` was deleted in phase 2 (plan §1.3
    // defect #6). It guessed playing time from OVR and yearsPro while
    // `gamesPlayedThisSeason` / `gamesStartedThisSeason` — and their
    // `PlayerSeasonHistory` snapshots — were already tracked and persisted, so
    // a 62-OVR every-down starter and a 62-OVR healthy scratch developed
    // identically. `realPlayingTimeShare(gamesStarted:gamesPlayed:positionCoach:)`
    // replaces it with the real counters.
}

// MARK: - Clamping Helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
