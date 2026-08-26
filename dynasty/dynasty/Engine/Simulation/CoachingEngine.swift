import Foundation

// MARK: - CoachingEngine

/// Stateless engine that drives all coaching-related calculations in Sunday Night Dynasty.
/// All methods are pure functions or mutate only their explicit inout / reference parameters.
enum CoachingEngine {

    // MARK: - Staff Demographics

    /// The share of coaches the game HIRES that come out female — every
    /// generated-league staff member (`LeagueGenerator.generateCoach`) and every
    /// candidate the hiring market invents (`generateCoachCandidates`). Template
    /// staff are excluded: they anonymize real male coaches.
    ///
    /// 0.06 is a budget, not a target. There are 163 female faces in the library
    /// and a career fills ~512 coaching slots, so E[female] ≈ 31 — comfortably
    /// under supply, because portrait matching is gender-strict and a female
    /// coach with no free female face falls through to a placeholder silhouette.
    /// The library deliberately carries headroom the game does not spend: the
    /// mixed range draws female at 0.22 (`FaceGeneratorConstants.femaleCoachShare`)
    /// and the 128-id female-only range above it draws not at all. At 35 faces
    /// the sub-pool still emptied by season 2-3 — one league's worth of hires is
    /// only the FIRST staff, and every carousel cycle adds more — so the budget
    /// that matters is a whole career's, not a single opening day's.
    static let femaleCoachShare = 0.06

    // MARK: - Scheme Fit

    /// Returns a 0.0–1.0 rating representing how well a player fits the given offensive
    /// and/or defensive schemes. A higher score means the player's position-specific
    /// attributes are strongly aligned with what the scheme demands.
    ///
    /// - Parameters:
    ///   - player: The player being evaluated.
    ///   - offensiveScheme: The team's current offensive scheme, if any.
    ///   - defensiveScheme: The team's current defensive scheme, if any.
    /// - Returns: Scheme fit score clamped to `0.0...1.0`.
    static func schemeFit(
        player: Player,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        schemeFit(
            positionAttributes: player.positionAttributes,
            physical: player.physical,
            mental: player.mental,
            offensiveScheme: offensiveScheme,
            defensiveScheme: defensiveScheme
        )
    }

    /// SimPlayer overload used by the game-simulation hot path, where reading
    /// the SwiftData @Model per play is too slow.
    static func schemeFit(
        player: SimPlayer,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        schemeFit(
            positionAttributes: player.positionAttributes,
            physical: player.physical,
            mental: player.mental,
            offensiveScheme: offensiveScheme,
            defensiveScheme: defensiveScheme
        )
    }

