import Foundation

enum LeagueGenerator {

    // MARK: - Roster Blueprint

    /// Position counts for a standard 53-man roster.
    private static let rosterBlueprint: [(Position, Int)] = [
        (.QB, 3), (.RB, 3), (.FB, 1), (.WR, 6), (.TE, 3),
        (.LT, 2), (.LG, 2), (.C, 2), (.RG, 2), (.RT, 1),
        (.DE, 4), (.DT, 3), (.OLB, 4), (.MLB, 3),
        (.CB, 5), (.FS, 2), (.SS, 2),
        (.K, 1), (.P, 1),
        // Extra depth
        (.WR, 1), (.DE, 1), (.CB, 1)
    ]
    // Total: 3+3+1+6+3+2+2+2+2+1+4+3+4+3+5+2+2+1+1+1+1+1 = 53

    /// All 15 coaching roles, one per staff member.
    private static let coachingStaffRoles: [CoachRole] = [
        .headCoach,
        .assistantHeadCoach,
        .offensiveCoordinator,
        .defensiveCoordinator,
        .specialTeamsCoordinator,
        .qbCoach,
        .rbCoach,
        .wrCoach,
        .olCoach,
        .dlCoach,
        .lbCoach,
        .dbCoach,
        .strengthCoach,
        .teamDoctor,
        .physio,
        .headTrainer
    ]

    // MARK: - Owner / Coach Names

    // Fictional and blocklist-checked, for the same reason the player pools in
    // `RandomNameGenerator` are: the first-name and surname arrays are drawn from
    // independently, so the reachable space is the whole cross product. These two
    // pairs used to be lists of real NFL owners and real head coaches (Kraft /
    // Jones / Irsay / Khan; McVay / Reid / Shanahan / Belichick), which every
    // league source rendered as living people — the template import path calls
    // `generateOwner` for all 32 clubs, so the shipped Fixed 2026 league named its
    // owners after the real ones. `scan_bundle.py` gate E asserts, on this file,
    // that every one of these cross products — 32 × 32, 16 × 32, 30 × 30 twice —
    // stays Levenshtein ≥ 3 from every real name (`docs/ANONYMIZATION_SPEC.md`
    // §1).

    private static let ownerFirstNames: [String] = [
        "Arlo", "Aurelio", "Carmine", "Corvin", "Cyprien",
        "Damarion", "Delmar", "Granger", "Kaeden", "Kamari",
        "Killian", "Lachlan", "Ludovic", "Manoa", "Miles",
        "Mordecai", "Nasir", "Obadiah", "Phineas", "Raiden",
        "Raylan", "Rocco", "Silas", "Sullivan", "Tavian",
        "Tomas", "Uriah", "Vincent", "Whitaker", "Yannick",
        "Yosef", "Zander"
    ]

    private static let ownerLastNames: [String] = [
        "Adkerson", "Beckwith", "Burkhalter", "Chastain", "Cuthbertson",
        "Danforth", "Denbrough", "Eberhardt", "Estabrook", "Fetterman",
        "Gorsuch", "Greenhalgh", "Hawthorne", "Jessup", "Ledbetter",
        "Longstreth", "Macalister", "Manzanares", "Maycomb", "Medlock",
        "Merriweather", "Osgood", "Pettigrew", "Pomeroy", "Poteet",
        "Prudhomme", "Radcliffe", "Shackleford", "Southgate", "Stockbridge",
        "Upshaw", "Zabriskie"
    ]

    /// Given names for the female owners of a GENERATED league. Crossed with the
    /// SAME `ownerLastNames` as the male pool, so gate E checks a sixth 16 × 32
    /// product on this file — fictional and blocklist-clean for exactly the
    /// reasons above.
    ///
    /// 16 entries, and the power of two is deliberate rather than tidy: swapping
    /// this array in for the 32-name male one must not move the seeded template
    /// stream, and `randomElement` resolves a power-of-two count in exactly one
    /// `next()` call (Lemire's method rejects nothing when the bound divides
    /// 2⁶⁴). Any other count would leave a — vanishing, but real — chance of a
    /// rejection loop consuming a second value and shifting every draw after it.
    private static let ownerFemaleFirstNames: [String] = [
        "Adele", "Beatrix", "Celeste", "Cordelia",
        "Delphine", "Eleanor", "Genevieve", "Harriet",
        "Imelda", "Josefina", "Lorraine", "Odette",
        "Seraphina", "Theodora", "Winifred", "Yvette"
    ]

    /// Share of a generated league's 32 owners drawn female. The real league had
    /// five female principal owners in 2026 (~16 %); the generated league sits a
    /// little under that because its owners are invented from scratch rather than
    /// inherited, and inheritance is what puts most of them in the chair.
    ///
    /// Read ONLY on the unseeded path — a template import takes the gender from
    /// the file instead (`LeagueTemplate.Identity.ownerGender`).
    private static let ownerFemaleShare: Double = 0.12


    private static let coachFirstNames: [String] = [
        "Cade", "Cassius", "Cedric", "Cortez", "Damir",
        "Darian", "Emiliano", "Emrys", "Enzo", "Fenwick",
        "Garrison", "Ivo", "Jibril", "Kellen", "Lorne",
        "Nakoa", "Onyx", "Pell", "Riggs", "Roderick",
        "Ruben", "Sabastian", "Saul", "Sorin", "Theo",
        "Tiago", "Trenton", "Ulises", "Weston", "Zeke"
    ]

    /// Given names for the ~6 % of generated-league staff that come out female
    /// (`CoachingEngine.femaleCoachShare`). Crossed with the SAME
    /// `coachLastNames` as the male pool, so gate E checks a second 30 × 30
    /// product on this file — fictional and blocklist-clean for exactly the
    /// reasons above.
    private static let coachFemaleFirstNames: [String] = [
        "Angela", "Bridget", "Camille", "Carmen", "Colleen",
        "Cynthia", "Danielle", "Deborah", "Denise", "Felicia",
        "Gloria", "Ingrid", "Janelle", "Justine", "Keisha",
        "Marisol", "Marlene", "Michelle", "Monica", "Nadia",
        "Noelle", "Octavia", "Patrice", "Priya", "Regina",
        "Rochelle", "Rosalind", "Sabrina", "Simone", "Vanessa"
    ]

    private static let coachLastNames: [String] = [
        "Ansley", "Battaglia", "Bidwell", "Brimmer", "Cantwell",
        "Dalrymple", "Falkenrath", "Fontenot", "Fullerton", "Galbraith",
        "Harcourt", "Hardesty", "Hillenbrand", "Inglewood", "Jorgensen",
        "Kittredge", "Milburn", "Moorcroft", "Netherton", "Ormsby",
        "Pemberton", "Petitjean", "Selwyn", "Shirtliff", "Steadman",
        "Swearingen", "Tillinghast", "Wetherell", "Wimberly", "Wolverton"
    ]

    // MARK: - Public API

    typealias GeneratedLeague = (
        league: League,
        teams: [Team],
        players: [Player],
        owners: [Owner],
        coaches: [Coach],
        draftPicks: [DraftPick]
    )

    /// Generates a complete league with 32 teams, rosters, owners, and coaching staffs.
    /// - Parameter startYear: The starting year for the league (defaults to 2025).
    /// - Returns: A tuple containing the league and all generated entities.
    static func generate(startYear: Int = 2025) -> GeneratedLeague {
        var allTeams: [Team] = []
        var allPlayers: [Player] = []
        var allOwners: [Owner] = []
        var allCoaches: [Coach] = []
        /// AI owner portraits already handed out — 32 picks from 96 ids, so no two
        /// owners in the same league share a face (`ExtrasCatalog.ownerFaceID`).
        var takenOwnerFaceIDs: Set<String> = []

        for teamDef in NFLTeamData.allTeams {
            // Create owner (budget matches team preview data)
            let owner = generateOwner(
                mediaMarket: teamDef.mediaMarket,
                teamAbbreviation: teamDef.abbreviation,
                takenFaceIDs: takenOwnerFaceIDs
            )
            if let ownerFaceID = owner.faceID { takenOwnerFaceIDs.insert(ownerFaceID) }
            allOwners.append(owner)

            // Create team
            let team = Team(
                name: teamDef.name,
                city: teamDef.city,
                abbreviation: teamDef.abbreviation,
                conference: teamDef.conference,
                division: teamDef.division,
                mediaMarket: teamDef.mediaMarket,
                owner: owner
            )

            // Create 53-man roster with realistic salary tiers.
            // Pass the team abbreviation so the starting QB matches the TeamPreview data.
            let teamPlayers = generateRoster(teamID: team.id, teamAbbreviation: teamDef.abbreviation)
            team.players = teamPlayers

            // Bug fix #1: Set cap usage to sum of all player salaries
            team.currentCapUsage = teamPlayers.reduce(0) { $0 + $1.annualSalary }

            allPlayers.append(contentsOf: teamPlayers)

            // Create coaching staff (12 coaches)
            var teamCoaches: [Coach] = []
            for role in coachingStaffRoles {
                let coach = generateCoach(role: role, teamID: team.id)
                allCoaches.append(coach)
                teamCoaches.append(coach)
            }

            // Initialize scheme expertise for coaches
            initializeSchemeExpertise(for: teamCoaches)

            // Initialize position and scheme familiarity for players
            initializePlayerFamiliarity(players: teamPlayers, coaches: teamCoaches)

            allTeams.append(team)
        }

        // Phase 4 faces: one batched pass over the whole league so the registry
        // is encoded once instead of ~2 000 times. Runs after every roster and
        // staff exists, so the deterministic pick sees the final population.
        // Idempotent — it only touches rows whose `faceID` is still nil.
        FaceLibrary.shared.backfill(players: allPlayers, coaches: allCoaches)
        #if DEBUG
        // Every person in a fresh random league must own a distinct portrait.
        FaceLibrary.shared.debugAuditActiveFaces(
            players: allPlayers, coaches: allCoaches, label: "generated-league"
        )
        #endif

        let league = League(
            teams: allTeams,
            currentSeason: startYear
        )

        // Bug fix #3: Generate draft picks for all teams — the upcoming draft's
        // real board plus the next three years of tradable future picks (plan
        // finding S1: without them the trade market has nothing to deal in).
        let draftPicks = generateInitialDraftPicks(teams: allTeams, seasonYear: startYear)
            + futureDraftPicks(teams: allTeams, afterSeason: startYear)

        return (league, allTeams, allPlayers, allOwners, allCoaches, draftPicks)
    }

    // MARK: - Career Backstory (random league)

    /// How many prior seasons a generated player's backstory covers. Matches the
    /// template's own window (the 2018-2025 scrape), so a random career table and
    /// a fixed-league one are the same shape.
    private static let backstorySeasonCap = 8

    /// Builds `PlayerSeasonHistory` rows for a freshly *generated* league, so a
    /// random career opens with the same kind of past a template career has.
    ///
    /// The generator rolls rosters but no history, which left the Career Stats
    /// table empty for every veteran on a random league — and left the
    /// development / retirement / draft-grade engines reading a league where
    /// nobody had ever played a game. Each prior season gets an OVR walked
    /// backwards along the position's own aging curve (a 33-year-old corner was
    /// better at 27; a 23-year-old receiver was worse at 21), participation from
    /// the implied role, and a statline from `SeasonStatSynthesizer`.
    ///
    /// Unlike the template path this is **not** determinism-constrained — the
    /// random generator already draws from `SystemRandomNumberGenerator`
    /// throughout — so a fresh league gets a fresh past.
    ///
    /// - Parameters:
    ///   - players: every player in the generated league.
    ///   - startYear: the season the career opens on; backstory covers the years
    ///     strictly before it.
    static func syntheticCareerHistory(
        players: [Player],
        startYear: Int
    ) -> [PlayerSeasonHistory] {
        var rng = SystemRandomNumberGenerator()
        var rows: [PlayerSeasonHistory] = []

        for player in players {
            let seasons = min(player.yearsPro, backstorySeasonCap)
            guard seasons > 0 else { continue }
            let ceiling = min(99, max(player.overall, player.truePotential))
            let nowRatio = abilityRatio(age: player.age, position: player.position)

            for offset in 1...seasons {
                let age = max(20, player.age - offset)
                let ratio = abilityRatio(age: age, position: player.position)
                let overall = min(ceiling, max(40, Int((Double(player.overall) * ratio / nowRatio).rounded())))
                let participation = SeasonStatSynthesizer.participation(
                    position: player.position, role: nil,
                    overall: overall, using: &rng
                )
                let stats = SeasonStatSynthesizer.line(
                    position: player.position,
                    overall: overall,
                    gamesPlayed: participation.gamesPlayed,
                    gamesStarted: participation.gamesStarted,
                    age: age,
                    using: &rng
                )
                rows.append(PlayerSeasonHistory(
                    playerID: player.id,
                    season: startYear - offset,
                    overallAtEndOfSeason: overall,
                    gamesPlayed: participation.gamesPlayed,
                    gamesStarted: participation.gamesStarted,
                    ageAtEndOfSeason: age,
                    // The generator has no trade/free-agency past to replay, so
                    // the whole backstory sits on the player's current club.
                    teamID: player.teamID,
                    position: player.position,
                    statLine: stats,
                    statsAreSynthesized: true
                ))
            }
        }
        return rows
    }

