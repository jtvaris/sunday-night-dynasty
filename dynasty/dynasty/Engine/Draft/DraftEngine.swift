import Foundation

/// Stateless engine that handles all NFL Draft logic: order generation,
/// AI pick selection, prospect-to-player conversion, pick value chart,
/// and trade evaluation.
enum DraftEngine {

    // MARK: - Draft Setup

    /// Generates the full 7-round, 224-pick draft order based on reverse standings.
    ///
    /// - Playoff teams pick later in each round.
    /// - The Championship runner-up picks 31st; the Championship winner picks 32nd.
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
    /// record first, then playoff teams by record, then the Championship runner-up,
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

        // Identify the Championship participants from playoff games.
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

        // Sort playoff teams worst-to-best among those eliminated before the Championship.
        playoffRecords.sort { worstFirst($0, $1) }

        // Build the pick order: non-playoff (worst first), then playoff losers,
        // then Championship runner-up, then Championship winner.
        var orderedTeamIDs: [UUID] = nonPlayoffRecords.map(\.teamID)
            + playoffRecords.map(\.teamID)

        if let loserID = superBowlLoserID {
            orderedTeamIDs.append(loserID)
        }
        if let winnerID = superBowlWinnerID {
            orderedTeamIDs.append(winnerID)
        }

