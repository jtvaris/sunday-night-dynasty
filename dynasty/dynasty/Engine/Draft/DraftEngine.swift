import Foundation

/// Stateless engine that handles all NFL Draft logic: order generation,
/// AI pick selection, prospect-to-player conversion, pick value chart,
/// and trade evaluation.
enum DraftEngine {

    // MARK: - Draft Setup

    /// Generates the full 7-round, 224-pick draft order based on reverse standings.
    ///
    /// - Playoff teams pick later in each round.
    /// - The Super Bowl loser picks 31st; the Super Bowl winner picks 32nd.
    ///
    /// - Parameters:
    ///   - teams: All 32 teams in the league.
    ///   - games: All games for the season (used to derive standings and playoff results).
    ///   - seasonYear: The year of the draft.
    /// - Returns: An array of 224 `DraftPick` objects ordered by overall pick number.
    static func generateDraftOrder(teams: [Team], games: [Game], seasonYear: Int) -> [DraftPick] {
        let orderedTeamIDs = draftSlotOrder(teams: teams, games: games)

        // Generate 7 rounds of 32 picks each.
        var picks: [DraftPick] = []
        for round in 1...7 {
            for (index, teamID) in orderedTeamIDs.enumerated() {
                let overall = (round - 1) * 32 + (index + 1)
                let pick = DraftPick(
                    seasonYear: seasonYear,
                    round: round,
                    pickNumber: overall,
                    originalTeamID: teamID,
                    currentTeamID: teamID
                )
                picks.append(pick)
            }
        }

        return picks
    }

    /// The 32 team IDs in slot order for a draft that follows `games`: worst
    /// record first, then playoff teams by record, then the Super Bowl loser,
    /// then the champion. Index 0 owns pick #1 of every round.
    ///
    /// Split out of `generateDraftOrder` because the future-pick rows minted years
    /// earlier (`LeagueGenerator.futureDraftPicks`) need exactly this ordering to
    /// be renumbered against when their year comes up, WITHOUT building a second
    /// set of pick rows that would duplicate the traded ones.
    static func draftSlotOrder(teams: [Team], games: [Game]) -> [UUID] {
        let records = StandingsCalculator.calculate(games: games, teams: teams)

        // Determine playoff teams for each conference (top 7 seeds).
        let afcPlayoff = StandingsCalculator.playoffTeams(
            records: records, teams: teams, conference: .AFC
        )
        let nfcPlayoff = StandingsCalculator.playoffTeams(
            records: records, teams: teams, conference: .NFC
        )
        let playoffTeamIDs = Set((afcPlayoff + nfcPlayoff).map(\.teamID))

        // Identify the Super Bowl participants from playoff games.
        // The championship game is the last played playoff game of the season.
        let playoffGames = games
            .filter { $0.isPlayoff && $0.isPlayed }
            .sorted { $0.week < $1.week }

        let superBowlWinnerID = playoffGames.last?.winnerID
        let superBowlLoserID = playoffGames.last?.loserID

        // Split teams into non-playoff and playoff groups.
        var nonPlayoffRecords = records.filter { !playoffTeamIDs.contains($0.teamID) }
        var playoffRecords = records.filter {
            playoffTeamIDs.contains($0.teamID)
            && $0.teamID != superBowlWinnerID
            && $0.teamID != superBowlLoserID
        }

        // Sort non-playoff teams worst-to-best (worst record picks first).
        nonPlayoffRecords.sort { worstFirst($0, $1) }

        // Sort playoff teams worst-to-best among those eliminated before the Super Bowl.
        playoffRecords.sort { worstFirst($0, $1) }

        // Build the pick order: non-playoff (worst first), then playoff losers,
        // then Super Bowl loser, then Super Bowl winner.
        var orderedTeamIDs: [UUID] = nonPlayoffRecords.map(\.teamID)
            + playoffRecords.map(\.teamID)

        if let loserID = superBowlLoserID {
            orderedTeamIDs.append(loserID)
        }
        if let winnerID = superBowlWinnerID {
            orderedTeamIDs.append(winnerID)
        }

        // Ensure we have exactly 32 teams. If Super Bowl IDs could not be determined
        // (e.g., no playoff games yet), fall back to pure reverse standings.
        if orderedTeamIDs.count != 32 {
            var fallback = records
            fallback.sort { worstFirst($0, $1) }
            orderedTeamIDs = fallback.map(\.teamID)
        }

        return orderedTeamIDs
    }

    // MARK: - AI Draft Logic

    /// AI selects the best prospect for a given team based on roster needs
    /// and prospect quality.
    ///
    /// The board this scores is the club's OWN, not the truth: every
    /// `trueOverall` / `truePotential` goes through `AIDraftPerception`, whose
    /// per-`(team, prospect)` error is deterministic, persona-shaped and
    /// fat-tailed. That is what makes 32 AI boards disagree, puts real busts in
    /// the top 10 and real steals in round 5, and leaves room for the user's
    /// scouting department to beat the market. See `AIDraftPerception` for the
    /// model and for the list of things deliberately left un-fogged (the user's
    /// picks, every trade valuation, the public `draftProjection`).
    ///
    /// - Parameters:
    ///   - team: The team making the pick.
    ///   - availableProspects: Prospects still on the board.
    ///   - teamRoster: Current players on the team's roster.
    ///   - perceptionEnabled: `false` scores the TRUE board — the pre-fog
    ///     behaviour, kept as the control arm for the `perception` balance
    ///     scenario. No shipping call site passes it.
    /// - Returns: The prospect the AI selects.
    static func aiMakePick(
        team: Team,
        availableProspects: [CollegeProspect],
        teamRoster: [Player],
        perceptionEnabled: Bool = true
    ) -> CollegeProspect {
        guard !availableProspects.isEmpty else {
            fatalError("aiMakePick called with no available prospects")
        }

        let needs = evaluateTeamNeeds(roster: teamRoster)
        // One lens per pick, not per prospect — the archetype draw is the same
        // for all 300 names on the board.
        let lens = perceptionEnabled ? AIDraftPerception.lens(forTeam: team.id) : nil

        // Score each prospect: combination of PERCEIVED talent and positional need.
        let scored = availableProspects.map { prospect -> (CollegeProspect, Double) in
            let perceivedOverall: Double
            let perceivedPotential: Double
            if let lens {
                let read = AIDraftPerception.read(
                    teamID: team.id,
                    prospectID: prospect.id,
                    trueOverall: prospect.trueOverall,
                    truePotential: prospect.truePotential,
                    lens: lens
                )
                perceivedOverall = read.overall
                perceivedPotential = read.potential
            } else {
                perceivedOverall = Double(prospect.trueOverall)
                perceivedPotential = Double(prospect.truePotential)
            }

            var score = perceivedOverall

            // Boost score for positions the team needs.
            let needMultiplier = needs[prospect.position] ?? 1.0
            score *= needMultiplier

            // QB premium: if team needs a QB, boost significantly.
            if prospect.position == .QB && (needs[.QB] ?? 1.0) > 1.2 {
                score *= 1.15
            }

            // Factor in potential (prospects with higher ceilings are more attractive).
            score += perceivedPotential * 0.15

            // Slight bonus for prospects projected to go in this range (consensus value).
            if let projection = prospect.draftProjection, projection > 0 {
                // Lower projection number = better prospect. Give a small bump.
                let projectionBonus = max(0.0, Double(100 - projection) * 0.05)
                score += projectionBonus
            }

            return (prospect, score)
        }

        // R24: weighted-random selection among the top of the need-adjusted
        // board instead of a pure argmax. The board-topper still goes ~65 %
        // of the time, but occasional small reaches/slides keep drafts
        // surprising while the need+value scoring stays fully explainable.
        let ranked = scored.sorted { $0.1 > $1.1 }
        let candidates = Array(ranked.prefix(4))
        let weights: [Double] = [0.65, 0.20, 0.10, 0.05]
        var roll = Double.random(in: 0..<1)
        for (index, candidate) in candidates.enumerated() {
            roll -= weights[min(index, weights.count - 1)]
            if roll < 0 { return candidate.0 }
        }
        return candidates[0].0
    }

    // MARK: - Convert Prospect to Player

