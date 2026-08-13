import Foundation
import SwiftData

// MARK: - PreseasonEngine (#205b — OFFSEASON_ROSTER_PLAN §4)
//
// Three exhibition games inside the single `.preseason` phase.
//
// ## THE CONTRACT CLOCK DOES NOT TICK HERE. NOT EVER.
//
// Invariant (1), and the reason it is written in capitals: three preseason
// "games" look exactly like three weeks, so this file is the natural place for
// someone to later add "…and age the deals". **That is bug #89** — the week-18
// double-tick that decremented every contract in the league twice and was
// classed CRITICAL. A contract year moves in exactly one place in this
// codebase: `FreeAgencyEngine.executeNewLeagueYear`. Preseason runs zero
// contract decrements, zero cap rollovers, zero franchise-tag arithmetic.
//
// This engine also never increments `career.currentWeek` and never advances
// `career.currentPhase`. The three games are **steps inside one phase**, held
// in `PreseasonState.step` — the same shape free agency already ships
// (`Career.freeAgencyRound` / `freeAgencyStep`). So: no new `SeasonPhase` case
// (invariant 2), no change to `phase(after:)`, no change to
// `TaskProgressStore.cycle(season:phase:week:)` (invariant 4).
//
// ## What one exhibition actually does
//
// 1. The coach's ``PreseasonPolicy`` composes **who dresses** — the only lever
//    `GameSimulator` has, since it fields the best available man at each
//    position off the roster it is handed.
// 2. `GameSimulator.simulate` plays the user's game in full, through the two
//    additive roster-override parameters (§4.4). The other 15 games in the
//    league are score-only.
// 3. A post-pass charges the snaps: scheme familiarity through
//    `VersatilityDevelopmentEngine.learnScheme` and injury exposure through
//    `MedicalEngine.injuryCheck` — the *exact* two calls the weekly regular-
//    season advance makes, at preseason intensity. No new development engine,
//    no new injury model.
// 4. The whole thing is captured in a ``PreseasonResult`` for the recap sheet.
//
// ## What an exhibition deliberately leaves behind: nothing
//
// - **No season stats.** `accumulateSeasonStats` is not called; preseason
//   production is evidence for the cut, not a line in the record book.
// - **No games played / started.** `gamesPlayedThisSeason` is untouched.
// - **No residual fatigue, on either club.** `PlayerDevelopmentEngine`'s
//   offseason pass zeroes fatigue at `.trainingCamp`, i.e. *before* preseason,
//   and the weekly fatigue-recovery pass is regular-season-only — so any
//   fatigue banked here would ride into Week 1 as a penalty paid by the user's
//   club alone (and by whichever three AI clubs he happened to draw). Both
//   rosters' `fatigue` is snapshotted and restored around the sim. Exertion is
//   modelled where it belongs: in the injury roll below.
// - **No workload double-charge.** `WeekAdvancer.applyCampWeeklyTick` already
//   runs the `WorkloadEngine` ledger for the `.preseason` phase; that stays the
//   one authority for camp load, and `MedicalEngine.injuryCheck` reads its
//   `workloadStatus` for free.
// - **Nothing at all on the AI opponent**, beyond the score. Its fatigue and
//   morale are restored after the sim: the club never scheduled this game, and
//   a league-wide injury/morale inflow through three arbitrary opponents is
//   exactly the kind of asymmetry the §6 measurement pass would have to chase.
enum PreseasonEngine {

    // MARK: - Constants
    //
    // R11: every number here is a balance constant with a stated derivation.
    // §6 (B7/B8) owns the re-measurement; the arithmetic each one is *chosen*
    // by is written out so the measurement pass has something to falsify.

    /// Exhibitions on the slate. Three, matching the modern NFL preseason.
    static let gamesPerPreseason = 3

    /// Share of the projected FIRST TEAM that opens any one exhibition under
    /// ``PreseasonPolicy/starterSeries``.
    ///
    /// DERIVATION (§6 B7): the policy has to be a real bet, so the three
    /// policies must not collapse into each other. 0.35 puts a starter series
    /// almost exactly one third of the way from "rested" to "full tilt", which
    /// makes the 27-combination slate a decision rather than a slider.
    /// MEASUREMENT PENDING: B re-derives this together with
    /// ``preseasonInjuryScale`` from an 8-season worst-case (`.fullTilt` ×3) vs
    /// best-case (`.startersRest` ×3) run.
    ///
    /// ## #208 FIX C — why this is a share of MEN and not a share of SNAPS
    ///
    /// It used to be a per-man discount: every starter dressed for every
    /// exhibition and was then charged 0.35 of a game's familiarity and 0.35 of
    /// a game's injury roll. The aggregate arithmetic was right and the BOX
    /// SCORE was a lie — `GameSimulator` fields the best man at each position
    /// for four quarters and credits defensive production only to
    /// `PlaySimulator.startingDL/startingLBs/startingDBs` (top-4 DL, top-3 LB,
    /// top-4 DB **by overall** of the roster it is handed). Dress the first
    /// team and the first team takes ~100 % of the tape; the bubble's only
    /// window is the 15 % of throws that escape the primary five, i.e. about
    /// one target each. That is why the recap read "Helped 0 / Hurt 0" in every
    /// game of the QA slate: the cohort the screen exists to judge had no box
    /// score to be judged on.
    ///
    /// So the share is realized where the simulator can actually see it — in
    /// **who dresses**. `1 / 0.35 ≈ 3`, so the first team is strided across the
    /// three-game slate: each projected starter opens exactly one exhibition and
    /// watches the other two, and roughly two thirds of every game's starting
    /// spots belong to men fighting for the 53. Expected exposure per starter
    /// over the slate is unchanged (one full game ≈ 3 × 0.35), which is what
    /// keeps B7's injury ceiling and B8's familiarity gate where they were
    /// measured — and it is also what an August slate really looks like.
    static let starterSnapShare: Double = 0.35