        // Ensure we have exactly 32 teams. If Championship IDs could not be determined
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
    /// ## Why the score is a SUM and not a product (task #155)
    ///
    /// This used to read `perceivedOverall * needMultiplier`, where the
    /// multiplier is `teamNeedComponents`' `multiplier × weight` — evidence
    /// times *league positional value*, the latter running 0.3 (K/P) to 1.0
    /// (QB/DE/CB/WR/LT). Multiplying a 40-99 rating by 0.3-1.0 does not tilt a
    /// board, it replaces it: two men the media had within a slot of each other
    /// came out 40 points apart if one played end and the other centre. The
    /// measured consequence, from the `perception` scenario's public-board
    /// diagnostic, was a round 1 that was **93 % premium-weight positions**
    /// (DE 30 %, QB 24 %, LT 13 %, WR 10 %, CB 8 %) with *zero* interior
    /// linemen, tackles, safeties or backs, and AI picks sitting a mean **61
    /// slots** off the public board in round 1 — every club reaching, every
    /// year, in the same direction.
    ///
    /// Positional value is real, and `DraftIntel.mediaConsensusOrder` leaves it
    /// out of the public board *on purpose* ("positional value is baked into the
    /// class blueprint"). So it belongs here — as an ADDITIVE tilt in rating
    /// points, the currency a war room actually argues in ("we'd take the end a
    /// round early"), where its size is legible and bounded. Every term below is
    /// in OVR points for the same reason.
    ///
    /// ## The consensus anchor was inert (task #155)
    ///
    /// The old "consensus value" term read `(100 - draftProjection) * 0.05`.
    /// `draftProjection` is a ROUND, 1...8 — never a pick number — so the bonus
    /// was 4.60...4.95 for the entire class: a constant, added to every score,
    /// cancelling out of every comparison. The AI board was anchored to nothing
    /// public at all. It now reads the media's published opinion at the
    /// resolution the media actually has it (`consensusSlot` below).
    ///
    /// ## There is one other AI pick function, and it is not this one
    ///
    /// `FantasyDraftEngine.aiPickIndex` scores the career-creation fantasy
    /// re-draft. It is a separate brain ON PURPOSE — different population
    /// (rostered players, not prospects), no fog, no public board, 53 rounds —
    /// and the reasoning is written out in full at its own declaration (F-71).
    /// The one thing the two share is the positional-value ladder, which both
    /// read off ``draftPositionalWeight``. If you change a term below, check
    /// whether it belongs there too; the answer is usually no.
    ///
    /// ## The board is a PLAN, not a die (D3's refinement)
    ///
    /// Three things arrived together and they are one idea:
    ///
    /// - **House taste** (`GMTaste`, F-26). Two permanent, deterministic
    ///   preferences per club, bounded at 4.0 OVR points in total. This is the
    ///   term that makes one AI board *recognisable* rather than merely wrong.
    /// - **Round-scaled need** (`needRoundScale`, F-29) and the **position run**
    ///   (`positionRunPoints` / `quarterbackRunPremium`, F-27). Both needed the
    ///   two inputs this function never received — `pickNumber` and
    ///   `recentPositions` — which is why they landed together.
    /// - **The top-4 weighted-random draw is gone** (F-62). It used to pick the
    ///   board-topper ~65 % of the time and one of the next three otherwise:
    ///   over a 350-man board whose top four sit within a point or two of each
    ///   other, that moved a pick by a handful of true-board slots and moved
    ///   nothing else. It was the one place in the model where the error came
    ///   from a die rolled at the moment of decision rather than from
    ///   information or philosophy, which is precisely what the design ruling
    ///   rejects. Everything above replaces it with error that has a cause.
    ///
    /// - Parameters:
    ///   - team: The team making the pick.
    ///   - availableProspects: Prospects still on the board.
    ///   - teamRoster: Current players on the team's roster.
    ///   - pickNumber: The overall pick number, 1-based. `0` (the default) means
    ///     "no slot context" and yields the round-NEUTRAL board — need weighted
    ///     as it is in rounds 2-3. One caller relies on that default,
    ///     `MultiSeasonSmokeTest.runAIDraft`, so its headless draft measures a
    ///     board without F-29's round scaling; noted here rather than silently,
    ///     because the next audit should either thread the pick number through
    ///     it or record that the divergence is intended.
    ///   - recentPositions: The positions taken by the league in pick order, most
    ///     recent LAST. Only the tail is read. Empty (the default) disables the
    ///     run model, which is the correct behaviour for any caller that does
    ///     not have a league-wide pick history.
    ///   - perceptionEnabled: `false` scores the TRUE board — the pre-fog
    ///     behaviour, kept as the control arm for the `perception` balance
    ///     scenario. No shipping call site passes it.
    ///   - tasteEnabled: `false` drops `GMTaste`'s house term, giving the
    ///     `perception` scenario a control arm for F-26 exactly as
    ///     `perceptionEnabled` gives it one for the fog. The two are separate
    ///     switches on purpose — information and philosophy are different
    ///     mechanisms and the diagnostic has to be able to attribute a change
    ///     to one of them. No shipping call site passes it.
    /// - Returns: The prospect the AI selects.
    static func aiMakePick(
        team: Team,
        availableProspects: [CollegeProspect],
        teamRoster: [Player],
        pickNumber: Int = 0,
        recentPositions: [Position] = [],
        perceptionEnabled: Bool = true,
        tasteEnabled: Bool = true
    ) -> CollegeProspect {
        guard !availableProspects.isEmpty else {
            fatalError("aiMakePick called with no available prospects")
        }

        // EVIDENCE and OPINION kept apart (see `teamNeedComponents`): the
        // multiplier is a fact about this roster, the weight is the league-wide
        // positional-value ranking every club shares. They are priced
        // separately below because they are not the same kind of claim.
        let needs = teamNeedComponents(roster: teamRoster)
        // One lens per pick, not per prospect — the archetype draw is the same
        // for all 300 names on the board.
        let lens = perceptionEnabled ? AIDraftPerception.lens(forTeam: team.id) : nil
        // One house per pick, for the same reason. Unlike the lens this is NOT
        // gated on `perceptionEnabled`: taste is not fog. The control arm of the
        // `perception` scenario measures a league that reads the board
        // perfectly and still disagrees about what it wants, which is the
        // comparison that shows the two mechanisms are independent.
        let house = tasteEnabled ? GMTaste.house(forTeam: team.id) : nil
        let boardContext = GMTaste.BoardContext(board: availableProspects)

        // --- Scoring weights, all in OVR points --------------------------------
        // They live here rather than at file scope because `sync_sources.sh`
        // slices this function into the balance harness by name; a `static let`
        // outside it would not come across and the `perception` scenario — the
        // instrument that measured every number below — would not compile.
        //
        //   deficitPoints        a genuine hole is worth up to ~+3.8 (a club with
        //                        nobody at the position at all), a one-body
        //                        shortfall +0.75 ≈ eight slots of board. Clubs
        //                        reach for needs; they do not reach a round.
        //   positionalValue*     the league premium, centred on the modal 0.8
        //                        weight: +1.6 for QB/DE/CB/WR/LT, 0 for the
        //                        second tier, -1.6 for backs and interior line.
        //   specialistDiscount   kickers and punters are not competing with an
        //                        end for the same roster spot. -8.0 on top of
        //                        their -4.0 tilt puts them past pick 130.
        //   quarterbackPremium   on top of the need bonus, for a club that
        //                        actually has a quarterback problem.
        //   consensusPull*       the public anchor: see `consensusSlot`.
        let potentialWeight = 0.15

        // F-28 + F-29 together, and this is the constant that pays for both.
        //
        // It was 5.0, flat across seven rounds, against a need multiplier whose
        // quality bumps were 0.2/0.1. F-28 raised those to 0.45/0.25 and F-29
        // doubles the whole term in round 1, so 5.0 would have priced a
        // two-body-short, replacement-level position group at
        // `0.75 × 5.0 × 2.0 = 7.5` board points — a quarter of the 29-point
        // talent span, for need alone, before a single taste or premium. The
        // `perception` scenario read the consequence directly: round-1 reaches
        // 12.40 → 13.08 and the true board's best man sliding past pick 5 in
        // 50 % of drafts against 38 % before.
        //
        // 3.5 puts the same worst case at 5.25 in round 1, 2.6 on day two and
        // 1.6 on day three, and an ordinary one-body shortfall at ~1.0 in round
        // 1. It trades "clubs draft for need" against "clubs draft a depth
        // chart": the ratio between the loudest hole and the quietest is
        // unchanged, only the level moved.
        let deficitPoints = 3.5
        let positionalValuePivot = 0.8

        // F-31 / F-30. This was 8.0 against a hand-written table that ran
        // 0.3...1.0, i.e. a realised opinion of ±1.6 points, 5.5 % of the
        // 29-point talent span. `draftPositionalWeight` now derives the table
        // from the money and it runs 0.3...1.6, so the SAME 8.0 would price the
        // QB-vs-RB gap at (1.6 − 0.48) × 8.0 = 9.0 points — a third of the
        // talent span, and a club that never looks at a back.
        //
        // 5.5 puts that gap at **6.2 points**, which is the audit's own target
        // ("~+6 board points instead of +3.2") and is roughly two letter
        // grades of tilt across the whole ladder: QB +4.4 over the pivot, WR
        // +1.3, DE +1.1, RB −1.8, FB −2.8. So the OPINION roughly doubled while
        // the constant halved. It trades positional realism (the money table
        // says 3.67 : 1, the real 2025 market 2.9 : 1, and the old board said
        // 1.0 : 0.6) against the risk of a league that drafts a depth chart
        // instead of players.
        let positionalValuePoints = 5.5

        // Specialists are now named rather than threshold-tested. The gate used
        // to read `weight <= 0.35`, which was safe while the table's bottom rung
        // was K/P alone; `draftPositionalWeight` floors the FULLBACK at 0.30 too
        // (`ContractEngine` pays both 0.25), so a threshold would have quietly
        // recruited fullbacks into a discount that exists for a different
        // reason. A kicker is not competing with an end for a roster spot; a
        // fullback is. The −8.0 itself is unchanged and is on the DO NOT TOUCH
        // list: no kicker has gone in round 1 since 2000.
        let specialistDiscount = 8.0
        // Trimmed 2.0 -> 1.0 when F-27's run jump landed, because the two are
        // the same statement at two temperatures and the club ALSO gets the
        // need term (a replacement-level quarterback room is worth ~+3.2 board
        // points in round 1 on its own). Measured at 2.0 the league took 4.5
        // quarterbacks a first round in the quiet years as well as the loud
        // ones; the point of F-27 is that the loud years are loud, not that
        // every year is.
        let quarterbackPremium = 1.0

        // F-27, the position run. The cheapest realistic panic model available,
        // and the most legible GM error in the sport: measured before this, the
        // game produced **2.9 quarterbacks per first round with almost no
        // variance**, against a real 15-year mean of ~3 with a real range of 1
        // (2022) to 6 (2024). The count was right and the shape was wrong.
        //
        //   runWindow            how far back "just now" reaches. Six picks is
        //                        about twenty minutes of a real round 1 —
        //                        long enough that a club sees the run, short
        //                        enough that it is a run and not a season.
        //   runThreshold         two at the same position inside the window.
        //                        Three never fires often enough to matter; one
        //                        is not a run, it is a pick.
        //   positionRunPoints    +1.5 — a fifth of a letter grade, ~10 slots of
        //                        round-1 board. Trades a visible chase against
        //                        a league that stampedes: at 3.0 the run
        //                        self-sustains, because every club that joins
        //                        it makes the next club likelier to join.
        //   quarterbackRunPremium  the QB rule, and the reason the item exists.
        //                        A club with a real quarterback problem that
        //                        watches two go inside five picks stops
        //                        waiting: `quarterbackPremium` 2.0 becomes 6.0.
        //                        This is what puts the fat right tail on the
        //                        QBs-per-round distribution without moving its
        //                        mean.
        let runWindow = 6
        let runThreshold = 2
        let positionRunPoints = 1.5
        let quarterbackRunWindow = 5
        let quarterbackRunPremium = 6.0
        // The multiplier a club's quarterback room must clear before either QB
        // premium fires at all. See the gate's own comment below for why it is
        // 1.3 and not the historical 1.2.
        let quarterbackNeedBar = 1.3

        // F-62, the consensus anchor. Raised from 12.0 against a round-1 board
        // whose mean |pick − publicRank| measured 23.6 slots, against a real
        // consensus that is typically within ~10-15 in round 1. The anchor is
        // the only term that pulls the other way from everything above — house
        // taste, round-scaled need and a three-times-wider positional table all
        // push a club further from the media — so it had to come up as they
        // went in, and the two were tuned in the same harness run.
        //
        // Sensitivity, which is the number to reason with: the term's
        // derivative at slot 16 is −(P/D)·exp(−16/D), so at 16.0/64.0 one OVR
        // point of misread is worth ~5.1 slots of round-1 board movement (it
        // was 6.8 at 12.0/64.0).
        let consensusPullPoints = 16.0
        let consensusDecayPicks = 64.0
        // Picks in a full round — `DraftIntel.picksPerRound`, restated locally
        // for the same slice reason as the weights above.
        let picksPerRound = 32.0

        // F-29, need by round. Real general managers draft for need in round 1
        // far more than the value curve justifies, and much less on day three,
        // where the board is what is left rather than what you wanted. Flat
        // weighting across seven rounds is the one thing no real war room does.
        //
        // Trades the realism of a needs-driven first round against reaching: at
        // 2.0 a genuine hole is worth up to ~+7.5 board points in round 1, which
        // is a real reach and is meant to be, and 0.6 on day three lets the best
        // player left win almost every argument. `pickNumber == 0` — a caller
        // with no slot context — takes the neutral 1.0 rung.
        let roundScale: Double
        switch pickNumber {
        case 1...32:  roundScale = 2.0
        case 33...96: roundScale = 1.0
        case 97...:   roundScale = 0.6
        default:      roundScale = 1.0
        }

        // The run tail, sampled once rather than per prospect.
        let runTail = recentPositions.suffix(runWindow)
        let quarterbacksInRunWindow = recentPositions
            .suffix(quarterbackRunWindow)
            .count { $0 == .QB }

        /// Where the MEDIA has this man, in pick numbers — the same published
        /// opinion `DraftIntel.consensusWindow` reads, and nothing else.
        ///
        /// A mock slot is a POINT opinion ("he goes 14th") and is used as-is. A
        /// projected round is a BAND opinion, and inside that band the media has
        /// no further view — so every man in a band gets his band's centre and
        /// the club's own board decides the order within it. That is the correct
        /// division of labour: the anchor supplies what is public, scouting
        /// supplies what is not.
        ///
        /// Duplicated in shape, not in code, from `DraftIntel.consensusWindow`:
        /// `DraftIntel` is a UI-facing type that this function cannot reach from
        /// inside the balance harness's engine-only slice.
        func consensusSlot(_ prospect: CollegeProspect) -> Double {
            if let mock = prospect.mockDraftPickNumber, mock > 0 { return Double(mock) }
            let round = Double(max(1, min(9, prospect.draftProjection ?? 9)))
            return (round - 1.0) * picksPerRound + picksPerRound / 2.0
        }

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

            // Talent, as this club reads it. Prospects with higher ceilings are
            // more attractive, at the long-standing 0.15 weight.
            var score = perceivedOverall + perceivedPotential * potentialWeight

            let need = needs[prospect.position] ?? (multiplier: 1.0, weight: positionalValuePivot)

            // EVIDENCE — a body short of the ideal count, or a group grading
            // under 70, or nobody there at all. Exactly 0 when the club has no
            // problem at the position, which is the common case on a full
            // roster and is why this is additive: a club with no hole should
            // draft the best man, not a discounted version of him. Scaled by
            // round (F-29): loud in round 1, neutral on day 2, quiet on day 3.
            score += deficitPoints * roundScale * max(0.0, need.multiplier - 1.0)

            // OPINION — the league-wide positional premium, the same for all 32
            // clubs, derived from the money table by `draftPositionalWeight`.
            // Realised range +1.4 (QB/LT tier) … −2.8 (FB/K/P), against ±1.6
            // for the whole board before F-30 widened the table.
            score += (need.weight - positionalValuePivot) * positionalValuePoints
            if prospect.position == .K || prospect.position == .P {
                score -= specialistDiscount
            }

            // HOUSE TASTE (F-26) — the club's two permanent preferences, in the
            // same currency as everything else and capped at ±4.0 in total.
            // This is the term that makes the 32 boards *different* rather than
            // merely *wrong*, and it is the only one a user can learn.
            if let house {
                score += GMTaste.boardAdjustment(
                    prospect: prospect,
                    house: house,
                    context: boardContext
                )
            }

            // THE RUN (F-27). Two men off the board at this position inside the
            // last six picks and the room starts counting how many are left.
            //
            // Quarterback is excluded here because he has his own, larger rule
            // below. Letting both fire paid a QB +1.5 AND +6.0 inside a run,
            // and the `perception` scenario showed exactly what that produces:
            // a run that sustains itself, because every club that joins it
            // makes the next club likelier to join.
            if prospect.position != .QB,
               runTail.count(where: { $0 == prospect.position }) >= runThreshold {
                score += positionRunPoints
            }

            // QB premium: a club with an actual quarterback problem will take
            // one ahead of a better player at another position. Read off the
            // EVIDENCE half — the old test used `multiplier × weight > 1.2`,
            // which for a weight-1.0 position is the same number.
            //
            // The bar moved 1.2 → 1.3 because F-28 moved what the number MEANS.
            // Under the old 0.2 quality bump, 1.2 was the exact score of a club
            // with two healthy-count but replacement-level quarterbacks, so the
            // strict `>` excluded it; under 0.45 the same club scores 1.45 and
            // a club merely one body short scores 1.15. At 1.3 the gate reads
            // "a replacement-level room, a thin AND weak room, or no
            // quarterback at all" and excludes "we carry two and one is a
            // backup", which is not a quarterback problem. Left at 1.2 the
            // premium fired on most of the league and the `perception` scenario
            // measured 4.5 quarterbacks a first round.
            //
            // The jump is F-27's headline: a club that needs one and has just
            // watched two go inside five picks pays 6.0 instead of 2.0. That is
            // the third-quarterback panic, and it is what turns a fixed 2.9 per
            // round into a distribution with a real right tail. Measured over 40
            // drafts: mean 3.88, sd 1.90, range 0-8, against a real 2018-25 mean
            // of 3.4 with sd 1.9 and a range of 1-6. Before it, sd was ~0.
            if prospect.position == .QB, (needs[.QB]?.multiplier ?? 1.0) > quarterbackNeedBar {
                score += quarterbacksInRunWindow >= runThreshold
                    ? quarterbackRunPremium
                    : quarterbackPremium
            }

            // The PUBLIC anchor. Decays over ~two rounds, so it dominates at the
            // top of the board — where the media has a sharp opinion and the
            // league is watching — and fades to noise by day three, where need
            // and positional value are all that is left to go on.
            score += consensusPullPoints * exp(-consensusSlot(prospect) / consensusDecayPicks)

            return (prospect, score)
        }