    /// Creates a `Player` from a drafted `CollegeProspect` by scaling the prospect's
    /// true attributes down with the readiness-driven rookie factors of plan §3.1.
    /// Rookies start below their ceiling and must develop to reach their true
    /// potential. Rookie contract terms are based on pick number.
    ///
    /// Causality note: the scale is driven by `nflReadiness` / `trueLearning`, never
    /// by the pick number. Players fall in the draft because they are worse, not the
    /// other way round — so a pro-ready mid-rounder can legitimately out-play a raw
    /// first-rounder in year one (`docs/DRAFT_NFL_REFERENCE.md` §7).
    ///
    /// - Parameters:
    ///   - prospect: The college prospect being drafted.
    ///   - teamID: The UUID of the team drafting the player.
    ///   - pickNumber: The overall draft pick number (1-224).
    ///   - draftSeason: The calendar year of this draft, stamped onto the player
    ///     as draft provenance (#40). `nil` leaves the season unrecorded.
    ///   - salaryCap: The club's ACTUAL salary cap, in thousands (required —
    ///     task #87 / F5).
    /// - Returns: A fully initialized `Player` ready to be inserted into the data store.
    static func convertToPlayer(
        prospect: CollegeProspect,
        teamID: UUID,
        pickNumber: Int,
        draftSeason: Int? = nil,
        salaryCap: Int
    ) -> Player {
        let contract = rookieContract(pickNumber: pickNumber, salaryCap: salaryCap)
        let factors = rookieScaleFactors(
            readiness: prospect.nflReadiness,
            learning: prospect.trueLearning,
            potential: prospect.truePotential
        )

        let player = Player(
            firstName: prospect.firstName,
            lastName: prospect.lastName,
            position: prospect.position,
            age: prospect.age,
            yearsPro: 0,
            physical: scalePhysical(prospect.truePhysical, factor: factors.physical),
            mental: scaleMental(prospect.trueMental, factor: factors.mental),
            positionAttributes: scalePositionAttributes(
                prospect.truePositionAttributes, factor: factors.skill
            ),
            personality: prospect.truePersonality,
            truePotential: prospect.truePotential,
            teamID: teamID,
            contractYearsRemaining: contract.years,
            annualSalary: contract.salary,
            draftPickNumber: pickNumber,
            draftedByTeamID: teamID,
            draftSeason: draftSeason,
            draftRound: roundForPick(pickNumber)
        )
        copyProspectMetadata(from: prospect, to: player)
        return player
    }

    /// Carries the prospect-side fields that have a `Player` counterpart across the
    /// draft boundary. `learning` becomes the canonical playbook-absorption stat and
    /// the hometown pair feeds the FA-drama storylines — `CollegeProspect` documented
    /// that carry-over but nothing ever performed it, so every drafted player used to
    /// arrive hometown-less.
    private static func copyProspectMetadata(from prospect: CollegeProspect, to player: Player) {
        player.learning = Player.storedLearning(prospect.trueLearning)
        player.competitiveness = Player.storedCompetitiveness(prospect.trueCompetitiveness)
        // Anchor for the phase-2 ±8 lifetime potential-drift cap (plan §2.6):
        // stamped here so a player drafted from now on never needs the legacy
        // "seed on first touch" fallback.
        player.draftTruePotential = player.truePotential
        player.hometownState = prospect.hometownState
        player.hometownCity = prospect.hometownCity
        // Phase 4 faces: the prospect only ever held a PREVIEW face (a class is
        // 350 prospects, so reserving them would drain the pool every spring).
        // Signing him is the moment it becomes real — he keeps the face the
        // user scouted whenever it is still free, otherwise he draws a fresh
        // one from the same bucket.
        player.faceID = FaceLibrary.shared.claimFace(
            prospect.faceID,
            personID: player.id,
            role: .player,
            age: player.age,
            position: player.position
        )
        carryPreDraftInjury(from: prospect, to: player)
    }

    /// Pre-draft medical continuity (task #78, finding S15).
    ///
    /// `ScoutingEngine.applyPreDraftAttrition` tears about 2 % of every declared
    /// class up in the spring, writes the injury into `medicalConcerns` and
    /// knocks the man's projection down for it — and then the draft boundary
    /// threw the whole thing away. A prospect who blew a knee at his pro day in
    /// March reported to camp in July at full health, so the medical risk the
    /// user had been asked to price was a pure scouting-screen fiction.
    ///
    /// The note is decoded back into the shared `MedicalEngine` vocabulary and
    /// applied two ways:
    ///
    /// * it always lands in `injuryHistory`, so `Player.priorInjuryCount` and
    ///   every re-injury / durability read see it for the rest of his career; and
    /// * whatever recovery is still outstanding once the offseason calendar has
    ///   run (`preDraftToCampWeeks`) becomes a live injury, so the rookie who
    ///   tore something serious actually misses camp.
    private static func carryPreDraftInjury(from prospect: CollegeProspect, to player: Player) {
        guard let carry = ScoutingEngine.preDraftInjury(from: prospect.medicalConcerns) else { return }

        player.injuryHistory = player.injuryHistory + [
            InjuryRecord(injuryTypeRaw: carry.type.rawValue, weeksOut: carry.weeksOut)
        ]

        let residual = carry.weeksOut - ScoutingEngine.preDraftToCampWeeks
        guard residual > 0 else { return }
        player.isInjured = true
        player.injuryWeeksRemaining = residual
        // The PROGNOSIS, not the residual. `injuryWeeksOriginal` is the
        // denominator every medical surface divides by — the "6 of 14 weeks"
        // line, the rehab progress bar, `MedicalEngine`'s setback branch
        // (`remaining < original`, which can never fire against a zero) and
        // `WeekAdvancer`'s `>= 4` notability test. Leaving it at the model
        // default of 0 printed "6 of 0 weeks remaining" and made rookie rehab
        // the one injury in the game that cannot suffer a setback.
        player.injuryWeeksOriginal = carry.weeksOut
        player.injuryType = carry.type
        player.rehabStatus = .onTrack
    }

    /// Draft round (1-7) for an overall pick number, matching the 32-pick round
    /// layout used by `generateDraftOrder`. Clamped to 1...7.
    static func roundForPick(_ pickNumber: Int) -> Int {
        min(7, max(1, ((pickNumber - 1) / 32) + 1))
    }

    /// R24: Creates a `Player` from an UNDRAFTED prospect. UDFAs use the same
    /// readiness-driven scaling as drafted rookies plus the undrafted discount
    /// (see `rookieScaleFactors`), mirroring `convertToPlayer` but without a
    /// draft pick number.
    ///
    /// The deal is ``udfaContract(salaryCap:)`` — **three years** at ~0.30 % of
    /// cap, cap-relative. It was a flat `Int.random(in: 450...750)` on a
    /// 1-2 year term until task #89, which is what this comment used to describe;
    /// a one-year UDFA deal expired before the man had played a second season.
    static func convertUDFAToPlayer(
        prospect: CollegeProspect,
        teamID: UUID,
        salaryCap: Int
    ) -> Player {
        let factors = rookieScaleFactors(
            readiness: prospect.nflReadiness,
            learning: prospect.trueLearning,
            potential: prospect.truePotential,
            undrafted: true
        )
        let contract = udfaContract(salaryCap: salaryCap)
        let player = Player(
            firstName: prospect.firstName,
            lastName: prospect.lastName,
            position: prospect.position,
            age: prospect.age,
            yearsPro: 0,
            physical: scalePhysical(prospect.truePhysical, factor: factors.physical),
            mental: scaleMental(prospect.trueMental, factor: factors.mental),
            positionAttributes: scalePositionAttributes(
                prospect.truePositionAttributes, factor: factors.skill
            ),
            personality: prospect.truePersonality,
            truePotential: prospect.truePotential,
            teamID: teamID,
            contractYearsRemaining: contract.years,
            annualSalary: contract.salary
        )
        copyProspectMetadata(from: prospect, to: player)
        return player
    }

    // MARK: - Rookie Scaling

    /// The three attribute-group multipliers applied when a prospect becomes a Player.
    struct RookieScaleFactors {
        /// Applied to the position-specific skills (50 % of `Player.overall`).
        let skill: Double
        /// Applied to the physical attributes (30 %).
        let physical: Double
        /// Applied to the mental attributes (20 %).
        let mental: Double
    }