    /// `practiceIntensity` a full game of snaps is worth to
    /// `VersatilityDevelopmentEngine.learnScheme`.
    ///
    /// DERIVATION (§6 B8): the two existing install channels are the camp pass
    /// (`PlayerDevelopmentEngine.processOffseason`, intensity 1.0, ×1.25 in an
    /// install year) and the weekly in-season rep (`WeekAdvancer` §8b,
    /// intensity 0.5). At 0.30, a three-game full-tilt slate banks 0.9 —
    /// a bit over half a camp, and a bit under two in-season weeks *per game*.
    /// That is the intended size: preseason is a meaningful head start on the
    /// playbook, not a second training camp.
    /// GATE: `PlaySimulator.famBustPivot` is 55 and the whole install-year
    /// mechanic depends on that cohort **opening Week 1 below it**. If the
    /// measured league mean crosses the pivot, this constant comes down —
    /// it is the tuning knob B8 names.
    static let preseasonSnapIntensity: Double = 0.30

    /// Multiplier on `MedicalEngine.injuryCheck`'s frequency for one full game
    /// of preseason exposure.
    ///
    /// DERIVATION (§6 B7): the regular season rolls `injuryCheck` once per
    /// rostered player per week — 18 rolls a season. Three exhibitions at
    /// scale `s` add `3s` roll-equivalents, i.e. `3s / 18` more season-total
    /// injuries in the worst case (a man who dresses full-tilt for all three).
    /// B7's ceiling is +8 %, which fixes `s ≤ 0.48`. At 0.45 the worst case is
    /// **+7.5 %** and the best case (starters rested all three) is +0 % for a
    /// starter and +7.5 % for the bubble — which is the right shape: the
    /// bubble is the cohort that has to play.
    /// `career.injuryFrequency.riskMultiplier` still multiplies on top, so the
    /// `.off` league setting still means zero preseason injuries too.
    static let preseasonInjuryScale: Double = 0.45

    // MARK: - Opening the phase

    /// Draws the three-game slate, once per (career, season).
    ///
    /// Idempotent by construction: an existing blob that still
    /// ``PreseasonState/matches(career:)`` is handed straight back, so a
    /// re-entered phase, a cold launch or a second call inside one advance
    /// cannot redraw a slate the user has already played.
    ///
    /// - Parameter existing: whatever `Career.preseasonData` currently decodes
    ///   to (`nil` on a save that has never reached preseason).
    static func openPreseasonIfNeeded(
        existing: PreseasonState?,
        career: Career,
        teams: [Team]
    ) -> PreseasonState {
        if let existing, existing.matches(career: career) { return existing }
        return PreseasonState(
            careerID: career.id,
            season: career.currentSeason,
            step: .plan(1),
            slate: drawSlate(career: career, teams: teams),
            results: []
        )
    }

    /// Three opponents, no repeats, division rivals excluded.
    ///
    /// Excluding the division is flavour with a purpose: the user meets those
    /// clubs twice in the games that count, and a preseason draw that hands him
    /// a third look at them reads as a scheduling bug. If the league is too
    /// small to honour that (a template with a short division), the filter
    /// relaxes rather than returning a short slate.
    ///
    /// The draw happens ONCE and is persisted, which is why this needs no
    /// seeded RNG: stability across a re-entered phase comes from the blob.
    private static func drawSlate(career: Career, teams: [Team]) -> [PreseasonMatchup] {
        guard let userTeamID = career.teamID,
              let userTeam = teams.first(where: { $0.id == userTeamID }) else { return [] }

        let others = teams.filter { $0.id != userTeamID }
        var pool = others.filter {
            !($0.conference == userTeam.conference && $0.division == userTeam.division)
        }
        if pool.count < gamesPerPreseason { pool = others }
        guard !pool.isEmpty else { return [] }

        let opponents = pool.shuffled().prefix(gamesPerPreseason)

        // Two at home, one on the road — the common NFL shape.
        let homePattern = [true, false, true]
        return opponents.enumerated().map { index, opponent in
            PreseasonMatchup(
                gameIndex: index + 1,
                opponentTeamID: opponent.id,
                opponentAbbreviation: opponent.abbreviation,
                opponentName: opponent.fullName,
                isHome: homePattern[index % homePattern.count]
            )
        }
    }

    // MARK: - The step machine

    /// Files a played exhibition and moves the flow to its recap.
    ///
    /// Re-filing the same game index replaces the stored result rather than
    /// appending a duplicate — a double tap on "Sim game" must not produce two
    /// game 2s.
    static func recordResult(_ result: PreseasonResult, into state: PreseasonState) -> PreseasonState {
        var next = state
        if let existingIndex = next.results.firstIndex(where: { $0.gameIndex == result.gameIndex }) {
            next.results[existingIndex] = result
        } else {
            next.results.append(result)
        }
        next.results.sort { $0.gameIndex < $1.gameIndex }
        next.step = .recap(result.gameIndex)
        return next
    }

    /// The user pressed Continue on a recap sheet: on to the next plan, or done.
    static func acknowledgeRecap(_ state: PreseasonState) -> PreseasonState {
        var next = state
        guard next.step.kind == .recap else { return next }
        let played = next.step.gameIndex
        let remaining = next.slate.contains { $0.gameIndex == played + 1 }
        next.step = remaining ? .plan(played + 1) : .complete
        return next
    }