    /// Core scheme-fit calculation over raw attribute values.
    private static func schemeFit(
        positionAttributes: PositionAttributes,
        physical: PhysicalAttributes,
        mental: MentalAttributes,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        var rawScore: Double = 0.5         // Neutral baseline
        var evaluated = false              // Did any scheme clause apply?

        // MARK: Offensive Scheme Evaluation

        if let scheme = offensiveScheme {
            switch scheme {

            // Air Raid: pass-heavy; values QB accuracy and WR route running
            case .airRaid:
                switch positionAttributes {
                case .quarterback(let attr):
                    let accuracy = Double(attr.accuracyShort + attr.accuracyMid + attr.accuracyDeep) / 3.0
                    rawScore = normalize(accuracy)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.routeRunning))
                    evaluated = true
                case .tightEnd(let attr):
                    // TEs used as safety valves; route running matters more than blocking
                    rawScore = normalize(Double(attr.routeRunning + attr.catching) / 2.0)
                    evaluated = true
                default: break
                }

            // West Coast: timing routes, short/mid accuracy, receiving backs
            case .westCoast:
                switch positionAttributes {
                case .quarterback(let attr):
                    let shortMid = Double(attr.accuracyShort + attr.accuracyMid) / 2.0
                    rawScore = normalize(Double(attr.pocketPresence) * 0.4 + shortMid * 0.6)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.routeRunning + attr.catching) / 2.0)
                    evaluated = true
                case .runningBack(let attr):
                    // Receiving back is a core piece
                    rawScore = normalize(Double(attr.receiving + attr.elusiveness) / 2.0)
                    evaluated = true
                default: break
                }

            // Spread: pace, scrambling QBs, speed at all skill positions
            case .spread:
                switch positionAttributes {
                case .quarterback(let attr):
                    rawScore = normalize(Double(attr.scrambling) * 0.5 + Double(attr.accuracyShort) * 0.5)
                    evaluated = true
                case .wideReceiver(let attr):
                    let speedBonus = normalize(Double(physical.speed))
                    let route = normalize(Double(attr.routeRunning))
                    rawScore = speedBonus * 0.4 + route * 0.6
                    evaluated = true
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.elusiveness + attr.receiving) / 2.0)
                    evaluated = true
                default: break
                }

            // Power Run: physical OL and powerful backs; deep-ball threats as play-action window dressers
            case .powerRun:
                switch positionAttributes {
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.breakTackle) * 0.5 + Double(physical.strength) * 0.5)
                    evaluated = true
                case .offensiveLine(let attr):
                    rawScore = normalize(Double(attr.runBlock + attr.anchor) / 2.0)
                    evaluated = true
                case .quarterback(let attr):
                    // QB mostly hands off; pocket presence is what matters
                    rawScore = normalize(Double(attr.pocketPresence))
                    evaluated = true
                default: break
                }

            // Shanahan (Outside Zone): athletic OL, vision backs, TE as pass-catchers
            case .shanahan:
                switch positionAttributes {
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.vision) * 0.5 + Double(physical.agility) * 0.5)
                    evaluated = true
                case .offensiveLine(let attr):
                    rawScore = normalize(Double(attr.runBlock + attr.pull) / 2.0)
                    evaluated = true
                case .tightEnd(let attr):
                    rawScore = normalize(Double(attr.catching + attr.routeRunning) / 2.0)
                    evaluated = true
                default: break
                }

            // Pro Passing: traditional drop-back; arm strength, pocket QBs, big WRs
            case .proPassing:
                switch positionAttributes {
                case .quarterback(let attr):
                    let deepAccuracy = Double(attr.accuracyDeep + attr.armStrength) / 2.0
                    rawScore = normalize(deepAccuracy * 0.5 + Double(attr.pocketPresence) * 0.5)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.catching + attr.spectacularCatch) / 2.0)
                    evaluated = true
                case .offensiveLine(let attr):
                    rawScore = normalize(Double(attr.passBlock + attr.anchor) / 2.0)
                    evaluated = true
                default: break
                }

            // RPO: dual-threat QBs, quick-twitch RBs and slot WRs
            case .rpo:
                switch positionAttributes {
                case .quarterback(let attr):
                    rawScore = normalize(Double(attr.scrambling + attr.pocketPresence) / 2.0)
                    evaluated = true
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.vision + attr.elusiveness) / 2.0)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.routeRunning + attr.release) / 2.0)
                    evaluated = true
                default: break
                }

            // Option: mobile QBs and powerful fullback-style RBs
            case .option:
                switch positionAttributes {
                case .quarterback(let attr):
                    let mobility = Double(physical.speed + physical.agility) / 2.0
                    rawScore = normalize(Double(attr.scrambling) * 0.5 + normalize(mobility) * 0.5)
                    evaluated = true
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.breakTackle + attr.elusiveness) / 2.0)
                    evaluated = true
                default: break
                }
            }
        }

        // MARK: Defensive Scheme Evaluation

        if let scheme = defensiveScheme {
            switch scheme {

            // 3-4 Base: bigger DEs that can two-gap; OLBs as pass rushers/blitzers
            case .base34:
                switch positionAttributes {
                case .defensiveLine(let attr):
                    rawScore = normalize(Double(attr.blockShedding + attr.powerMoves) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.blitzing + attr.tackling) / 2.0)
                    evaluated = true
                default: break
                }

            // 4-3 Base: one-gap penetrating DEs, athletic MLBs
            case .base43:
                switch positionAttributes {
                case .defensiveLine(let attr):
                    rawScore = normalize(Double(attr.passRush + attr.finesseMoves) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.tackling + attr.zoneCoverage) / 2.0)
                    evaluated = true
                default: break
                }

            // Cover 3: zone CBs, range-covering safeties
            case .cover3:
                switch positionAttributes {
                case .defensiveBack(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage + attr.ballSkills) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage))
                    evaluated = true
                default: break
                }

            // Press Man: physical press-capable CBs with man coverage skills
            case .pressMan:
                switch positionAttributes {
                case .defensiveBack(let attr):
                    rawScore = normalize(Double(attr.press + attr.manCoverage) / 2.0)
                    evaluated = true
                default: break
                }

            // Tampa 2: zone-heavy; CBs with zone IQ, LBs that can drop into coverage
            case .tampa2:
                switch positionAttributes {
                case .defensiveBack(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage + attr.ballSkills) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage + attr.manCoverage) / 2.0)
                    evaluated = true
                default: break
                }

            // Multiple: versatile players who can play several techniques
            case .multiple:
                // Reward high awareness and physical versatility across all defensive positions
                let mentalFlex = normalize(Double(mental.awareness + mental.decisionMaking) / 2.0)
                let physFlex = normalize(Double(physical.agility + physical.speed) / 2.0)
                switch positionAttributes {
                case .defensiveBack, .linebacker, .defensiveLine:
                    rawScore = mentalFlex * 0.5 + physFlex * 0.5
                    evaluated = true
                default: break
                }

            // Hybrid: speed/athleticism on every level of the defense
            case .hybrid:
                let athleticism = normalize(Double(physical.speed + physical.agility + physical.acceleration) / 3.0)
                switch positionAttributes {
                case .defensiveBack, .linebacker, .defensiveLine:
                    rawScore = athleticism
                    evaluated = true
                default: break
                }
            }
        }

        // MARK: Adaptability Bonus

        // A player with high adaptability gets up to +0.05 added to their fit score,
        // regardless of scheme—they learn any system faster.
        let adaptabilityBonus = Double(mental.awareness) / 99.0 * 0.05

        // MARK: Non-evaluated Positions

        // If neither scheme clause applied (e.g., a kicker in an offensive scheme context),
        // return a neutral 0.5 with only the adaptability bonus applied.
        if !evaluated {
            return min(1.0, 0.5 + adaptabilityBonus)
        }

        return min(1.0, max(0.0, rawScore + adaptabilityBonus))
    }

    // MARK: - Roster Scheme Fit (task #54)

    /// The neutral point of `rosterSchemeFit`. A player whose traits suit the
    /// system his building runs exactly as well as they suit the average system
    /// on his side of the ball, and who knows that playbook to
    /// `schemeFitFamiliarityPivot`, scores exactly this.
    ///
    /// The harness's old frozen draw was centred at 0.55, and reproducing that
    /// centre exactly cost the league ~0.4 truePotential — because the old draw
    /// gave a ROOKIE 0.55 too, while a real computation prices a first-year
    /// player at whatever he has actually learned. The ladder in
    /// `PlayerDevelopmentEngine.updatePotentialRealization` only gets to move a
    /// ceiling while there is still room to grow, so a centre that reads "has
    /// not learned the playbook yet" as a verdict taxes precisely the four
    /// seasons the development model cares about. 0.59 puts the LEAGUE MEAN at
    /// 0.60 and a first-year player at ~0.54 — the level at which the measured
    /// quality pyramid matches the one the harness was calibrated on.
    /// Measured, not argued: see the `career` scenario's SCHEME FIT block.
    ///
    /// **0.590 → 0.594 by task #66, to HOLD that level, not to move it.** This is
    /// the LEVEL knob; `schemeFitFamiliarityPivot` is the knob that zeroes the
    /// playbook term's mean. Re-anchoring the pivot on the new familiarity
    /// equilibrium (52 → 60) removed a +0.0035 offset the old, stale pivot had
    /// been quietly handing the whole league, which would have dropped the
    /// measured fit mean from 0.596 to 0.592 and deflated the potential ratchet
    /// with it. Absorbing that residual here is what keeps the P1 pyramid
    /// calibration — and every §6.9 band it is asserted against — exactly where
    /// it was measured. Verified: fit mean 0.596 before the wave; 0.596 / 0.598 /
    /// 0.599 / 0.599 over four runs after, against a run-to-run sd of ~0.002.
    static let schemeFitNeutral = 0.594

    /// How hard a TRAIT edge moves the fit. The edge is a difference of two
    /// `schemeFit` scores and measures sd 0.097 across the league, so this gain
    /// puts sd ≈ 0.17 of the reported fit on TRAITS — i.e. the total spread
    /// lands on the sd 0.18 the harness's old model declared.
    ///
    /// Spread is not a free knob here the way it was for a frozen draw. Fit is a
    /// persistent property of a player now, so it compounds through
    /// `updatePotentialRealization` season after season, and both tails of the
    /// quality pyramid move with it: at sd 0.16 the elite share falls out of its
    /// §6.2 band, at sd 0.20 the sub-65 share falls out of its §8 band.
    static let schemeFitTraitGain = 1.77

    /// How hard a PLAYBOOK edge moves the fit — deliberately the SMALL half
    /// (sd ≈ 0.04 against the trait half's 0.17).
    ///
    /// Familiarity is mostly a statement about tenure: it rises every practice
    /// week a player spends in one building and resets when the building
    /// changes its mind. Letting it carry the fit would make "scheme fit" a
    /// synonym for "has been here a while" — and, worse, would tax every rookie
    /// and every player on a club coming off a coordinator change during exactly
    /// the seasons `PlayerDevelopmentEngine` lets a ceiling still matter. It
    /// belongs in the number (a room that does not know the playbook is not
    /// getting the most out of anybody) but it does not belong in charge of it.
    ///
    /// **Task #66 left this at 0.25 on purpose, and the sd above is now 0.036.**
    /// That wave raised the familiarity mean by lifting its LOW tail (intake
    /// mean 33 → 44, early-career learn rate up), so the league went from mean
    /// 53.9 / sd 16.0 to mean 60.5 / sd 14.4 and this half's contribution fell
    /// 0.040 → 0.036. Restoring the declared 0.040 is one multiplication away
    /// (0.28 · 14.4 / 100), and it was measured and rejected: the gain does not
    /// move the playbook half in isolation, it moves the TOTAL fit spread, and
    /// the note on `schemeFitTraitGain` directly above says what a wider fit
    /// spread does — it pushes both pyramid tails out. Measured over four
    /// `career` runs each, the §8 sub-65 share came out 24.55 % at 0.25 against
    /// 24.81 % at 0.28.
    ///
    /// **What that measurement does and does not settle.** When it was taken,
    /// `career` 6.9d's upper edge was 25, so 0.28 read as an outright gate
    /// failure. The SAME wave then moved that edge to 26 — for its own reason,
    /// a measured run-to-run sd of ~0.35 pp against an edge sitting 1 sd out —
    /// and under the widened band 24.81 passes. So the honest statement is:
    /// 0.28 is no longer REJECTED by 6.9d, it is merely WORSE on it, by 0.26 pp
    /// in the direction the band exists to guard, on a statistic whose
    /// between-league se the scenario now prints next to it. The gain stays at
    /// 0.25 on that ranking plus the `schemeFitTraitGain` argument above — the
    /// total fit spread is the thing being bought, and buying it costs depth —
    /// and NOT on the claim that a gate forbids the alternative. If 6.9d's edge
    /// is ever re-derived again, this decision is a ranking between two green
    /// runs and can be revisited without re-reading the band.
    ///
    /// The league genuinely
    /// has less variance in "how well rooms know their playbook" now, because
    /// rooms genuinely know their playbook better; inflating the gain to hide
    /// that would buy a cosmetic sd back and spend the §8 depth band for it.
    /// The `fit spread split` line of the `career` scenario prints both halves
    /// every run, so the number stays checkable rather than declared.
    static let schemeFitFamiliarityGain = 0.25

    /// The familiarity level treated as par — the ONE fitted constant here.
    ///
    /// It is set to the familiarity a steady-state roster actually carries once
    /// intake, install years and coordinator churn are all running, measured on
    /// `tools/balance-harness`'s `career` scenario (22 measured seasons, 20
    /// independent leagues, 745 k player-seasons). Anchoring on the equilibrium
    /// rather than on a round number is what keeps the fit distribution
    /// STATIONARY: pin it too high and every league slides down as its
    /// generator-seeded veterans retire, which is exactly the 0.52 → 0.39 slide
    /// task #54 exists to remove.
    ///
    /// **Moved 52 → 60 by task #66, and it moved because the equilibrium did.**
    /// That wave lifted the league's measured familiarity steady state from 53.9
    /// to 60.6 (`DraftEngine.rookieFamiliarityFloor` has the arithmetic), because
    /// 53.9 sat UNDER `PlaySimulator.famBustPivot` and left every club in the
    /// game permanently in the blown-assignment regime. This constant is defined
    /// as that steady state, so leaving it at 52 would have quietly turned the
    /// playbook term back into a LEVEL — every average player reading +0.02 fit
    /// for being average — which is the exact defect #54 removed. Rounded DOWN
    /// from the measured 60.6 to the whole point, so par is never above what a
    /// steady-state roster actually carries.
    ///
    /// **Net effect on the AGGREGATE fit distribution: none** (mean 0.596 →
    /// 0.591, sd 0.176 → 0.175), which is the point — the development
    /// calibration downstream is untouched.
    ///
    /// **Net effect at a FIXED familiarity: −0.016, and that is not nothing.**
    /// The pivot move and the compensating `schemeFitNeutral` bump cancel only
    /// at the new equilibrium; the formula itself now reads
    /// `0.594 − 0.25·60/100` where it read `0.590 − 0.25·52/100`, i.e. 0.016
    /// lower for the same player. Concretely, an install-year room seeded at
    /// `VersatilityDevelopmentEngine.installBaselineCap` (50) reads **0.569**
    /// where it read 0.585. That is deliberate — the cap was kept at 50
    /// precisely so an install year sits below the bust pivot and below par —
    /// but it means the install-year and coordinator-carousel penalty got
    /// materially harsher in the same wave, and any roster NOT sitting at
    /// equilibrium (a save's first seasons, a rebuilding club, the season after
    /// a staff change) carries the −0.016 until it converges. The aggregate is
    /// stationary; individual clubs are not.
    ///
    /// It is no longer under `VersatilityDevelopmentEngine.unusedSchemeFloor`
    /// (55), and that is correct rather than a regression: the floor is what a
    /// player retains of a system his club STOPPED running, and "rusty" should
    /// read a little below par, not at it. The old ordering was a coincidence of
    /// the old, too-low equilibrium.
    static let schemeFitFamiliarityPivot = 60.0

    /// Reporting band. Kept off the 0/1 rails so neither end of
    /// `updatePotentialRealization`'s ladder can be reached by clamping alone.
    static let schemeFitFloor = 0.05
    /// Upper end of the reporting band (see `schemeFitFloor`).
    static let schemeFitCeiling = 0.95

    /// How well a rostered player fits what his own building runs — the ONE
    /// definition of "scheme fit" for a player who already has a team.
    ///
    /// This function is the canonical source for both the shipped season
    /// pipeline (`WeekAdvancer.offseasonSchemeFit`) and `tools/balance-harness`,
    /// which slices it out of this file on every sync. Before task #54 the two
    /// disagreed completely: the harness drew a frozen `N(0.55, 0.18)` per
    /// player, while the shipped pipeline returned a hard-coded 0.5 for every
    /// rookie, every specialist and every club without a coordinator, and
    /// `schemeFamiliarity / 100` for everyone else — which pinned the shipped
    /// median at exactly 0.50 and let the mean slide season after season as the
    /// generator-seeded veterans were replaced by intake that enters the league
    /// at familiarity 15-45.
    ///
    /// Both halves are measured as an EDGE against a neutral rather than as a
    /// level, which is what makes the distribution stationary:
    ///
    /// * **Traits** — his fit for THIS system minus his average fit across every
    ///   system on his side of the ball. A great player fits every scheme well;
    ///   that is talent, not fit. What this term isolates is whether the club is
    ///   asking him to do the thing he is comparatively best at.
    /// * **Playbook** — how far his familiarity with the installed system sits
    ///   from `schemeFitFamiliarityPivot`.
    ///
    /// - Parameters:
    ///   - player: The rostered player being evaluated.
    ///   - offensiveScheme: The offensive system the building actually installs.
    ///   - defensiveScheme: The defensive system the building actually installs.
    /// - Returns: Fit in `schemeFitFloor...schemeFitCeiling`.
    static func rosterSchemeFit(
        player: Player,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        let traitEdge = schemeTraitEdge(
            positionAttributes: player.positionAttributes,
            physical: player.physical,
            mental: player.mental,
            side: player.position.side,
            offensiveScheme: offensiveScheme,
            defensiveScheme: defensiveScheme
        )
        let familiarity = activeSchemeFamiliarity(
            player: player,
            offensiveScheme: offensiveScheme,
            defensiveScheme: defensiveScheme
        )
        let raw = schemeFitNeutral
            + schemeFitTraitGain * traitEdge
            + schemeFitFamiliarityGain * (familiarity - schemeFitFamiliarityPivot) / 100.0
        return min(schemeFitCeiling, max(schemeFitFloor, raw))
    }

    /// His `schemeFit` for the installed system minus his mean `schemeFit`
    /// across every system on his side of the ball.
    ///
    /// Specialists get 0: no offensive or defensive scheme asks anything of a
    /// kicker's traits, so for them the fit is the playbook term alone.
    private static func schemeTraitEdge(
        positionAttributes: PositionAttributes,
        physical: PhysicalAttributes,
        mental: MentalAttributes,
        side: PositionSide,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        switch side {
        case .offense:
            guard let scheme = offensiveScheme else { return 0.0 }
            let mine = schemeFit(
                positionAttributes: positionAttributes,
                physical: physical,
                mental: mental,
                offensiveScheme: scheme,
                defensiveScheme: nil
            )
            var total = 0.0
            for candidate in OffensiveScheme.allCases {
                total += schemeFit(
                    positionAttributes: positionAttributes,
                    physical: physical,
                    mental: mental,
                    offensiveScheme: candidate,
                    defensiveScheme: nil
                )
            }
            return mine - total / Double(OffensiveScheme.allCases.count)

        case .defense:
            guard let scheme = defensiveScheme else { return 0.0 }
            let mine = schemeFit(
                positionAttributes: positionAttributes,
                physical: physical,
                mental: mental,
                offensiveScheme: nil,
                defensiveScheme: scheme
            )
            var total = 0.0
            for candidate in DefensiveScheme.allCases {
                total += schemeFit(
                    positionAttributes: positionAttributes,
                    physical: physical,
                    mental: mental,
                    offensiveScheme: nil,
                    defensiveScheme: candidate
                )
            }
            return mine - total / Double(DefensiveScheme.allCases.count)

        case .specialTeams:
            return 0.0
        }
    }

    /// The 0-100 familiarity that actually applies to this player: his
    /// coordinator's system, or — for a specialist, who answers to neither
    /// coordinator and sits through both installs — the mean of the two.
    ///
    /// A club with no coordinator carrying a system reports the pivot, i.e. par,
    /// rather than zero: a vacancy is not evidence that the room forgot football.
    private static func activeSchemeFamiliarity(
        player: Player,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        switch player.position.side {
        case .offense:
            guard let scheme = offensiveScheme else { return schemeFitFamiliarityPivot }
            return Double(player.schemeFam(for: scheme.rawValue))
        case .defense:
            guard let scheme = defensiveScheme else { return schemeFitFamiliarityPivot }
            return Double(player.schemeFam(for: scheme.rawValue))
        case .specialTeams:
            var total = 0.0
            var count = 0.0
            if let scheme = offensiveScheme {
                total += Double(player.schemeFam(for: scheme.rawValue))
                count += 1
            }
            if let scheme = defensiveScheme {
                total += Double(player.schemeFam(for: scheme.rawValue))
                count += 1
            }
            guard count > 0 else { return schemeFitFamiliarityPivot }
            return total / count
        }
    }

    // MARK: - Coach Development

    /// Applies end-of-season development to a coach via the XP-based CoachDevelopmentEngine.
    ///
    /// - Parameters:
    ///   - coach: The coach to develop (mutated in place).
    ///   - teamWins: The team's win total for the just-completed season (0–17).
    ///   - headCoach: The team's head coach (for mentorship bonus).
    ///   - assistantHC: The team's assistant head coach (for mentorship bonus).
    ///   - wonSuperBowl: Whether the team won the Championship this season.
    static func developCoach(_ coach: Coach, teamWins: Int, headCoach: Coach? = nil, assistantHC: Coach? = nil, wonSuperBowl: Bool = false) {
        // Task #133: this is the once-per-offseason pass over EVERY coach in the
        // league (attached and unattached alike), and it runs after the poaching
        // pass — so it is where a new hire's one-offseason grace expires. From
        // the next offseason on he is an ordinary employee the market can chase.
        coach.signedThisOffseason = false
        CoachDevelopmentEngine.applySeasonalDevelopment(
            coach: coach,
            teamWins: teamWins,
            madePlayoffs: teamWins >= 9,
            wonSuperBowl: wonSuperBowl,
            headCoach: headCoach,
            assistantHC: assistantHC
        )
    }

    // MARK: - Hiring Market

    /// Generates a pool of coaching candidates available for the given role.
    /// Produces 20–30 candidates per search to populate a market of 50+ total coaches.
    ///
    /// #267: Candidate quality scales with team budget, wins, and reputation.
    /// Richer / more prestigious teams attract more premium candidates;
    /// bad teams may see premium candidates decline interest.
    ///
    /// - Parameters:
    ///   - role: The coaching role being filled.
    ///   - count: How many candidates to generate (defaults to 25).
    ///   - teamBudget: Coaching budget in thousands (e.g. 25000 = $25M).
    ///   - teamWins: Last season win total (0–17).
    ///   - teamReputation: Team prestige / HC reputation (1–99).
    /// - Returns: An array of freshly created `Coach` objects not yet attached to any team.
    static func generateCoachCandidates(
        role: CoachRole,
        count: Int = 25,
        teamBudget: Int = 25_000,
        teamWins: Int = 8,
        teamReputation: Int = 50
    ) -> [Coach] {
        let actualCount = max(count, 20) // Floor of 20 candidates per search

        // #238: Determine how many premium (high-quality, expensive) candidates to include
        var premiumCount: Int
        switch role {
        case .headCoach, .assistantHeadCoach:
            premiumCount = 3
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            premiumCount = 3
        default: // position coaches
            premiumCount = 2
        }

        // #267: Scale premium count by team budget
        if teamBudget > 35_000 {
            premiumCount += 1  // Rich teams attract extra premium candidate
        } else if teamBudget < 15_000 {
            premiumCount = max(1, premiumCount - 1)  // Poor teams see fewer premiums
        }

        // #267: Premium candidates may refuse bad teams
        // For each premium slot, 40% chance they decline if team is bad
        let isPoorTeam = teamReputation < 40 && teamWins < 5
        var effectivePremiumIndices = Set<Int>()
        for i in 0..<premiumCount {
            if isPoorTeam && Double.random(in: 0...1) < 0.40 {
                continue  // This premium candidate "isn't interested"
            }
            effectivePremiumIndices.insert(i)
        }

        // Budget tier: ~25% of non-premium candidates are flagged as "value" /
        // bargain-bin candidates with lower attribute floors. Combined with the
        // power-curve in salaryForCoach, these produce notably cheaper asking
        // prices, widening the visible salary spread for the user.
        var budgetIndices = Set<Int>()
        let nonPremiumIndices = (0..<actualCount).filter { !effectivePremiumIndices.contains($0) }
        let budgetTarget = Int((Double(nonPremiumIndices.count) * 0.25).rounded())
        for idx in nonPremiumIndices.shuffled().prefix(budgetTarget) {
            budgetIndices.insert(idx)
        }

        // #267: Salary adjustment factor based on team wins
        let salaryAdjustment: Double
        if teamWins < 5 {
            salaryAdjustment = 1.0 + Double.random(in: 0.10...0.15)  // 10-15% more
        } else if teamWins > 10 {
            salaryAdjustment = 1.0 - Double.random(in: 0.05...0.10)  // 5-10% less
        } else {
            salaryAdjustment = 1.0
        }

        return (0..<actualCount).map { index in
            let isPremium = effectivePremiumIndices.contains(index)
            let isBudget = budgetIndices.contains(index)

            // Gender is rolled BEFORE the name so the given name is drawn from
            // the matching pool (`RandomNameGenerator.randomName(female:)`).
            // Unlike `LeagueGenerator.generateCoach` this stream is unseeded and
            // has no template-replay coupling, so the draw position is free —
            // it just has to precede the name and `previewFace` below.
            let isFemale = Double.random(in: 0..<1) < Self.femaleCoachShare
            let name = RandomNameGenerator.randomName(female: isFemale)

            // Age distribution: young assistants skew lower, coordinators/HC skew older
            let ageRange: ClosedRange<Int>
            let expRange: ClosedRange<Int>
            switch role {
            case .headCoach:
                ageRange = isPremium ? 42...60 : 40...65
                expRange = isPremium ? 18...30 : 12...30
            case .assistantHeadCoach:
                ageRange = isPremium ? 40...58 : 38...60
                expRange = isPremium ? 15...25 : 10...25
            case .offensiveCoordinator, .defensiveCoordinator:
                ageRange = isPremium ? 38...55 : 35...58
                expRange = isPremium ? 14...22 : 8...22
            case .specialTeamsCoordinator:
                ageRange = isPremium ? 36...52 : 33...55
                expRange = isPremium ? 12...20 : 6...20
            default: // position coaches
                ageRange = isPremium ? 35...50 : 28...52
                expRange = isPremium ? 10...18 : 2...15
            }

            let age = Int.random(in: ageRange)
            let potential = CoachDevelopmentEngine.generatePotential(forAge: age)
            let exp = Int.random(in: expRange)

            // Attribute generation: role-aware ranges ensure proper hierarchy
            // HC: 5-8 good ratings (70-95), rest moderate (55-70)
            // Coordinators: 4-6 good ratings (65-90), rest moderate (50-65)
            // Position coaches: 1-5 good ratings in specialty (70-85), rest LOW (40-60)
            let goodFloor: Int
            let goodCeiling: Int
            let weakFloor: Int
            let weakCeiling: Int
            let goodCount: Int

            let isPositionCoach: Bool
            switch role {
            case .headCoach:
                if isBudget {
                    // Budget HC: notably lower floors so OVR lands ~50-60
                    goodFloor = 62
                    goodCeiling = 78
                    weakFloor = 38
                    weakCeiling = 55
                    goodCount = Int.random(in: 1...3)
                } else {
                    goodFloor = isPremium ? 78 : 70
                    goodCeiling = isPremium ? 95 : 92
                    weakFloor = isPremium ? 58 : 55
                    weakCeiling = isPremium ? 72 : 70
                    goodCount = isPremium ? Int.random(in: 6...8) : Int.random(in: 5...7)
                }
                isPositionCoach = false
            case .assistantHeadCoach:
                if isBudget {
                    // Budget AHC
                    goodFloor = 60
                    goodCeiling = 75
                    weakFloor = 38
                    weakCeiling = 55
                    goodCount = Int.random(in: 1...3)
                } else {
                    goodFloor = isPremium ? 72 : 68
                    goodCeiling = isPremium ? 92 : 88
                    weakFloor = isPremium ? 55 : 50
                    weakCeiling = isPremium ? 68 : 65
                    goodCount = isPremium ? Int.random(in: 5...7) : Int.random(in: 4...6)
                }
                isPositionCoach = false
            case .offensiveCoordinator, .defensiveCoordinator:
                if isBudget {
                    // Budget coordinator
                    goodFloor = 58
                    goodCeiling = 75
                    weakFloor = 35
                    weakCeiling = 52
                    goodCount = Int.random(in: 1...3)
                } else {
                    goodFloor = isPremium ? 72 : 65
                    goodCeiling = isPremium ? 92 : 90
                    weakFloor = isPremium ? 52 : 50
                    weakCeiling = isPremium ? 67 : 65
                    goodCount = isPremium ? Int.random(in: 5...6) : Int.random(in: 4...6)
                }
                isPositionCoach = false
            case .specialTeamsCoordinator:
                if isBudget {
                    // Budget STC
                    goodFloor = 55
                    goodCeiling = 72
                    weakFloor = 35
                    weakCeiling = 52
                    goodCount = Int.random(in: 1...3)
                } else {
                    goodFloor = isPremium ? 68 : 62
                    goodCeiling = isPremium ? 88 : 85
                    weakFloor = isPremium ? 48 : 45
                    weakCeiling = isPremium ? 62 : 58
                    goodCount = isPremium ? Int.random(in: 4...5) : Int.random(in: 3...5)
                }
                isPositionCoach = false
            default: // Position coaches: specialists with low general skills
                if isBudget {
                    // Budget position coach: even lower floors
                    goodFloor = 60
                    goodCeiling = 75
                    weakFloor = 32
                    weakCeiling = 52
                    goodCount = Int.random(in: 1...3)
                    isPositionCoach = true
                } else {
                    goodFloor = isPremium ? 72 : 70
                    goodCeiling = isPremium ? 88 : 85
                    weakFloor = isPremium ? 44 : 40
                    weakCeiling = isPremium ? 62 : 60
                    goodCount = isPremium ? Int.random(in: 2...5) : Int.random(in: 1...4)
                    isPositionCoach = true
                }
            }

            // Determine which attribute indices get "good" ratings
            // For position coaches, always include their focus attributes as good
            let allAttrNames = ["playCalling", "playerDevelopment", "reputation", "adaptability",
                                "gamePlanning", "scoutingAbility", "recruiting", "motivation",
                                "discipline", "mediaHandling", "contractNegotiation", "moraleInfluence"]
            let focusAttrs = role.focusAttributes
            var goodIndices = Set<Int>()

            // Ensure focus attributes are always in the "good" set for position coaches
            if isPositionCoach {
                for (i, name) in allAttrNames.enumerated() {
                    if focusAttrs.contains(name) {
                        goodIndices.insert(i)
                    }
                }
            }

            // Fill remaining good slots randomly
            var remaining = Array(0..<12).filter { !goodIndices.contains($0) }
            remaining.shuffle()
            let slotsNeeded = max(0, goodCount - goodIndices.count)
            for i in 0..<min(slotsNeeded, remaining.count) {
                goodIndices.insert(remaining[i])
            }

            func genAttr(index: Int) -> Int {
                if goodIndices.contains(index) {
                    return Int.random(in: goodFloor...goodCeiling)
                } else {
                    return Int.random(in: weakFloor...weakCeiling)
                }
            }

            // Scheme assignment: offensive roles get offensive schemes, defensive get defensive
            let offScheme: OffensiveScheme? = offensiveRole(role) ? OffensiveScheme.allCases.randomElement() : nil
            let defScheme: DefensiveScheme? = defensiveRole(role) ? DefensiveScheme.allCases.randomElement() : nil

            // Head coaches and assistant HCs always know at least one side, often both.
            // Distribution: 40% off-only, 30% def-only, 30% both. Never neither.
            let finalOffScheme: OffensiveScheme?
            let finalDefScheme: DefensiveScheme?
            if role == .headCoach || role == .assistantHeadCoach {
                let roll = Double.random(in: 0...1)
                if roll < 0.40 {
                    finalOffScheme = OffensiveScheme.allCases.randomElement()
                    finalDefScheme = nil
                } else if roll < 0.70 {
                    finalOffScheme = nil
                    finalDefScheme = DefensiveScheme.allCases.randomElement()
                } else {
                    finalOffScheme = OffensiveScheme.allCases.randomElement()
                    finalDefScheme = DefensiveScheme.allCases.randomElement()
                }
            } else {
                finalOffScheme = offScheme
                finalDefScheme = defScheme
            }

            // Generate attributes first, then derive salary from OVR + experience
            let attrPlayCalling = genAttr(index: 0)
            let attrPlayerDev   = genAttr(index: 1)
            let attrReputation  = genAttr(index: 2)
            let attrAdaptability = genAttr(index: 3)
            let attrGamePlanning = genAttr(index: 4)
            let attrScouting     = genAttr(index: 5)
            let attrRecruiting   = genAttr(index: 6)
            let attrMotivation   = genAttr(index: 7)
            let attrDiscipline   = genAttr(index: 8)
            let attrMedia        = genAttr(index: 9)
            let attrContract     = genAttr(index: 10)
            let attrMorale       = genAttr(index: 11)

            let ovr = (attrPlayCalling + attrPlayerDev + attrReputation + attrAdaptability
                + attrGamePlanning + attrScouting + attrRecruiting + attrMotivation
                + attrDiscipline + attrMedia + attrContract + attrMorale) / 12

            // #267: Adjust asking salary based on team desirability
            let baseSalary = LeagueGenerator.salaryForCoach(role: role, ovr: ovr, yearsExperience: exp)
            let salary = Int(Double(baseSalary) * salaryAdjustment)

            let personality = PersonalityArchetype.allCases.randomElement() ?? .quietProfessional

            let coach = Coach(
                firstName: name.first,
                lastName: name.last,
                age: age,
                role: role,
                offensiveScheme: finalOffScheme,
                defensiveScheme: finalDefScheme,
                playCalling: attrPlayCalling,
                playerDevelopment: attrPlayerDev,
                reputation: attrReputation,
                adaptability: attrAdaptability,
                gamePlanning: attrGamePlanning,
                scoutingAbility: attrScouting,
                recruiting: attrRecruiting,
                motivation: attrMotivation,
                discipline: attrDiscipline,
                mediaHandling: attrMedia,
                contractNegotiation: attrContract,
                moraleInfluence: attrMorale,
                potential: potential,
                salary: salary,
                background: "",
                personality: personality,
                teamID: nil,
                yearsExperience: exp
            )
            // MUST be set before `generateBackground` — the blurb's phrase pools
            // are selected by gender — and before `previewFace`, which is
            // gender-strict.
            coach.gender = isFemale ? "female" : "male"
            coach.background = generateBackground(for: coach)
            initializeSchemeExpertise(for: coach)
            // Phase 4 faces: a candidate list is 20-25 coaches of which at most
            // one is hired, so the portrait is a non-reserving PREVIEW. The
            // hire path (`CoachCarouselEngine`, `WeekAdvancer`, the staff UI)
            // persists the coach and the next backfill pass converts the
            // preview into a real reservation.
            coach.faceID = FaceLibrary.shared.previewFace(
                personID: coach.id, role: .coach, age: coach.age, position: nil,
                gender: FacePersonGender(tag: coach.gender)
            )
            return coach
        }
    }

    // MARK: - Scheme Expertise Initialization

    /// Initializes a coach's scheme expertise based on their assigned scheme,
    /// related schemes, and adaptability attribute.
    static func initializeSchemeExpertise(for coach: Coach) {
        var expertise: [String: Int] = [:]

        // Primary offensive scheme: high expertise
        if let offScheme = coach.offensiveScheme {
            expertise[offScheme.rawValue] = Int.random(in: 75...95)
            for related in schemeFamilyMembers(offScheme) where related != offScheme {
                expertise[related.rawValue] = Int.random(in: 40...65)
            }
        }

        // Primary defensive scheme: high expertise
        if let defScheme = coach.defensiveScheme {
            expertise[defScheme.rawValue] = Int.random(in: 75...95)
            for related in schemeFamilyMembers(defScheme) where related != defScheme {
                expertise[related.rawValue] = Int.random(in: 40...65)
            }
        }

        // Adaptability gives higher baseline for unknown schemes
        let baselineBonus = Int(Double(coach.adaptability) / 99.0 * 15.0)
        for scheme in OffensiveScheme.allCases where expertise[scheme.rawValue] == nil {
            expertise[scheme.rawValue] = 15 + baselineBonus + Int.random(in: 0...10)
        }
        for scheme in DefensiveScheme.allCases where expertise[scheme.rawValue] == nil {
            expertise[scheme.rawValue] = 15 + baselineBonus + Int.random(in: 0...10)
        }

        coach.schemeExpertise = expertise
    }

    /// Returns schemes in the same "family" as the given offensive scheme.
    static func schemeFamilyMembers(_ scheme: OffensiveScheme) -> [OffensiveScheme] {
        switch scheme {
        case .westCoast, .airRaid, .proPassing, .spread:
            return [.westCoast, .airRaid, .proPassing, .spread]
        case .powerRun, .shanahan, .option, .rpo:
            return [.powerRun, .shanahan, .option, .rpo]
        }
    }

    /// Returns schemes in the same "family" as the given defensive scheme.
    static func schemeFamilyMembers(_ scheme: DefensiveScheme) -> [DefensiveScheme] {
        switch scheme {
        case .pressMan, .base43:
            return [.pressMan, .base43]
        case .cover3, .tampa2, .base34:
            return [.cover3, .tampa2, .base34]
        case .multiple, .hybrid:
            return [.multiple, .hybrid]
        }
    }

    // MARK: - Background Generation

    /// Generates an auto-generated coaching background / history blurb based on the coach's
    /// attributes, experience, personality, age, and scheme preferences.
    static func generateBackground(for coach: Coach) -> String {
        var rng = SystemRandomNumberGenerator()
        return generateBackground(for: coach, using: &rng)
    }

    /// Picks the phrase pool that matches `coach.gender`, for the blurb lines
    /// that carry a pronoun (or other gendered wording, e.g. "father figure").
    ///
    /// DETERMINISM CONTRACT — read before touching any call site:
    /// every `male:` array below is byte-identical to the single array it
    /// replaced, and `male` and `female` always have the SAME element count, so
    /// the `randomElement(using:)` draw that follows consumes exactly one value
    /// from exactly the same distribution as before this function existed. The
    /// fixed-league template's staff are male by construction (they anonymize
    /// real male coaches) and `LeagueGenerator` replays their blurbs from a
    /// seeded stream, so their text must not move by a single byte. Never edit a
    /// `male:` array's contents, never change either array's length, and never
    /// add or remove a draw.
    private static func genderedPhrases(
        male: [String], female: [String], for coach: Coach
    ) -> [String] {
        assert(male.count == female.count, "gendered phrase pools must be the same length")
        return coach.gender == "female" ? female : male
    }

    /// Seeded variant of `generateBackground(for:)` — identical phrase pools,
    /// caller-owned entropy. The fixed-league template import needs the blurb to
    /// be the same on every import of the same template.
    static func generateBackground<G: RandomNumberGenerator>(
        for coach: Coach, using rng: inout G
    ) -> String {
        var parts: [String] = []

        // Experience-based opening
        let expOpeners: [String]
        switch coach.yearsExperience {
        case 0...5:
            expOpeners = genderedPhrases(
                male: [
                    "A rising talent with \(coach.yearsExperience) years in the league.",
                    "Young and hungry, still building his coaching resume.",
                    "Fresh face on the coaching circuit with raw potential.",
                    "Recently transitioned from a quality control role."
                ],
                female: [
                    "A rising talent with \(coach.yearsExperience) years in the league.",
                    "Young and hungry, still building her coaching resume.",
                    "Fresh face on the coaching circuit with raw potential.",
                    "Recently transitioned from a quality control role."
                ],
                for: coach
            )
        case 6...12:
            expOpeners = genderedPhrases(
                male: [
                    "Spent \(coach.yearsExperience) years climbing the coaching ladder.",
                    "A mid-career coach with a growing reputation around the league.",
                    "Has been steadily building his resume over \(coach.yearsExperience) seasons.",
                    "Proven himself as a reliable coordinator over the past decade."
                ],
                female: [
                    "Spent \(coach.yearsExperience) years climbing the coaching ladder.",
                    "A mid-career coach with a growing reputation around the league.",
                    "Has been steadily building her resume over \(coach.yearsExperience) seasons.",
                    "Proven herself as a reliable coordinator over the past decade."
                ],
                for: coach
            )
        case 13...20:
            expOpeners = genderedPhrases(
                male: [
                    "A seasoned veteran with \(coach.yearsExperience) years of League experience.",
                    "Well-respected throughout the league after nearly two decades of coaching.",
                    "One of the more experienced coaches available, with \(coach.yearsExperience) years under his belt.",
                    "A veteran presence who has seen it all in his \(coach.yearsExperience)-year career."
                ],
                female: [
                    "A seasoned veteran with \(coach.yearsExperience) years of League experience.",
                    "Well-respected throughout the league after nearly two decades of coaching.",
                    "One of the more experienced coaches available, with \(coach.yearsExperience) years under her belt.",
                    "A veteran presence who has seen it all in her \(coach.yearsExperience)-year career."
                ],
                for: coach
            )
        default:
            expOpeners = genderedPhrases(
                male: [
                    "A grizzled coaching lifer with \(coach.yearsExperience) years in the business.",
                    "Has been coaching longer than some of his players have been alive.",
                    "An old-school football mind with over two decades of experience.",
                    "One of the longest-tenured coaches in professional football."
                ],
                female: [
                    "A grizzled coaching lifer with \(coach.yearsExperience) years in the business.",
                    "Has been coaching longer than some of her players have been alive.",
                    "An old-school football mind with over two decades of experience.",
                    "One of the longest-tenured coaches in professional football."
                ],
                for: coach
            )
        }
        parts.append(expOpeners.randomElement(using: &rng)!)

        // Attribute-based flavor (pick the highest attribute for emphasis)
        let attrMap: [(String, Int)] = [
            ("play-calling", coach.playCalling),
            ("player development", coach.playerDevelopment),
            ("game planning", coach.gamePlanning),
            ("scouting", coach.scoutingAbility),
            ("recruiting", coach.recruiting),
            ("motivation", coach.motivation),
            ("discipline", coach.discipline),
            ("media handling", coach.mediaHandling),
            ("contract negotiation", coach.contractNegotiation),
            ("morale building", coach.moraleInfluence)
        ]

        if let topAttr = attrMap.max(by: { $0.1 < $1.1 }) {
            let attrPhrases: [String]
            switch topAttr.0 {
            case "play-calling":
                attrPhrases = genderedPhrases(
                    male: [
                        "Known for creative play-calling that keeps defenses guessing.",
                        "His game-day play-calling is considered among the best in the league.",
                        "Offensive coordinators around the league study his play sheets."
                    ],
                    female: [
                        "Known for creative play-calling that keeps defenses guessing.",
                        "Her game-day play-calling is considered among the best in the league.",
                        "Offensive coordinators around the league study her play sheets."
                    ],
                    for: coach
                )
            case "player development":
                attrPhrases = genderedPhrases(
                    male: [
                        "Known for developing raw talent into starters.",
                        "Has a track record of turning late-round picks into All-Stars.",
                        "Players who work under him consistently improve year over year."
                    ],
                    female: [
                        "Known for developing raw talent into starters.",
                        "Has a track record of turning late-round picks into All-Stars.",
                        "Players who work under her consistently improve year over year."
                    ],
                    for: coach
                )
            case "game planning":
                attrPhrases = genderedPhrases(
                    male: [
                        "Meticulous game planner who leaves no stone unturned.",
                        "His game plans are legendary for exploiting opponent weaknesses.",
                        "Spends 18-hour days during the week perfecting his game plan."
                    ],
                    female: [
                        "Meticulous game planner who leaves no stone unturned.",
                        "Her game plans are legendary for exploiting opponent weaknesses.",
                        "Spends 18-hour days during the week perfecting her game plan."
                    ],
                    for: coach
                )
            case "scouting":
                attrPhrases = genderedPhrases(
                    male: [
                        "Has an exceptional eye for talent that others overlook.",
                        "Former scouts credit him with finding several hidden gems.",
                        "Known for spending extra hours in the film room evaluating prospects."
                    ],
                    female: [
                        "Has an exceptional eye for talent that others overlook.",
                        "Former scouts credit her with finding several hidden gems.",
                        "Known for spending extra hours in the film room evaluating prospects."
                    ],
                    for: coach
                )
            case "recruiting":
                attrPhrases = genderedPhrases(
                    male: [
                        "Free agents consistently cite him as a reason they signed.",
                        "His recruiting pitch is considered one of the best in the league.",
                        "Players want to play for him — it's that simple."
                    ],
                    female: [
                        "Free agents consistently cite her as a reason they signed.",
                        "Her recruiting pitch is considered one of the best in the league.",
                        "Players want to play for her — it's that simple."
                    ],
                    for: coach
                )
            case "motivation":
                attrPhrases = genderedPhrases(
                    male: [
                        "His halftime speeches are the stuff of locker room legend.",
                        "Players run through walls for him on game day.",
                        "Known for getting the absolute maximum out of his roster."
                    ],
                    female: [
                        "Her halftime speeches are the stuff of locker room legend.",
                        "Players run through walls for her on game day.",
                        "Known for getting the absolute maximum out of her roster."
                    ],
                    for: coach
                )
            case "discipline":
                attrPhrases = genderedPhrases(
                    male: [
                        "Runs a tight ship — his teams are among the least penalized in the league.",
                        "Demands accountability from every player, coach, and staff member.",
                        "His attention to detail borders on obsessive, in the best way."
                    ],
                    female: [
                        "Runs a tight ship — her teams are among the least penalized in the league.",
                        "Demands accountability from every player, coach, and staff member.",
                        "Her attention to detail borders on obsessive, in the best way."
                    ],
                    for: coach
                )
            case "media handling":
                attrPhrases = genderedPhrases(
                    male: [
                        "A natural in front of the cameras who shields his players from distractions.",
                        "His press conferences are masterclasses in saying nothing and everything.",
                        "The media respects him, and he uses that to protect his locker room."
                    ],
                    female: [
                        "A natural in front of the cameras who shields her players from distractions.",
                        "Her press conferences are masterclasses in saying nothing and everything.",
                        "The media respects her, and she uses that to protect her locker room."
                    ],
                    for: coach
                )
            case "contract negotiation":
                // Already gender-neutral — one pool for both genders.
                attrPhrases = [
                    "Has a keen understanding of the salary cap and player value.",
                    "Works closely with the front office on roster construction.",
                    "Known for identifying value signings in free agency."
                ]
            case "morale building":
                attrPhrases = genderedPhrases(
                    male: [
                        "His locker rooms are consistently described as tight-knit families.",
                        "Creates an environment where players genuinely enjoy coming to work.",
                        "Team chemistry has never been an issue under his leadership."
                    ],
                    female: [
                        "Her locker rooms are consistently described as tight-knit families.",
                        "Creates an environment where players genuinely enjoy coming to work.",
                        "Team chemistry has never been an issue under her leadership."
                    ],
                    for: coach
                )
            default:
                attrPhrases = ["A well-rounded coaching mind."]
            }
            parts.append(attrPhrases.randomElement(using: &rng)!)
        }

        // Personality flavor
        switch coach.personality {
        case .fieryCompetitor:
            parts.append(genderedPhrases(
                male: ["Brings an intense, fiery energy to every practice.", "His competitive fire is contagious in the building."],
                female: ["Brings an intense, fiery energy to every practice.", "Her competitive fire is contagious in the building."],
                for: coach).randomElement(using: &rng)!)
        case .quietProfessional:
            // Already gender-neutral — one pool for both genders.
            parts.append(["Prefers to let the results speak for themselves.", "A quiet operator who avoids the spotlight."].randomElement(using: &rng)!)
        case .mentor:
            parts.append(genderedPhrases(
                male: ["Players describe him as a father figure in the locker room.", "Young coaches seek him out for career advice."],
                female: ["Players describe her as a mentor figure in the locker room.", "Young coaches seek her out for career advice."],
                for: coach).randomElement(using: &rng)!)
        case .teamLeader:
            parts.append(genderedPhrases(
                male: ["A natural leader who commands respect from Day 1.", "His leadership style unites entire organizations."],
                female: ["A natural leader who commands respect from Day 1.", "Her leadership style unites entire organizations."],
                for: coach).randomElement(using: &rng)!)
        case .dramaQueen:
            parts.append(genderedPhrases(
                male: ["Not afraid of controversy — thrives in the spotlight.", "His bold personality makes headlines, for better or worse."],
                female: ["Not afraid of controversy — thrives in the spotlight.", "Her bold personality makes headlines, for better or worse."],
                for: coach).randomElement(using: &rng)!)
        case .loneWolf:
            parts.append(genderedPhrases(
                male: ["Keeps his inner circle small and his playbook close.", "A football hermit who lives and breathes the game in isolation."],
                female: ["Keeps her inner circle small and her playbook close.", "A football hermit who lives and breathes the game in isolation."],
                for: coach).randomElement(using: &rng)!)
        case .feelPlayer:
            parts.append(genderedPhrases(
                male: ["Trusts his gut instincts over analytics.", "Makes decisions by feel — and his feel is usually right."],
                female: ["Trusts her gut instincts over analytics.", "Makes decisions by feel — and her feel is usually right."],
                for: coach).randomElement(using: &rng)!)
        case .classClown:
            parts.append(genderedPhrases(
                male: ["Keeps the locker room loose with his sense of humor.", "Players love his lighthearted approach to a grueling season."],
                female: ["Keeps the locker room loose with her sense of humor.", "Players love her lighthearted approach to a grueling season."],
                for: coach).randomElement(using: &rng)!)
        case .steadyPerformer:
            parts.append(genderedPhrases(
                male: ["Consistent and reliable — never the highest high or lowest low.", "His steady hand has guided teams through turbulent stretches."],
                female: ["Consistent and reliable — never the highest high or lowest low.", "Her steady hand has guided teams through turbulent stretches."],
                for: coach).randomElement(using: &rng)!)
        }

        // Scheme reference if applicable
        if let offScheme = coach.offensiveScheme {
            let schemePhrases = genderedPhrases(
                male: [
                    "Runs a \(offScheme.displayName) offense.",
                    "His offensive philosophy centers on the \(offScheme.displayName) system.",
                    "Brings a \(offScheme.displayName) scheme that he's refined over the years."
                ],
                female: [
                    "Runs a \(offScheme.displayName) offense.",
                    "Her offensive philosophy centers on the \(offScheme.displayName) system.",
                    "Brings a \(offScheme.displayName) scheme that she's refined over the years."
                ],
                for: coach
            )
            parts.append(schemePhrases.randomElement(using: &rng)!)
        }
        if let defScheme = coach.defensiveScheme {
            let schemePhrases = genderedPhrases(
                male: [
                    "Favors a \(defScheme.displayName) defense.",
                    "Built a top-tier defense using his \(defScheme.displayName) scheme.",
                    "His \(defScheme.displayName) defensive system has been widely imitated."
                ],
                female: [
                    "Favors a \(defScheme.displayName) defense.",
                    "Built a top-tier defense using her \(defScheme.displayName) scheme.",
                    "Her \(defScheme.displayName) defensive system has been widely imitated."
                ],
                for: coach
            )
            parts.append(schemePhrases.randomElement(using: &rng)!)
        }

        // Cap at 2-3 sentences for readability
        let selected = Array(parts.prefix(3))
        return selected.joined(separator: " ")
    }

    // MARK: - Coach Chemistry

    /// Evaluates the personality chemistry between two coaches.
    /// Returns a value: positive = good fit, zero = neutral, negative = conflict.
    ///
    /// Range: roughly -1.0 (conflict) to +1.0 (excellent fit).
    static func coachChemistry(
        coachA: PersonalityArchetype,
        coachB: PersonalityArchetype
    ) -> Double {
        // Same personality = generally good synergy
        if coachA == coachB {
            return coachA == .dramaQueen ? -0.3 : 0.6
        }

        switch (coachA, coachB) {
        // Excellent pairings
        case (.mentor, .quietProfessional), (.quietProfessional, .mentor):
            return 0.8
        case (.teamLeader, .steadyPerformer), (.steadyPerformer, .teamLeader):
            return 0.7
        case (.mentor, .teamLeader), (.teamLeader, .mentor):
            return 0.7
        case (.quietProfessional, .steadyPerformer), (.steadyPerformer, .quietProfessional):
            return 0.6
        case (.teamLeader, .fieryCompetitor), (.fieryCompetitor, .teamLeader):
            return 0.5

        // Good pairings
        case (.mentor, .steadyPerformer), (.steadyPerformer, .mentor):
            return 0.5
        case (.feelPlayer, .fieryCompetitor), (.fieryCompetitor, .feelPlayer):
            return 0.4
        case (.classClown, .teamLeader), (.teamLeader, .classClown):
            return 0.3

        // Tension pairings
        case (.fieryCompetitor, .quietProfessional), (.quietProfessional, .fieryCompetitor):
            return -0.3
        case (.dramaQueen, .quietProfessional), (.quietProfessional, .dramaQueen):
            return -0.4
        case (.loneWolf, .teamLeader), (.teamLeader, .loneWolf):
            return -0.4
        case (.classClown, .mentor), (.mentor, .classClown):
            return -0.3
        case (.loneWolf, .mentor), (.mentor, .loneWolf):
            return -0.3

        // Conflict pairings
        case (.dramaQueen, .fieryCompetitor), (.fieryCompetitor, .dramaQueen):
            return -0.8
        case (.dramaQueen, .loneWolf), (.loneWolf, .dramaQueen):
            return -0.7
        case (.classClown, .loneWolf), (.loneWolf, .classClown):
            return -0.5
        case (.dramaQueen, .classClown), (.classClown, .dramaQueen):
            return -0.5

        // Default: mildly positive (most people can work together)
        default:
            return 0.1
        }
    }

    /// How a pairing reads: the three bands every staff surface names.
    ///
    /// Task #135: the thresholds used to be spelled out three times — once in
    /// `chemistryLabel`, once in `chemistrySymbol`, once in the auto-hire's
    /// ranking switch — so "the badge the row will wear" and "the band the
    /// hiring pass penalises" were two independent definitions of one thing.
    /// One switch now, three readers.
    enum ChemistryBand {
        case good
        case tension
        case conflict
    }

    static func chemistryBand(score: Double) -> ChemistryBand {
        switch score {
        case 0.3...:       return .good
        case -0.29...0.29: return .tension
        default:           return .conflict
        }
    }

    /// Returns a chemistry label string for display in the UI.
    static func chemistryLabel(score: Double) -> String {
        switch chemistryBand(score: score) {
        case .good:     return "Good fit"
        case .tension:  return "Tension"
        case .conflict: return "Conflict"
        }
    }

    /// Returns a chemistry symbol for compact display.
    static func chemistrySymbol(score: Double) -> String {
        switch chemistryBand(score: score) {
        case .good:     return "\u{2713}"  // checkmark
        case .tension:  return "\u{26A0}"  // warning
        case .conflict: return "\u{2717}"  // X mark
        }
    }

    // MARK: - Star Ratings

    /// Maps a 1-99 attribute value to a 1-5 star rating.
    /// 1-20 = 1 star, 21-40 = 2 stars, 41-60 = 3 stars, 61-80 = 4 stars, 81-99 = 5 stars.
    static func starRating(for attribute: Int) -> Int {
        switch attribute {
        case 81...99: return 5
        case 61...80: return 4
        case 41...60: return 3
        case 21...40: return 2
        default:      return 1
        }
    }

    /// Returns a string of star characters for the given attribute.
    static func starString(for attribute: Int) -> String {
        let stars = starRating(for: attribute)
        let filled = String(repeating: "\u{2605}", count: stars)    // ★
        let empty  = String(repeating: "\u{2606}", count: 5 - stars) // ☆
        return filled + empty
    }

    // MARK: - HC Promotion Poaching

    /// Check if coordinators receive HC interview requests (NFL-realistic).
    /// Unlike `checkCoordinatorPoaching`, this focuses on coordinator-to-HC pipeline
    /// based on overall rating, team success, and motivation.
    ///
    /// - Parameters:
    ///   - coaches: The coaching staff to evaluate.
    ///   - teamWins: The team's win total for the season.
    /// - Returns: Coaches who have accepted HC positions elsewhere.
    static func checkHCPromotionPoaching(
        coaches: [Coach],
        teamWins: Int
    ) -> [Coach] {
        var poached: [Coach] = []

        let candidates = coaches.filter { coach in
            [CoachRole.offensiveCoordinator, .defensiveCoordinator, .assistantHeadCoach].contains(coach.role)
            && coachOverallRating(coach) >= 70
        }

        for coach in candidates {
            let ovr = coachOverallRating(coach)
            var chance = Double(ovr - 60) / 40.0 * 0.30
            if teamWins >= 10 { chance += 0.10 }
            if teamWins >= 13 { chance += 0.10 }
            if teamWins >= 11 { chance -= 0.05 }  // Winners slightly less likely to leave
            chance += Double(coach.motivation - 50) / 50.0 * 0.10

            if Double.random(in: 0...1) < max(0.0, chance) {
                poached.append(coach)
            }
        }

        return poached
    }

    /// Computes a coach's overall rating as the average of their 12 core attributes.
    static func coachOverallRating(_ coach: Coach) -> Int {
        (coach.playCalling + coach.playerDevelopment + coach.reputation + coach.adaptability
            + coach.gamePlanning + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.mediaHandling + coach.contractNegotiation + coach.moraleInfluence) / 12
    }

    // MARK: - Developer Reputation as Free-Agent Appeal (TODO §5.7)

    /// Bounds of the free-agency multiplier. A staff cannot buy a player, but a
    /// reputation for making players better is worth roughly the same as a
    /// modest contract sweetener — which is what ±15 % of a decision score is.
    static let developmentAppealRange: ClosedRange<Double> = 0.85...1.15

    /// How much a franchise's coaching staff is worth to a free agent who cares
    /// about getting better, expressed as a multiplier on his decision score.
    ///
    /// `1.0` is a neutral staff (and the value for a team with no staff at all,
    /// so a missing lookup can never quietly favour or punish anyone).
    /// Below `1.0` a player would rather be coached somewhere else; above it,
    /// the building itself is part of the pitch.
    ///
    /// The score behind it is `CoachDevelopmentEngine.DeveloperRecord.score` —
    /// each coach's development attributes blended with what the young players
    /// on his watch actually gained (`PlayerSeasonHistory` deltas). Early in a
    /// career that is a projection off attributes; after a few seasons it is a
    /// record, and a staff that lets rookies stagnate loses the pitch it was
    /// hired on.
    ///
    /// ## Weighting
    ///
    /// A free agent's development is not the head coach's personal project: the
    /// position coach runs his drills, the coordinator runs his unit, and the
    /// head coach sets whether any of that is taken seriously. So the staff
    /// score is a weighted blend rather than the HC's number — and a team with
    /// a great HC and nobody under him does not get to claim a great classroom.
    ///
    /// - Parameters:
    ///   - teamID: The franchise being evaluated.
    ///   - coaches: Coaches to consider — the league-wide array is fine, it is
    ///     filtered to `teamID` here.
    static func developmentAppeal(teamID: UUID, coaches: [Coach]) -> Double {
        let staff = coaches.filter { $0.teamID == teamID && !$0.isRetired }
        guard !staff.isEmpty else { return 1.0 }

        // Resolved once for the whole staff: the free-agency loop calls this per
        // candidate per team, and letting each coach look the season up himself
        // would turn one `Career` read into one per seat.
        let season = staff.lazy.compactMap { CoachDevelopmentEngine.activeSeason(for: $0) }.first

        func averageScore(_ group: [Coach]) -> Double? {
            guard !group.isEmpty else { return nil }
            let total = group.reduce(0.0) {
                $0 + Double(CoachDevelopmentEngine.developerRecord(coach: $1, currentSeason: season).score)
            }
            return total / Double(group.count)
        }

        let headCoach = averageScore(staff.filter { $0.role == .headCoach })
        let coordinators = averageScore(staff.filter {
            $0.role == .assistantHeadCoach
                || $0.role == .offensiveCoordinator
                || $0.role == .defensiveCoordinator
                || $0.role == .specialTeamsCoordinator
        })
        let positionCoaches = averageScore(staff.filter { positionCoachRoles.contains($0.role) })

        // Missing layers are dropped rather than defaulted: an empty seat is
        // not a 50-rated coach, it is one fewer voice in the blend, and the
        // remaining weights renormalise around it.
        let layers: [(score: Double, weight: Double)] = [
            headCoach.map { ($0, 0.35) },
            coordinators.map { ($0, 0.30) },
            positionCoaches.map { ($0, 0.35) },
        ].compactMap { $0 }
        guard !layers.isEmpty else { return 1.0 }

        let totalWeight = layers.reduce(0.0) { $0 + $1.weight }
        let staffScore = layers.reduce(0.0) { $0 + $1.score * $1.weight } / totalWeight

        // 50 (a league-average staff) maps to exactly 1.0; the ends of the
        // rating scale reach the ends of the band.
        let appeal = 1.0 + (staffScore - 50.0) / 50.0 * 0.15
        return min(developmentAppealRange.upperBound, max(developmentAppealRange.lowerBound, appeal))
    }

    /// The roles that actually stand in front of a position group at practice.
    /// Medical staff develop nobody's technique, so they are not in the blend.
    private static let positionCoachRoles: Set<CoachRole> = [
        .qbCoach, .rbCoach, .wrCoach, .olCoach,
        .dlCoach, .lbCoach, .dbCoach, .strengthCoach,
    ]

    // MARK: - Coordinator Poaching

    /// Evaluates a coaching staff and returns the subset of coordinators or position coaches
    /// who may receive head-coaching offers based on their reputation and the team's success.
    ///
    /// - Parameters:
    ///   - coaches: The full coaching staff to evaluate.
    ///   - teamWins: The team's win total for the season.
    ///   - currentSeason: The season whose offseason this pass runs in — the
    ///     grace test needs it, because the flag alone cannot say WHICH
    ///     offseason a man signed in.
    /// - Returns: Coaches currently being targeted with HC offers (may be empty).
    static func checkCoordinatorPoaching(coaches: [Coach], teamWins: Int, currentSeason: Int) -> [Coach] {
        // Only non-HC coaching roles are eligible for poaching.
        //
        // Task #96: the medical family (team doctor, physio, head trainer) used
        // to sit in this pool and be pulled out of buildings at the same ~20 %
        // a season as a position coach — this function's own doc says it returns
        // the men "who may receive head-coaching offers", and a physician does
        // not receive one. Between them they were roughly a fifth of the ~90
        // detachments a season that fed the unbounded unemployed bench, and the
        // one fifth with nowhere to be re-hired: `CoachRole.hiringFamilies` keeps
        // medical seats medical, so a poached physio could only ever be replaced
        // by an invented one.
        // Task #133: a man cannot be hired away from a job he has not started.
        // The user fills his staff DURING the coaching-changes phase and this
        // pass runs on the advance OUT of it, so without the `signedThisOffseason`
        // clause his brand-new position coaches were on the market the same
        // evening they signed — two of fifteen, on average, on a fresh save.
        // The flag is cleared by `developCoach` further down the same advance,
        // and every AI hire (which lands after this pass anyway) is unaffected.
        // The `hireSeasonYear >= currentSeason` half exists because the flag
        // alone would grant a FREE YEAR to any coach hired after this advance
        // (free agency, midseason): developCoach has already run for the year,
        // nothing clears the flag until next offseason, and a man who then
        // coached the full season would arrive here still "brand new".
        let candidates = coaches.filter {
            $0.role != .headCoach && $0.role != .assistantHeadCoach && $0.role.family != .medical
                && !($0.signedThisOffseason && $0.hireSeasonYear >= currentSeason)
        }

        // Win bonus: teams on winning records attract more HC searches
        let winBonus: Double
        switch teamWins {
        case 12...: winBonus = 0.15
        case 9...11: winBonus = 0.07
        case 6...8:  winBonus = 0.0
        default:     winBonus = -0.05
        }

        return candidates.filter { coach in
            // Base probability driven by reputation (0–99 mapped to 0.0–0.40)
            let reputationFactor = Double(coach.reputation) / 99.0 * 0.40

            // Coordinators are far more visible than position coaches
            let rolePremium: Double
            switch coach.role {
            case .offensiveCoordinator, .defensiveCoordinator:
                rolePremium = 0.15
            case .specialTeamsCoordinator, .qbCoach:
                rolePremium = 0.05
            default:
                rolePremium = 0.0
            }

            let poachChance = max(0.0, reputationFactor + rolePremium + winBonus)
            return Double.random(in: 0.0..<1.0) < poachChance
        }
    }

    // MARK: - Player Development Bonus

    /// Calculates a multiplier applied to a player's development rate under a given coach.
    ///
    /// - Parameters:
    ///   - coach: The coach overseeing this player's development.
    ///   - player: The player being developed.
    /// - Returns: Multiplier in the range `0.8...1.5`.
    static func coachDevelopmentBonus(coach: Coach, player: Player) -> Double {
        var multiplier: Double = 1.0

        // MARK: Coach playerDevelopment Attribute
        // 50 is neutral; each point above/below shifts the multiplier by ~0.004
        let devAttributeBonus = (Double(coach.playerDevelopment) - 50.0) / 50.0 * 0.2
        multiplier += devAttributeBonus

        // MARK: Motivation bonus
        // A highly motivating coach squeezes extra effort out of players
        let motivationBonus = (Double(coach.motivation) - 50.0) / 50.0 * 0.05
        multiplier += motivationBonus

        // MARK: Position Role Match
        // A coach who specializes in this player's position group provides an extra boost
        let positionMatch = positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
        multiplier += positionMatch ? 0.15 : 0.0

        // MARK: Scheme Fit Contribution
        // Players in a good scheme fit develop faster because reps translate to real growth
        let fit = schemeFit(
            player: player,
            offensiveScheme: coach.offensiveScheme,
            defensiveScheme: coach.defensiveScheme
        )
        // Scheme fit of 0.5 is neutral; range contributes −0.05 to +0.10
        let schemeFitBonus = (fit - 0.5) * 0.20
        multiplier += schemeFitBonus

        // MARK: Personality Compatibility
        multiplier += personalityCompatibility(coachPersonality: coach.personality, playerPersonality: player.personality)

        // MARK: Player Coachability
        // High coachability amplifies coaching; low coachability diminishes it
        let coachabilityFactor = (Double(player.mental.coachability) - 50.0) / 50.0 * 0.10
        multiplier += coachabilityFactor

        // MARK: Player Work Ethic
        let workEthicFactor = (Double(player.mental.workEthic) - 50.0) / 50.0 * 0.05
        multiplier += workEthicFactor

        return min(1.5, max(0.8, multiplier))
    }

    // MARK: - Hierarchical Development Bonus

    /// Seasons a coordinator must have spent on the same team, running the same
    /// scheme, before continuity starts paying (plan §2.9.3,
    /// `DEVELOPMENT_NFL_REFERENCE.md` §5: "continuity matters as much as
    /// quality").
    static let coordinatorContinuitySeasons = 3

    /// What that continuity is worth on the development multiplier stack.
    /// Deliberately the same order of magnitude as the −0.03 adjustment-period
    /// penalty it mirrors: stability compounds, churn taxes.
    static let coordinatorContinuityBonus = 0.05

    /// The attribute value each layer below treats as "an average coach", i.e.
    /// the point at which that layer contributes nothing.
    ///
    /// Task #97 (root cause). Every layer used to pivot on 50 — the midpoint of
    /// the 1-99 attribute scale, and a perfectly good pivot for a league whose
    /// coaches were drawn uniformly across it. The shipped league is not that
    /// league. `LeagueGenerator.makeCoach` forces every attribute named in
    /// `CoachRole.focusAttributes` into the role's "good" band for position
    /// coaches, and all seven position-coach roles plus the strength coach name
    /// `playerDevelopment` — so the shipped position coach, who carries the
    /// heaviest layer here (±0.15), draws playerDevelopment from U(70,85):
    /// mean 77.5, sd 4.6. Measured over 200k staffs, the expected multiplier
    /// this function returns was 1.1646, i.e. the league ran a permanent +16 %
    /// development bonus that no camp ever gave back and no gate ever saw (the
    /// balance harness drew every coach from N(58,15) and measured 1.0594).
    ///
    /// 60 is a PARTIAL re-centring, not a neutral one, and the comment used to
    /// claim otherwise — read the number before you trust the prose. The four
    /// layers' shipped input means are HC motivation 73.4, AHC
    /// playerDevelopment 66.4, coordinator 65.6, position coach 77.5; the pivot
    /// that would make "average staff, no effect" true is their slope-weighted
    /// mean ≈ 72, i.e. 70 to the near ten, which puts E[bonus] at ≈ 1.016.
    /// At 60 the same means give
    ///   1 + (13.4·0.08 + 6.4·0.04 + 5.6·0.10 + 17.5·0.15)/50 ≈ 1.090,
    /// so average shipped staff still carries a permanent +9 % development
    /// bonus — down from +16 %, about half the gap closed. Measured effect in
    /// the app: −6.4 % development volume.
    ///
    /// That residual is deliberate, and it is gate-fitted rather than derived:
    /// 60 is the largest re-centring that keeps the §6/§8 asserts green with
    /// the corrected `shippedCoachAttrs` rig, and the rest of the development
    /// calibration is currently fitted around the +9 %. Going to 70 is the
    /// principled end state but is a calibration wave, not a constant edit — it
    /// needs the harness re-run and the blue-chip count re-checked against §8's
    /// 25-35 ceiling.
    ///
    /// This constant and the harness's coach draw are ONE change. Re-centring
    /// alone, against a rig that still drew N(58,15), took E[bonus] to 0.954
    /// and reddened six asserts; fixing the rig alone left the pivot at 50 and
    /// took the league to 34 blue chips against §8's 25-35 ceiling. Both were
    /// measured before this was written.
    static let developmentBonusPivot = 60.0

    /// Calculate layered coaching bonus from HC → AHC → Coordinator → Position Coach
    ///
    /// - Parameter player: read for `position.side` only, which selects WHICH
    ///   system the coordinator layer holds him responsible for knowing (see
    ///   "Layer 3b" below). Until that layer existed this parameter was accepted
    ///   and never read — Swift does not warn on an unused function parameter,
    ///   so it sat in the signature of the single hottest function in the
    ///   development stack looking load-bearing.
    /// - Parameter coordinatorContinuity: the unit's coordinator has been in the
    ///   building `coordinatorContinuitySeasons`+ years AND has not changed the
    ///   scheme. Computed by the caller, which is the layer that knows the
    ///   current season and the team's scheme history.
    static func hierarchicalDevelopmentBonus(
        headCoach: Coach?,
        assistantHC: Coach?,
        coordinator: Coach?,
        positionCoach: Coach?,
        player: Player,
        coordinatorContinuity: Bool = false
    ) -> Double {
        var multiplier = 1.0

        // Layer 1: HC team-wide bonus
        if let hc = headCoach {
            let hcBonus = (Double(hc.motivation) - developmentBonusPivot) / 50.0 * 0.08
            multiplier += hcBonus
            if hc.isInAdjustmentPeriod { multiplier -= 0.05 }
        }

        // Layer 2: AHC secondary bonus
        if let ahc = assistantHC {
            let ahcBonus = (Double(ahc.playerDevelopment) - developmentBonusPivot) / 50.0 * 0.04
            multiplier += ahcBonus
        }

        // Layer 3: Coordinator unit bonus
        if let coord = coordinator {
            let coordBonus = (Double(coord.playerDevelopment) - developmentBonusPivot) / 50.0 * 0.10
            multiplier += coordBonus
            if coord.isInAdjustmentPeriod { multiplier -= 0.03 }
            // Continuity reward (plan §2.9.3). Mutually exclusive with the
            // adjustment penalty by construction: a coordinator who was
            // promoted this offseason cannot also have three seasons in the
            // same seat with an unchanged scheme.
            if coordinatorContinuity { multiplier += coordinatorContinuityBonus }

            // Layer 3b: scheme mastery — the coordinator's own command of the
            // system his unit actually installs. Penalty-only, and it is the
            // MISSING HALF of a mechanic that already exists.
            //
            // `CoachingModifiers` Mech 6 reads exactly this number —
            // `oc.expertise(for: oc.offensiveScheme)` — and pays a
            // POSITIVE-ONLY game-day bonus above `CoachingModifiers.schemeCenter`
            // (70). Below that centre it charges nothing, and until now nothing
            // else in the engine read the number at all, so a coordinator asked
            // to run a system he has never coached was FREE.
            //
            // That is reachable, not hypothetical. `initializeSchemeExpertise`
            // seeds 75-95 in a coach's OWN scheme, 40-65 across his family and
            // 15-40 everywhere else, and `SchemeSelectionView.commitPending`
            // rewrites `coordinator.offensiveScheme` WITHOUT touching
            // `schemeExpertise` — the one and only way in the game for the two
            // to diverge, and it is the headline decision of the Coaching
            // Changes phase. The ROSTER already paid for that install through
            // `activeSchemeFamiliarity`; the man who chose it paid nothing.
            //
            // Where the two numbers come from, neither of them rounded for
            // looking reasonable:
            //  * Par is 70 because that is `CoachingModifiers.schemeCenter` —
            //    the same quantity off the same coach, so the pair is now
            //    two-sided instead of half-open: above par the sim pays him,
            //    below par the development stack charges him.
            //  * Saturation is 20 because that is what `Coach.expertise(for:)`
            //    returns for a scheme it holds no record of, i.e. the model's
            //    own statement of "knows nothing about this system", and it
            //    sits at the bottom of the 15-40 unknown-scheme band above.
            //  * The full-ignorance charge is `coordinatorContinuityBonus`
            //    negated. Three seasons running one system is worth +0.05 on
            //    this multiplier; installing one he has never run is worth
            //    −0.05. The swing between those poles is 0.10, which is exactly
            //    this layer's own authority over 50 attribute points — so
            //    "does not know the playbook" can cost at most what "is a poor
            //    developer" costs, and no more.
            //
            // A coordinator carrying no system on this player's side is charged
            // nothing, for the reason `activeSchemeFamiliarity` already gives:
            // a vacancy is not evidence that the room forgot football. The same
            // holds for an empty `schemeExpertise` table (legacy rows written
            // before the field existed) — no record is not a record of zero.
            //
            // Declared as locals rather than file-scope `static let`s on
            // purpose: `tools/balance-harness/sync_sources.sh` slices this
            // function out whole but copies only a NAMED LIST of top-level
            // constants, so a new one at file scope would not reach the rig and
            // the harness would stop compiling.
            let schemeMasteryPar = 70.0
            let schemeMasteryFloor = 20.0
            let installedScheme: String?
            switch player.position.side {
            case .offense:      installedScheme = coord.offensiveScheme?.rawValue
            case .defense:      installedScheme = coord.defensiveScheme?.rawValue
            case .specialTeams: installedScheme = nil
            }
            if let installedScheme, !coord.schemeExpertise.isEmpty {
                let mastery = Double(coord.expertise(for: installedScheme))
                let shortfall = (schemeMasteryPar - mastery) / (schemeMasteryPar - schemeMasteryFloor)
                let ignorance = min(1.0, max(0.0, shortfall))
                multiplier -= coordinatorContinuityBonus * ignorance
            }
        }

        // Layer 4: Position coach direct bonus
        if let pos = positionCoach {
            let posBonus = (Double(pos.playerDevelopment) - developmentBonusPivot) / 50.0 * 0.15
            multiplier += posBonus
        }

        return max(0.5, min(1.8, multiplier))
    }

    // MARK: - Position Role Matching

    /// Returns `true` if the coach's role is a direct position-group match for the player.
    static func positionRoleMatch(coachRole: CoachRole, playerPosition: Position) -> Bool {
        switch coachRole {
        case .qbCoach:
            return playerPosition == .QB
        case .rbCoach:
            return playerPosition == .RB || playerPosition == .FB
        case .wrCoach:
            return playerPosition == .WR || playerPosition == .TE
        case .olCoach:
            return [.LT, .LG, .C, .RG, .RT].contains(playerPosition)
        case .dlCoach:
            return [.DE, .DT].contains(playerPosition)
        case .lbCoach:
            return [.MLB, .OLB].contains(playerPosition)
        case .dbCoach:
            return [.CB, .FS, .SS].contains(playerPosition)
        case .strengthCoach:
            return true  // Strength coach benefits every player equally
        default:
            return false
        }
    }

    // MARK: - Scout Candidate Generation

    /// Generates a pool of scout candidates available for the given scout role.
    ///
    /// - Parameters:
    ///   - role: The scouting role being filled.
    ///   - count: How many candidates to generate (defaults to 20).
    ///   - seed: R27 — when provided, the pool is generated deterministically
    ///           (same team/role/season always sees the same candidates).
    /// - Returns: An array of freshly created `Scout` objects not yet attached to any team.
    static func generateScoutCandidates(role: ScoutRole, count: Int = 20, seed: UInt64? = nil) -> [Scout] {
        var seededRNG = ScoutPoolGenerator(state: (seed ?? 0) == 0 ? 0x9E3779B97F4A7C15 : seed!)
        var systemRNG = SystemRandomNumberGenerator()

        func makeScout() -> Scout {
            let name: (first: String, last: String)
            let experience: Int
            let spec: Position?
            let accuracy: Int, personality: Int, potential: Int, salary: Int

            let expRange: ClosedRange<Int>
            let salaryRange: ClosedRange<Int>
            if role.isChief {
                expRange = 8...25
                salaryRange = 650...2_000
            } else {
                expRange = 1...15
                salaryRange = 150...1_000
            }

            if seed != nil {
                name = RandomNameGenerator.randomName(using: &seededRNG)
                experience = Int.random(in: expRange, using: &seededRNG)
                let ceil = min(99, 40 + experience * 3)
                let floor = max(25, ceil - 35)
                spec = role.isChief ? nil : Position.allCases.randomElement(using: &seededRNG)
                accuracy = Int.random(in: floor...ceil, using: &seededRNG)
                personality = Int.random(in: floor...ceil, using: &seededRNG)
                potential = Int.random(in: floor...ceil, using: &seededRNG)
                salary = Int.random(in: salaryRange, using: &seededRNG)
            } else {
                name = RandomNameGenerator.randomName(using: &systemRNG)
                experience = Int.random(in: expRange, using: &systemRNG)
                let ceil = min(99, 40 + experience * 3)
                let floor = max(25, ceil - 35)
                spec = role.isChief ? nil : Position.allCases.randomElement(using: &systemRNG)
                accuracy = Int.random(in: floor...ceil, using: &systemRNG)
                personality = Int.random(in: floor...ceil, using: &systemRNG)
                potential = Int.random(in: floor...ceil, using: &systemRNG)
                salary = Int.random(in: salaryRange, using: &systemRNG)
            }

            return Scout(
                firstName: name.first,
                lastName: name.last,
                teamID: nil,
                positionSpecialization: spec,
                accuracy: accuracy,
                personalityRead: personality,
                potentialRead: potential,
                experience: experience,
                salary: salary,
                scoutRole: role
            )
        }

        return (0..<count).map { _ in makeScout() }
    }

    /// R27: Stable seed for a team's scout hiring pool: same team + role + season
    /// always produces the same candidate list (FNV-1a over a stable string —
    /// `Hasher` is randomized per launch, so it cannot be used here).
    static func scoutPoolSeed(teamID: UUID, role: ScoutRole, season: Int) -> UInt64 {
        let key = "\(teamID.uuidString)|\(role.rawValue)|\(season)"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// R27: SplitMix64 — small deterministic RNG for seeded candidate pools.
private struct ScoutPoolGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Private Helpers

private extension CoachingEngine {

    /// Maps a raw attribute value (1–99) to a 0.0–1.0 normalized score.
    static func normalize(_ value: Double) -> Double {
        (value - 1.0) / 98.0
    }

    /// Returns `true` if the coach role is primarily offensive.
    static func offensiveRole(_ role: CoachRole) -> Bool {
        switch role {
        case .offensiveCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach:
            return true
        default:
            return false
        }
    }

    /// Returns `true` if the coach role is primarily defensive.
    static func defensiveRole(_ role: CoachRole) -> Bool {
        switch role {
        case .defensiveCoordinator, .dlCoach, .lbCoach, .dbCoach:
            return true
        default:
            return false
        }
    }

    /// Returns a bonus/penalty based on how well the coach and player personalities mesh.
    ///
    /// Range is roughly −0.10 to +0.10.
    static func personalityCompatibility(
        coachPersonality: PersonalityArchetype,
        playerPersonality: PlayerPersonality
    ) -> Double {
        let playerArch = playerPersonality.archetype

        switch coachPersonality {

        // Mentor coaches draw out the best in coachable, team-oriented players; clash with lone wolves
        case .mentor:
            switch playerArch {
            case .quietProfessional, .steadyPerformer, .teamLeader: return  0.08
            case .mentor:                                            return  0.04
            case .loneWolf:                                          return -0.06
            case .dramaQueen:                                        return -0.04
            default:                                                 return  0.02
            }

        // Team leaders inspire willing players but butt heads with dramatic or lone-wolf personalities
        case .teamLeader:
            switch playerArch {
            case .teamLeader, .steadyPerformer, .quietProfessional: return  0.06
            case .fieryCompetitor:                                   return  0.04
            case .dramaQueen, .loneWolf:                             return -0.06
            default:                                                 return  0.01
            }

        // Fiery competitors push feel-players and competitors hard; grate on quiet professionals
        case .fieryCompetitor:
            switch playerArch {
            case .fieryCompetitor:                                   return  0.06
            case .feelPlayer:                                        return  0.04
            case .quietProfessional, .mentor:                        return -0.04
            case .dramaQueen:                                        return -0.08
            default:                                                 return  0.01
            }

        // Quiet professionals work well with almost everyone; zero friction
        case .quietProfessional:
            switch playerArch {
            case .dramaQueen, .classClown:                           return -0.04
            default:                                                 return  0.03
            }

        // Steady performers are reliable coaches; modest bonuses across the board
        case .steadyPerformer:
            switch playerArch {
            case .steadyPerformer, .quietProfessional:               return  0.04
            case .dramaQueen:                                        return -0.03
            default:                                                 return  0.02
            }

        // Drama Queens can energize feel-players but distract class clowns and lone wolves
        case .dramaQueen:
            switch playerArch {
            case .feelPlayer, .fieryCompetitor:                      return  0.05
            case .classClown, .loneWolf:                             return -0.08
            case .quietProfessional:                                 return -0.04
            default:                                                 return  0.0
            }

        // Lone wolf coaches are detached; work with self-sufficient players, poor with team types
        case .loneWolf:
            switch playerArch {
            case .loneWolf:                                          return  0.04
            case .teamLeader, .mentor:                               return -0.06
            default:                                                 return  0.0
            }

        // Feel players rely on vibes; great match with similarly emotional players
        case .feelPlayer:
            switch playerArch {
            case .feelPlayer, .dramaQueen:                           return  0.06
            case .steadyPerformer, .quietProfessional:               return -0.02
            default:                                                 return  0.02
            }

        // Class clowns keep the mood light; works for most but can undermine serious players
        case .classClown:
            switch playerArch {
            case .classClown, .feelPlayer, .teamLeader:              return  0.04
            case .quietProfessional, .mentor, .steadyPerformer:      return -0.04
            default:                                                  return  0.01
            }
        }
    }
}

// MARK: - PositionAttributes Convenience Extension

private extension PositionAttributes {
    /// Provides a QB's mental decision-making proxy through the Player's mental attributes
    /// when scheme calculations need it (RPO reads, option execution, etc.).
    /// This avoids coupling PositionAttributes to Player directly inside the enum switch.
    func decisionMaking_equiv(player: Player) -> Int {
        player.mental.decisionMaking
    }
}