    /// Readiness-driven rookie scaling (plan §3.1). Replaces the old pick-number
    /// `rookieScaleFactor`, which had the causality backwards: it decided how good
    /// a rookie was from *where he was picked* rather than from what he is.
    ///
    /// - `skill` rises with `nflReadiness` — technique is what needs NFL coaching.
    /// - `physical` is near-flat: bodies arrive NFL-ready.
    /// - `mental` rises with `learning` — smart rookies pick up the pro game faster.
    ///
    /// **Calibration deviation from plan §3.1.** The plan lists
    /// `0.62 + readiness/99·0.28` / `0.97` / `0.80 + learning/99·0.12` *and* states
    /// the intent "day-1 OVR ≈ 70-85 % of true ability". Those two cannot both hold,
    /// because `scaleAttribute` interpolates from a **floor of 35**, not from zero:
    /// a factor of 0.83 on a 82-rated skill yields 74, i.e. 90 % — not 83 %.
    /// Measured over 60 simulated classes the literal constants put first-rounders
    /// at 76.5 OVR mean (93 % of true ability) against a league average of ~70.6,
    /// i.e. every first-rounder would arrive as an above-average starter and the #1
    /// pick as a top-10 player in the league on day one.
    ///
    /// The intercepts are therefore lowered while the plan's *spreads* (0.28 / 0.12)
    /// and the constant physical factor are kept verbatim, which preserves every
    /// relative statement the plan makes and only moves the level. Measured result
    /// (60 classes × 350): R1 72.6 [p05 68.1, p95 78.9] · R2 67.5 · R3 65.3 ·
    /// R4 63.9 · R5 62.9 · R6 62.0 · R7 61.3 · UDFA 55.1 [p05 52.1, p95 58.2] —
    /// inside the target bands (R1 68-76, UDFA 50-58, league avg ~70.6).
    ///
    /// **Phase-2 recalibration (plan §5 stage 5, the `career` harness).** Those
    /// levels made `DRAFT_NFL_REFERENCE.md` §6 unreachable *by arithmetic*. A
    /// first-rounder arriving at 72.6 is already at the league mean, so the
    /// primary-starter bar (OVR 75, the top ~third of the league per
    /// `DEVELOPMENT_NFL_REFERENCE.md` §8) sits **2.4 points away** — and the
    /// weakest development the realization model can produce (R at its 0.20
    /// clamp) still clears it. Measured hit rate: **98 %** against the
    /// reference's 55-65 %. There is no R weighting that fixes that; the
    /// distance from entry to the starter bar is what sets the hit rate.
    ///
    /// The intercepts are therefore lowered again so a rookie enters at roughly
    /// **70-75 % of his eventual level** — precisely the "rookies contribute at
    /// 55-85 % of eventual level" band in `DEVELOPMENT_NFL_REFERENCE.md` §2 —
    /// leaving the realization model 10-13 points of room to separate the
    /// ascenders from the busts inside the rookie deal. The plan's spreads
    /// (0.28 skill / 0.12 mental) are again untouched: only the level moves.
    ///
    /// **The rawness term (`potential`).** `DEVELOPMENT_NFL_REFERENCE.md` §2's
    /// "rookies contribute at 55-85 % of eventual level" is a BAND, and which end
    /// of it a rookie sits at is decided by how far his eventual level is from
    /// replacement: the 95-ceiling athletic project shows 55 % of what he will
    /// become, the 78-ceiling four-year college starter shows 85 %. Modelling
    /// that is what makes rookie-year play flat across the draft (which it
    /// empirically is — rookie starters come from every round) while career
    /// outcomes stay steeply slot-correlated (which they also are).
    ///
    /// Measured consequence (career harness, stage 5): without it a first-round
    /// rookie entered ~4 OVR above a seventh-rounder AND carried a 10-point
    /// higher ceiling, so his hit rate came out ~73 % against the reference's
    /// 55-65 % while rounds 3-7 flattened into each other. With it the entry
    /// levels compress to ~61-62 across the whole board and the ROUND signal is
    /// carried entirely by the ceiling, which is where the reference puts it.
    ///
    /// - Parameters:
    ///   - readiness: `CollegeProspect.nflReadiness` (25-95).
    ///   - learning: `CollegeProspect.trueLearning` (25-99).
    ///   - potential: `CollegeProspect.truePotential` — the eventual level the
    ///     rawness term measures the entry against. The default is the league's
    ///     typical intake ceiling, i.e. a neutral rawness of ~0.
    ///   - undrafted: `true` for UDFAs, who take an extra development discount —
    ///     no team spent a pick on them and their NFL starter rate is < 5 %
    ///     (`docs/DRAFT_NFL_REFERENCE.md` §6).
    static func rookieScaleFactors(
        readiness: Int,
        learning: Int,
        potential: Int = rawnessPivot,
        undrafted: Bool = false
    ) -> RookieScaleFactors {
        let readinessShare = Double(min(99, max(0, readiness))) / 99.0
        let learningShare = Double(min(99, max(0, learning))) / 99.0
        let rawness = min(1.0, max(0.0, Double(potential - rawnessPivot) / 23.0))
        return RookieScaleFactors(
            skill: 0.05 + readinessShare * 0.14 - rawness * 0.34 - (undrafted ? 0.03 : 0.0),
            physical: (undrafted ? 0.90 : 0.95) - rawness * 0.30,
            mental: 0.20 + learningShare * 0.20 - rawness * 0.36 - (undrafted ? 0.05 : 0.0)
        )
    }

    /// Ceiling at which the rawness term is zero — a prospect whose eventual
    /// level is only this high is, by definition, close to it already.
    ///
    /// **Task #32 re-derivation, 76 → 69.** This pivot is not a free constant:
    /// it is measured against `DraftClassBuilder`'s potential distribution, and
    /// that distribution moved when the intake ratchet was fixed (see
    /// `DraftClassBuilder.drawUpside`). Holding 76 while the board's mean
    /// potential fell 81.1 → 75.2 would have collapsed `rawness` toward zero for
    /// the whole board and handed every rookie a much higher ENTRY rating —
    /// exactly the §6 hit-rate inflation the phase-2 recalibration above was
    /// written to remove.
    ///
    /// The pivot is therefore re-solved on the new band means. It is fixed by
    /// the ONE thing it exists to control — where a rookie ENTERS — and that is
    /// measured end-to-end by the `career` scenario's `entryOVR` column:
    ///
    /// | band | old pot | new pot | (pot−69)/23 | old entryOVR | new entryOVR |
    /// |---|---|---|---|---|---|
    /// | R1 | 95.2 | 90.5 | 0.93 | 58.3 | 57.4 |
    /// | R2 | 89.1 | 86.9 | 0.78 | 59.0 | 58.2 |
    /// | R3 | 84.2 | 84.7 | 0.68 | 59.3 | 58.6 |
    /// | R4 | 80.3 | 78.2 | 0.40 | 59.3 | 58.8 |
    /// | R5 | 78.7 | 75.3 | 0.27 | 59.1 | 58.7 |
    /// | R6 | 76.3 | 72.5 | 0.15 | 59.0 | 58.6 |
    /// | R7 | 74.0 | 69.2 | 0.01 | 58.9 | 58.6 |
    /// | UDFA | 70.4 | 65.7 | 0    | 57.6 | 57.4 |
    ///
    /// i.e. entry is flat across the board (which is the point of the phase-2
    /// recalibration above — the ROUND signal lives in the ceiling, not in the
    /// day-one rating) and lands within 0.9 of where it was, so §6's hit-rate
    /// curve is being moved by the ceilings this wave changed and by nothing
    /// else. Holding the pivot at 76 instead would have zeroed the rawness term
    /// for rounds 5-7 and lifted the whole board's entry — the inflation the
    /// phase-2 note was written to remove. The `/23.0` divisor is unchanged.
    static let rawnessPivot = 69

    // MARK: - Rookie Familiarity

    /// Constant term of a rookie's day-one scheme familiarity — **the INTAKE
    /// term of the league's whole familiarity equilibrium (task #66).**
    ///
    /// ### Why the equilibrium has to clear 55
    ///
    /// `PlaySimulator.famBustPivot` is 55: at or above it a squad never rolls a
    /// blown assignment, below it every snap carries a bust chance and the
    /// completion channel is docked. `VersatilityDevelopmentEngine.unusedSchemeFloor`
    /// is the same 55, deliberately. So 55 is the line between "this room knows
    /// the playbook" and "this room is guessing" — and a LEAGUE-WIDE steady
    /// state that sits under it means every club in the game is permanently in
    /// the guessing regime, which makes the whole mechanic a flat tax instead of
    /// a difference between clubs.
    ///
    /// ### The equilibrium arithmetic
    ///
    /// `learnScheme` scales its gain by `headroom = (100 − F)/100`, so
    /// familiarity closes a fixed FRACTION of its gap to 100 every season:
    ///
    ///     100 − F(t+1) = (1 − c)·(100 − F(t))
    ///
    /// where `c` is the season's total learning weight ÷ 100. A season is one
    /// camp rep at intensity 1.0 plus 17 practice weeks at 0.5 = 9.5
    /// intensity-units, each worth `k = 1.5 · (coachability/70) · (expertise/60)
    /// · (playerDevelopment/70) · (learning/65)`, so `c ≈ 9.5·k/100 ≈ 0.13` for a
    /// league-typical player under a league-typical coordinator.
    ///
    /// That recurrence has no interior fixed point on its own — it converges to
    /// 100. What pins the LEAGUE MEAN below 100 is turnover: every season a
    /// share of the population is replaced by intake at `I` (this constant's
    /// formula) or reset to `VersatilityDevelopmentEngine.installBaseline` `B`
    /// by a coordinator change. With mean residency `n` seasons before a
    /// reset-or-exit, the population mean is the average of the trajectory
    /// starting from the entry level `E`:
    ///
    ///     F̄ = 100 − (100 − E)·(1 − (1−c)ⁿ)/(n·c)
    ///
    /// Measured on `tools/balance-harness`'s `career` scenario (20 leagues × 22
    /// measured seasons, 745 k player-seasons), the shipped stack ran at
    /// `E ≈ 33`, `c ≈ 0.13`, `n ≈ 5` → **F̄ = 53.9**, i.e. 1.1 points UNDER the
    /// bust pivot. Raising this floor 10 → 20 lifts `E` to ≈ 42 and the
    /// early-career term in `learnScheme` (`earlyCareerLearnBonus`) lifts `c` to
    /// ≈ 0.16 for the first four seasons, which is where the drag lives; the two
    /// together put the measured steady state at **59.8** — inside the 58-62
    /// target band, ~5 points of margin over the pivot. See the SCHEME FIT block
    /// of the `career` scenario for the measurement that replaces this estimate.
    ///
    /// Deliberately NOT fixed by moving `famBustPivot`: the pivot is a statement
    /// about football (a room that does not know the install busts assignments),
    /// the equilibrium is a statement about how fast the game teaches. The
    /// second one was wrong.
    static let rookieFamiliarityFloor = 20.0