    /// The exit gate's half of the answer (`WeekAdvancer` owns the other half,
    /// the roster ceiling). A slate that could not be drawn at all — a broken
    /// or one-team league — is `complete`, because a user must never be
    /// trapped in a phase by a missing opponent.
    ///
    /// **Ask this about a SEEDED blob.** `nil` answers `true` — a save that has
    /// never reached preseason cannot be held in it — so a caller that gates on
    /// this must seed through ``openPreseasonIfNeeded(existing:career:teams:)``
    /// first, or it is asking about a slate that does not exist yet and will
    /// always be told to go ahead. `CareerShellView.ensuredPreseasonState()` is
    /// the one place that does the seeding for both consumers (the required
    /// task row's completion and `performShellAdvance`'s precheck).
    static func canLeavePreseason(_ state: PreseasonState?) -> Bool {
        guard let state else { return true }
        return state.isComplete || state.slate.isEmpty
    }

    /// Games still on the slate, for the refusal's copy and the task counter.
    static func gamesRemaining(_ state: PreseasonState?) -> Int {
        guard let state else { return 0 }
        return max(0, state.slate.count - state.results.count)
    }

    /// The letter behind a refused advance, so a dismissed alert is not the only
    /// record of it — the same shape `WeekAdvancer.rosterLimitInboxMessage`
    /// gives the cutdown gate, and it lands with an action button that opens the
    /// slate rather than leaving the user to find it.
    static func unplayedSlateInboxMessage(_ state: PreseasonState?, season: Int) -> InboxMessage {
        let remaining = gamesRemaining(state)
        let played = (state?.results.count ?? 0)
        return InboxMessage(
            sender: .leagueOffice,
            subject: "Preseason slate unfinished — \(remaining) game\(remaining == 1 ? "" : "s") left",
            body: "Your club has played \(played) of \(state?.slate.count ?? 0) exhibitions. "
                + "The league will not certify final cuts before the preseason slate is complete — "
                + "and your staff has no film on the bubble until it is. Play the remaining "
                + "game\(remaining == 1 ? "" : "s"), then cut to 53.",
            date: "Preseason, Season \(season)",
            category: .leagueNotice,
            actionRequired: true,
            actionDestination: .preseason
        )
    }

    // MARK: - Simulating one exhibition