    /// Fraction of his own peak ability a player of `age` holds at `position`.
    /// Inside the peak window it is 1.0; the pre-peak climb is steeper than the
    /// post-peak decline, which is the shape every aging curve in
    /// `docs/DEVELOPMENT_NFL_REFERENCE.md` §1 shows.
    private static func abilityRatio(age: Int, position: Position) -> Double {
        let peak = position.peakAgeRange
        if age < peak.lowerBound {
            return max(0.62, 1.0 - 0.045 * Double(peak.lowerBound - age))
        }
        if age > peak.upperBound {
            return max(0.70, 1.0 - 0.030 * Double(age - peak.upperBound))
        }
        return 1.0
    }

    // MARK: - Fixed League (Template Import)

    /// Builds a league from a baked **fixed template** instead of generating a
    /// random one (`docs/REALISTIC_LEAGUE_PLAN.md` phase 3).
    ///
    /// This is the second of the two league sources the new-career flow offers.
    /// Where `generate(startYear:)` rolls 32 fresh rosters, this one replays a
    /// constant, pre-calibrated 2026 snapshot: the same 1 807 players, the same
    /// ratings, the same staffs, the same pick ownership on every import
    /// (`LeagueTemplateImporter` documents the seeding).
    ///
    /// The result is a superset of `GeneratedLeague` — the template path also
    /// produces `PlayerSeasonHistory` rows from each player's baked career arc.
    /// The random path's equivalent is the separate
    /// `syntheticCareerHistory(players:startYear:)` backstory pass.
    ///
    /// - Parameters:
    ///   - template: A decoded template — see `LeagueTemplateLoader.load(_:)`.
    ///   - startYear: Season the career opens on. Defaults to the template's own
    ///     `leagueYear`.
    static func generateFromTemplate(
        _ template: LeagueTemplate,
        startYear: Int? = nil
    ) -> LeagueTemplateImporter.ImportedLeague {
        LeagueTemplateImporter.build(from: template, startYear: startYear)
    }

    /// Convenience: loads the bundled template for `profile` and imports it.
    ///
    /// Throws `LeagueTemplateLoader.LoadError` when the profile is not in this
    /// build (the dev profile in a Release product) or the file is malformed.
    static func generateFromTemplate(
        profile: LeagueTemplate.Profile,
        startYear: Int? = nil
    ) throws -> LeagueTemplateImporter.ImportedLeague {
        let template = try LeagueTemplateLoader.load(profile)
        return generateFromTemplate(template, startYear: startYear)
    }

    // MARK: - Draft Pick Generation

    /// The order the first draft of a new career is picked in: worst record
    /// first, exactly as the league does it.
    ///
    /// This replaced a hardcoded 32-name list copied from a real mock draft. That
    /// list had two properties that made no sense inside a generated league:
    /// four franchises appeared twice (they had traded up in reality) and four —
    /// IND, JAX, GB, ATL — did not appear at all, so **those clubs started a
    /// brand-new career with no first-round pick and nothing anywhere explaining
    /// why**. The Draft tab simply showed six picks and no round 1. It also
    /// contradicted the team picker, which advertises each club's record: a 4-13
    /// team could find itself picking 16th, or not at all.
    ///
    /// Records come from the same `NFLTeamData` previews the picker shows, so
    /// the order the user sees on draft day is the order the standings he chose
    /// from imply. Fully deterministic (no RNG); ties break on abbreviation.
    ///
    /// **Scope (second look, task #85).** This orders exactly ONE draft: the
    /// career's first. A career opens at `.coachingChanges`, i.e. in the
    /// offseason that FOLLOWS the previews' season, so the previews' records are
    /// the right input for it — and every later draft is renumbered from real
    /// standings by `WeekAdvancer.adoptFuturePicks` /
    /// `DraftEngine.draftSlotOrder`. Two things that follows from, both
    /// deliberate and both easy to break by accident:
    ///
    ///  * **These rows must stay `isProvisionalOrder == false`.**
    ///    `adoptFuturePicks` renumbers only provisional rows; if this pool were
    ///    ever minted provisional, season 1's board would be re-slotted from a
    ///    season that has not been played yet — `StandingsCalculator` over zero
    ///    games — and the whole first round would come out in standings-tie
    ///    order.
    ///  * **This is NOT `draftSlotOrder`'s rule, and cannot be.** The real
    ///    league orders picks 19-32 by round of playoff elimination and puts the
    ///    Super Bowl loser and champion last; `draftSlotOrder` does exactly that
    ///    for every later draft. The previews carry no playoff results, only a
    ///    W-L, so season 1 necessarily orders its twelve best clubs by record
    ///    alone. Do not "fix" the two to agree — the input, not the rule, is
    ///    what differs.
    /// Rounds in an NFL draft — and therefore the picks a club starts a career
    /// with, before trades and compensatory awards.
    static let roundsPerDraft = 7

    static func initialDraftOrder(teams: [Team]) -> [Team] {
        teams.sorted { lhs, rhs in
            let l = NFLTeamData.previews[lhs.abbreviation]
            let r = NFLTeamData.previews[rhs.abbreviation]
            let lWins = l?.lastSeasonWins ?? 8
            let rWins = r?.lastSeasonWins ?? 8
            let lGames = lWins + (l?.lastSeasonLosses ?? 9)
            let rGames = rWins + (r?.lastSeasonLosses ?? 9)
            let lPct = lGames > 0 ? Double(lWins) / Double(lGames) : 0.5
            let rPct = rGames > 0 ? Double(rWins) / Double(rGames) : 0.5
            if lPct != rPct { return lPct < rPct }
            return lhs.abbreviation < rhs.abbreviation
        }
    }

    /// Generates 7 rounds of draft picks for each team, worst record first.
    ///
    /// Every club gets exactly one pick in every round — 224 rows, 32 per round.
    /// Compensatory picks are minted later by `CompensatoryPickEngine`; trades
    /// move ownership. Nothing here hands a franchise an extra first or takes
    /// one away.
    ///
    /// - Parameters:
    ///   - teams: All 32 generated teams.
    ///   - seasonYear: The draft year.
    /// - Returns: An array of all draft picks.
    static func generateInitialDraftPicks(teams: [Team], seasonYear: Int) -> [DraftPick] {
        let order = initialDraftOrder(teams: teams)
        var picks: [DraftPick] = []
        var overallPick = 1

        for round in 1...roundsPerDraft {
            for team in order {
                picks.append(DraftPick(
                    seasonYear: seasonYear,
                    round: round,
                    pickNumber: overallPick,
                    originalTeamID: team.id,
                    currentTeamID: team.id,
                    teamAbbreviation: team.abbreviation
                ))
                overallPick += 1
            }
        }

        return picks
    }

    /// How many future draft years exist as tradable `DraftPick` rows at any
    /// moment. Three is the NFL's own horizon (the Ted Thompson rule: you may
    /// trade picks up to three drafts out), and it is what makes a "2029 first"
    /// something a rebuilder can actually ask for.
    static let futurePickHorizon = 3

    /// Mints the pick rows for the `horizon` drafts AFTER `season` — the whole
    /// point of plan finding S1: during a regular season the current draft's board
    /// is either unbuilt or already spent, so without these the tradable pick pool
    /// is empty and every pick-for-player deal dies on a `guard !picks.isEmpty`.
    ///
    /// Each row is owned by the team that earned it (`original == current`), so a
    /// later trade shows provenance for free. `pickNumber` is the midpoint of the
    /// round and `isProvisionalOrder` is `true` — see `DraftPick.isProvisionalOrder`
    /// for why a future pick is priced as a round, not as a slot.
    ///
    /// No RNG: teams are walked in abbreviation order, so the output depends only
    /// on the roster of teams and the year. The template import calls this too and
    /// its determinism gate (TVAL) must stay green.
    static func futureDraftPicks(
        teams: [Team],
        afterSeason season: Int,
        horizon: Int = futurePickHorizon
    ) -> [DraftPick] {
        let ordered = teams.sorted { $0.abbreviation < $1.abbreviation }
        var picks: [DraftPick] = []
        for year in (season + 1)...(season + max(1, horizon)) {
            for round in 1...7 {
                for team in ordered {
                    picks.append(DraftPick(
                        seasonYear: year,
                        round: round,
                        pickNumber: round * 32 - 16,
                        originalTeamID: team.id,
                        currentTeamID: team.id,
                        teamAbbreviation: team.abbreviation,
                        isProvisionalOrder: true
                    ))
                }
            }
        }
        return picks
    }

    // MARK: - Private Generators

    private static func generateOwner(
        mediaMarket: MediaMarket,
        teamAbbreviation: String,
        takenFaceIDs: Set<String> = []
    ) -> Owner {
        var rng = SystemRandomNumberGenerator()
        return generateOwner(
            mediaMarket: mediaMarket,
            teamAbbreviation: teamAbbreviation,
            using: &rng,
            takenFaceIDs: takenFaceIDs
        )
    }

    /// Seeded variant of `generateOwner` — the fixed-league template import needs
    /// the same owner every time it runs (`LeagueTemplateImporter`).
    ///
    /// - Parameters:
    ///   - genderOverride: `"male"` / `"female"` from the template
    ///     (`LeagueTemplate.Identity.ownerGender`). Non-nil SUPPRESSES the gender
    ///     draw — see the coupling note in the body.
    ///   - takenFaceIDs: The AI owner portraits already handed out in this
    ///     league. Owners are created exactly once per league and never retired
    ///     or replaced, so the caller's running set is the whole uniqueness story
    ///     — see `ExtrasCatalog.ownerFaceID` for why no claim registry or
    ///     cooldown is involved. Not `inout` on purpose: `inout` cannot carry a
    ///     default value, and every existing call site should stay
    ///     source-compatible.
    static func generateOwner<G: RandomNumberGenerator>(
        mediaMarket: MediaMarket,
        teamAbbreviation: String,
        genderOverride: String? = nil,
        using rng: inout G,
        takenFaceIDs: Set<String> = []
    ) -> Owner {
        // COUPLING — the same shape as `generateCoach`'s gender draw, and gated
        // for a sharper reason: this function runs on the SEEDED template stream
        // for all 32 clubs (`LeagueTemplateImporter.build`), so one extra
        // `Double.random` here would move every value after it — the name, the
        // avatar, patience, spending, meddling, prefersWinNow — for the whole
        // Fixed 2026 league. A template therefore states the gender and NO draw
        // happens; only the generated league rolls for it.
        //
        // The name-pool swap below costs nothing by construction
        // (`ownerFemaleFirstNames` documents why); the avatar swap is the one
        // thing that intentionally moves — every owner now draws from his or her
        // own illustration set — and all 32 template seeds were replayed to
        // confirm the draw count, and therefore patience / spending / meddling /
        // prefersWinNow, came out identical.
        let isFemale: Bool
        if let genderOverride {
            isFemale = genderOverride == "female"
        } else {
            isFemale = Double.random(in: 0..<1, using: &rng) < ownerFemaleShare
        }
        let first = (isFemale ? ownerFemaleFirstNames : ownerFirstNames)
            .randomElement(using: &rng)!
        let last = ownerLastNames.randomElement(using: &rng)!
        // Burned draw — the retired cartoon-avatar pick. `randomElement` over a
        // non-power-of-two collection consumes a VARIABLE number of RNG words
        // (rejection sampling), so this must reproduce the exact bounds the old
        // list had (11 male ids / 3 female ids) to keep every subsequent draw —
        // patience, spending, meddling, prefersWinNow — bit-identical for a
        // given seed. Do not "simplify" to a single rng.next().
        _ = Int.random(in: 0..<(isFemale ? 3 : 11), using: &rng)
        // Derived from the owner's own UUID and gender, so it consumes NO random
        // value — a seeded template import keeps drawing exactly the numbers it
        // drew before this portrait existed, and the avatar/patience/spending
        // draws above are untouched. The id itself is fresh per league (it always
        // was: `Owner.init` defaulted it), so the portrait is fixed for the life
        // of a save rather than identical across two imports of the same template
        // — which is all any UI needs, and `ExtrasCatalog.ownerFaceID` explains
        // why nothing stronger is warranted.
        let ownerID = UUID()
        let faceID = ExtrasCatalog.shared.ownerFaceID(
            for: ownerID,
            gender: isFemale ? .female : .male,
            taken: takenFaceIDs
        )

        // Use team-specific spending willingness from preview data (with ±5 jitter)
        // so the generated budget matches what the player saw on the Team Selection screen.
        let preview = NFLTeamData.previews[teamAbbreviation]
        let baseSpending = preview?.spendingWillingness ?? 50
        let spending = max(1, min(99, baseSpending + Int.random(in: -5...5, using: &rng)))

        // Coaching budget from preview (converted to thousands) — matches Team Selection display
        let coachingBudget = (preview?.coachingBudget ?? 35) * 1_000

        return Owner(
            id: ownerID,
            name: "\(first) \(last)",
            avatarID: "",   // retired cartoon id — field kept only for schema stability
            patience: Int.random(in: 2...9, using: &rng),
            spendingWillingness: spending,
            meddling: Int.random(in: 5...80, using: &rng),
            prefersWinNow: Bool.random(using: &rng),
            coachingBudget: coachingBudget,
            // R27: dedicated scouting pot scales with spending willingness
            scoutingBudget: BudgetEngine.defaultScoutingBudget(spendingWillingness: spending),
            // R31: dedicated medical pot scales with spending willingness
            medicalBudget: BudgetEngine.defaultMedicalBudget(spendingWillingness: spending),
            gender: isFemale ? "female" : "male",
            faceID: faceID
        )
    }