    /// Weight a rookie's day-one familiarity puts on `CollegeProspect.nflReadiness`
    /// — "how much of this is already pro football".
    static let rookieFamiliarityReadinessWeight = 0.20

    /// Weight a rookie's day-one familiarity puts on `CollegeProspect.trueLearning`
    /// — the same stat `learnScheme` ramps on, so the man who will pick the
    /// playbook up fastest also walks in knowing more of it.
    static let rookieFamiliarityLearningWeight = 0.15

    /// What an undrafted signing gives up against a drafted rookie: he arrives
    /// after the install has started and takes third-team reps in it.
    static let rookieFamiliarityUDFAPenalty = 5.0

    /// Seeds a freshly converted rookie's position and scheme familiarity, mirroring
    /// `LeagueGenerator.initializePlayerFamiliarity` for veterans.
    ///
    /// Fixes the fam-0 bug: `convertToPlayer` never wrote `schemeFamiliarity`, so
    /// every rookie in the league entered at familiarity 0 and took the maximum
    /// scheme penalty — identically, regardless of how smart or pro-ready he was.
    ///
    /// Starting value is `rookieFamiliarityFloor + readiness·0.20 + learning·0.15`
    /// (≈ 25-55): below the 70 completion pivot and below the 55 bust pivot for all
    /// but the most pro-ready, so rookies still err, but a smart, pro-ready rookie
    /// ramps from ~55 while a raw one starts at ~25. UDFAs take a further −5.
    ///
    /// **Task #66 — this is the INTAKE term of the league's familiarity
    /// equilibrium.** See `rookieFamiliarityFloor` for the derivation of why it
    /// moved from 10 to 20.
    ///
    /// - Parameters:
    ///   - player: The freshly created rookie (mutated in place).
    ///   - prospect: The prospect he was converted from — supplies readiness/learning.
    ///   - offensiveScheme: The drafting team's OC scheme, if any.
    ///   - defensiveScheme: The drafting team's DC scheme, if any.
    ///   - isUndrafted: `true` for UDFA signings.
    static func initializeRookieFamiliarity(
        player: Player,
        prospect: CollegeProspect,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?,
        isUndrafted: Bool = false
    ) {
        // Primary position is always fully known.
        player.positionFamiliarity[player.position.rawValue] = 100

        let raw = rookieFamiliarityFloor
            + Double(prospect.nflReadiness) * rookieFamiliarityReadinessWeight
            + Double(prospect.trueLearning) * rookieFamiliarityLearningWeight
            - (isUndrafted ? rookieFamiliarityUDFAPenalty : 0.0)
        let starting = min(100, max(0, Int(raw.rounded())))

        switch player.position.side {
        case .offense:
            if let scheme = offensiveScheme {
                player.schemeFamiliarity[scheme.rawValue] = starting
            }
        case .defense:
            if let scheme = defensiveScheme {
                player.schemeFamiliarity[scheme.rawValue] = starting
            }
        case .specialTeams:
            // Specialists belong to no coordinator, so they are exposed to both
            // installs — the same treatment `assignCareerSchemeFamiliarity` gives
            // K/P veterans.
            if let scheme = offensiveScheme {
                player.schemeFamiliarity[scheme.rawValue] = starting
            }
            if let scheme = defensiveScheme {
                player.schemeFamiliarity[scheme.rawValue] = starting
            }
        }
    }

    /// Convenience overload for callers that hold the drafting team's staff rather
    /// than the resolved coordinator schemes.
    static func initializeRookieFamiliarity(
        player: Player,
        prospect: CollegeProspect,
        coaches: [Coach],
        isUndrafted: Bool = false
    ) {
        initializeRookieFamiliarity(
            player: player,
            prospect: prospect,
            offensiveScheme: coaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme,
            defensiveScheme: coaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme,
            isUndrafted: isUndrafted
        )
    }

    /// Scales a single attribute value: `floor + Int(Double(trueValue - floor) * factor)`.
    ///
    /// **Phase-2 recalibration (plan §5 stage 5, `career` harness).** The floor
    /// was 35 — an "empty" rating, far below anything an NFL roster carries — so
    /// the conversion was effectively `entry ≈ 0.6 × true ability` and the whole
    /// class arrived spread out in proportion to its true talent. Measured
    /// consequence: entry OVR ranged 72.6 (R1) down to 55.1 (UDFA), a 17-point
    /// gap, which put the primary-starter bar (75) within arm's reach of every
    /// first-rounder and out of reach of every seventh — hit rates 98 % / 0 %
    /// against `DRAFT_NFL_REFERENCE.md` §6's 60 % / 10 %.
    ///
    /// Raising the floor to a real replacement-level rating and shrinking the
    /// factors makes rookies converge on a common rookie level (~59-65 OVR)
    /// regardless of where they were picked — which is what actually happens:
    /// first-round and seventh-round rookies play about the same as ROOKIES.
    /// The round then shows up where it belongs, in `truePotential` and
    /// therefore in the development ceiling, over years 2-5. It also puts the
    /// entry level at 55-85 % of eventual level for everyone, exactly the band
    /// `DEVELOPMENT_NFL_REFERENCE.md` §2 gives — high-ceiling prospects land at
    /// the raw end of it, polished low-ceiling ones at the ready end.
    private static let attributeFloor = 52

    private static func scaleAttribute(_ trueValue: Int, factor: Double) -> Int {
        attributeFloor + Int(Double(trueValue - attributeFloor) * factor)
    }

    /// Scales physical attributes with the given factor.
    static func scalePhysical(_ attrs: PhysicalAttributes, factor: Double) -> PhysicalAttributes {
        PhysicalAttributes(
            speed: scaleAttribute(attrs.speed, factor: factor),
            acceleration: scaleAttribute(attrs.acceleration, factor: factor),
            strength: scaleAttribute(attrs.strength, factor: factor),
            agility: scaleAttribute(attrs.agility, factor: factor),
            stamina: scaleAttribute(attrs.stamina, factor: factor),
            durability: scaleAttribute(attrs.durability, factor: factor)
        )
    }

    /// Scales mental attributes with the given factor.
    /// Scales the mental attributes a rookie has NOT yet learned, and passes the
    /// ones he already is straight through.
    ///
    /// **Phase-2 fix (plan §5 stage 5).** This used to scale all six. Work ethic,
    /// coachability and leadership are character, not craft — a rookie does not
    /// arrive with 60 % of his own drive and grow into the rest — and scaling
    /// them had a measurable side effect: league work ethic collapsed to p50 60,
    /// which is the dominant term of the R factor's `base` and the gate on the
    /// §2.3 post-payday complacency trigger. `DEVELOPMENT_NFL_REFERENCE.md` §2
    /// lists work ethic among the differentiators that DECIDE a trajectory, so
    /// it has to arrive intact and stay a trait. Awareness, decision making and
    /// clutch are the pro-game learning curve and keep the discount — exactly
    /// the trio `applyCatchUpGrowth` then develops.
    static func scaleMental(_ attrs: MentalAttributes, factor: Double) -> MentalAttributes {
        MentalAttributes(
            awareness: scaleAttribute(attrs.awareness, factor: factor),
            decisionMaking: scaleAttribute(attrs.decisionMaking, factor: factor),
            clutch: scaleAttribute(attrs.clutch, factor: factor),
            workEthic: attrs.workEthic,
            coachability: attrs.coachability,
            leadership: attrs.leadership
        )
    }