    /// Convenience entry point for the UI: fetches the career-scoped league
    /// itself, then delegates. The math lives in one place — the array-taking
    /// overload below — so the screen and `WeekAdvancer` can never diverge.
    static func simulateGame(
        career: Career,
        matchup: PreseasonMatchup,
        policy: PreseasonPolicy,
        modelContext: ModelContext
    ) -> PreseasonResult? {
        let careerID = career.id
        let teams = (try? modelContext.fetch(
            FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.careerID == careerID })
        )) ?? []
        let players = (try? modelContext.fetch(
            FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.careerID == careerID })
        )) ?? []
        let coaches = (try? modelContext.fetch(
            FetchDescriptor<Coach>(predicate: #Predicate<Coach> { $0.careerID == careerID })
        )) ?? []
        return simulateGame(
            career: career,
            matchup: matchup,
            policy: policy,
            teams: teams,
            allPlayers: players,
            allCoaches: coaches
        )
    }

    /// Plays one exhibition and returns everything the recap needs.
    ///
    /// Mutates exactly three things on the user's live rows: scheme
    /// familiarity, injury state, and (via the simulator) the morale nudge a
    /// hot or cold game leaves in his own locker room. Everything else — both
    /// clubs' fatigue, the opponent's morale — is restored before returning.
    ///
    /// Returns `nil` only when the game cannot be played at all (no user club,
    /// missing opponent, empty roster); the caller leaves the step where it is.
    static func simulateGame(
        career: Career,
        matchup: PreseasonMatchup,
        policy: PreseasonPolicy,
        teams: [Team],
        allPlayers: [Player],
        allCoaches: [Coach]
    ) -> PreseasonResult? {
        guard let userTeamID = career.teamID,
              let userTeam = teams.first(where: { $0.id == userTeamID }),
              let opponent = teams.first(where: { $0.id == matchup.opponentTeamID })
        else { return nil }

        let userRoster = allPlayers.filter { $0.teamID == userTeamID && !$0.isRetired }
        let opponentRoster = allPlayers.filter { $0.teamID == opponent.id && !$0.isRetired }

        // An injured man does not dress for an exhibition. (The regular-season
        // path still lets him — that is a shipped simplification this wave does
        // not reopen; here the override makes doing it right free.)
        let userAvailable = userRoster.filter { !$0.isInjured && !$0.isHoldingOut }
        let opponentAvailable = opponentRoster.filter { !$0.isInjured && !$0.isHoldingOut }
        guard !userAvailable.isEmpty, !opponentAvailable.isEmpty else { return nil }

        // The club's PROJECTED starting lineup — the same `startingLineupIDs`
        // the weekly starter tally and the 3D matchup resolver use, so "starter"
        // means one thing across the whole game. Everyone else is the bubble.
        let starterIDs = WeekAdvancer.startingLineupIDs(available: userAvailable)
        let dressed = dressedRoster(
            available: userAvailable,
            starterIDs: starterIDs,
            policy: policy,
            gameIndex: matchup.gameIndex
        )
        let dressedIDs = Set(dressed.map(\.id))
        guard !dressed.isEmpty else { return nil }

        // The AI opponent always plays the league-standard preseason: it dresses
        // everybody available and its own coaches decide the rest. Its rows are
        // restored afterwards, so this costs the league nothing.
        let opponentDressed = opponentAvailable

        // --- snapshot what an exhibition is not allowed to leave behind ------
        var fatigueBefore: [UUID: Int] = [:]
        var opponentMoraleBefore: [UUID: Int] = [:]
        for player in dressed { fatigueBefore[player.id] = player.fatigue }
        for player in opponentDressed {
            fatigueBefore[player.id] = player.fatigue
            opponentMoraleBefore[player.id] = player.morale
        }

        let userCoaches = allCoaches.filter { $0.teamID == userTeamID }
        let opponentCoaches = allCoaches.filter { $0.teamID == opponent.id }

        let homeTeam = matchup.isHome ? userTeam : opponent
        let awayTeam = matchup.isHome ? opponent : userTeam

        // No weather: `GameWeather.forGame` bands snow off the REGULAR-season
        // week number, and weeks 1-3 are September there. Preseason is August;
        // rolling snow into it would be a calendar artifact on screen.
        // No opponent-prep boost and no saved game plan either — an exhibition
        // is not a week the staff game-planned.
        let result = GameSimulator.simulate(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeCoaches: matchup.isHome ? userCoaches : opponentCoaches,
            awayCoaches: matchup.isHome ? opponentCoaches : userCoaches,
            weather: nil,
            homeRosterOverride: matchup.isHome ? dressed : opponentDressed,
            awayRosterOverride: matchup.isHome ? opponentDressed : dressed
        )

        // --- restore -----------------------------------------------------
        for player in dressed {
            if let fatigue = fatigueBefore[player.id] { player.fatigue = fatigue }
        }
        for player in opponentDressed {
            if let fatigue = fatigueBefore[player.id] { player.fatigue = fatigue }
            if let morale = opponentMoraleBefore[player.id] { player.morale = morale }
        }

        // --- charge the snaps (user's club only) --------------------------
        let familiarityGains = applySchemeSnaps(
            career: career,
            team: userTeam,
            dressed: dressed,
            starterIDs: starterIDs,
            policy: policy,
            teamCoaches: userCoaches
        )
        let injuries = rollInjuries(
            career: career,
            dressed: dressed,
            starterIDs: starterIDs,
            policy: policy,
            teamCoaches: userCoaches
        )

        let userScore = matchup.isHome ? result.homeScore : result.awayScore
        let opponentScore = matchup.isHome ? result.awayScore : result.homeScore

        return PreseasonResult(
            gameIndex: matchup.gameIndex,
            matchup: matchup,
            policy: policy,
            userScore: userScore,
            opponentScore: opponentScore,
            userLines: result.playerStats.filter { dressedIDs.contains($0.playerID) },
            bubblePlayerIDs: dressed.map(\.id).filter { !starterIDs.contains($0) },
            // The lineup this game was played with, banked onto the payload so
            // the recap never has to re-derive it from a roster that has moved
            // on (a starter hurt in game 1 is not game 2's starter).
            starterPlayerIDs: Array(starterIDs),
            injuries: injuries,
            familiarityGains: familiarityGains,
            leagueScoreboard: leagueScoreboard(
                teams: teams,
                excluding: [userTeamID, opponent.id]
            )
        )
    }

    // MARK: - Policy → who dresses

    /// Applies the policy, then guarantees the club can actually field a
    /// football team.
    ///
    /// The policy is the ONLY lever there is (§4.2): `GameSimulator` fields the
    /// best available man at each position for four quarters, so the answer to
    /// "who plays" is entirely decided by who is in this array.
    ///
    /// - `.fullTilt` — everybody available. The ones take the tape.
    /// - `.startersRest` — nobody from the projected first team. The bubble's
    ///   own best men become the starting units and produce a real box score.
    /// - `.starterSeries` — ``openingFirstTeam(available:starterIDs:gameIndex:)``:
    ///   a `starterSnapShare` stride of the first team opens this exhibition and
    ///   the rest of the ones watch, so about two thirds of the starting spots
    ///   belong to the bubble (#208 FIX C — see ``starterSnapShare``).
    ///
    /// Resting a man cannot rest a *position* out of existence: a club carries
    /// one kicker and one punter, and handing `GameSimulator` a roster with no
    /// `K` means no field goals for four quarters. Any position the policy would
    /// empty gets its best man back.
    static func dressedRoster(
        available: [Player],
        starterIDs: Set<UUID>,
        policy: PreseasonPolicy,
        gameIndex: Int
    ) -> [Player] {
        switch policy {
        case .fullTilt:
            return available
        case .startersRest:
            return coveringEveryPosition(
                available.filter { !starterIDs.contains($0.id) },
                from: available
            )
        case .starterSeries:
            let opening = openingFirstTeam(
                available: available, starterIDs: starterIDs, gameIndex: gameIndex
            )
            return coveringEveryPosition(
                available.filter { !starterIDs.contains($0.id) || opening.contains($0.id) },
                from: available
            )
        }
    }

    /// Which of the projected starters open exhibition `gameIndex`.
    ///
    /// A **stride**, not a window: the first team is ordered by position and
    /// then every `stride`-th man is taken, so game 1 does not get the whole
    /// offence and game 3 the whole defence. `stride = round(1 / starterSnapShare)`
    /// is 3 at the shipped constant, which means each starter opens exactly one
    /// of the three exhibitions — the real-league shape, and the reason the
    /// aggregate exposure over the slate matches the old per-man 0.35 discount.
    ///
    /// Deterministic: the ordering is (position, id), so replaying a game index
    /// dresses the same men and a recap cannot disagree with the tape.
    static func openingFirstTeam(
        available: [Player],
        starterIDs: Set<UUID>,
        gameIndex: Int
    ) -> Set<UUID> {
        let period = max(1, Int((1.0 / max(starterSnapShare, 0.01)).rounded()))
        let slot = ((gameIndex - 1) % period + period) % period
        let firstTeam = available
            .filter { starterIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let left = positionRank[lhs.position] ?? 0
                let right = positionRank[rhs.position] ?? 0
                if left != right { return left < right }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        return Set(
            firstTeam.enumerated()
                .filter { $0.offset % period == slot }
                .map(\.element.id)
        )
    }

    /// Declaration order of `Position`, so the stride above spreads across the
    /// two sides of the ball instead of clustering.
    private static let positionRank: [Position: Int] = {
        var rank: [Position: Int] = [:]
        for (index, position) in Position.allCases.enumerated() { rank[position] = index }
        return rank
    }()

    /// Puts back the best man at any position the policy emptied.
    private static func coveringEveryPosition(_ dressed: [Player], from available: [Player]) -> [Player] {
        var out = dressed
        let covered = Set(out.map(\.position))
        for position in Set(available.map(\.position)) where !covered.contains(position) {
            guard let best = available
                .filter({ $0.position == position })
                .max(by: { $0.overall < $1.overall })
            else { continue }
            out.append(best)
        }
        return out
    }

    /// The exposure share one dressed man takes in this game.
    ///
    /// **1.0 for everybody, by construction.** Since #208 FIX C the policy is
    /// expressed in who dresses (see ``dressedRoster(available:starterIDs:policy:gameIndex:)``),
    /// and a man who dressed for an exhibition played it — there is no
    /// half-present player in this simulator, and pretending there was is what
    /// let a starter take 100 % of the box score while being charged 35 % of the
    /// risk. The function stays as the single named home of the question
    /// "how much of this game did he take", so a future partial-snap model has
    /// one place to land.
    static func snapShare(
        for player: Player,
        starterIDs: Set<UUID>,
        policy: PreseasonPolicy
    ) -> Double {
        1.0
    }

    // MARK: - Familiarity

    /// Scheme reps banked by the men who played, through the EXACT call the
    /// weekly advance makes (`WeekAdvancer` §8b) at preseason intensity.
    ///
    /// `seedActiveSchemes` runs first for the same reason it does weekly (#54):
    /// a UDFA signed three weeks ago, a camp body, a man promoted off the
    /// practice squad has no dictionary entry for this building's systems at
    /// all, and an absent key answers 0 to every familiarity read in
    /// `PlaySimulator`.
    ///
    /// The install-year ×1.25 (`schemeInstallIntensityBonus`) rides along
    /// unchanged: a staff putting in a brand-new system teaches faster in
    /// August too.
    private static func applySchemeSnaps(
        career: Career,
        team: Team,
        dressed: [Player],
        starterIDs: Set<UUID>,
        policy: PreseasonPolicy,
        teamCoaches: [Coach]
    ) -> [PreseasonFamiliarityGain] {
        let oc = teamCoaches.first { $0.role == .offensiveCoordinator }
        let dc = teamCoaches.first { $0.role == .defensiveCoordinator }
        let installedSchemes = Set([
            oc?.offensiveScheme?.rawValue, dc?.defensiveScheme?.rawValue,
        ].compactMap { $0 })
        guard !installedSchemes.isEmpty else { return [] }

        let installBonus = team.schemeInstallSeason == career.currentSeason
            ? VersatilityDevelopmentEngine.schemeInstallIntensityBonus
            : 1.0

        var gains: [PreseasonFamiliarityGain] = []
        for player in dressed {
            VersatilityDevelopmentEngine.seedActiveSchemes(
                player: player, activeSchemes: installedSchemes
            )

            let intensity = preseasonSnapIntensity
                * snapShare(for: player, starterIDs: starterIDs, policy: policy)
                * installBonus
            guard intensity > 0 else { continue }

            let coordinator: Coach?
            let scheme: String?
            switch player.position.side {
            case .offense:
                coordinator = oc
                scheme = oc?.offensiveScheme?.rawValue
            case .defense:
                coordinator = dc
                scheme = dc?.defensiveScheme?.rawValue
            case .specialTeams:
                // A kicker learns no playbook. He still takes the injury roll.
                continue
            }
            guard let scheme else { continue }

            let gain = VersatilityDevelopmentEngine.learnScheme(
                player: player,
                scheme: scheme,
                coordinator: coordinator,
                practiceIntensity: intensity
            )
            guard gain > 0 else { continue }
            player.schemeFamiliarity[scheme] = min(100, (player.schemeFamiliarity[scheme] ?? 0) + gain)
            gains.append(PreseasonFamiliarityGain(
                playerID: player.id,
                playerName: player.fullName,
                position: player.position,
                points: gain,
                scheme: scheme
            ))
        }
        return gains
    }

    // MARK: - Injuries

    /// One `MedicalEngine.injuryCheck` per dressed man — the EXACT call the
    /// weekly advance makes (`WeekAdvancer` step 6), scaled by
    /// ``preseasonInjuryScale`` and the man's snap share.
    ///
    /// `career.injuryFrequency.riskMultiplier` is still the outer factor, so
    /// the league's `.off` setting still means no preseason injuries and
    /// `.low` still halves them — invariant respected end to end.
    private static func rollInjuries(
        career: Career,
        dressed: [Player],
        starterIDs: Set<UUID>,
        policy: PreseasonPolicy,
        teamCoaches: [Coach]
    ) -> [PreseasonInjury] {
        let staff = WeekAdvancer.medicalStaffByTeam(coaches: teamCoaches).values.first
        let doctor = staff?.doctor
        let physio = staff?.physio
        let trainer = staff?.trainer

        var injuries: [PreseasonInjury] = []
        for player in dressed where !player.isInjured {
            let multiplier = career.injuryFrequency.riskMultiplier
                * preseasonInjuryScale
                * snapShare(for: player, starterIDs: starterIDs, policy: policy)
            guard multiplier > 0 else { continue }

            guard let injury = MedicalEngine.injuryCheck(
                player: player,
                playType: .run,   // no play type at this granularity, same as weekly
                doctor: doctor,
                physio: physio,
                trainer: trainer,
                frequencyMultiplier: multiplier
            ) else { continue }

            // THE STAMP IS THE LEAGUE YEAR THIS PRESEASON BELONGS TO, NOT THE
            // ONE ON THE CAREER ROW.
            //
            // `career.currentSeason` is still the FINISHED year N right through
            // the offseason — the `+= 1` happens at the `rosterCuts →
            // regularSeason` step (`PreseasonState`'s header says so, and it is
            // why the blob carries its own season key). `career.currentWeek` is
            // whatever the postseason left behind (19-22); nothing resets it
            // until `startNewSeason`. Stamping those two would file an August
            // 2027 ACL as "2026, Week 22".
            //
            // That is not only a wrong label on `PlayerDetailView`'s injury
            // card. `WeekAdvancer`'s offseason development pass derives
            // `majorInjuryLastSeason` from `$0.season == season`, and season N's
            // pass has already run at `.trainingCamp` — BEFORE these games are
            // played. A season-N stamp is therefore a record no health factor
            // can ever read. Stamped N+1, the NEXT camp's pass finds it, which
            // is exactly the camp that should be asking.
            //
            // Week 0 is `InjuryRecord`'s documented "unknown/none" sentinel and
            // is the honest value here: a preseason exhibition is not week 21.
            // Same reasoning `LiveGameEngine` writes out where it stamps.
            //
            // NOTE: `PreseasonState.season` (see `openPreseasonIfNeeded`) stays
            // `career.currentSeason` — that is an idempotency key for the draw,
            // not a calendar label, and moving it would re-seed the slate.
            MedicalEngine.applyInjury(
                player: player,
                injuryType: injury,
                doctor: doctor,
                physio: physio,
                season: career.currentSeason + 1,
                week: 0
            )
            injuries.append(PreseasonInjury(
                playerID: player.id,
                playerName: player.fullName,
                position: player.position,
                injuryType: injury.rawValue,
                weeksOut: player.injuryWeeksOriginal
            ))
        }
        return injuries
    }

    // MARK: - The rest of the league

    /// The other 15 exhibitions, score-only.
    ///
    /// Same bargain the regular season strikes for its 15 AI games and the
    /// postseason strikes for the clubs it never box-scores: one authority for
    /// a plausible final, `WeekAdvancer.simulateGameScore()`. Nothing here
    /// touches a record, a stat line or a `Game` row — these numbers exist so
    /// the recap's league scoreboard is not blank.
    private static func leagueScoreboard(teams: [Team], excluding: Set<UUID>) -> [PreseasonScoreLine] {
        let rest = teams.filter { !excluding.contains($0.id) }.shuffled()
        var lines: [PreseasonScoreLine] = []
        var index = 0
        while index + 1 < rest.count {
            let home = rest[index]
            let away = rest[index + 1]
            let score = WeekAdvancer.simulateGameScore()
            lines.append(PreseasonScoreLine(
                homeTeamID: home.id,
                awayTeamID: away.id,
                homeAbbreviation: home.abbreviation,
                awayAbbreviation: away.abbreviation,
                homeScore: score.home,
                awayScore: score.away
            ))
            index += 2
        }
        return lines
    }
}