    /// Generates a full 53-man roster with realistic salary tiers.
    /// The starting QB uses the name and target overall from the TeamPreview data
    /// so the roster matches what the player saw on the Team Selection screen.
    /// Total salary targets ~$200-230M (80-90% of $255M cap).
    private static func generateRoster(teamID: UUID, teamAbbreviation: String) -> [Player] {
        var players: [Player] = []
        var depthChart: [Position: Int] = [:]

        // Look up the team's preview to get the named starting QB
        let preview = NFLTeamData.previews[teamAbbreviation]

        for (position, count) in rosterBlueprint {
            for _ in 0..<count {
                let depthIndex = depthChart[position, default: 0]

                // For the starting QB (depthIndex 0), use the named QB from TeamPreview
                if position == .QB && depthIndex == 0, let preview = preview {
                    let player = generateNamedQB(
                        previewName: preview.startingQBName,
                        targetOverall: preview.startingQBOverall,
                        teamID: teamID
                    )
                    players.append(player)
                } else {
                    let player = generatePlayer(position: position, teamID: teamID, depthIndex: depthIndex)
                    players.append(player)
                }
                depthChart[position] = depthIndex + 1
            }
        }

        // Adjust total salary to target 80-95 % of the cap. `realisticSalary`
        // supplies the SHAPE of a cap sheet (who is paid what, relative to what
        // he is worth); this supplies the LEVEL, and holding it here is what
        // keeps aggregate payroll where the #27/#53 economy calibration put it
        // no matter how the shape is re-derived.
        let targetCap = Int.random(in: rosterCapTargetBand)
        let currentTotal = players.reduce(0) { $0 + $1.annualSalary }

        if currentTotal > 0 {
            let ratio = Double(targetCap) / Double(currentTotal)
            for player in players {
                let adjusted = Int((Double(player.annualSalary) * ratio).rounded())
                // Enforce minimum salary of $750K
                player.annualSalary = max(750, adjusted)
            }
        }

        return players
    }

    /// Internal (not private) since R32: `WeekAdvancer`'s roster-floor pass
    /// reuses it to generate street free agents when the FA pool runs dry.
    static func generatePlayer(position: Position, teamID: UUID, depthIndex: Int) -> Player {
        let name = RandomNameGenerator.randomName()
        let age = randomAge(for: position)
        let yearsPro = max(0, age - Int.random(in: 21...23))
        // The player's own level = where his age puts him + who he is. The
        // second term is the P1 pyramid wave's addition; see `talentLevelShift`.
        // Both are folded into ONE shift before it is applied, so the position
        // skills, the physicals and the mentals all move together and `overall`
        // moves with them roughly 1:1.
        let levelShift = ageLevelShift(age: age, position: position)
            + talentLevelShift(depthIndex: depthIndex)
        let ageShift = Int(levelShift.rounded())
        let posAttrs = randomPositionAttributes(
            for: position, depthIndex: depthIndex, ageShift: ageShift
        )
        // Bodies come from the shared per-position priors so veterans and draft
        // prospects are drawn from one distribution. Previously every player at
        // every position got `PhysicalAttributes.random()` (uniform 40...99), so
        // a centre was as likely to be a 95-speed athlete as a cornerback.
        // `levelShift` (not `ageShift`) — the physical and mental priors take a
        // Double, so they get the exact level; only the position-skill range,
        // which is an integer range, has to round.
        let physical = PositionPhysicalProfile.sample(
            for: position,
            levelShift: veteranLevelShift(depthIndex: depthIndex) + levelShift
        )
        // Mental follows the same route as physical (phase-2 plan §2.2/§2.7):
        // the shared position-shaped priors instead of `MentalAttributes.random()`
        // (uniform 40...99). The level is anchored to `baseLevel` (69.5 — the
        // uniform draw's exact mean) plus the same depth-tier shift, so a QB's
        // awareness tilt survives while league-average mental — and therefore
        // league-average `overall` — is unchanged. See the arithmetic in
        // `veteranLevelShift`.
        let mental = PositionPhysicalProfile.sampleMental(
            for: position,
            targetAverage: PositionPhysicalProfile.baseLevel
                + veteranLevelShift(depthIndex: depthIndex) + levelShift
        )
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement()!,
            motivation: Motivation.allCases.randomElement()!
        )
        let contractYears = realisticContractYears(yearsPro: yearsPro, age: age)