    /// Scales position-specific attributes with the given factor.
    static func scalePositionAttributes(_ attrs: PositionAttributes, factor: Double) -> PositionAttributes {
        switch attrs {
        case .quarterback(let qb):
            return .quarterback(QBAttributes(
                armStrength: scaleAttribute(qb.armStrength, factor: factor),
                accuracyShort: scaleAttribute(qb.accuracyShort, factor: factor),
                accuracyMid: scaleAttribute(qb.accuracyMid, factor: factor),
                accuracyDeep: scaleAttribute(qb.accuracyDeep, factor: factor),
                pocketPresence: scaleAttribute(qb.pocketPresence, factor: factor),
                scrambling: scaleAttribute(qb.scrambling, factor: factor)
            ))
        case .wideReceiver(let wr):
            return .wideReceiver(WRAttributes(
                routeRunning: scaleAttribute(wr.routeRunning, factor: factor),
                catching: scaleAttribute(wr.catching, factor: factor),
                release: scaleAttribute(wr.release, factor: factor),
                spectacularCatch: scaleAttribute(wr.spectacularCatch, factor: factor)
            ))
        case .runningBack(let rb):
            return .runningBack(RBAttributes(
                vision: scaleAttribute(rb.vision, factor: factor),
                elusiveness: scaleAttribute(rb.elusiveness, factor: factor),
                breakTackle: scaleAttribute(rb.breakTackle, factor: factor),
                receiving: scaleAttribute(rb.receiving, factor: factor)
            ))
        case .tightEnd(let te):
            return .tightEnd(TEAttributes(
                blocking: scaleAttribute(te.blocking, factor: factor),
                catching: scaleAttribute(te.catching, factor: factor),
                routeRunning: scaleAttribute(te.routeRunning, factor: factor),
                speed: scaleAttribute(te.speed, factor: factor)
            ))
        case .offensiveLine(let ol):
            return .offensiveLine(OLAttributes(
                runBlock: scaleAttribute(ol.runBlock, factor: factor),
                passBlock: scaleAttribute(ol.passBlock, factor: factor),
                pull: scaleAttribute(ol.pull, factor: factor),
                anchor: scaleAttribute(ol.anchor, factor: factor)
            ))
        case .defensiveLine(let dl):
            return .defensiveLine(DLAttributes(
                passRush: scaleAttribute(dl.passRush, factor: factor),
                blockShedding: scaleAttribute(dl.blockShedding, factor: factor),
                powerMoves: scaleAttribute(dl.powerMoves, factor: factor),
                finesseMoves: scaleAttribute(dl.finesseMoves, factor: factor)
            ))
        case .linebacker(let lb):
            return .linebacker(LBAttributes(
                tackling: scaleAttribute(lb.tackling, factor: factor),
                zoneCoverage: scaleAttribute(lb.zoneCoverage, factor: factor),
                manCoverage: scaleAttribute(lb.manCoverage, factor: factor),
                blitzing: scaleAttribute(lb.blitzing, factor: factor)
            ))
        case .defensiveBack(let db):
            return .defensiveBack(DBAttributes(
                manCoverage: scaleAttribute(db.manCoverage, factor: factor),
                zoneCoverage: scaleAttribute(db.zoneCoverage, factor: factor),
                press: scaleAttribute(db.press, factor: factor),
                ballSkills: scaleAttribute(db.ballSkills, factor: factor)
            ))
        case .kicking(let k):
            return .kicking(KickingAttributes(
                kickPower: scaleAttribute(k.kickPower, factor: factor),
                kickAccuracy: scaleAttribute(k.kickAccuracy, factor: factor)
            ))
        }
    }

    // MARK: - Pick Value Chart

    /// Returns the trade value of a draft pick using a classic NFL-style value chart.
    ///
    /// - Pick 1 = 3000, Pick 32 ~= 590, Pick 224 = 2.
    /// - Values decrease steeply in early rounds and flatten in later rounds.
    ///
    /// - Parameter pickNumber: Overall pick number (1-224).
    /// - Returns: Integer value for trade evaluation purposes.
    static func pickValue(_ pickNumber: Int) -> Int {
        guard pickNumber >= 1 && pickNumber <= 224 else { return 0 }

        // Classic NFL Draft Trade Value Chart (simplified piecewise curve).
        // First round (1-32): steep decline from 3000.
        // Second round (33-64): moderate decline.
        // Rounds 3-7 (65-224): gradual decline to near-minimum.
        if pickNumber <= 32 {
            return firstRoundValue(pickNumber)
        } else if pickNumber <= 64 {
            return secondRoundValue(pickNumber)
        } else {
            return laterRoundValue(pickNumber)
        }
    }

    // Wave 5 cleanup: the draft-day trade brain that used to live here
    // (`evaluateTradeOffer`, `generateAITradeOffers` on the dead `TradeOffer`
    // model) was never called — `DraftDayTradeEngine` + `TradeValueEngine`
    // are the draft room's real trade path (docs/TRADE_OVERHAUL_PLAN.md §2).

    // MARK: - Media Commentary

    /// Generates a media grade, headline, and comment for a draft pick.
    ///
    /// Compares the prospect's projected round against the actual pick to determine
    /// whether the pick is a reach, solid, or great value. Need-match boosts the grade.
    ///
    /// - Parameters:
    ///   - prospect: The college prospect who was drafted.
    ///   - pickNumber: The overall pick number (1-224).
    ///   - teamNeeds: Positions the drafting team needs most.
    /// - Returns: A tuple of (grade, headline, comment).
    static func generateMediaGrade(
        prospect: CollegeProspect,
        pickNumber: Int,
        teamNeeds: [Position]
    ) -> (grade: String, headline: String, comment: String) {
        let gradeScale = ["A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F"]

        // Determine the actual round from pick number.
        let actualRound = ((pickNumber - 1) / 32) + 1

        // Determine the projected round (draftProjection is a round number, e.g. 1, 2, 3...).
        let projectedRound = prospect.draftProjection ?? actualRound

        // Base grade index: start at B (index 4).
        var gradeIndex = 4

        // Compare projected vs actual round.
        let roundDelta = actualRound - projectedRound
        // Negative delta = picked earlier than projected (reach), positive = picked later (value).

        if roundDelta < -1 {
            gradeIndex += 3 // Major reach: C- or worse
        } else if roundDelta == -1 {
            gradeIndex += 2 // Moderate reach: C+
        } else if roundDelta == 0 {
            gradeIndex -= 1 // Solid pick: B+
        } else if roundDelta == 1 {
            gradeIndex -= 2 // Good value: A-
        } else {
            gradeIndex -= 3 // Great value: A or A+
        }

        // Need match bonus: picking a position of need = +1 grade (lower index).
        if teamNeeds.contains(prospect.position) {
            gradeIndex -= 1
        }

        // High-talent bonus: if true overall >= 80, slight boost.
        if prospect.trueOverall >= 80 {
            gradeIndex -= 1
        }

        // Clamp to valid range.
        gradeIndex = max(0, min(gradeScale.count - 1, gradeIndex))
        let grade = gradeScale[gradeIndex]

        // Generate headline and comment.
        let teamAbbr = prospect.mockDraftTeam ?? "Team"
        let name = prospect.lastName
        let pos = prospect.position.rawValue
        let roundLabel = roundName(actualRound)

        let headline: String
        let comment: String

        if roundDelta >= 2 {
            // Great value
            let headlines = [
                "\(name) falls to \(roundLabel) \u{2014} steal!",
                "Incredible value: \(name) in \(roundLabel)!",
                "\(pos) \(name) is a draft-day steal!"
            ]
            headline = headlines[pickNumber % headlines.count]
            let comments = [
                "\(prospect.fullName) was projected to go much earlier. This is a tremendous value pick that could pay dividends for years.",
                "How did \(prospect.fullName) fall this far? A gift for the franchise that just landed a potential star at \(pos)."
            ]
            comment = comments[pickNumber % comments.count]
        } else if roundDelta == 1 {
            let headlines = [
                "Nice value on \(name) in \(roundLabel)",
                "\(name) slides just enough \u{2014} solid get"
            ]
            headline = headlines[pickNumber % headlines.count]
            comment = "\(prospect.fullName) was expected to go a round earlier. Getting a player of this caliber at pick \(pickNumber) is smart drafting."
        } else if roundDelta == 0 {
            let headlines = [
                "\(name) goes right where expected",
                "No surprises: \(pos) \(name) at pick \(pickNumber)"
            ]
            headline = headlines[pickNumber % headlines.count]
            comment = "\(prospect.fullName) lands right at his projected slot. A consensus pick that fills a roster need."
        } else if roundDelta == -1 {
            let headlines = [
                "Slight reach for \(name) at \(pickNumber)",
                "\(name) picked a bit early?"
            ]
            headline = headlines[pickNumber % headlines.count]
            comment = "\(prospect.fullName) was projected to go in the next round. A bit of a reach, but the talent is there if the coaching staff can develop him."
        } else {
            // Major reach
            let headlines = [
                "Surprising reach for \(name) at \(pickNumber)!",
                "Eyebrows raised: \(name) goes early",
                "Bold pick: \(pos) \(name) at \(pickNumber)"
            ]
            headline = headlines[pickNumber % headlines.count]
            let comments = [
                "\(prospect.fullName) was not expected to go this early. The front office must see something the rest of us don't.",
                "This is a head-scratcher. \(prospect.fullName) was projected much later. A risky move that needs to pan out."
            ]
            comment = comments[pickNumber % comments.count]
        }

        return (grade: grade, headline: headline, comment: comment)
    }