// MARK: - The camp case (#208 FIX C)

extension PreseasonEngine {

    /// Did one exhibition move a man's case for the 53 — read off his REAL box
    /// score, against what his position is expected to do with the chances he
    /// actually got.
    ///
    /// ## Why this is a delta and not a total
    ///
    /// The verdict this replaces scored a stat line in absolute fantasy-shaped
    /// points and demanded three "involvements" before it would say anything.
    /// Both halves misread this simulator. A camp cutdown is decided on lines
    /// like *one target, one catch, one touchdown*: an absolute scorer calls
    /// that 7 points and a volume floor of three throws it away as noise — so
    /// every game of the QA slate reported **Helped 0 / Hurt 0** while the table
    /// underneath it showed real production.
    ///
    /// So the question asked here is not "how much did he do" but **"how much
    /// more than his position asks of a man with that many chances"**. A back
    /// with 12 carries is measured against 12 × 4.2 yards and 12 × a 3 % score
    /// rate; a receiver with 2 targets against 2 × 8.0 yards, a 62 % catch rate
    /// and a 5 % touchdown rate. The unit is *case points*: production minus
    /// expectation, positive when he beat the spot.
    ///
    /// ## What this evaluator deliberately cannot say
    ///
    /// - **A man with no credited event is `quiet`, never `hurt`.** An interior
    ///   lineman has no box-score row at all, and `PlaySimulator` credits
    ///   defensive production only to the top-4 DL / top-3 LB / top-4 DB of the
    ///   roster it is handed. A zero line is therefore evidence about the
    ///   simulator, not about the player, and reading it as a bad afternoon
    ///   would have the screen accusing men it cannot see.
    /// - **A defender cannot be `hurt`.** There is no missed-tackle or
    ///   blown-coverage column in `PlayerGameStats`; the worst a credited
    ///   defender's line can be is small. Defensive cases move one way, and the
    ///   copy never implies otherwise.
    /// - **A man carted off cannot be blamed for the short line.** The old
    ///   scorer needed an explicit guard for this because it measured totals;
    ///   a delta does not, since a first-quarter exit simply produces a small
    ///   number of chances and therefore a small delta. Only an actual negative
    ///   event — a pick, a missed kick — can push him past the bar, and those
    ///   are his. The row prints the injury chip beside the verdict either way.
    enum CampCase {