        // The man is built BEFORE he is priced (task #87 / F1): the seeder is
        // rating-aware now, and `overall` is a blend of all three attribute
        // blocks that only `Player` knows how to compute. Salary and morale are
        // written back a few lines down.
        let player = Player(
            firstName: name.first,
            lastName: name.last,
            position: position,
            age: age,
            yearsPro: yearsPro,
            physical: physical,
            mental: mental,
            positionAttributes: posAttrs,
            personality: personality,
            teamID: teamID,
            contractYearsRemaining: contractYears,
            annualSalary: 750
        )
        let salary = realisticSalary(
            for: position, overall: player.overall, age: age,
            yearsPro: yearsPro, depthIndex: depthIndex,
            salaryCap: ContractEngine.openingSalaryCap
        )
        player.annualSalary = salary
        player.morale = initialMorale(
            personality: personality.archetype,
            age: age,
            depthIndex: depthIndex,
            contractYears: contractYears,
            salary: salary,
            marketValue: ContractEngine.estimateMarketValue(
                overall: player.overall, position: position, age: age,
                salaryCap: ContractEngine.openingSalaryCap
            ),
            position: position
        )
        player.learning = learningValue(mental: mental)
        player.competitiveness = competitivenessValue(
            archetype: personality.archetype, mental: mental
        )
        // Where he is from. Written here because nothing else ever wrote it:
        // the whole hometown layer (`HometownDetector`'s regional discount, the
        // "comes home" FA storyline, `PlayerPreferenceEngine`'s family term) is
        // guarded on `hometownState != nil` and so has never fired for a single
        // player. See `HometownGenerator` for the distribution.
        let hometown = HometownGenerator.randomHometown()
        player.hometownState = hometown.state
        player.hometownCity = hometown.city
        // Realization-consistent ceiling (plan §2.7) — replaces the `Player`
        // init's uniform `Int.random(in: 50...99)` default.
        player.truePotential = veteranPotential(
            overall: player.overall, age: age, position: position,
            depthIndex: depthIndex
        )
        // Anchor for the phase-2 ±8 lifetime potential-drift cap (plan §2.6).
        player.draftTruePotential = player.truePotential
        return player
    }

    /// Playbook-absorption rating, generated the same way `DraftClassBuilder`
    /// generates a prospect's. Without this every generated veteran would sit on
    /// the `Player.learning` model default (55) and the whole league would
    /// install schemes at one flat rate.
    ///
    /// Phase 2 (plan §2.2): the math is `MentalAttributeModel.learning` — the
    /// validated `0.40·awareness + 0.60·N(level, 15)` — with the veteran's own
    /// mental average as the level, so veterans, rookies and backfilled legacy
    /// rows all come out of one distribution. The old local
    /// `0.6·awareness + 0.4·U[40,99]` produced a visibly tighter spread.
    static func learningValue(mental: MentalAttributes) -> Int {
        MentalAttributeModel.learning(
            awareness: mental.awareness,
            level: mental.average
        )
    }

    /// Fighter mentality for a generated veteran (plan §2.1), from the same
    /// shared model the draft class uses.
    static func competitivenessValue(
        archetype: PersonalityArchetype,
        mental: MentalAttributes
    ) -> Int {
        MentalAttributeModel.competitiveness(
            archetype: archetype,
            workEthic: mental.workEthic,
            clutch: mental.clutch
        )
    }

    /// Realization-consistent potential ceiling for a generated veteran
    /// (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.7).
    ///
    /// The old behaviour was the `Player` init default, `Int.random(in: 50...99)`
    /// — uncorrelated with age, tier or current ability, so a 31-year-old
    /// 62-OVR depth man carried an expected ceiling of 83. Combined with
    /// slot-correlated draft intake (~79.5 mean potential) that was the dominant
    /// leg of the league **potential ratchet** (+0.9/season measured).
    ///
    /// Its phase-2 replacement shrank the upside with age (22yo ≈ 14 points,
    /// 28yo ≈ 2) and removed it entirely past the position's peak window, on the
    /// argument that this would leave the league's potential level stationary
    /// from season 1 rather than climbing toward the draft's. That argument was
    /// never measured against the draft, and the reconciliation note below is
    /// what happened when it finally was.
    ///
    /// **P1 pyramid calibration (2026-07-30) — the upside is now EARNED, not
    /// granted.** The rule above is age-anchored, which was the phase-2 fix, but
    /// it still handed *every* player inside his peak window a positive upside
    /// draw: `max(0, N(mu, 4))` is never negative, so a 26-year-old journeyman
    /// backup arrived with a ceiling 2-6 points above his rating and a
    /// 22-year-old with 14. Combined with the old
    /// `developmentCeiling = 0.60·pot + 39`, which added a further +7 to +11 on
    /// top for exactly those low-potential players, every generated veteran
    /// started the save with 6-9 OVR of free catch-up room — and the measured
    /// consequence was the 3-season smoke's 90+ share going 3.5 % → 9.5 %.
    ///
    /// **Headroom reconciliation (task #69, 2026-08-04) — MEASURED, and the
    /// prescription was wrong.** The P1 rule above was never checked against the
    /// other end of the pipeline. It is now, and the two disagree by ten OVR
    /// points of ceiling at the same age and the same rating:
    ///
    /// `./run.sh career` builds a league purely out of `DraftClassBuilder`
    /// intake, runs it 30 seasons to its own stationary state and reports the
    /// `HEADROOM AT EQUILIBRIUM` block:
    ///
    /// | age | mean OVR | mean pot | **headroom** | p10 | p50 | p90 |
    /// |---|---|---|---|---|---|---|
    /// | 21 | 62.5 | 81.4 | **18.9** | 9 | 17 | 32 |
    /// | 24 | 66.7 | 80.1 | **13.5** | 6 | 12 | 24 |
    /// | 27 | 72.2 | 82.5 | **10.3** | 4 |  9 | 19 |
    /// | 30 | 77.1 | 86.4 |  **9.3** | 3 |  9 | 16 |
    /// | 33 | 79.3 | 88.0 |  **8.7** | 3 |  9 | 14 |
    /// | all | 70.7 | 82.7 | **12.0** | 4 | 11 | 22 |
    ///
    /// against **2.05** here. So `MultiSeasonSmokeTest`'s standing complaint —
    /// `leaguePot` climbing 73 → 78 across four seasons while the §8 80+ share
    /// rides it out of band — really is this generator converting itself into
    /// the draft's cross-section.
    ///
    /// **The obvious fix makes the game worse, and that is the finding.** The
    /// rule was replaced with a Γ(3) draw whose mean is the measured column
    /// above (mean headroom 12.22, per-age within 0.9 of the equilibrium at
    /// every age, `potential >= 90` 28.1 % against the pipeline's 28.9 %), the
    /// app was built, and the four-season smoke was run on it:
    ///
    /// | 80+ share | base | s1 | s2 | s3 | s4 | mean OVR | leaguePot |
    /// |---|---|---|---|---|---|---|---|
    /// | P1 rule (headroom 2.10) | 17.1 | 16.4 | 18.4 | 18.9 | **20.0** | 71.08 → 72.10 | 73.1 → 79.6 |
    /// | matched (headroom 12.22) | 17.6 | 17.6 | 22.6 | 23.8 | **26.1** | 71.08 → **73.10** | 83.4 → 84.7 |
    ///
    /// (Band 12-19; both rows are the same four-season `PERF_SMOKE_SEASONS=4`
    /// run on the same build settings, measured back to back.) The transient the
    /// change was supposed to close DID close — `leaguePot` went flat instead of
    /// climbing six and a half points — and the league ran away underneath it
    /// anyway: 90+ reached 4.8 % against the P1 rule's 3.2 %, and the mean drift
    /// doubled.
    ///
    /// Note what the top row also says: at the FLOOR of this lever — a
    /// generated veteran arriving 2 points under his ceiling, which is as close
    /// to "no catch-up room" as the rule can get — season 4 is already at
    /// 20.0 %. There is no headroom setting that reaches the band, because the
    /// climb that remains is the draft's own intake, and that is not this file.
    ///
    /// **Which locates the real residual, and it is not here.** At the SAME
    /// potential level the harness league is stationary (`leaguePot` 82.7, mean
    /// OVR 70.7, drift +0.005/season over 21 measured seasons) and the shipped
    /// league climbs half a point a season. Same ceilings, different outcome, so
    /// what differs is the machine between them: with the ceilings matched the
    /// shipped offseason spends `+2.0 … +2.9` OVR per player per season
    /// (`SMOKE: diag devsource offseasonDevelop`) against `+1.3 … +2.0` on the
    /// P1 ceilings — it converts whatever it is given. That is the task-#51 gap,
    /// still open, and it is where the residual actually lives.
    ///
    /// Two hypotheses were tested and killed on the way, so nobody re-tests
    /// them:
    ///
    ///  * *"headroom is concentrated on the players who cannot realise it, so a
    ///    random draw over-supplies the ones who can."* The equilibrium's
    ///    work-ethic quartiles inside the growth window measure 12.6 / 12.8 /
    ///    13.0 / 14.0 — flat, and if anything sloping the other way, because
    ///    high-work-ethic men are drafted higher and start with more ceiling.
    ///  * *"match potential by age instead of headroom by age."* Worth 3.5
    ///    points of prime-age ceiling, i.e. about a third of the growth fuel —
    ///    not the 1.2 OVR/season of drift the measurement would have to remove.
    ///
    /// So the P1 rule is KEPT, unchanged, on the narrow ground that it is the
    /// setting that does not make the shipped league worse — not because it is
    /// right. The measurement above is the brief for the development-side wave
    /// that has to happen first; when it lands, re-run `./run.sh career`,
    /// re-read the `HEADROOM AT EQUILIBRIUM` block and reconcile onto the NEW
    /// equilibrium, which is what this generator should have been fitted to all
    /// along. `leaguegen` assert `8.hea` prints both numbers on every run so the
    /// gap cannot go quiet.
    ///
    /// Two changes, both matching `DEVELOPMENT_NFL_REFERENCE.md` §2's core claim
    /// that "potential is a ceiling few touch" and that the ceiling is set by
    /// TRAJECTORY:
    ///
    ///  1. **Age is measured against the growth years, not the peak window.**
    ///     §1 puts growth *before* the peak window opens and then says
    ///     "plateau". A player already inside his window has, by definition,
    ///     arrived; his remaining upside is the last technique/processing
    ///     increment, not a development runway. So the full runway is only for
    ///     players still climbing toward `peakAgeRange.lowerBound`.
    ///  2. **Upside is gated on the player's own trajectory.** A generated
    ///     veteran's depth tier is the game's statement about what he has
    ///     already become: a starter at 27 has realised his projection, a
    ///     fourth-stringer at 27 has not and is not going to. `tierEarned`
    ///     therefore scales the runway by how much of it the player's current
    ///     standing still justifies, and the draw is centred so that roughly a
    ///     third of players get **no** upside at all — the plateauer, which §2
    ///     calls the single most common outcome. (The equilibrium block above
    ///     contradicts this reading — measured headroom by ability tier is flat
    ///     at ~12 — but see the falsification note: correcting it is a
    ///     development-side wave, not a generator constant.)
    static func veteranPotential(overall: Int, age: Int, position: Position) -> Int {
        veteranPotential(overall: overall, age: age, position: position, depthIndex: 2)
    }

    /// Depth-aware form. `depthIndex` is the trajectory signal — see the rule 2
    /// discussion above. The `depthIndex: 2` default keeps every existing caller
    /// that has no depth context (legacy rows, street free agents) on the most
    /// conservative branch.
    static func veteranPotential(
        overall: Int, age: Int, position: Position, depthIndex: Int
    ) -> Int {
        let peak = position.peakAgeRange
        // Past peak: what you see is what is left. (Unchanged.)
        if age > peak.upperBound {
            return min(99, overall + Int.random(in: 0...2))
        }
        // Inside the peak window a player has arrived; only a token increment is
        // left, and only for those still holding a job at the top of the chart.
        if age >= peak.lowerBound {
            let token = depthIndex == 0 ? 3.0 : (depthIndex == 1 ? 2.0 : 1.0)
            let draw = PositionPhysicalProfile.gaussian(mean: token * 0.5, sd: token)
            return min(99, overall + max(0, Int(draw.rounded())))
        }
        // Still climbing: the runway shrinks as the window approaches, and how
        // much of it the player gets is what his depth tier has already earned.
        let yearsToWindow = Double(peak.lowerBound - age)
        let runway = min(12.0, 2.5 * yearsToWindow)
        let earned = tierEarnedUpside(depthIndex: depthIndex)
        // Centre at 0.55·(runway·earned) with a matching sd: the negative half of
        // the draw is clipped to zero, so ~1 in 3 young players comes out with no
        // headroom at all — the plateauer §2 calls the most common outcome.
        let mu = 0.55 * runway * earned
        let draw = PositionPhysicalProfile.gaussian(mean: mu, sd: max(1.0, mu * 0.8))
        return min(99, overall + max(0, Int(draw.rounded())))
    }

    /// How much of a young player's remaining runway his current standing
    /// justifies. A rookie already starting is a player his club believes in; a
    /// camp body at the bottom of the chart is not, and the reference's
    /// bust/plateau shares (§2: ~25 % bust, ~40 % plateau) are the outcome those
    /// two facts have to produce.
    static func tierEarnedUpside(depthIndex: Int) -> Double {
        switch depthIndex {
        case 0:  return 1.00
        case 1:  return 0.70
        default: return 0.45
        }
    }

    /// Rating level of a generated 21-year-old relative to the depth tier's
    /// nominal ratings (plan §5 stage 6).
    ///
    /// **P1 pyramid calibration (2026-07-30): −6 → −8, and `primeAgeLevel`
    /// 11 → 6.** Both halves of this curve were anchored on a league the engine
    /// no longer sustains. The old +11 prime level was fitted against the
    /// development loop's THEN-measured veteran plateaus (yp4-7 ≈ 78.6,
    /// yp8+ ≈ 82); with `PlayerDevelopmentEngine.developmentCeiling` no longer
    /// handing every player a ceiling above his own potential, the same loop now
    /// plateaus 4-5 points lower, so the generator's prime level follows it down.
    /// See `targetQualityPyramid` for the measured landing point.
    static let rookieAgeLevel: Double = -8.0
    /// Rating level of a generated player inside his position's peak window.
    static let primeAgeLevel: Double = 6.0
    /// Give-back per year once a generated player is past his peak window.
    static let pastPeakAgeDecay: Double = 1.2

    // MARK: - Target Quality Pyramid (the calibration contract)

    /// **What this generator is calibrated to produce, and why those numbers.**
    ///
    /// `docs/DEVELOPMENT_NFL_REFERENCE.md` §8 states the league's quality
    /// pyramid as ABSOLUTE shares of the ~1 700 rostered players:
    ///
    /// | band | §8 target | shipped before this wave | this generator |
    /// |---|---|---|---|
    /// | 90+ ("blue chip", 25-35 players) | 1-2 % | **3.3 %** | 1.80 % (30.5) |
    /// | 80+ | 12-16 % | **37.4 %** | 17.10 % |
    /// | 75+ (starter-quality) | 30-40 % | **62.1 %** | 35.06 % |
    /// | sub-65 (depth / special teams) | ~25 % | **9.4 %** | 23.43 % |
    /// | league mean (derived, not prescribed) | ~71-72 | **76.5** | 71.00 |
    /// | league sd | — | 8.1 | 8.88 |
    /// | rating range | — | 52…93 | 40…97 |
    /// | depth-tier means (starter/backup/depth) | — | 83.5 / 76.0 / 69.8 | 77.3 / 70.9 / 64.9 |
    ///
    /// The old league was not merely too high, it was **too narrow**: every band
    /// missed in the direction of "everybody is a starter". The cause is visible
    /// in the arithmetic. A player's rating was
    /// `tierBase + veteranLevelShift + ageLevelShift + noise`, and the noise term
    /// — the only thing separating two 27-year-old starters at the same position
    /// — has a standard deviation of just **1.85 OVR** (it is the average of four
    /// uniforms plus two averaged Gaussian blocks, all weighted down). So the
    /// entire spread of the league was three depth tiers times one age curve:
    /// a lattice, not a pyramid, and a lattice cannot have a rare top or a thick
    /// floor.
    ///
    /// The fix is therefore not only a level cut. It adds the missing dimension —
    /// `talentLevelShift`, a per-player quality draw — and lowers and widens the
    /// tier ranges around it.
    ///
    /// **Every number above is measured twice, on purpose.**
    /// `cd tools/balance-harness && ./run.sh leaguegen` drives THIS code (the
    /// rating path is awk-sliced verbatim into the harness) over 400 leagues and
    /// asserts the bands; `tools/league-data/make_templates.py` carries an
    /// independent Python mirror of the same math (`reference_overall`), because
    /// the fixed-2026 template league is calibrated onto that mirror. The
    /// `leaguegen` scenario pins the two against each other — they agree to 0.00
    /// on the mean and ≤ 0.26 pp on every share — so a mirror that silently drifts
    /// from this file cannot take both league sources wrong together.
    ///
    /// The mean lands where the DEVELOPMENT stack's own 30-season equilibrium
    /// lands (career harness: 71.4), which is the point of matching them — drift
    /// is by definition the distance between where the generator starts and where
    /// the engine settles.
    enum targetQualityPyramid {
        static let mean = 71.00
        static let sd = 8.88
        static let share90Plus = 1.80
        static let share80Plus = 17.10
        static let share75Plus = 35.06
        static let shareSub65 = 23.43
    }

    /// Per-player quality spread inside a depth tier — **the pyramid's missing
    /// dimension** (see `targetQualityPyramid`).
    ///
    /// Two starting left tackles are not the same player. One is a perennial
    /// All-Pro and one is the reason his club spends a first-round pick on the
    /// position; the generator had no way to say so, because a tier and an age
    /// determined a rating to within ±1.85. This is that draw: a level shift in
    /// OVR points applied to all three rating components at once, so it moves
    /// `overall` about 1:1.
    ///
    /// It is a **split normal** — a wider upper half than lower half — for the
    /// starter tier, because that is the shape §8 describes and a symmetric draw
    /// cannot produce it. A symmetric σ big enough to put 1-2 % of the league
    /// past 90 also puts far too many in the 80-85 shoulder (measured: σ 6.0
    /// symmetric gives 90+ 1.45 % but 80+ 16.6 %, against a 12-16 band). The
    /// asymmetry buys the rare top without the fat shoulder: a small number of
    /// genuine stars, a normal spread of ordinary starters.
    ///
    /// Backups and depth get a symmetric draw: there is no "star" tail among
    /// players who are not starting, and the wide lower half is exactly the
    /// sub-65 floor §8 asks for (23 % of this generator's league, against 9.4 %
    /// before).
    ///
    /// Note that a split normal has a non-zero mean, `√(2/π)·(σ_up − σ_down)` ≈
    /// +2.4 OVR for the starter tier, so it lifts as well as spreads; the tier
    /// ranges below are set with that lift already in them.
    static func talentLevelShift(depthIndex: Int) -> Double {
        var rng = SystemRandomNumberGenerator()
        return talentLevelShift(depthIndex: depthIndex, using: &rng)
    }

    /// Seeded variant, so the template pipeline and the random league execute
    /// identical arithmetic.
    static func talentLevelShift<G: RandomNumberGenerator>(
        depthIndex: Int, using generator: inout G
    ) -> Double {
        let (down, up): (Double, Double)
        switch depthIndex {
        case 0:  (down, up) = (4.5, 7.5)   // starters: rare stars, real busts
        case 1:  (down, up) = (4.5, 4.5)   // backups
        default: (down, up) = (5.0, 5.0)   // depth / special teams
        }
        // Truncated at ±2.6σ. An untruncated draw reaches −5σ often enough to
        // matter: measured over a 400-league Monte-Carlo it put the league's
        // worst player at **OVR 33**, which is not a rostered NFL body at all.
        // Clipping costs nothing at the top (the 90+ share and the league mean
        // are unchanged to two decimals) and moves the floor to 40.
        let z = PositionPhysicalProfile.truncatedGaussian(
            mean: 0, sd: 1, limit: talentSpreadLimit, using: &generator
        )
        return z * (z >= 0 ? up : down)
    }

    /// Truncation on the talent draw, in standard deviations. See
    /// `talentLevelShift`.
    static let talentSpreadLimit: Double = 2.6

    /// Age-shaped rating level, so that **the league the game hands you is a
    /// league this engine sustains** (plan §5 stage 6).
    ///
    /// The stage-6 gate is that `MultiSeasonSmokeTest`'s league mean must not
    /// drift, and drift is by definition the distance between where the
    /// generator starts and where the development / retirement / roster loop
    /// settles. The generator used to draw a player's ratings from his DEPTH
    /// TIER alone: a 21-year-old fourth-stringer and a 28-year-old fourth
    /// stringer came out of the same 50-70 bucket. That is not a league this
    /// engine sustains — measured over five seasons the loop plateaus with
    /// cohorts at yp1 ≈ 65.5, yp2 ≈ 70, yp3 ≈ 74, yp4-7 ≈ 78.6, yp8+ ≈ 82, i.e.
    /// exactly the growth curve `developPlayer` produces — so every generated
    /// young player started ~8 points above where he belonged, carried a
    /// ceiling far above his rating, and promptly grew into it. The whole
    /// measured OVR drift is that inconsistency working itself out.
    ///
    /// This is a level curve, not a spread change: the depth tiers, the
    /// position priors and the within-tier spread are all untouched, so nothing
    /// about the game's internal balance — always one player's rating against
    /// another's, at the same age — changes.
    static func ageLevelShift(age: Int, position: Position) -> Double {
        let peak = position.peakAgeRange
        if age >= peak.lowerBound {
            let past = max(0, age - peak.upperBound)
            return primeAgeLevel - Double(past) * pastPeakAgeDecay
        }
        let entryAge = 21.0
        let span = max(1.0, Double(peak.lowerBound) - entryAge)
        let progress = min(1.0, max(0.0, (Double(age) - entryAge) / span))
        return rookieAgeLevel + (primeAgeLevel - rookieAgeLevel) * progress
    }

    /// Level shift applied to the shared physical AND mental priors by depth
    /// tier. Starters are better athletes than camp bodies, and the 53-man
    /// blueprint holds 19 starters / 15 backups / 19 depth players, so the ±3
    /// shifts cancel exactly (19·(+3) + 15·0 + 19·(−3) = 0) — league-average
    /// physicals and mentals, and therefore league-average `overall`, are
    /// unchanged by either migration.
    ///
    /// Mental arithmetic (plan §2.7 OVR-preservation check): the retired
    /// `MentalAttributes.random()` drew uniform 40...99, mean exactly 69.5 =
    /// `PositionPhysicalProfile.baseLevel`. `sampleMental(targetAverage:)`
    /// shifts its position-shaped priors so their six-attribute mean lands ON
    /// `targetAverage`, so passing `baseLevel + shift` reproduces 69.5 league-wide.
    /// Mental carries 20 % of `overall` → ΔOVR ≈ 0.2 · 0 = 0.
    static func veteranLevelShift(depthIndex: Int) -> Double {
        switch depthIndex {
        case 0:  return 3
        case 1:  return 0
        default: return -3
        }
    }

    /// Creates the starting QB using the name and target overall from TeamPreview.
    /// The preview name format is "F. Last" (e.g., "S. Osgood"); a multi-initial
    /// form ("C.J. Osgood") parses the same way.
    private static func generateNamedQB(previewName: String, targetOverall: Int, teamID: UUID) -> Player {
        // Parse the preview name: split on last space to get firstName and lastName.
        // Examples: "S. Osgood" -> ("S.", "Osgood"), "C.J. Osgood" -> ("C.J.", "Osgood")
        let parts = previewName.split(separator: " ", maxSplits: .max, omittingEmptySubsequences: true)
        let firstName: String
        let lastName: String
        if parts.count >= 2 {
            firstName = parts.dropLast().joined(separator: " ")
            lastName = String(parts.last!)
        } else {
            firstName = String(parts.first ?? "J.")
            lastName = "Doe"
        }

        // Generate physical and mental attributes that produce the target overall.
        // Physicals come from the shared QB priors shifted so their average
        // matches the target (a named 88-OVR QB gets an 88-average QB body, not
        // a receiver's); mental is generated around the same target.
        let mental = attributesForTarget(target: targetOverall, count: 6, variance: 5)

        let qbProfile = PositionPhysicalProfile.profile(for: .QB)
        let physicalAttrs = PositionPhysicalProfile.sample(
            for: .QB,
            levelShift: Double(targetOverall) - qbProfile.meanAverage,
            spread: 0.6
        )
        let mentalAttrs = MentalAttributes(
            awareness: mental[0], decisionMaking: mental[1], clutch: mental[2],
            workEthic: mental[3], coachability: mental[4], leadership: mental[5]
        )

        // Named starting QB: scale position attributes to match the target overall
        // so the QB's position-specific skills are consistent with their reputation.
        let posAttrs = qbPositionAttributesForTarget(target: targetOverall)
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement()!,
            motivation: Motivation.allCases.randomElement()!
        )

        // Franchise QB age: typically 24-32 for a starter
        let age: Int
        if targetOverall >= 85 {
            age = Int.random(in: 25...32)  // Elite QBs are in their prime
        } else if targetOverall >= 75 {
            age = Int.random(in: 24...30)
        } else {
            age = Int.random(in: 22...28)  // Young or developing
        }
        let yearsPro = max(1, age - Int.random(in: 21...23))
        let contractYears = realisticContractYears(yearsPro: yearsPro, age: age)

        // Same order as `generatePlayer`: build, then price (task #87 / F1).
        let player = Player(
            firstName: firstName,
            lastName: lastName,
            position: .QB,
            age: age,
            yearsPro: yearsPro,
            physical: physicalAttrs,
            mental: mentalAttrs,
            positionAttributes: posAttrs,
            personality: personality,
            teamID: teamID,
            contractYearsRemaining: contractYears,
            annualSalary: 750
        )
        let salary = realisticSalary(
            for: .QB, overall: player.overall, age: age,
            yearsPro: yearsPro, depthIndex: 0,
            salaryCap: ContractEngine.openingSalaryCap
        )
        player.annualSalary = salary
        player.morale = initialMorale(
            personality: personality.archetype,
            age: age,
            depthIndex: 0,
            contractYears: contractYears,
            salary: salary,
            marketValue: ContractEngine.estimateMarketValue(
                overall: player.overall, position: .QB, age: age,
                salaryCap: ContractEngine.openingSalaryCap
            ),
            position: .QB
        )
        player.learning = learningValue(mental: mentalAttrs)
        player.competitiveness = competitivenessValue(
            archetype: personality.archetype, mental: mentalAttrs
        )
        // Same hometown pass the ordinary veteran path runs — the named QB is a
        // starter and therefore one of the likeliest players in the league to
        // reach free agency as somebody's hometown storyline.
        let hometown = HometownGenerator.randomHometown()
        player.hometownState = hometown.state
        player.hometownCity = hometown.city
        // The named starting QB is depth index 0 by construction.
        player.truePotential = veteranPotential(
            overall: player.overall, age: age, position: .QB, depthIndex: 0
        )
        player.draftTruePotential = player.truePotential
        return player
    }

    /// Generates an array of attribute values that average to approximately the target.
    /// Each value is clamped to 40-99 and has slight random variance.
    private static func attributesForTarget(target: Int, count: Int, variance: Int) -> [Int] {
        var values = (0..<count).map { _ in
            let v = target + Int.random(in: -variance...variance)
            return min(99, max(40, v))
        }
        // Adjust to hit the target average more precisely
        let currentAvg = values.reduce(0, +) / count
        let diff = target - currentAvg
        if diff != 0 {
            // Spread the difference across attributes
            for i in 0..<min(abs(diff), count) {
                values[i] = min(99, max(40, values[i] + (diff > 0 ? 1 : -1)))
            }
        }
        return values
    }

    private static func generateCoach(role: CoachRole, teamID: UUID) -> Coach {
        var rng = SystemRandomNumberGenerator()
        return generateCoach(role: role, teamID: teamID, using: &rng)
    }

    /// Seeded variant of `generateCoach`.
    ///
    /// - Parameters:
    ///   - nameOverride: When non-nil, the coach's name is taken verbatim instead
    ///     of drawn from the pools — the template import supplies the baked
    ///     (anonymized) HC/OC/DC names and lets the rest of the staff generate.
    ///   - schemeOverride: Forces the coach's scheme identity, so a template
    ///     team really runs the scheme its source staff ran (a fact the
    ///     anonymization deliberately keeps, `ANONYMIZATION_SPEC.md` §4).
    static func generateCoach<G: RandomNumberGenerator>(
        role: CoachRole,
        teamID: UUID,
        nameOverride: (first: String, last: String)? = nil,
        ageOverride: Int? = nil,
        schemeOverride: (offensive: OffensiveScheme?, defensive: DefensiveScheme?)? = nil,
        using rng: inout G
    ) -> Coach {
        let last = nameOverride?.last ?? coachLastNames.randomElement(using: &rng)!
        let age = ageOverride ?? Int.random(in: 35...68, using: &rng)

        // COUPLING — the gender draw sits HERE, after the age, and only on the
        // generated path. `LeagueTemplateImporter.makeStaff` relies on a non-nil
        // `nameOverride` short-circuiting every pool draw so that the age is the
        // FIRST draw of the stream, which `make_templates.py::template_coach_age`
        // replays to pick an age-appropriate portrait for the template's named
        // coaches. A draw ahead of the age — or any draw at all on the override
        // path — silently moves those portraits onto the wrong age band, and
        // gate 19 measures it. Template staff are male by construction anyway
        // (they anonymize real male coaches), so this costs them nothing.
        let first: String
        let gender: String
        if let nameOverride {
            first = nameOverride.first
            gender = "male"
        } else {
            let isFemale = Double.random(in: 0..<1, using: &rng) < CoachingEngine.femaleCoachShare
            gender = isFemale ? "female" : "male"
            first = (isFemale ? coachFemaleFirstNames : coachFirstNames).randomElement(using: &rng)!
        }

        let potential = CoachDevelopmentEngine.generatePotential(forAge: age, using: &rng)
        let experience = max(0, age - Int.random(in: 28...40, using: &rng))

        let wantsOffense = (role == .headCoach || role == .offensiveCoordinator || role == .assistantHeadCoach)
        let wantsDefense = (role == .headCoach || role == .defensiveCoordinator || role == .assistantHeadCoach)
        let offScheme: OffensiveScheme? = wantsOffense
            ? (schemeOverride?.offensive ?? OffensiveScheme.allCases.randomElement(using: &rng)!)
            : nil
        let defScheme: DefensiveScheme? = wantsDefense
            ? (schemeOverride?.defensive ?? DefensiveScheme.allCases.randomElement(using: &rng)!)
            : nil

        let personality = PersonalityArchetype.allCases.randomElement(using: &rng)!

        // Role-aware attribute generation: proper hierarchy
        // HC: highest overall, Coordinators: mid, Position coaches: specialists
        let goodFloor: Int
        let goodCeiling: Int
        let weakFloor: Int
        let weakCeiling: Int
        let goodCount: Int
        let isPositionCoach: Bool

        switch role {
        case .headCoach:
            goodFloor = 70; goodCeiling = 95; weakFloor = 55; weakCeiling = 70
            goodCount = Int.random(in: 5...8, using: &rng)
            isPositionCoach = false
        case .assistantHeadCoach:
            goodFloor = 68; goodCeiling = 90; weakFloor = 50; weakCeiling = 65
            goodCount = Int.random(in: 4...6, using: &rng)
            isPositionCoach = false
        case .offensiveCoordinator, .defensiveCoordinator:
            goodFloor = 65; goodCeiling = 90; weakFloor = 50; weakCeiling = 65
            goodCount = Int.random(in: 4...6, using: &rng)
            isPositionCoach = false
        case .specialTeamsCoordinator:
            goodFloor = 62; goodCeiling = 85; weakFloor = 45; weakCeiling = 58
            goodCount = Int.random(in: 3...5, using: &rng)
            isPositionCoach = false
        default: // Position coaches: specialists
            goodFloor = 70; goodCeiling = 85; weakFloor = 40; weakCeiling = 60
            goodCount = Int.random(in: 1...5, using: &rng)
            isPositionCoach = true
        }

        let allAttrNames = ["playCalling", "playerDevelopment", "reputation", "adaptability",
                            "gamePlanning", "scoutingAbility", "recruiting", "motivation",
                            "discipline", "mediaHandling", "contractNegotiation", "moraleInfluence"]
        let focusAttrs = role.focusAttributes
        var goodIndices = Set<Int>()

        if isPositionCoach {
            for (i, name) in allAttrNames.enumerated() {
                if focusAttrs.contains(name) { goodIndices.insert(i) }
            }
        }
        var remaining = Array(0..<12).filter { !goodIndices.contains($0) }
        remaining.shuffle(using: &rng)
        let slotsNeeded = max(0, goodCount - goodIndices.count)
        for i in 0..<min(slotsNeeded, remaining.count) {
            goodIndices.insert(remaining[i])
        }

        func genAttr(_ index: Int) -> Int {
            goodIndices.contains(index)
                ? Int.random(in: goodFloor...goodCeiling, using: &rng)
                : Int.random(in: weakFloor...weakCeiling, using: &rng)
        }

        let tmpPlayCalling = genAttr(0)
        let tmpPlayerDev   = genAttr(1)
        let tmpReputation  = genAttr(2)
        let tmpAdaptability = genAttr(3)
        let tmpGamePlanning = genAttr(4)
        let tmpScouting     = genAttr(5)
        let tmpRecruiting   = genAttr(6)
        let tmpMotivation   = genAttr(7)
        let tmpDiscipline   = genAttr(8)
        let tmpMedia        = genAttr(9)
        let tmpContract     = genAttr(10)
        let tmpMorale       = genAttr(11)

        let ovr = (tmpPlayCalling + tmpPlayerDev + tmpReputation + tmpAdaptability
            + tmpGamePlanning + tmpScouting + tmpRecruiting + tmpMotivation
            + tmpDiscipline + tmpMedia + tmpContract + tmpMorale) / 12

        let salary = Self.salaryForCoach(
            role: role, ovr: ovr, yearsExperience: experience, using: &rng
        )

        let coach = Coach(
            firstName: first,
            lastName: last,
            age: age,
            role: role,
            offensiveScheme: offScheme,
            defensiveScheme: defScheme,
            playCalling: tmpPlayCalling,
            playerDevelopment: tmpPlayerDev,
            reputation: tmpReputation,
            adaptability: tmpAdaptability,
            gamePlanning: tmpGamePlanning,
            scoutingAbility: tmpScouting,
            recruiting: tmpRecruiting,
            motivation: tmpMotivation,
            discipline: tmpDiscipline,
            mediaHandling: tmpMedia,
            contractNegotiation: tmpContract,
            moraleInfluence: tmpMorale,
            potential: potential,
            salary: salary,
            background: "",
            personality: personality,
            teamID: teamID,
            yearsExperience: experience
        )
        // Before `generateBackground`: the blurb reads pronouns off the coach.
        coach.gender = gender
        coach.background = CoachingEngine.generateBackground(for: coach, using: &rng)
        // Pre-existing staff: treat as hired before career starts
        coach.hireSeasonYear = 2025
        coach.contractYearsRemaining = Int.random(in: 1...4, using: &rng)
        return coach
    }

    // MARK: - Morale Initialization (#278)

    /// Computes initial morale for a generated player based on several factors.
    /// Base range: 65-75. Adjustments for contract, age/depth, and personality.
    private static func initialMorale(
        personality: PersonalityArchetype,
        age: Int,
        depthIndex: Int,
        contractYears: Int,
        salary: Int,
        marketValue: Int,
        position: Position
    ) -> Int {
        var rng = SystemRandomNumberGenerator()
        return initialMorale(
            personality: personality, age: age, depthIndex: depthIndex,
            contractYears: contractYears, salary: salary, marketValue: marketValue,
            position: position, using: &rng
        )
    }

    /// Seeded variant of `initialMorale`.
    ///
    /// `marketValue` is **this man's own** `ContractEngine.estimateMarketValue`
    /// (task #87). It used to be a lookup into `averageMarketSalary`, a hardcoded
    /// per-position table on the pre-normalisation scale — so a 96-OVR starter
    /// and a 62-OVR starter were held to the same "am I paid fairly?" bar, and
    /// the bar itself was a fourth set of salary numbers that nothing else in the
    /// game used.
    static func initialMorale<G: RandomNumberGenerator>(
        personality: PersonalityArchetype,
        age: Int,
        depthIndex: Int,
        contractYears: Int,
        salary: Int,
        marketValue: Int,
        position: Position,
        using rng: inout G
    ) -> Int {
        // Base morale: 65-75 (not a flat 70)
        var morale = Int.random(in: 65...75, using: &rng)

        // Contract situation
        if contractYears <= 1 {
            // Expiring contract: anxious = lower morale
            morale -= Int.random(in: 5...10, using: &rng)
        }

        // Salary perception — against HIS market value, not a position average.
        let marketAvg = max(1, marketValue)
        if salary > Int(Double(marketAvg) * 1.3) {
            // Overpaid = happy
            morale += 5
        } else if salary < Int(Double(marketAvg) * 0.7) {
            // Underpaid = unhappy
            morale -= 5
        }

        // Age vs depth: veteran backup is unhappy, young starter is excited
        let peakStart = position.peakAgeRange.lowerBound
        if depthIndex == 0 && age < peakStart {
            // Young starter: excited
            morale += 5
        } else if depthIndex >= 1 && age >= peakStart + 2 {
            // Veteran backup: frustrated
            morale -= Int.random(in: 5...10, using: &rng)
        }

        // Personality variance
        switch personality {
        case .teamLeader, .mentor, .steadyPerformer:
            morale += Int.random(in: 0...5, using: &rng)
        case .dramaQueen:
            morale -= Int.random(in: 3...8, using: &rng)
        case .loneWolf:
            morale -= Int.random(in: 0...5, using: &rng)
        case .fieryCompetitor:
            morale += Int.random(in: -3...3, using: &rng)
        case .classClown:
            morale += Int.random(in: -2...4, using: &rng)
        case .quietProfessional, .feelPlayer:
            morale += Int.random(in: -2...2, using: &rng)
        }

        return min(99, max(30, morale))
    }

    // MARK: - Helpers

    /// Draws a generated veteran's age from a PYRAMID over the position's
    /// career span instead of a flat uniform (plan §5 stage 6).
    ///
    /// `DEVELOPMENT_NFL_REFERENCE.md` §8 puts a real roster at median age
    /// 25.5-26.5 with **≤ ~2 %** of players 33 or older; a uniform draw over
    /// e.g. a quarterback's 22-38 span produced a league at median 28 with
    /// **14 %** at 33+. That is not a cosmetic difference: `MultiSeasonSmokeTest`
    /// retired 190-210 of those players in season one alone, and every one of
    /// them came back as a draft pick from a pipeline calibrated elsewhere,
    /// which is a large part of the measured OVR drift. The engine's own
    /// steady state (median 25, 33+ ≈ 1.5 %) already matches the reference —
    /// only the generator did not.
    ///
    /// Taking the smaller of two uniform draws puts the mean a third of the way
    /// up the span rather than halfway and thins the tail quadratically, which
    /// is the shape a fixed-size league with annual intake actually has.
    private static func randomAge(for position: Position) -> Int {
        let span = careerAgeSpan(for: position)
        return min(Int.random(in: span), Int.random(in: span))
    }

    private static func careerAgeSpan(for position: Position) -> ClosedRange<Int> {
        switch position {
        case .QB:
            return 22...38
        case .RB, .FB:
            return 21...31
        case .WR:
            return 21...34
        case .TE:
            return 22...33
        case .LT, .LG, .C, .RG, .RT:
            return 22...35
        case .DE, .DT:
            return 22...34
        case .OLB, .MLB:
            return 22...33
        case .CB:
            return 21...33
        case .FS, .SS:
            return 22...33
        case .K, .P:
            return 22...40
        }
    }

    // MARK: - Coach Salary from OVR + Experience

    /// Computes a realistic coach salary (in thousands) based on role ranges, OVR, and experience.
    /// Higher OVR coaches command salaries toward the top of their role's range.
    /// Experience adds a slight bump (up to ~10% of the range).
    static func salaryForCoach(role: CoachRole, ovr: Int, yearsExperience: Int) -> Int {
        var rng = SystemRandomNumberGenerator()
        return salaryForCoach(role: role, ovr: ovr, yearsExperience: yearsExperience, using: &rng)
    }

    /// Seeded variant of `salaryForCoach`.
    ///
    /// The ±5 % noise term used to draw from the system generator even when the
    /// caller had passed a seeded one, which made a template import produce a
    /// different coach salary on every run — caught by
    /// `LeagueTemplateValidation`'s determinism check (505/512 staff slots
    /// differed on `salary` alone). Every generation path now threads its own
    /// generator all the way down.
    static func salaryForCoach<G: RandomNumberGenerator>(
        role: CoachRole, ovr: Int, yearsExperience: Int, using rng: inout G
    ) -> Int {
        let range = role.salaryRange
        let spread = range.max - range.min

        // OVR drives most of the salary: map 30-90 OVR onto 0.0-1.0
        let ovrFraction = Double(min(max(ovr, 30), 90) - 30) / 60.0

        // Experience bonus: up to 10% of spread for 25+ years
        let expFraction = min(Double(yearsExperience) / 25.0, 1.0) * 0.10

        // Power curve: lower-OVR coaches get a steeper discount so the visible
        // salary spread widens. OVR ~70 maps to ~50% of spread (vs ~67% linear)
        // while OVR 85+ still hits near max.
        let curvedOvrFraction = pow(ovrFraction, 1.6)

        let rawSalary = Double(range.min) + Double(spread) * (curvedOvrFraction * 0.90 + expFraction)

        // Add +-5% noise so coaches with identical OVR don't all cost the same
        let noise = rawSalary * Double.random(in: -0.05...0.05, using: &rng)
        let final = Int((rawSalary + noise).rounded())

        return min(range.max, max(range.min, final))
    }

    // MARK: - Realistic Salary (Bug Fix #5; rewritten task #87 / F1)

    /// Opening payroll a generated roster is normalised onto, in thousands —
    /// 80-95 % of ``ContractEngine/openingSalaryCap``. `LeagueTemplateImporter`
    /// draws from this same band (on its own seed stream) for the fixed league.
    static let rosterCapTargetBand: ClosedRange<Int> = (ContractEngine.openingSalaryCap * 80 / 100)...(ContractEngine.openingSalaryCap * 95 / 100)

    /// How long a rookie contract runs, in league years. Every drafted player is
    /// on a slotted deal for this long, which is why `yearsPro` alone identifies
    /// the cheapest population on a roster.
    static let rookieDealYears = 4

    /// OVR a player gains per season while he is still short of his position's
    /// peak window, and loses per season once he is past it.
    ///
    /// Deliberately coarse — these exist to make the SHAPE of a real cap sheet
    /// fall out of the seeder rather than to model development (the development
    /// stack does that, and the `career` harness measures it at −1 to −2 OVR/yr
    /// past peak). A rising 26-year-old is legitimately underpaid on the deal he
    /// signed at 23; a declining 34-year-old is legitimately overpaid on the one
    /// he signed at 31.
    static let preePeakOverallGain = 1.6
    static let postPeakOverallLoss = 1.4

    /// The rating at which a club stops letting a young player run out his rookie
    /// deal and pays him early. Set at the `marketBasePercent` shoulder where a
    /// contract starts resetting a market rather than filling a slot: 82 is
    /// comfortably inside the league's top 12 % and below the 85 the audit and
    /// `HoldoutEngine` both use for "star", so the men who arrive at year four
    /// still on rookie money are the ones a club genuinely hesitated over.
    static let earlyExtensionOverall = 82

    /// Returns a salary in thousands for a rostered player, seeded from what he
    /// was worth **when his current deal was signed**.
    ///
    /// ## What this replaced, and why it had to go (task #87 / F1)
    ///
    /// The old seeder took `position`, `yearsPro` and `depthIndex` — and nothing
    /// else. **It never looked at `overall`.** A 96-OVR starter and a 62-OVR
    /// starter at the same position drew their pay from the same uniform band,
    /// and the whole roster was then scaled onto a cap target, so what a league
    /// actually shipped was a payroll with the right TOTAL and no relationship
    /// at all between a man's ability and his salary.
    ///
    /// Measured on the shipped 2026 template (1 807 players) that produced:
    ///
    /// | metric | value |
    /// |---|---|
    /// | league-wide salary ÷ market | **0.725** |
    /// | 85+ OVR cohort, mean salary ÷ market | **0.666** |
    /// | players under `HoldoutEngine.subMarketThreshold` (0.85×) | **68.1 %** |
    /// | players under `TradeValueEngine`'s bargain line (0.70×) | **60.8 %** |
    ///
    /// Two thirds of the league was a holdout candidate on the morning of season
    /// one, three fifths carried a permanent trade-value premium, and because
    /// `realisticContractYears` gives veterans 1-2 years remaining, roughly half
    /// the highly-paid starter population reached free agency after season one
    /// and re-priced from 0.67× market to 1.0-1.6× — doubling star payroll at
    /// every position outside QB/LT/CB inside two league years, against 5-8 %
    /// cap growth.
    ///
    /// ## What it does now
    ///
    /// One idea: **a man mid-contract is paid what he was worth when he signed,
    /// not what he is worth today.** That is the whole reason a real cap sheet is
    /// full of players below their current ask without any of them being a
    /// grievance — and it is a rating-aware, tenure-aware discount that falls out
    /// of the market model instead of sitting beside it.
    ///
    /// So the deal is priced against the league of `dealAge` seasons ago:
    ///
    /// * **a smaller cap** — the engine rolls the cap forward 5-8 % a league year
    ///   (``ContractEngine/capGrowthRange``), so a three-year-old deal was
    ///   negotiated against a money supply ~18 % smaller;
    /// * **a different player** — pre-peak he was worse than he is now (and is
    ///   therefore underpaid today), past peak he was better (and is therefore
    ///   overpaid today);
    /// * **a different kind of deal** — a rookie contract is slotted, not
    ///   negotiated, and comes in far under market; a veteran starter's was
    ///   negotiated at roughly that year's market; a depth man's is a one-year
    ///   deal at or near the minimum.
    ///
    /// `generateRoster` / `LeagueTemplateImporter.normalizeRosterSalaries` then
    /// scale the finished roster onto its cap target exactly as before, so
    /// aggregate payroll still lands at 80-95 % of the cap. The normalization is
    /// a LEVEL; everything above is the SHAPE, and the shape is what was missing.
    private static func realisticSalary(
        for position: Position,
        overall: Int,
        age: Int,
        yearsPro: Int,
        depthIndex: Int,
        salaryCap: Int
    ) -> Int {
        var rng = SystemRandomNumberGenerator()
        return realisticSalary(
            for: position, overall: overall, age: age, yearsPro: yearsPro,
            depthIndex: depthIndex, salaryCap: salaryCap, using: &rng
        )
    }

    /// Seeded variant — the fixed-league template import prices every contract
    /// through this exact function, deterministically.
    static func realisticSalary<G: RandomNumberGenerator>(
        for position: Position,
        overall: Int,
        age: Int,
        yearsPro: Int,
        depthIndex: Int,
        salaryCap: Int,
        using rng: inout G
    ) -> Int {
        // Clubs extend their best young players BEFORE the rookie deal runs out.
        // That is not a nicety — it is the single most consequential fact about a
        // real cap sheet, and leaving it out is what produced a day-one league in
        // which two fifths of the 85+ cohort was a holdout candidate purely
        // because a 25-year-old star was still being priced off the rookie scale
        // he signed at 21. A man who plays out a whole rookie contract at that
        // level is the exception; the rule is the extension in year three.
        let extendedEarly = overall >= earlyExtensionOverall && yearsPro >= 3
        let onRookieScale = yearsPro <= rookieDealYears && !extendedEarly

        // How long ago the deal was written. A man still on his rookie contract
        // signed it the day he was drafted — that is not a draw, it is his
        // tenure. An early extension was written in year three. Everyone else
        // re-signed at some point in the last few years.
        let dealAge: Int
        if onRookieScale {
            dealAge = yearsPro
        } else if yearsPro <= rookieDealYears {
            dealAge = max(0, yearsPro - 3)
        } else {
            dealAge = Int.random(in: 0...3, using: &rng)
        }

        // The cap it was written against.
        let capThen = max(
            1_000,
            Int(Double(salaryCap) / pow(1.0 + ContractEngine.capGrowthPerSeason, Double(dealAge)))
        )
        // ...and the player it was written for.
        let overallThen = min(99, max(40, overall - overallDrift(
            position: position, age: age, years: dealAge
        )))
        let ageThen = max(21, age - dealAge)

        let marketThen = ContractEngine.estimateMarketValue(
            overall: overallThen, position: position, age: ageThen, salaryCap: capThen
        )

        // What KIND of deal it is.
        let band: ClosedRange<Double>
        if onRookieScale {
            // Slotted rookie scale — the discount that makes an NFL roster
            // affordable at all (DEVELOPMENT_NFL_REFERENCE §8). The spread is
            // draft position standing in for itself: a first-rounder is paid
            // roughly what he was worth as a rookie, a day-three pick a fraction
            // of it. Note this multiplies his ROOKIE-YEAR market against the
            // ROOKIE-YEAR cap, so the discount against TODAY's ask is far
            // steeper than the band alone suggests.
            band = 0.40...0.78
        } else if depthIndex >= 2 {
            // Roster filler on one-year veteran deals at or near the minimum.
            band = 0.50...0.85
        } else {
            // Negotiated at that year's market, with the usual spread between a
            // club that had leverage and one that did not.
            band = 0.86...1.12
        }

        let salary = Double(marketThen) * Double.random(in: band, using: &rng)
        return max(750, Int(salary.rounded()))
    }

    /// Net OVR a player of this position gained over the last `years` seasons —
    /// positive before his peak window, negative after it. See
    /// ``preePeakOverallGain`` for why it is this coarse.
    static func overallDrift(position: Position, age: Int, years: Int) -> Int {
        guard years > 0 else { return 0 }
        let peak = position.peakAgeRange
        var drift = 0.0
        for step in 0..<years {
            // The age he was going INTO that season.
            let then = age - step - 1
            if then < peak.lowerBound {
                drift += preePeakOverallGain
            } else if then > peak.upperBound {
                drift -= postPeakOverallLoss
            }
        }
        return Int(drift.rounded())
    }

    // MARK: - Realistic Contract Years (Bug Fix #6)

    /// Returns contract years remaining based on career stage.
    /// - Veteran stars (7+ years): 1-2 years (expiring = interesting decisions)
    /// - Mid-career (3-6 years pro): 2-4 years
    /// - Young players on rookie deals (0-2 years pro): 3-4 years
    private static func realisticContractYears(yearsPro: Int, age: Int) -> Int {
        var rng = SystemRandomNumberGenerator()
        return realisticContractYears(yearsPro: yearsPro, age: age, using: &rng)
    }

    /// Seeded variant of `realisticContractYears`.
    static func realisticContractYears<G: RandomNumberGenerator>(
        yearsPro: Int, age: Int, using rng: inout G
    ) -> Int {
        if yearsPro <= 2 {
            // Young players on rookie deals
            return Int.random(in: 3...4, using: &rng)
        } else if yearsPro <= 6 {
            // Mid-career players
            return Int.random(in: 2...4, using: &rng)
        } else {
            // Veteran stars — expiring contracts create drama
            return Int.random(in: 1...2, using: &rng)
        }
    }

    // MARK: - Player Familiarity Initialization

    /// Sets initial position and scheme familiarity for generated players.
    private static func initializePlayerFamiliarity(players: [Player], coaches: [Coach]) {
        var rng = SystemRandomNumberGenerator()
        initializePlayerFamiliarity(players: players, coaches: coaches, using: &rng)
    }

    /// Seeded variant of `initializePlayerFamiliarity` — the fixed-league
    /// template import runs the exact same rules through its own generator.
    static func initializePlayerFamiliarity<G: RandomNumberGenerator>(
        players: [Player], coaches: [Coach], using rng: inout G
    ) {
        let oc = coaches.first { $0.role == .offensiveCoordinator }
        let dc = coaches.first { $0.role == .defensiveCoordinator }

        for player in players {
            // Primary position always 100
            player.positionFamiliarity[player.position.rawValue] = 100

            // Veterans get some secondary position familiarity
            if player.yearsPro >= 3 {
                let viablePositions = VersatilityEngine.viablePositions(for: player)
                for (pos, rating) in viablePositions where rating >= .unconvincing && pos != player.position {
                    let maxFam = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: pos)
                    let startFam = Int.random(in: 10...min(maxFam, 20 + player.yearsPro * 5), using: &rng)
                    player.positionFamiliarity[pos.rawValue] = startFam
                }
            }

            // Scheme familiarity with the system this building actually installs.
            //
            // **Tenure-aware since task #66.** This used to be a flat
            // `55...85` for everybody, which handed a first-year player the same
            // command of the playbook as a nine-year starter and put the t=0
            // league mean at 70 — 9 points above the steady state the
            // development stack actually runs to. That gap is why a save's
            // scheme fit visibly SLID for its first decade: the generator seeded
            // a league that had to decay into equilibrium instead of one that
            // started there. The ladder below is the measured equilibrium
            // trajectory from `tools/balance-harness`'s `career` scenario
            // (20 leagues × 22 measured seasons; see its SCHEME FIT block).
            //
            // **Draw ONLY where the value is used.** `Position.side` is
            // `.specialTeams` for K and P, so a kicker has no installed system
            // to be familiar with and consumes no draw — exactly as the flat
            // `55...85` it replaced did. Hoisting the draw out of the branches
            // would be harmless in the `SystemRandomNumberGenerator` path and a
            // determinism break in the SEEDED one (the fixed-league template
            // import): every player generated after the roster's first
            // specialist would read a different stream position, which moves
            // secondary-position familiarity and all of
            // `assignCareerSchemeFamiliarity` for the rest of the club.
            switch player.position.side {
            case .offense:
                if let offScheme = oc?.offensiveScheme {
                    player.schemeFamiliarity[offScheme.rawValue] =
                        activeSchemeSeed(yearsPro: player.yearsPro, using: &rng)
                }
            case .defense:
                if let defScheme = dc?.defensiveScheme {
                    player.schemeFamiliarity[defScheme.rawValue] =
                        activeSchemeSeed(yearsPro: player.yearsPro, using: &rng)
                }
            case .specialTeams:
                break
            }

            // Baseline scheme familiarity from career history (based on yearsPro).
            // Veterans have played in multiple schemes over their careers, so they
            // should have non-zero familiarity in several schemes — not just the
            // current team's scheme.
            assignCareerSchemeFamiliarity(player: player, using: &rng)
        }
    }

    /// Day-one familiarity with the system this player's own building installs,
    /// as a function of how long he has been a pro (task #66).
    ///
    /// The curve is the measured equilibrium ladder, fitted to three digits:
    ///
    ///     centre(yearsPro) = 78 − 34 · 0.78^yearsPro
    ///
    /// | yearsPro | 0  | 1  | 2  | 3  | 4  | 6  | 8  | 10 |
    /// |----------|----|----|----|----|----|----|----|----|
    /// | harness  | 44 | 52 | 57 | 61 | 64 | 69 | 73 | 75 |
    /// | curve    | 44 | 51 | 57 | 62 | 65 | 70 | 73 | 75 |
    ///
    /// The asymptote is 78 rather than 100 because turnover never stops: a
    /// ten-year veteran in the shipped league has been through coordinators, and
    /// `VersatilityDevelopmentEngine.installBaseline` caps what a fresh install
    /// gives him at 50. The ±16 band is the WITHIN-tenure spread (the old flat
    /// draw's ±15, kept, so this change moves the centre and not the variance).
    ///
    /// Note where this lands relative to `PlaySimulator`'s 55 blown-assignment
    /// pivot: a rookie is under it, a third-year starter is over it. That is the
    /// mechanic doing its job on day one of a new save instead of on season ten.
    static func activeSchemeSeed<G: RandomNumberGenerator>(
        yearsPro: Int, using rng: inout G
    ) -> Int {
        let centre = 78.0 - 34.0 * pow(0.78, Double(max(0, min(yearsPro, 15))))
        let lo = max(10, Int((centre - 16).rounded()))
        let hi = min(95, Int((centre + 16).rounded()))
        guard lo < hi else { return lo }
        return Int.random(in: lo...hi, using: &rng)
    }

    /// Assigns baseline scheme familiarity to a player based on their career history.
    /// More veteran players have exposure to a wider variety of schemes from previous
    /// teams, position groups, and college experience. The "expert" scheme represents
    /// the system they spent the most time in. Existing values (e.g. set by the team's
    /// current coordinator above) are preserved if they are higher than the career
    /// baseline assignment.
    private static func assignCareerSchemeFamiliarity<G: RandomNumberGenerator>(
        player: Player, using rng: inout G
    ) {
        // Determine the appropriate scheme pool based on position side.
        // Offense and defense players generally only learn schemes for their side;
        // special teams (K/P) and FB are exposed to either, so we pick from both.
        let schemes: [String]
        switch player.position {
        case .QB, .RB, .WR, .TE, .LT, .LG, .C, .RG, .RT:
            schemes = OffensiveScheme.allCases.map { $0.rawValue }
        case .DE, .DT, .OLB, .MLB, .CB, .FS, .SS:
            schemes = DefensiveScheme.allCases.map { $0.rawValue }
        case .K, .P, .FB:
            schemes = OffensiveScheme.allCases.map { $0.rawValue }
                + DefensiveScheme.allCases.map { $0.rawValue }
        }

        // Tier definitions: (numSecondary, secondaryRange, expertRange, weakRange?)
        // Each tier produces a list of (schemeName, familiarityValue) assignments.
        let assignments: [(scheme: String, value: Int)]

        switch player.yearsPro {
        case 0...2:
            // Rookies / sophomores: 1 scheme at 30-50%, others 0%.
            // (College + brief NFL exposure to a single system.)
            guard let primary = schemes.randomElement(using: &rng) else { return }
            assignments = [(primary, Int.random(in: 30...50, using: &rng))]

        case 3...5:
            // Developing veterans: 2 schemes at 30-60%, 1 expert at 60-80%.
            var pool = schemes.shuffled(using: &rng)
            guard pool.count >= 3 else {
                assignments = pool.map { ($0, Int.random(in: 30...60, using: &rng)) }
                applyAssignments(assignments, to: player)
                return
            }
            let expert = pool.removeFirst()
            let secondary1 = pool.removeFirst()
            let secondary2 = pool.removeFirst()
            assignments = [
                (expert, Int.random(in: 60...80, using: &rng)),
                (secondary1, Int.random(in: 30...60, using: &rng)),
                (secondary2, Int.random(in: 30...60, using: &rng))
            ]

        case 6...9:
            // Established veterans: 1 expert at 70-90%, 2 secondaries at 50-75%,
            // 1 weak/older exposure at 20-40%.
            var pool = schemes.shuffled(using: &rng)
            guard pool.count >= 4 else {
                assignments = pool.map { ($0, Int.random(in: 50...75, using: &rng)) }
                applyAssignments(assignments, to: player)
                return
            }
            let expert = pool.removeFirst()
            let secondary1 = pool.removeFirst()
            let secondary2 = pool.removeFirst()
            let weak = pool.removeFirst()
            assignments = [
                (expert, Int.random(in: 70...90, using: &rng)),
                (secondary1, Int.random(in: 50...75, using: &rng)),
                (secondary2, Int.random(in: 50...75, using: &rng)),
                (weak, Int.random(in: 20...40, using: &rng))
            ]

        default:
            // Long veterans (10+): 1 expert at 80-95%, 3-4 secondaries at 50-80%.
            var pool = schemes.shuffled(using: &rng)
            let secondaryCount = min(Int.random(in: 3...4, using: &rng), max(0, pool.count - 1))
            guard !pool.isEmpty else { return }
            let expert = pool.removeFirst()
            var built: [(String, Int)] = [(expert, Int.random(in: 80...95, using: &rng))]
            for _ in 0..<secondaryCount {
                guard !pool.isEmpty else { break }
                built.append((pool.removeFirst(), Int.random(in: 50...80, using: &rng)))
            }
            assignments = built
        }

        applyAssignments(assignments, to: player)
    }

    /// Applies a list of scheme/value assignments to the player. Only overwrites
    /// existing entries when the new value is higher, so the team's current-scheme
    /// boost from the coordinator pass is preserved.
    private static func applyAssignments(_ assignments: [(scheme: String, value: Int)], to player: Player) {
        for (scheme, value) in assignments {
            let existing = player.schemeFamiliarity[scheme] ?? 0
            if value > existing {
                player.schemeFamiliarity[scheme] = value
            }
        }
    }

    // MARK: - Coach Scheme Expertise Initialization

    /// Sets initial scheme expertise for generated coaches.
    private static func initializeSchemeExpertise(for coaches: [Coach]) {
        var rng = SystemRandomNumberGenerator()
        initializeSchemeExpertise(for: coaches, using: &rng)
    }

    /// Seeded variant of `initializeSchemeExpertise` — the template import uses
    /// these EXACT veteran-coach rules (primary 75-95, family 40-65, an
    /// adaptability-scaled baseline everywhere else).
    static func initializeSchemeExpertise<G: RandomNumberGenerator>(
        for coaches: [Coach], using rng: inout G
    ) {
        for coach in coaches {
            var expertise: [String: Int] = [:]

            // Primary offensive scheme: high expertise
            if let offScheme = coach.offensiveScheme {
                expertise[offScheme.rawValue] = Int.random(in: 75...95, using: &rng)
                for related in schemeFamilyMembers(offScheme) where related != offScheme {
                    expertise[related.rawValue] = Int.random(in: 40...65, using: &rng)
                }
            }

            // Primary defensive scheme: high expertise
            if let defScheme = coach.defensiveScheme {
                expertise[defScheme.rawValue] = Int.random(in: 75...95, using: &rng)
                for related in schemeFamilyMembers(defScheme) where related != defScheme {
                    expertise[related.rawValue] = Int.random(in: 40...65, using: &rng)
                }
            }

            // Adaptability gives higher baseline for unknown schemes
            let baselineBonus = Int(Double(coach.adaptability) / 99.0 * 15.0)
            for scheme in OffensiveScheme.allCases where expertise[scheme.rawValue] == nil {
                expertise[scheme.rawValue] = 15 + baselineBonus + Int.random(in: 0...10, using: &rng)
            }
            for scheme in DefensiveScheme.allCases where expertise[scheme.rawValue] == nil {
                expertise[scheme.rawValue] = 15 + baselineBonus + Int.random(in: 0...10, using: &rng)
            }

            coach.schemeExpertise = expertise
        }
    }

    /// Returns schemes in the same "family" as the given offensive scheme.
    private static func schemeFamilyMembers(_ scheme: OffensiveScheme) -> [OffensiveScheme] {
        switch scheme {
        case .westCoast, .airRaid, .proPassing, .spread:
            return [.westCoast, .airRaid, .proPassing, .spread]
        case .powerRun, .shanahan, .option, .rpo:
            return [.powerRun, .shanahan, .option, .rpo]
        }
    }

    /// Returns schemes in the same "family" as the given defensive scheme.
    private static func schemeFamilyMembers(_ scheme: DefensiveScheme) -> [DefensiveScheme] {
        switch scheme {
        case .pressMan, .base43:
            return [.pressMan, .base43]
        case .cover3, .tampa2, .base34:
            return [.cover3, .tampa2, .base34]
        case .multiple, .hybrid:
            return [.multiple, .hybrid]
        }
    }

    /// Position-attribute range based on depth tier.
    /// Starters (0): 66-88, Backups (1): 57-79, Deep depth (2+): 47-69 —
    /// shifted by `ageLevelShift` + `talentLevelShift` at the draw site.
    ///
    /// **P1 pyramid calibration (2026-07-30)**: was 75-95 / 60-80 / 50-70. Two
    /// separate problems, both visible in `targetQualityPyramid`'s table:
    ///
    ///  * **Level.** These are 50 % of `overall`, so their midpoints set the
    ///    league's level more than anything else does. The old midpoints
    ///    (85/70/60) plus a +11 prime age level put the average STARTER at 83.5
    ///    in a league §8 wants to average ~72.
    ///  * **A truncated top.** 95 + an 11-point prime shift is 106, clamped to
    ///    99, so a prime-age starter drew position skills from a range whose top
    ///    half did not exist. The league's maximum rating was 93 — the generator
    ///    could not make a 96-OVR superstar at all, which is the other half of
    ///    why the 90+ band was simultaneously too crowded (3.3 %) and too flat.
    ///    Lowering the range so `hi + shift` lands near 99 for a genuine star,
    ///    rather than for every starter, restores the tail: the range is now
    ///    36..98 instead of 53..93.
    static func positionAttributeRange(forDepth depthIndex: Int) -> ClosedRange<Int> {
        switch depthIndex {
        case 0:  return 66...88
        case 1:  return 57...79
        default: return 47...69
        }
    }

    /// Returns a single random attribute value within the depth tier's range,
    /// moved by the player's `ageLevelShift` (plan §5 stage 6) and clamped to
    /// the legal 1-99 rating scale.
    private static func rndAttr(_ depthIndex: Int, _ shift: Int = 0) -> Int {
        let base = positionAttributeRange(forDepth: depthIndex)
        let low = min(99, max(1, base.lowerBound + shift))
        let high = min(99, max(low, base.upperBound + shift))
        return Int.random(in: low...high)
    }

    private static func randomPositionAttributes(
        for position: Position,
        depthIndex: Int,
        ageShift: Int
    ) -> PositionAttributes {
        switch position {
        case .QB:
            return .quarterback(QBAttributes(
                armStrength: rndAttr(depthIndex, ageShift),
                accuracyShort: rndAttr(depthIndex, ageShift),
                accuracyMid: rndAttr(depthIndex, ageShift),
                accuracyDeep: rndAttr(depthIndex, ageShift),
                pocketPresence: rndAttr(depthIndex, ageShift),
                scrambling: rndAttr(depthIndex, ageShift)
            ))

        case .WR:
            return .wideReceiver(WRAttributes(
                routeRunning: rndAttr(depthIndex, ageShift),
                catching: rndAttr(depthIndex, ageShift),
                release: rndAttr(depthIndex, ageShift),
                spectacularCatch: rndAttr(depthIndex, ageShift)
            ))

        case .RB, .FB:
            return .runningBack(RBAttributes(
                vision: rndAttr(depthIndex, ageShift),
                elusiveness: rndAttr(depthIndex, ageShift),
                breakTackle: rndAttr(depthIndex, ageShift),
                receiving: rndAttr(depthIndex, ageShift)
            ))

        case .TE:
            return .tightEnd(TEAttributes(
                blocking: rndAttr(depthIndex, ageShift),
                catching: rndAttr(depthIndex, ageShift),
                routeRunning: rndAttr(depthIndex, ageShift),
                speed: rndAttr(depthIndex, ageShift)
            ))

        case .LT, .LG, .C, .RG, .RT:
            return .offensiveLine(OLAttributes(
                runBlock: rndAttr(depthIndex, ageShift),
                passBlock: rndAttr(depthIndex, ageShift),
                pull: rndAttr(depthIndex, ageShift),
                anchor: rndAttr(depthIndex, ageShift)
            ))

        case .DE, .DT:
            return .defensiveLine(DLAttributes(
                passRush: rndAttr(depthIndex, ageShift),
                blockShedding: rndAttr(depthIndex, ageShift),
                powerMoves: rndAttr(depthIndex, ageShift),
                finesseMoves: rndAttr(depthIndex, ageShift)
            ))

        case .OLB, .MLB:
            return .linebacker(LBAttributes(
                tackling: rndAttr(depthIndex, ageShift),
                zoneCoverage: rndAttr(depthIndex, ageShift),
                manCoverage: rndAttr(depthIndex, ageShift),
                blitzing: rndAttr(depthIndex, ageShift)
            ))

        case .CB, .FS, .SS:
            return .defensiveBack(DBAttributes(
                manCoverage: rndAttr(depthIndex, ageShift),
                zoneCoverage: rndAttr(depthIndex, ageShift),
                press: rndAttr(depthIndex, ageShift),
                ballSkills: rndAttr(depthIndex, ageShift)
            ))

        case .K, .P:
            return .kicking(KickingAttributes(
                kickPower: rndAttr(depthIndex, ageShift),
                kickAccuracy: rndAttr(depthIndex, ageShift)
            ))
        }
    }

    /// Generates QB position attributes whose average is approximately the target overall,
    /// so a "84 OVR" franchise QB has accuracy/arm strength values consistent with that rating.
    private static func qbPositionAttributesForTarget(target: Int) -> PositionAttributes {
        let values = attributesForTarget(target: target, count: 6, variance: 6)
        return .quarterback(QBAttributes(
            armStrength: values[0],
            accuracyShort: values[1],
            accuracyMid: values[2],
            accuracyDeep: values[3],
            pocketPresence: values[4],
            scrambling: values[5]
        ))
    }
}