    // MARK: - Staff Recommendations

    /// A single coaching staff recommendation for a draft pick.
    struct StaffRecommendation: Identifiable {
        let id = UUID()
        let staffTitle: String
        let message: String
        let prospectID: UUID
        let icon: String
        /// Detailed reasoning explaining why this prospect is recommended.
        var reason: String = ""
    }

    /// Generates 2-3 coaching staff recommendations based on team needs and available prospects.
    ///
    /// - Parameters:
    ///   - availableProspects: Prospects still on the board.
    ///   - teamNeeds: Positions the team needs most (sorted by priority).
    ///   - coaches: The team's coaching staff.
    /// - Returns: An array of 2-3 staff recommendations.
    static func generateStaffRecommendations(
        availableProspects: [CollegeProspect],
        teamNeeds: [Position],
        coaches: [Coach]
    ) -> [StaffRecommendation] {
        guard !availableProspects.isEmpty else { return [] }

        var recommendations: [StaffRecommendation] = []

        // Find the OC's recommendation (offensive need).
        let offensivePositions: Set<Position> = [.QB, .RB, .FB, .WR, .TE, .LT, .LG, .C, .RG, .RT]
        let offensiveNeeds = teamNeeds.filter { offensivePositions.contains($0) }
        let bestOffensive = availableProspects
            .filter { offensivePositions.contains($0.position) }
            .sorted { ($0.scoutedOverall ?? $0.consensusOverall) > ($1.scoutedOverall ?? $1.consensusOverall) }
            .first

        if let prospect = bestOffensive {
            let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
            let title = oc.map { "\($0.lastName), OC" } ?? "Offensive Coordinator"
            let needsMatch = offensiveNeeds.contains(prospect.position)
            let message: String
            let reason: String
            let schemeName = oc?.offensiveScheme.map { "\($0)" } ?? "our offense"
            if needsMatch {
                message = "We need to address \(prospect.position.rawValue). \(prospect.fullName) is the best available and fills a real gap."
                let posGrade = gradeForPositionGroup(prospect.position, needs: teamNeeds)
                reason = "Your \(prospect.position.rawValue) corps is weak (\(posGrade) grade). \(prospect.fullName) fits \(schemeName) and can start Day 1."
            } else {
                message = "\(prospect.fullName) is the best offensive talent on the board. Too good to pass up at \(prospect.position.rawValue)."
                reason = "\(prospect.fullName) is a premium talent at \(prospect.position.rawValue). Even without an immediate need, this caliber of player elevates \(schemeName)."
            }
            recommendations.append(StaffRecommendation(
                staffTitle: title,
                message: message,
                prospectID: prospect.id,
                icon: "sportscourt.fill",
                reason: reason
            ))
        }

        // Find the DC's recommendation (defensive need).
        let defensivePositions: Set<Position> = [.DE, .DT, .OLB, .MLB, .CB, .FS, .SS]
        let defensiveNeeds = teamNeeds.filter { defensivePositions.contains($0) }
        let bestDefensive = availableProspects
            .filter { defensivePositions.contains($0.position) }
            .sorted { ($0.scoutedOverall ?? $0.consensusOverall) > ($1.scoutedOverall ?? $1.consensusOverall) }
            .first

        if let prospect = bestDefensive, prospect.id != bestOffensive?.id {
            let dc = coaches.first(where: { $0.role == .defensiveCoordinator })
            let title = dc.map { "\($0.lastName), DC" } ?? "Defensive Coordinator"
            let needsMatch = defensiveNeeds.contains(prospect.position)
            let message: String
            let reason: String
            if needsMatch {
                message = "There's a talented \(prospect.position.rawValue) still on the board. \(prospect.fullName) can transform our defense."
                let isPassRusher = prospect.position == .DE || prospect.position == .OLB
                if isPassRusher {
                    reason = "Pass rush is your biggest defensive need. \(prospect.fullName) projects as an immediate edge threat in our scheme."
                } else {
                    let posGrade = gradeForPositionGroup(prospect.position, needs: teamNeeds)
                    reason = "Your \(prospect.position.rawValue) group grades out at \(posGrade). \(prospect.fullName) fills a critical gap and can compete for a starting role."
                }
            } else {
                message = "\(prospect.fullName) is an elite \(prospect.position.rawValue) prospect. He'd be an instant impact player on this defense."
                reason = "\(prospect.fullName) is too talented to pass up. Best defensive player on the board regardless of need."
            }
            recommendations.append(StaffRecommendation(
                staffTitle: title,
                message: message,
                prospectID: prospect.id,
                icon: "shield.fill",
                reason: reason
            ))
        }

        // Chief Scout's sleeper pick: highest potential prospect that isn't already recommended.
        let alreadyRecommended = Set(recommendations.map(\.prospectID))
        let sleeperPick = availableProspects
            .filter { !alreadyRecommended.contains($0.id) }
            .sorted { $0.truePotential > $1.truePotential }
            .first

        if let prospect = sleeperPick {
            let scoutName = coaches.first(where: { $0.role == .headCoach })
            let title = scoutName.map { "Scout (\($0.lastName)'s staff)" } ?? "Chief Scout"
            let message = "\(prospect.fullName) is my sleeper pick. Our scouts had him rated higher than the public boards. He's got serious upside at \(prospect.position.rawValue)."
            let reason = "\(prospect.fullName) is my sleeper. His combine numbers don't match his tape \u{2014} he plays faster than he tests. Potential ceiling is elite."
            recommendations.append(StaffRecommendation(
                staffTitle: title,
                message: message,
                prospectID: prospect.id,
                icon: "binoculars.fill",
                reason: reason
            ))
        }

        return recommendations
    }