        // MARK: Verdict

        enum Verdict: String, Codable {
            /// Played himself closer to the 53.
            case helped
            /// Did his job. Nothing moved.
            case held
            /// Played himself further from it.
            case hurt
            /// Dressed, barely featured. The box score has nothing to say.
            case quiet

            var moved: Bool { self == .helped || self == .hurt }
        }

        /// One man's afternoon, decided.
        struct Read {
            let verdict: Verdict
            /// Production minus positional expectation, in case points.
            let delta: Double
            /// Chances the box score can see (throws, touches, targets,
            /// credited defensive events, kicks).
            let opportunities: Int
            /// One line of evidence: the play that carried the verdict, and how
            /// it sat against the bar. English-only, sentence case.
            let reason: String

            var moved: Bool { verdict.moved }
        }

        // MARK: Thresholds
        //
        // R11: presentation constants, MEASURED rather than felt. The bar was
        // fixed by a 4 000-game Monte Carlo over plausible exhibition box scores
        // (30-odd throws, 25 carries, ~50 credited tackles, 0-3 sacks, 0-2
        // takeaways, spread over the ~66 men a camp roster dresses):
        //
        //     bar    avg movers/game    games inside the 2-6 band
        //     ±4.0        5.3                    76 %
        //     ±4.5        4.5                    85 %   ← shipped
        //     ±5.0        3.6                    88 %
        //     ±5.5        2.9                    82 %
        //
        // ±4.5 is the peak of the band with the mover count still comfortably
        // inside it, and it lands the two cases the spec names: any touchdown
        // catch clears it (a score is worth ~4.8 case points over any plausible
        // expectation, so even a six-yard one counts), a nine-tackle afternoon
        // or a takeaway clears it, three interceptions is nowhere near the
        // bottom of it — and a man who ran eleven times for forty does not
        // move, which is the intended shape. The cut sheet is written from
        // plays, not from volume.
        //
        // The counts the recap chips print are the CUT COHORT's share of this,
        // i.e. roughly two thirds of the figures above under `.starterSeries`.