        // THE CLUB TAKES THE MAN AT THE TOP OF ITS OWN BOARD (F-62).
        //
        // This used to be a weighted-random draw over the top four —
        // `[0.65, 0.20, 0.10, 0.05]`, shipped as R24 to "keep drafts
        // surprising". Measured, it was cosmetic: over a 350-man board whose
        // top four sit within one or two points of each other, a 35 % off-argmax
        // draw moves a pick by a handful of true-board slots and changes nothing
        // a user could name. The real reaching has always come from the fog
        // (13.25 round-1 reaches with `AIDraftPerception` on, 8.33 with it off).
        //
        // It was also the one term in this whole function that was a die rolled
        // at the moment of decision, which `docs/AI_DESIGN_DECISIONS.md` D3
        // rejects by name: a front office that is *mistaken* is an opponent, one
        // that is *incoherent* is a slot machine. Everything that replaced it —
        // house taste, round-scaled need, the run — is error with a cause, and
        // is the same error next April.
        //
        // Ties break on the prospect's UUID rather than on array order, because
        // `availableProspects` arrives from a SwiftData fetch whose order is not
        // stable and two men can genuinely score identically on a coarse board.
        guard var best = scored.first else {
            fatalError("aiMakePick scored no prospects from a non-empty board")
        }
        for candidate in scored.dropFirst() {
            if candidate.1 > best.1
                || (candidate.1 == best.1 && candidate.0.id.uuidString < best.0.id.uuidString) {
                best = candidate
            }
        }
        return best.0
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
        // The school was surviving onto `DraftPick.playerCollege` and the pick
        // dossier but never onto the man himself, so every row that reads
        // `Player.college` — the rookie-class reveal, the profile header — went
        // blank the moment he stopped being a prospect.
        player.college = prospect.college
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
    ///
    /// ## This is the door that closes the pool (#204 defect D1)
    ///
    /// Signing a man **consumes** him: `prospect.isDeclaringForDraft = false` is
    /// set here, at the single conversion point every UDFA signing path in the
    /// game routes through — the Draft Day panel, the OTAs market and any future
    /// caller. It used to be the *callers'* job, and the bulk OTAs loop simply
    /// never did it, so every AI-signed UDFA stayed "declared" for
    /// `ClassDepthView`, the scouting hub and `ScoutingEngine.getUDFAPool`'s own
    /// membership filter until `purgeStaleSeasonData` deleted the row a season
    /// later. Those screens were telling the user that a hundred men who already
    /// had jobs were still available.
    ///
    /// Putting it here rather than in each caller also makes the two signing
    /// paths mutually exclusive by construction: the pool predicate is one
    /// authority (`ScoutingEngine.udfaPoolMembers`), so a man signed on draft
    /// night is not in the pool the OTAs board opens on. No process-global
    /// "already handled this season" flag is needed to prevent double-signing.
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
        prospect.isDeclaringForDraft = false   // consumed — see the doc comment (D1)
        return player
    }

    /// The overall an undrafted prospect would ENTER the league at, without
    /// building a `Player`.
    ///
    /// The UDFA market needs this to price a man and to read his path to a role,
    /// and it must not create a `Player` to find out: that would claim a face out
    /// of a pool `MultiSeasonSmokeTest.auditFaces` already reports running to
    /// `free=0`, for a candidate nobody may end up signing
    /// (`OFFSEASON_ROSTER_PLAN.md` §2.1).
    ///
    /// **Exact, not an estimate.** `Player.overall` and
    /// `CollegeProspect.overallValue` are the same weighted mean
    /// (`skill·0.5 + physical·0.3 + mental·0.2`), and ``scaleAttribute`` is affine
    /// in the attribute, so scaling the three group means with the same three
    /// factors ``convertUDFAToPlayer`` uses reproduces the converted player's
    /// overall to within per-attribute integer rounding.
    ///
    /// Using `prospect.trueOverall` instead would be a real distortion, not a
    /// nuance: an undrafted man converts at ~55 OVR against a college true value
    /// in the mid-60s, so the raw number would have every UDFA reading as
    /// competition for a starter in `SigningInterestEngine.roleScore`.
    static func udfaEntryOverall(prospect: CollegeProspect) -> Int {
        let factors = rookieScaleFactors(
            readiness: prospect.nflReadiness,
            learning: prospect.trueLearning,
            potential: prospect.truePotential,
            undrafted: true
        )
        let skill = scaledMean(prospect.truePositionAttributes.overall, factor: factors.skill)
        let physical = scaledMean(prospect.truePhysical.average, factor: factors.physical)
        let mental = scaledMean(prospect.trueMental.average, factor: factors.mental)
        return Int((skill * 0.5 + physical * 0.3 + mental * 0.2).rounded())
    }

    /// ``scaleAttribute`` over a group MEAN — the same affine map, undivided by
    /// per-attribute rounding.
    private static func scaledMean(_ value: Double, factor: Double) -> Double {
        Double(attributeFloor) + (value - Double(attributeFloor)) * factor
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
        case .snapping(let s):
            return .snapping(SnapAttributes(
                snapVelocity: scaleAttribute(s.snapVelocity, factor: factor),
                snapAccuracy: scaleAttribute(s.snapAccuracy, factor: factor)
            ))
        case .holding(let h):
            return .holding(HoldAttributes(
                handling: scaleAttribute(h.handling, factor: factor),
                placement: scaleAttribute(h.placement, factor: factor)
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

        // High-talent bonus — from the PUBLIC number, never the hidden one
        // (F-36).
        //
        // This read `prospect.trueOverall >= 80` and moved the published grade
        // by a full letter off it. `trueOverall` is the ground truth the game
        // develops the player from and the number `ProspectFog` exists to keep
        // off every screen: a media grade computed from it is the media knowing
        // something no scout in the league does, and on the user's own card it
        // is a hidden rating leaking back through a letter he is shown.
        //
        // `DraftIntel.publicOVREstimate` is the same public read the live pick
        // grade already uses (`DraftDayCoordinator.computePickGrade`) — the
        // user's own scouted number when his building has filed on the man, the
        // media's projected-round band when it has not. 78 is the band the
        // projection table puts a strong round-1 grade at, so the bonus fires
        // on the same *published* tier it used to fire on in truth.
        //
        // Measurement note, recorded because it changes what this fix IS:
        // `generateMediaGrade` has **zero callers**. The audit lists it as "the
        // one real fog breach surviving in a live path", and on this tree it is
        // not live — the shipped grade path is `PickGradeCalculator` via
        // `computePickGrade`, which was already clean, and nothing writes
        // `DraftPick.mediaGrade`. So this is a latent breach disarmed, not a
        // user-visible number corrected. It is fixed rather than deleted because
        // the function is a whole published-grade surface, not a fragment.
        if DraftIntel.publicOVREstimate(for: prospect) >= 78 {
            gradeIndex -= 1
        }

        // Clamp to valid range.
        gradeIndex = max(0, min(gradeScale.count - 1, gradeIndex))
        let grade = gradeScale[gradeIndex]

        // Generate headline and comment.
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

    /// Returns the top team need positions sorted by priority (highest need first).
    static func topTeamNeeds(roster: [Player], limit: Int = 5) -> [Position] {
        guard !roster.isEmpty else { return [] }
        let needs = evaluateTeamNeeds(roster: roster)
        return needs.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    // MARK: - Private Helpers

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
    /// there at all. The weight is the league-wide positional-value ranking,
    /// derived from ``draftPositionalWeight``, and is the same for all 32 clubs.
    ///
    /// So on a full 53-man roster, where the ideal counts sum to 48 and genuine
    /// deficits are rare, `topTeamNeeds` returns the highest-weight positions
    /// for *every club in the league* — a positional-value table wearing a need
    /// model's clothes. That is fine for the draft board it was written for
    /// (where "best available at a premium position" is a real strategy) and
    /// wrong for anything that means "this club has a hole": see
    /// ``teamNeedDeficits``.
    ///
    /// ## The quality half used to be inverted in magnitude (F-28)
    ///
    /// A position group averaging under 60 OVR was worth `+0.2` of multiplier,
    /// i.e. **+1.0 board point** through `aiMakePick`'s `deficitPoints`. Being
    /// two bodies short at any position was worth `2 × 0.15 = +0.3`, i.e.
    /// **+1.5**. So a club whose entire cornerback room graded 55 valued that
    /// hole *less* than a club two bodies short at fullback. The audit's verdict
    /// was that this is a bug and not a taste, and it is: a replacement-level
    /// starting group is the loudest need a real front office has.
    ///
    /// The bumps below price a sub-60 room at **+2.25 board points** and a
    /// sub-70 room at **+1.25**, against +0.75 for each missing body. The
    /// ordering is now the right way round and the count half still speaks.
    ///
    /// **What was NOT changed, and why.** The audit also asks for the 48-vs-46
    /// ideal-count reconciliation (the counts sum to 48 against rosters that
    /// leave free agency at 46, so most positions carry a deficit of 0). That
    /// half is deliberately left: `idealCounts` reaches ~30 call sites through
    /// ``topTeamNeeds`` and ``teamNeedDeficits`` — free agency, the practice
    /// squad, the UDFA market, camp, retirement and a dozen screens — and moving
    /// it is a league-wide behaviour change that deserves its own measured pass
    /// rather than a ride on a draft-board wave.
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

            // If the team has players at this position but they are low-rated,
            // boost need. F-28: these two bumps used to be 0.2 / 0.1, which
            // priced a replacement-level starting group BELOW a two-body
            // shortfall at fullback. See the doc comment above.
            if let overalls = positionOveralls[position], !overalls.isEmpty {
                let avgOverall = Double(overalls.reduce(0, +)) / Double(overalls.count)
                if avgOverall < 60.0 {
                    multiplier += replacementLevelBump
                } else if avgOverall < 70.0 {
                    multiplier += belowAverageBump
                }
            } else {
                // No players at all at this position — significant need.
                multiplier += 0.3
            }

            needs[position] = (multiplier: multiplier, weight: draftPositionalWeight(position))
        }

        return needs
    }

    /// Multiplier bump for a position group whose starters average under 60 OVR
    /// — a replacement-level room.
    ///
    /// Trades need against best-available. Through `aiMakePick`'s
    /// `deficitPoints` of 5.0 this is worth **+2.25 board points**, i.e. most of
    /// one letter grade: enough that a club with a genuinely broken position
    /// group reaches for it, not enough to take a bad player over a good one.
    /// At the old 0.2 it was worth +1.0 and lost to a two-body shortfall
    /// anywhere on the roster, which is the inversion F-28 names.
    private static let replacementLevelBump = 0.45

    /// Multiplier bump for a group averaging 60-70 OVR — startable, not good.
    /// Roughly half of ``replacementLevelBump`` so the two rungs stay ordered
    /// and a mediocre room is a nudge rather than an emergency.
    private static let belowAverageBump = 0.25

    /// THE positional-value table for the draft board, derived from the money.
    ///
    /// ## Three copies of one idea, two of them wrong (F-30)
    ///
    /// This used to be a hand-written four-tier `switch` inside
    /// ``teamNeedComponents``, and `FreeAgencyEngine.holePriority` is a third
    /// copy whose own doc comment says it "mirrors
    /// `DraftEngine.teamNeedComponents`". They had drifted, and the drift had
    /// two live inversions:
    ///
    /// - **RT** is PAID `0.85` by `ContractEngine.positionMultiplier` — above
    ///   MLB 0.80, safety 0.75 and TE 0.70 — and was DRAFTED at 0.6, below all
    ///   three.
    /// - **FB** is paid `0.25`, the bottom tier, the same as a kicker — and was
    ///   drafted at 0.6, the same as a right tackle.
    ///
    /// The classic "two constants that were supposed to be equal and drifted"
    /// pair. `ContractEngine.positionMultiplier` is the authoritative one: it
    /// carries a documented ratio audit against the real 2025 top-of-market and
    /// it sets each position's share of payroll, so it is the only one of the
    /// three that has ever been calibrated against anything outside the game.
    /// Deriving from it means the inversions cannot recur.
    ///
    /// ## The mapping, and why it widens the board (F-31)
    ///
    /// `positionMultiplier / 1.25`, clamped to `0.3 ... 1.6`. The divisor puts
    /// the modal position near the old 0.8 pivot so nothing shifts wholesale;
    /// the clamp keeps the quarterback (2.2 / 1.25 = 1.76) from running away
    /// with a board he already has a dedicated premium on, and floors the
    /// bottom where `ContractEngine` stops distinguishing a fullback from a
    /// punter.
    ///
    /// The realised spread is **much wider than what it replaces**, which is
    /// F-31's whole point: the old opinion ran ±1.6 points — 5.5 % of the
    /// 29-point talent span — and priced a quarterback exactly 3.2 points above
    /// a back of identical grade, against a money table that prices the same gap
    /// at 3.67 : 1 and a real 2025 market at 2.9 : 1. Here QB : RB is
    /// 1.6 : 0.48 = 3.33 : 1.
    ///
    /// Note the consequence for `aiMakePick`'s `positionalValuePoints`: because
    /// the TABLE widened by roughly a factor of three, the multiplier on it had
    /// to come DOWN to keep the realised tilt inside the design's 2-4 point
    /// band. A reader who sees `8.0` become a smaller number and concludes the
    /// positional opinion shrank has it backwards — see that constant's own
    /// comment for the arithmetic.
    static func draftPositionalWeight(_ position: Position) -> Double {
        min(positionalWeightCeiling,
            max(positionalWeightFloor,
                ContractEngine.positionMultiplier(position) / positionalWeightDivisor))
    }

    /// Divisor mapping money multipliers onto board weights. Chosen so the
    /// league's modal position lands near the historical 0.8 pivot — it trades
    /// continuity with the old table against nothing else, since `aiMakePick`
    /// subtracts the pivot and a uniform shift cancels out of every comparison.
    private static let positionalWeightDivisor = 1.25

    /// Ceiling on ``draftPositionalWeight``, and the one constant here that was
    /// set by measurement rather than by the money.
    ///
    /// `ContractEngine` pays a quarterback 2.2, which maps to 1.76. The draft
    /// board prices him THREE more times and the money table has no equivalent
    /// of any of them: `aiMakePick`'s need-gated `quarterbackPremium`, F-27's
    /// position-run jump, and — the one that is easy to forget — the public
    /// consensus anchor itself, since `DraftClassBuilder` already bakes
    /// positional value into the projections the media board is sorted on.
    ///
    /// Left at 1.76 the four stacked. The `perception` scenario read it
    /// directly: **5.0 quarterbacks per first round**, a 16 % round-1 QB share,
    /// against a real 15-year mean near 3.4 (2018-25: 5, 1, 4, 5, 1, 3, 6, 2).
    /// At 1.6 it was 4.5; at 1.25, 4.3.
    ///
    /// 1.05 prices the quarterback on the TABLE like a left tackle and leaves
    /// the rest of his premium to the two terms that are conditional — which is
    /// the correct division: what a quarterback is worth to a club that has one
    /// and what he is worth to a club that does not are different numbers, and
    /// only the second belongs in a need-blind ladder. Measured there, the
    /// league takes 4.2 a first round with sd 1.3 and a 1-to-6 range, and the
    /// SHAPE is now right even where the level still runs a little hot.
    ///
    /// One caveat on that level, recorded because it changes how to read it:
    /// the `perception` rig builds its 45-man rosters out of rookie-scaled
    /// prospects averaging ~58 OVR, so **every club in the rig has a
    /// replacement-level quarterback room** and clears the premium's gate. A
    /// real league averages ~70 and only a handful of clubs will. The measured
    /// 4.2 is therefore an upper bound, not the shipped number.
    ///
    /// The trade: fidelity to the payroll ladder (QB : RB lands at 2.2 : 1 on
    /// the table here, against 3.67 : 1 in the money and 2.9 : 1 in the real
    /// 2025 market) against a first round that is recognisably a first round.
    /// Counting the conditional terms, a club that needs one values him ~5.1
    /// points over a back of identical grade, which is F-31's "~+6" target.
    private static let positionalWeightCeiling = 1.05

    /// Floor on ``draftPositionalWeight``. `ContractEngine` pays a fullback and
    /// a punter the same 0.25, and the draft board should not pretend to
    /// distinguish them either — but it must not let the term run past the
    /// specialist discount that is applied separately.
    private static let positionalWeightFloor = 0.3

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