    /// Returns the top team need positions sorted by priority (highest need first).
    static func topTeamNeeds(roster: [Player], limit: Int = 5) -> [Position] {
        guard !roster.isEmpty else { return [] }
        let needs = evaluateTeamNeeds(roster: roster)
        return needs.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    // MARK: - Fan Reactions / Social Media

    /// Generates 3-5 social media style fan reactions for a draft pick.
    ///
    /// - Parameters:
    ///   - prospect: The college prospect who was drafted.
    ///   - pickNumber: The overall pick number (1-224).
    ///   - teamNeeds: Positions the drafting team needs most.
    ///   - gmName: The player's GM name (for personalized tweets).
    /// - Returns: An array of 3-5 fan reaction strings.
    static func generateFanReaction(
        prospect: CollegeProspect,
        pickNumber: Int,
        teamNeeds: [Position],
        gmName: String = "GM"
    ) -> [String] {
        let actualRound = ((pickNumber - 1) / 32) + 1
        let projectedRound = prospect.draftProjection ?? actualRound
        let roundDelta = actualRound - projectedRound
        let needsMatch = teamNeeds.contains(prospect.position)
        let pos = prospect.position.rawValue
        let name = prospect.lastName

        var pool: [String] = []

        // Great value + fills a need
        if roundDelta >= 1 && needsMatch {
            pool.append("LETS GOOO! Perfect pick! \u{1F525}")
            pool.append("Steal of the draft! \(name) at \(pos)! \u{1F4AA}")
            pool.append("I literally screamed. \(name) was my #1 choice \u{1F389}")
        }

        // Good value pick
        if roundDelta >= 1 {
            pool.append("How did \(name) fall to us?? Christmas came early \u{1F381}")
            pool.append("Great value. \(name) is gonna be a problem \u{1F60F}")
        }

        // Fills a need
        if needsMatch {
            pool.append("Finally addressing \(pos)! About time \u{1F64F}")
            pool.append("We NEEDED a \(pos) so badly. Smart pick \u{2705}")
        }

        // Reach pick
        if roundDelta < -1 {
            pool.append("Who?? Never heard of this guy \u{1F610}")
            pool.append("This is a REACH. Could've gotten him way later \u{1F926}")
            pool.append("I'm gonna be sick. What are we doing?? \u{1F922}")
        }

        // Moderate reach
        if roundDelta == -1 {
            pool.append("Hmm, bit of a reach but I trust the process \u{1F914}")
            pool.append("Slight reach imo but let's see \u{1F440}")
        }

        // Neutral / trust the GM
        pool.append("In \(gmName) we trust \u{1F4AA}")
        pool.append("Welcome to the squad \(name)! \u{1F3C8}")

        // QB-specific reactions
        if prospect.position == .QB {
            if needsMatch {
                pool.append("FRANCHISE QB!! \u{1F451}")
            } else {
                pool.append("Another QB? What about the defense?? \u{1F620}")
            }
        }

        // Missed opportunity reactions (if QB was a need but they didn't draft one)
        if teamNeeds.first == .QB && prospect.position != .QB {
            pool.append("Trade up for a QB! Why didn't we!? \u{1F624}")
            pool.append("So we're just gonna ignore the QB situation huh \u{1F644}")
        }

        // Pick 3-5 unique reactions
        pool.shuffle()
        let count = min(pool.count, Int.random(in: 3...5))
        return Array(pool.prefix(count))
    }

    // MARK: - Private Helpers

    /// Returns a letter grade for a position group based on how high the need is.
    private static func gradeForPositionGroup(_ position: Position, needs: [Position]) -> String {
        guard let index = needs.firstIndex(of: position) else { return "B" }
        switch index {
        case 0: return "D"
        case 1: return "C-"
        case 2: return "C"
        case 3: return "C+"
        default: return "B-"
        }
    }

    /// Returns a human-readable round name.
    private static func roundName(_ round: Int) -> String {
        switch round {
        case 1: return "Round 1"
        case 2: return "Round 2"
        case 3: return "Round 3"
        case 4: return "Round 4"
        case 5: return "Round 5"
        case 6: return "Round 6"
        case 7: return "Round 7"
        default: return "Round \(round)"
        }
    }

    /// Sorts records so the worst team comes first (lowest win percentage).
    private static func worstFirst(_ lhs: StandingsRecord, _ rhs: StandingsRecord) -> Bool {
        if lhs.winPercentage != rhs.winPercentage {
            return lhs.winPercentage < rhs.winPercentage
        }
        // Tiebreaker: worse point differential picks earlier.
        return lhs.pointDifferential < rhs.pointDifferential
    }

    /// Evaluates which positions a team needs most.
    /// Returns a dictionary of position -> multiplier (> 1.0 means higher need).
    private static func evaluateTeamNeeds(roster: [Player]) -> [Position: Double] {
        teamNeedComponents(roster: roster).mapValues { $0.multiplier * $0.weight }
    }

    /// The two halves of a need score, kept apart.
    ///
    /// `evaluateTeamNeeds` multiplies them together and the product is all any
    /// caller could read, which hid a real distinction: **`multiplier` is
    /// evidence, `weight` is opinion.** The multiplier is a fact about this
    /// roster — a body short of the ideal count, or a position group whose mean
    /// grades under 70 — and sits at exactly 1.0 when the club has no problem
    /// there at all. The weight is the league-wide positional-value ranking
    /// (QB/DE/CB/WR/LT at 1.0, K/P at 0.3) and is the same for all 32 clubs.
    ///
    /// So on a full 53-man roster, where the ideal counts sum to 48 and genuine
    /// deficits are rare, `topTeamNeeds` returns the weight-1.0 quintet
    /// {QB, DE, CB, WR, LT} for *every club in the league* — a positional-value
    /// table wearing a need model's clothes. That is fine for the draft board it
    /// was written for (where "best available at a premium position" is a real
    /// strategy) and wrong for anything that means "this club has a hole": see
    /// ``teamNeedDeficits``.
    private static func teamNeedComponents(
        roster: [Player]
    ) -> [Position: (multiplier: Double, weight: Double)] {
        // Ideal roster composition targets (starters per position).
        let idealCounts: [Position: Int] = [
            .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
            .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
            .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
            .CB: 5, .FS: 2, .SS: 2,
            .K: 1, .P: 1
        ]

        // Count current roster players by position.
        var currentCounts: [Position: Int] = [:]
        for player in roster {
            currentCounts[player.position, default: 0] += 1
        }

        // Calculate average overall by position to detect quality gaps.
        var positionOveralls: [Position: [Int]] = [:]
        for player in roster {
            positionOveralls[player.position, default: []].append(player.overall)
        }

        var needs: [Position: (multiplier: Double, weight: Double)] = [:]
        for position in Position.allCases {
            let ideal = idealCounts[position] ?? 1
            let current = currentCounts[position] ?? 0
            let deficit = max(0, ideal - current)

            // Base multiplier: higher deficit = higher need.
            var multiplier = 1.0 + Double(deficit) * 0.15

            // If the team has players at this position but they are low-rated, boost need.
            if let overalls = positionOveralls[position], !overalls.isEmpty {
                let avgOverall = Double(overalls.reduce(0, +)) / Double(overalls.count)
                if avgOverall < 60.0 {
                    multiplier += 0.2
                } else if avgOverall < 70.0 {
                    multiplier += 0.1
                }
            } else {
                // No players at all at this position — significant need.
                multiplier += 0.3
            }

            // Apply positional value weight — K/P should rarely surface as top needs.
            let positionalWeight: Double
            switch position {
            case .QB, .DE, .CB, .WR, .LT:
                positionalWeight = 1.0
            case .DT, .OLB, .MLB, .FS, .SS, .TE:
                positionalWeight = 0.8
            case .RB, .RG, .LG, .C, .RT, .FB:
                positionalWeight = 0.6
            case .K, .P:
                positionalWeight = 0.3
            }

            needs[position] = (multiplier: multiplier, weight: positionalWeight)
        }

        return needs
    }

    /// The positions where this roster has a GENUINE hole, best first.
    ///
    /// The deficit-only sibling of ``topTeamNeeds``, and the one a market should
    /// read. `topTeamNeeds` ranks by `multiplier × positionalWeight`, and on a
    /// full roster the multiplier is 1.0 nearly everywhere (ideal counts sum to
    /// 48 against a 53-man roster), so the ranking collapses to the positional
    /// weights and hands back the identical quintet {QB, DE, CB, WR, LT} for
    /// every club in the league. Used as a *need* signal that is not a nudge, it
    /// is a blanket league-wide premium on five positions: free agency's
    /// `topNeedBonus` was multiplying the same five for all 32 clubs, and the
    /// AI's own-core re-sign was reading "we need this position" for any
    /// quarterback, end, corner, receiver or left tackle alive.
    ///
    /// This returns only positions whose EVIDENCE half clears 1.0 — a body short
    /// of the ideal count, a group averaging under 70, or nobody there at all —
    /// so an empty result is a real and common answer: a well-built roster has no
    /// holes and gets no bonus. Ranking among the survivors still uses the full
    /// score, so positional value decides WHICH holes matter most; it just no
    /// longer invents them.
    ///
    /// Deterministically ordered. `topTeamNeeds` sorts a `Dictionary` on value
    /// alone, and Swift's per-process `Dictionary` seed means equal scores — which
    /// is exactly what a full roster produces — come back in a different order in
    /// every run of the game. The `rawValue` tiebreak makes the same roster
    /// return the same list twice, which a bonus this visible needs.
    ///
    /// ``topTeamNeeds`` is deliberately left alone: the draft room and
    /// `WeekAdvancer.refillAIRosters` want the value ranking they were built on.
    static func teamNeedDeficits(roster: [Player], limit: Int = 5) -> [Position] {
        guard !roster.isEmpty else { return [] }
        var scored: [(position: Position, score: Double)] = []
        for (position, components) in teamNeedComponents(roster: roster) {
            guard components.multiplier > 1.0 else { continue }
            scored.append((position: position, score: components.multiplier * components.weight))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.position.rawValue < rhs.position.rawValue
        }
        return scored.prefix(limit).map(\.position)
    }

    // MARK: - Rookie Wage Scale (task #89)

    /// The rookie wage scale, as cap SHARE anchors at named draft slots.
    ///
    /// ## Why this is a curve and not a step table
    ///
    /// This used to be an eleven-branch `switch` on the pick number — a stair,
    /// not a slope. Picks 17 and 32 were paid the same money; so were 33 and 64,
    /// and 65 and 100. The real rookie scale is strictly monotonic per pick, and
    /// the flat tiers had a second cost: `rookieContractBand` reads the first and
    /// last pick of a round, so a prospect screen printed "~$5M / 4yr" for the
    /// whole of rounds 2, 3, 5, 6 and 7 as if a round were one price.
    ///
    /// The LEVELS were the larger defect. Measured at a $265M cap the old table
    /// paid #1 overall **$39.75M (15.0 % of cap)** against a real slot of
    /// 3.9-4.3 %, and every slot through #100 ran 1.7-3.6× reality. A whole draft
    /// class cost a club **10.4 % of cap** in year one (real: ~4-5 %), a #1 pick
    /// was paid more than a 90-OVR quarterback in his prime and **22× his own
    /// market value**, and `TradeValueEngine.contractMultiplier` therefore
    /// stamped every first-rounder with the ×0.8 "overpaid contract" penalty —
    /// the game inverted the most valuable asset class in the sport.
    ///
    /// The anchors below are the real NFL slot shares (2024 scale, $255.4M cap),
    /// interpolated log-linearly between so every pick differs from its
    /// neighbour. Cap-relative, so the scale grows with the cap the way the real
    /// one does.
    private static let rookieSlotAnchors: [(pick: Double, capPercent: Double)] = [
        (1,   4.10),   // #1 overall — a real top slot, ~$10.9M at a $265M cap
        (5,   3.05),
        (10,  2.40),
        (16,  1.95),
        (32,  1.50),   // end of round 1
        (64,  0.75),   // end of round 2
        (100, 0.55),   // round 3
        (160, 0.42),   // round 5
        (224, 0.38)    // round 7 — still above the veteran minimum, as in life
    ]

    /// The veteran minimum as a cap SHARE — the same `0.28 %` the free-agent
    /// market, the negotiation engine and ``rookieContract`` floor money at,
    /// expressed on this table's scale so the curve below can stop there.
    private static let veteranMinimumCapPercent = 0.28

    /// Cap share of one draft slot, log-linearly interpolated across
    /// ``rookieSlotAnchors``. Strictly decreasing per pick until it reaches the
    /// veteran minimum.
    ///
    /// **Past the last anchor the curve keeps going.** It used to return #224's
    /// share flat for every pick beyond it, which was fine while 224 was the last
    /// pick in the draft and stopped being fine the moment compensatory picks
    /// shipped: `CompensatoryPickEngine.applyAwards` splices the awards into the
    /// pool and RENUMBERS the whole thing 1…N, so a normal league year runs to
    /// ~230-256 and every pick past 224 was paid the identical #224 slot. The end
    /// of round 7 — the one stretch of the draft where the money genuinely is
    /// almost flat — was the only place the scale had a step left in it.
    ///
    /// The extension is the FINAL SEGMENT'S own slope continued: same
    /// log-linear rate the 160 → 224 stretch decays at (−0.156 % a pick), so
    /// there is no kink at the join, floored at the veteran minimum because no
    /// contract in the league pays less than that. At the slope above the floor
    /// binds around pick 419, i.e. never in practice — a 256-pick league year
    /// ends at 0.362 %, comfortably above it — so the tail is strictly
    /// decreasing across every draft the game can actually produce, and the floor
    /// is there to make that a guarantee rather than an observation.
    static func rookieSlotCapPercent(pickNumber: Int) -> Double {
        let p = Double(max(1, pickNumber))
        guard let first = rookieSlotAnchors.first, let last = rookieSlotAnchors.last else { return 0.38 }
        if p <= first.pick { return first.capPercent }
        if p >= last.pick {
            guard rookieSlotAnchors.count >= 2 else { return last.capPercent }
            let previous = rookieSlotAnchors[rookieSlotAnchors.count - 2]
            let span = last.pick - previous.pick
            guard span > 0 else { return last.capPercent }
            let slope = (log(last.capPercent) - log(previous.capPercent)) / span
            let extrapolated = exp(log(last.capPercent) + slope * (p - last.pick))
            return max(veteranMinimumCapPercent, extrapolated)
        }
        for index in 0..<(rookieSlotAnchors.count - 1) {
            let low = rookieSlotAnchors[index]
            let high = rookieSlotAnchors[index + 1]
            guard p >= low.pick, p <= high.pick else { continue }
            let t = (p - low.pick) / (high.pick - low.pick)
            return exp(log(low.capPercent) + t * (log(high.capPercent) - log(low.capPercent)))
        }
        return last.capPercent
    }

    /// Rookie contract years and salary for a draft slot.
    ///
    /// **Every drafted round is four years.** It used to be four for rounds 1-4
    /// and three for 5-7, which is not the rule the league runs: all seven rounds
    /// sign four-year deals. Undrafted free agents sign three
    /// (``udfaContract(salaryCap:)``).
    ///
    /// Floored at the veteran minimum — the same `max(0.28 % · cap, 750)` the
    /// free-agent market and the negotiation engine use — because no rookie deal
    /// can pay less than the league minimum.
    static func rookieContract(pickNumber: Int, salaryCap: Int) -> (years: Int, salary: Int) {
        let capPercent = rookieSlotCapPercent(pickNumber: pickNumber)
        let veteranMinimum = max(Int(0.0028 * Double(salaryCap)), 750)
        let salary = max(Int(capPercent * Double(salaryCap) / 100.0), veteranMinimum)
        return (years: 4, salary: salary)
    }

    /// The undrafted deal: three years at ~0.30 % of cap.
    ///
    /// This was the one piece of rookie money in the game that never became
    /// cap-relative (task #87 / F3) — a flat `Int.random(in: 450...750)` on a
    /// `Int.random(in: 1...2)`-year deal, so a UDFA on a $600M cap thirty seasons
    /// in was still being paid 2026 money, and half of them expired before they
    /// had played a second season. Real UDFA deals are three years at the
    /// minimum-plus.
    static func udfaContract(salaryCap: Int) -> (years: Int, salary: Int) {
        let veteranMinimum = max(Int(0.0028 * Double(salaryCap)), 750)
        return (years: 3, salary: max(Int(0.0030 * Double(salaryCap)), veteranMinimum))
    }

    /// The rookie-money BAND for a projected draft round, at a given cap —
    /// the same ``rookieContract`` slots the draft actually writes, read from
    /// the first and last pick of the round (task #87 / F17).
    ///
    /// `ProspectDetailView` used to print its own hardcoded round→band table
    /// ("~$12-40M / 4yr"), which never called this engine and never moved with
    /// the cap, so the number a user read on a prospect and the number the draft
    /// wrote him were unrelated.
    ///
    /// Task #89: this now reports a real band. While the slot table was a step
    /// function the two ends of rounds 2, 3, 5, 6 and 7 were the SAME number, so
    /// the prospect screen printed "~$5M / 4yr" for a whole round as if the round
    /// were one price; ``rookieSlotCapPercent`` is strictly decreasing per pick,
    /// so `low < high` everywhere.
    static func rookieContractBand(round: Int, salaryCap: Int) -> (low: Int, high: Int, years: Int) {
        let clamped = min(max(round, 1), 7)
        let firstPick = (clamped - 1) * 32 + 1
        let lastPick = clamped * 32
        let top = rookieContract(pickNumber: firstPick, salaryCap: salaryCap)
        let bottom = rookieContract(pickNumber: lastPick, salaryCap: salaryCap)
        return (low: min(top.salary, bottom.salary),
                high: max(top.salary, bottom.salary),
                years: top.years)
    }

    // MARK: - Pick Value Chart Internals

    /// First round pick values (1-32). Steep decline.
    private static func firstRoundValue(_ pick: Int) -> Int {
        // Piecewise linear approximation of the classic Jimmy Johnson chart.
        let values: [Int: Int] = [
            1: 3000, 2: 2600, 3: 2200, 4: 1800, 5: 1700,
            6: 1600, 7: 1500, 8: 1400, 9: 1350, 10: 1300,
            11: 1250, 12: 1200, 13: 1150, 14: 1100, 15: 1050,
            16: 1000, 17: 950, 18: 900, 19: 875, 20: 850,
            21: 800, 22: 780, 23: 760, 24: 740, 25: 720,
            26: 700, 27: 680, 28: 660, 29: 640, 30: 620,
            31: 600, 32: 590
        ]
        return values[pick] ?? 590
    }

    /// Second round pick values (33-64). Moderate decline.
    private static func secondRoundValue(_ pick: Int) -> Int {
        // Linearly interpolate from ~580 down to ~270.
        let start = 580.0
        let end = 270.0
        let progress = Double(pick - 33) / 31.0
        return Int(start - (start - end) * progress)
    }

    /// Rounds 3-7 pick values (65-224). Gradual decline to near-minimum.
    private static func laterRoundValue(_ pick: Int) -> Int {
        // Linearly interpolate from ~260 down to 2.
        let start = 260.0
        let end = 2.0
        let progress = Double(pick - 65) / 159.0
        return max(2, Int(start - (start - end) * progress))
    }
}