        /// At or above this many case points the outing counts for him.
        static let helpedMargin: Double = 4.5
        /// At or below it, against him.
        static let hurtMargin: Double = -4.5
        /// Under this many visible chances a `held` reads as `quiet` instead:
        /// two touches that came out even is not evidence, it is a cameo. A man
        /// can still MOVE on one snap — that is the whole point of the delta —
        /// so this gates the middle bucket only.
        static let quietOpportunityFloor = 3

        // MARK: Positional expectation
        //
        // League-average shapes. They are the denominator of every verdict, so
        // they are stated once, here, rather than folded into the weights.

        static let yardsPerAttempt = 6.8
        static let passTDRate = 0.045
        static let interceptionRate = 0.025
        static let yardsPerCarry = 4.2
        static let rushTDRate = 0.030
        /// A back's targets are check-downs; a receiver's are routes.
        static let yardsPerTargetBack = 6.0
        static let yardsPerTargetReceiver = 8.0
        static let catchRate = 0.62
        static let receivingTDRate = 0.050
        static let fieldGoalRate = 0.84
        /// What a credited defender's afternoon is worth on average — about
        /// four stops. The one flat bar in the file, because the box score
        /// shows a defender's production without ever showing his chances.
        static let defenderGameBar = 3.5

        // MARK: Weights (case points per unit)

        static let passYardPoints = 0.04
        static let passTDPoints = 4.0
        static let interceptionPoints = 5.0
        static let rushYardPoints = 0.12
        static let rushTDPoints = 5.0
        static let receivingYardPoints = 0.10
        static let receptionPoints = 0.8
        static let receivingTDPoints = 5.0
        static let tacklePoints = 0.9
        static let sackPoints = 3.5
        static let takeawayPoints = 6.0
        static let forcedFumblePoints = 4.0
        static let passDeflectionPoints = 1.5
        static let fieldGoalMadePoints = 2.5
        static let fieldGoalMissedPoints = 3.0

        // MARK: The read

        /// One driver of the verdict — a term of the delta with the words to
        /// explain it. The biggest one becomes the recap's line of evidence.
        private struct Driver {
            let points: Double
            let phrase: String
        }

        static func read(_ s: PlayerGameStats) -> Read {
            var delta = 0.0
            var opportunities = 0
            var drivers: [Driver] = []

            // --- Passing ------------------------------------------------
            if s.attempts > 0 {
                let attempts = Double(s.attempts)
                opportunities += s.attempts

                let yards = passYardPoints * (Double(s.passingYards) - yardsPerAttempt * attempts)
                let scores = passTDPoints * (Double(s.passingTDs) - passTDRate * attempts)
                let picks = -interceptionPoints * (Double(s.interceptions) - interceptionRate * attempts)
                delta += yards + scores + picks

                drivers.append(Driver(
                    points: yards,
                    phrase: "\(s.completions) of \(s.attempts) for \(s.passingYards)"
                ))
                if s.passingTDs > 0 {
                    drivers.append(Driver(
                        points: scores,
                        phrase: "\(count(s.passingTDs, "touchdown pass", plural: "touchdown passes"))"
                    ))
                }
                if s.interceptions > 0 {
                    drivers.append(Driver(
                        points: picks,
                        phrase: "\(count(s.interceptions, "interception")) on \(s.attempts) throws"
                    ))
                }
            }

            // --- Rushing (a scrambling quarterback is credited here too) ---
            if s.carries > 0 {
                let carries = Double(s.carries)
                opportunities += s.carries

                let yards = rushYardPoints * (Double(s.rushingYards) - yardsPerCarry * carries)
                let scores = rushTDPoints * (Double(s.rushingTDs) - rushTDRate * carries)
                delta += yards + scores

                drivers.append(Driver(
                    points: yards,
                    phrase: "\(String(format: "%.1f", s.yardsPerCarry)) a carry on \(count(s.carries, "carry", plural: "carries"))"
                ))
                if s.rushingTDs > 0 {
                    drivers.append(Driver(
                        points: scores,
                        phrase: count(s.rushingTDs, "rushing score")
                    ))
                }
            }

            // --- Receiving ------------------------------------------------
            if s.targets > 0 {
                let targets = Double(s.targets)
                opportunities += s.targets
                let yardsBar = (s.position == .RB || s.position == .FB)
                    ? yardsPerTargetBack : yardsPerTargetReceiver

                let yards = receivingYardPoints * (Double(s.receivingYards) - yardsBar * targets)
                let hands = receptionPoints * (Double(s.receptions) - catchRate * targets)
                let scores = receivingTDPoints * (Double(s.receivingTDs) - receivingTDRate * targets)
                delta += yards + hands + scores

                drivers.append(Driver(
                    points: yards,
                    phrase: "\(s.receivingYards) yards on \(count(s.targets, "target"))"
                ))
                drivers.append(Driver(
                    points: hands,
                    phrase: "\(s.receptions) of \(s.targets) caught"
                ))
                if s.receivingTDs > 0 {
                    drivers.append(Driver(
                        points: scores,
                        phrase: count(s.receivingTDs, "touchdown catch", plural: "touchdown catches")
                    ))
                }
            }

            // --- Defence ---------------------------------------------------
            let sacks = s.sacks
            let defensiveEvents = s.tackles + s.interceptionsCaught + s.forcedFumbles
                + s.passDeflectionCount + Int(sacks.rounded())
            if defensiveEvents > 0 {
                opportunities += defensiveEvents

                let production = tacklePoints * Double(s.tackles)
                    + sackPoints * sacks
                    + takeawayPoints * Double(s.interceptionsCaught)
                    + forcedFumblePoints * Double(s.forcedFumbles)
                    + passDeflectionPoints * Double(s.passDeflectionCount)
                delta += production - defenderGameBar

                if s.tackles > 0 {
                    drivers.append(Driver(
                        points: tacklePoints * Double(s.tackles) - defenderGameBar,
                        phrase: count(s.tackles, "stop")
                    ))
                }
                if sacks > 0 {
                    drivers.append(Driver(
                        points: sackPoints * sacks,
                        phrase: "\(sackText(sacks)) \(sacks == 1.0 ? "sack" : "sacks")"
                    ))
                }
                if s.interceptionsCaught > 0 {
                    drivers.append(Driver(
                        points: takeawayPoints * Double(s.interceptionsCaught),
                        phrase: count(s.interceptionsCaught, "interception")
                    ))
                }
                if s.forcedFumbles > 0 {
                    drivers.append(Driver(
                        points: forcedFumblePoints * Double(s.forcedFumbles),
                        phrase: count(s.forcedFumbles, "forced fumble")
                    ))
                }
                if s.passDeflectionCount > 0 {
                    drivers.append(Driver(
                        points: passDeflectionPoints * Double(s.passDeflectionCount),
                        phrase: count(s.passDeflectionCount, "pass break-up")
                    ))
                }
            }

            // --- Kicking ----------------------------------------------------
            if s.fieldGoalsAttempted > 0 {
                let attempted = Double(s.fieldGoalsAttempted)
                let missed = Double(max(0, s.fieldGoalsAttempted - s.fieldGoalsMade))
                opportunities += s.fieldGoalsAttempted

                let kicks = fieldGoalMadePoints * (Double(s.fieldGoalsMade) - fieldGoalRate * attempted)
                    - fieldGoalMissedPoints * (missed - (1.0 - fieldGoalRate) * attempted)
                delta += kicks
                drivers.append(Driver(
                    points: kicks,
                    phrase: "\(s.fieldGoalsMade) of \(s.fieldGoalsAttempted) on field goals"
                ))
            }

            // --- Verdict -----------------------------------------------------
            let verdict: Verdict
            if opportunities == 0 {
                verdict = .quiet
            } else if delta >= helpedMargin {
                verdict = .helped
            } else if delta <= hurtMargin {
                verdict = .hurt
            } else {
                verdict = opportunities >= quietOpportunityFloor ? .held : .quiet
            }

            return Read(
                verdict: verdict,
                delta: delta,
                opportunities: opportunities,
                reason: reason(verdict: verdict, drivers: drivers)
            )
        }

        // MARK: The line of evidence

        /// The one sentence the recap prints beside a man's name.
        ///
        /// The driver quoted is the term that CARRIED the verdict — the biggest
        /// positive when he helped himself, the biggest negative when he hurt
        /// himself — so the sentence and the pill can never contradict each
        /// other.
        private static func reason(verdict: Verdict, drivers: [Driver]) -> String {
            guard let driver = pick(verdict: verdict, from: drivers) else {
                return "No box score \u{2014} nothing on tape either way."
            }
            let head = driver.phrase.prefix(1).uppercased() + driver.phrase.dropFirst()
            switch verdict {
            case .helped: return "\(head) \u{2014} more than the spot asks for."
            case .hurt:   return "\(head) \u{2014} well under what the spot asks."
            case .held:   return "\(head) \u{2014} about what the spot asks."
            case .quiet:  return "\(head) \u{2014} not enough to read either way."
            }
        }

        private static func pick(verdict: Verdict, from drivers: [Driver]) -> Driver? {
            switch verdict {
            case .helped: return drivers.max { $0.points < $1.points }
            case .hurt:   return drivers.min { $0.points < $1.points }
            case .held, .quiet: return drivers.max { abs($0.points) < abs($1.points) }
            }
        }

        // MARK: Small English helpers (English-only, one home)

        private static func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
            let word = value == 1 ? singular : (plural ?? singular + "s")
            return "\(value) \(word)"
        }

        private static func sackText(_ sacks: Double) -> String {
            sacks == sacks.rounded() ? "\(Int(sacks))" : String(format: "%.1f", sacks)
        }
    }
}
