import Foundation

// MARK: - Importer

/// Turns a baked `LeagueTemplate` into the game's SwiftData graph.
///
/// ## The determinism contract
///
/// Every random decision is driven by a `SeededLeagueRandom` whose seed is
/// `template.globalSeed &+ <stable entity id>`:
///
/// | Entity | Seed |
/// |---|---|
/// | Player | `globalSeed + UInt64(player.id hex)` |
/// | Team-level (owner) | `globalSeed + fnv1a(teamKey)` |
/// | Team cap sheet | `globalSeed + fnv1a("teamKey|cap")` |
/// | Scheme expertise / familiarity | `globalSeed + fnv1a("teamKey|staff")` |
/// | Coach | `globalSeed + fnv1a("teamKey|CoachRole")` |
/// | Career statline (per season) | `globalSeed + player.id + statSeedOffset + year` |
///
/// Nothing reads `SystemRandomNumberGenerator`, `Int.random(in:)` or
/// `Date()`, and no seed depends on iteration order, so **two imports of the
/// same template file produce byte-identical leagues** — the "fixed constant
/// league" requirement from `docs/REALISTIC_LEAGUE_PLAN.md` §6.
///
/// ## The attribute solve
///
/// A template row carries a `ratingTarget` (the OVR the transform calibrated
/// this player to) and mean-zero `areaHints`, not attributes.
/// `TemplateAttributeSolver` reconstructs the grid with the game's OWN
/// machinery; this importer supplies its inputs:
///
/// 1. It computes the level the *random* generator would use for this player's
///    depth tier and age — `LeagueGenerator.veteranLevelShift` +
///    `LeagueGenerator.ageLevelShift` — so a template player's physical /
///    mental / position-skill split matches a generated player's at the same
///    tier and age. This is what keeps the calibration decision honest: the
///    template league sits exactly where the random league sits.
/// 2. It bisects one extra uniform level offset `d` on top of that (the
///    player's individual ability) until `Player.overall` lands on
///    `ratingTarget`. Physicals come from `PositionPhysicalProfile.sample`,
///    mentals from `sampleMental`, position skills from the tier band plus the
///    row's `areaHints`.
/// 3. A final ±1 round-robin closes the last rounding point exactly.
///
/// Because the draw is a pure function of `(seed, d)`, the bisection is
/// deterministic too.
enum LeagueTemplateImporter {

    // MARK: - Result

    /// Everything one template import produces.
    ///
    /// A superset of `LeagueGenerator.GeneratedLeague`: the template path also
    /// materialises career history from the baked arcs (the random path builds
    /// its own via `LeagueGenerator.syntheticCareerHistory`).
    struct ImportedLeague {
        let league: League
        let teams: [Team]
        let players: [Player]
        let owners: [Owner]
        let coaches: [Coach]
        let draftPicks: [DraftPick]
        /// `PlayerSeasonHistory` rows built from every player's `careerArc`.
        /// Insert these alongside the rest of the graph.
        let seasonHistory: [PlayerSeasonHistory]
        /// Which profile this league came from.
        let profile: LeagueTemplate.Profile

        /// The subset the existing career-creation flow already knows how to
        /// insert, so a call site can reuse `finalizeCareer` unchanged and
        /// insert `seasonHistory` separately.
        var generated: LeagueGenerator.GeneratedLeague {
            (league, teams, players, owners, coaches, draftPicks)
        }
    }

    // MARK: - Entry point

    /// Builds the full league graph from `template`.
    ///
    /// - Parameters:
    ///   - template: A decoded template (see `LeagueTemplateLoader`).
    ///   - startYear: Season the career opens on. Defaults to the template's own
    ///     `leagueYear` (2026) — the season AFTER the snapshot's records.
    static func build(from template: LeagueTemplate, startYear: Int? = nil) -> ImportedLeague {
        let season = startYear ?? template.leagueYear
        let seed = template.globalSeed
        let namePool = SupportStaffNamePool(template: template)

        // Team key ("LA") → the Team we create for it, so pick provenance and
        // career-arc team references can be resolved after the fact.
        var teamsByKey: [String: Team] = [:]

        var allTeams: [Team] = []
        var allPlayers: [Player] = []
        var allOwners: [Owner] = []
        var allCoaches: [Coach] = []
        var allHistory: [PlayerSeasonHistory] = []
        /// AI owner portraits already handed out in this league — see
        /// `ExtrasCatalog.ownerFaceID`. Mirrors `LeagueGenerator.generate`.
        var takenOwnerFaceIDs: Set<String> = []
        // Career rows still waiting on the complete key → Team map. `seed` is the
        // player's own entity seed, carried through so the stat synthesizer can
        // open a deterministic sub-stream on it (the arcs are built after the
        // roster loop, where the seed is otherwise out of scope).
        var pendingHistory: [(
            player: Player,
            arcs: [LeagueTemplate.ArcRow],
            statLines: [LeagueTemplate.StatLine]?,
            seed: UInt64
        )] = []

        for teamTemplate in template.teams {
            let identity = teamTemplate.identity
            let appAbbr = identity.appAbbr
            let definition = LeagueTeamData.allTeams.first { $0.abbreviation == appAbbr }
            var teamRNG = SeededLeagueRandom(seed: seed &+ fnv1a(identity.key))

            // `ownerGender` is present in both profiles and SUPPRESSES the gender
            // draw, which is the whole point: the draw would consume a seeded
            // value and move every owner attribute after it (see the coupling
            // note in `generateOwner`). It still steers the name pool, the
            // illustrated avatar and the AI portrait, none of which cost an extra
            // draw. A template baked before the field reads as nil → male, which
            // is what those files' owners always were.
            let owner = LeagueGenerator.generateOwner(
                mediaMarket: definition?.mediaMarket ?? .medium,
                teamAbbreviation: appAbbr,
                genderOverride: identity.ownerGender,
                using: &teamRNG,
                takenFaceIDs: takenOwnerFaceIDs
            )
            if let ownerFaceID = owner.faceID { takenOwnerFaceIDs.insert(ownerFaceID) }
            // A template may name its own owner (the dev profile carries the real
            // 2026 principal owners). The draw above still runs and still consumes
            // the same RNG values, so only the label changes — patience, spending,
            // meddling and the avatar stay the template's deterministic ones. The
            // publish file carries no `ownerName`, so it keeps the fictional name.
            if let ownerName = identity.ownerName, !ownerName.isEmpty {
                owner.name = ownerName
            }
            allOwners.append(owner)

            let team = Team(
                name: identity.nickname,
                city: identity.city,
                abbreviation: appAbbr,
                conference: Conference(rawValue: teamTemplate.conference) ?? definition?.conference ?? .AFC,
                division: Division(rawValue: teamTemplate.division) ?? definition?.division ?? .east,
                mediaMarket: definition?.mediaMarket ?? .medium,
                owner: owner
            )
            // 2025 record — feeds the phase-2 "team collapsed last season"
            // motivation triggers league-wide (`Team.lastSeasonWins`).
            team.lastSeasonWins = teamTemplate.record2025.wins
            team.lastSeasonLosses = teamTemplate.record2025.losses

            // --- Roster ---------------------------------------------------
            var roster: [Player] = []
            for playerTemplate in teamTemplate.players {
                guard let position = Position(rawValue: playerTemplate.pos) else { continue }
                let playerSeed = seed &+ entitySeed(playerTemplate.id)
                let player = makePlayer(
                    playerTemplate,
                    position: position,
                    teamID: team.id,
                    seed: playerSeed
                )
                roster.append(player)
                if let arcs = playerTemplate.careerArc, !arcs.isEmpty {
                    pendingHistory.append((player, arcs, playerTemplate.statLines, playerSeed))
                }
            }
            assignJerseyNumbers(roster)
            normalizeRosterSalaries(
                roster,
                toCapUsage: capTarget(teamKey: identity.key, globalSeed: seed)
            )
            team.players = roster
            team.currentCapUsage = roster.reduce(0) { $0 + $1.annualSalary }
            allPlayers.append(contentsOf: roster)

            // --- Staff ----------------------------------------------------
            let staff = makeStaff(
                teamTemplate,
                teamID: team.id,
                season: season,
                globalSeed: seed,
                namePool: namePool
            )
            allCoaches.append(contentsOf: staff)

            var staffRNG = SeededLeagueRandom(seed: seed &+ fnv1a(identity.key + "|staff"))
            LeagueGenerator.initializeSchemeExpertise(for: staff, using: &staffRNG)
            LeagueGenerator.initializePlayerFamiliarity(
                players: roster, coaches: staff, using: &staffRNG
            )

            teamsByKey[identity.key] = team
            allTeams.append(team)
        }

        // --- Career history (needs the key → Team map) --------------------
        for entry in pendingHistory {
            allHistory.append(contentsOf: seasonHistory(
                for: entry.player,
                arcs: entry.arcs,
                statLines: entry.statLines,
                playerSeed: entry.seed,
                snapshotYear: season - 1,
                teamsByKey: teamsByKey
            ))
        }

        // --- 2026 picks, trades included ----------------------------------
        // Plus three years of future picks. They are NOT in the template file
        // (nothing about the import changes) and carry no RNG draw, so the
        // determinism gate is unaffected — see `LeagueGenerator.futureDraftPicks`.
        let picks = draftPicks(
            template: template, season: season, teamsByKey: teamsByKey
        ) + LeagueGenerator.futureDraftPicks(teams: allTeams, afterSeason: season)

        let league = League(teams: allTeams, currentSeason: season)

        return ImportedLeague(
            league: league,
            teams: allTeams,
            players: allPlayers,
            owners: allOwners,
            coaches: allCoaches,
            draftPicks: picks,
            seasonHistory: allHistory,
            profile: template.profile
        )
    }

    // MARK: - Players

    /// Sub-stream offsets. Attributes, personality/mental-software and the
    /// contract each run on their own generator derived from the player's seed,
    /// so re-drawing the attribute solve (the bisection re-runs `draw` 27 times)
    /// can never shift a player's personality or salary.
    private static let traitSeedOffset: UInt64 = 0x7A17_5000_0000_0001
    private static let contractSeedOffset: UInt64 = 0xC0_7AC0_0000_0002
    /// Career stat synthesis. Its own stream so re-tuning the stat model can
    /// never shift a player's attributes, personality, salary or face.
    private static let statSeedOffset: UInt64 = 0x57A7_5000_0000_0003

    private static func makePlayer(
        _ template: LeagueTemplate.PlayerTemplate,
        position: Position,
        teamID: UUID,
        seed: UInt64
    ) -> Player {
        let depthIndex = template.depthIndex
        let ageShift = Double(Int(LeagueGenerator.ageLevelShift(age: template.age, position: position).rounded()))
        let tierShift = LeagueGenerator.veteranLevelShift(depthIndex: depthIndex)
        let band = LeagueGenerator.positionAttributeRange(forDepth: depthIndex)

        // The levels the RANDOM generator would use for this tier and age, so a
        // template player's physical / mental / skill split matches a generated
        // player's. The solver adds the individual ability offset on top.
        let levels = TemplateAttributeSolver.Levels(
            skill: Double(band.lowerBound + band.upperBound) / 2.0 + ageShift,
            physical: tierShift + ageShift,
            mental: PositionPhysicalProfile.baseLevel + tierShift + ageShift
        )
        let solved = TemplateAttributeSolver.solve(
            position: position,
            ratingTarget: template.ratingTarget,
            areaHints: template.areaHints ?? [:],
            levels: levels,
            seed: seed
        )

        var traitRNG = SeededLeagueRandom(seed: seed &+ traitSeedOffset)
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement(using: &traitRNG)!,
            motivation: Motivation.allCases.randomElement(using: &traitRNG)!
        )

        var contractRNG = SeededLeagueRandom(seed: seed &+ contractSeedOffset)
        // COUPLING — `make_templates.py::template_contract_years` replays THIS
        // draw to bake `template.contractYears`, so a pre-career reader (the
        // team picker) can see a club's expiring men without importing anything.
        // The draw therefore stays here even though the row now carries the
        // answer: `realisticSalary` and `initialMorale` below run on the SAME
        // sub-stream, so dropping it would re-price and re-mood every man in the
        // fixed league. Adding a draw ahead of it — here or in the mirror — makes
        // the baked number a lie, which the assert catches in DEBUG and
        // make_templates gate 20 catches at bake time.
        let drawnContractYears = LeagueGenerator.realisticContractYears(
            yearsPro: template.yearsPro, age: template.age, using: &contractRNG
        )
        assert(
            template.contractYears == nil || template.contractYears == drawnContractYears,
            "template contractYears \(String(describing: template.contractYears)) disagrees "
            + "with the importer's draw \(drawnContractYears) for \(template.name) — the "
            + "make_templates.py mirror has drifted from realisticContractYears"
        )
        let contractYears = template.contractYears ?? drawnContractYears

        let (firstName, lastName) = splitName(template)
        // Built before priced, exactly as `LeagueGenerator.generatePlayer` does
        // it — the seeder is rating-aware since task #87 (F1) and `overall` is a
        // blend only `Player` computes. Salary and morale are written back below,
        // still off `contractRNG`, so the contract sub-stream stays a pure
        // function of the player's seed.
        let player = Player(
            firstName: firstName,
            lastName: lastName,
            position: position,
            age: template.age,
            yearsPro: template.yearsPro,
            physical: solved.physical,
            mental: solved.mental,
            positionAttributes: solved.positionAttributes,
            personality: personality,
            teamID: teamID,
            contractYearsRemaining: contractYears,
            annualSalary: 750,
            // Draft provenance: round and year are real, the overall pick is the
            // profile's pick of record (fuzzed within round in publish).
            draftPickNumber: template.effectiveDraftPick,
            draftSeason: template.draftYear,
            draftRound: template.draftRound
        )
        let salary = LeagueGenerator.realisticSalary(
            for: position,
            overall: player.overall,
            age: template.age,
            yearsPro: template.yearsPro,
            depthIndex: depthIndex,
            salaryCap: ContractEngine.openingSalaryCap,
            using: &contractRNG
        )
        player.annualSalary = salary
        player.morale = LeagueGenerator.initialMorale(
            personality: personality.archetype,
            age: template.age,
            depthIndex: depthIndex,
            contractYears: contractYears,
            salary: salary,
            marketValue: ContractEngine.estimateMarketValue(
                overall: player.overall, position: position, age: template.age,
                salaryCap: ContractEngine.openingSalaryCap
            ),
            position: position,
            using: &contractRNG
        )

        // Phase-2 mental software, same models the draft class and the random
        // generator use — only the entropy source differs.
        player.learning = MentalAttributeModel.learning(
            awareness: solved.mental.awareness, level: solved.mental.average, using: &traitRNG
        )
        player.competitiveness = MentalAttributeModel.competitiveness(
            archetype: personality.archetype,
            workEthic: solved.mental.workEthic,
            clutch: solved.mental.clutch,
            using: &traitRNG
        )
        // The template's `potential` IS the phase-2 veteran rule
        // (`LeagueGenerator.veteranPotential`) already applied by the transform
        // against this exact `ratingTarget`, so it is taken verbatim rather than
        // re-rolled — that is what makes the ceiling constant across imports.
        player.truePotential = min(99, max(player.overall, template.potential))
        player.draftTruePotential = player.truePotential

        // Biography (no place for these on a randomly generated player).
        player.college = template.college
        player.heightInches = template.heightIn
        player.weightPounds = template.weightLb
        player.jerseyNumber = template.jersey

        // Phase-4 portrait. The transform pre-assigned it (unique across the
        // whole league, bucket-matched to age + position); the runtime picker
        // could not, because it hashes `player.id` — a fresh `UUID()` on every
        // import. `FaceLibrary.backfill` still runs after the import and now
        // finds these rows already served: it registers them as in-use, so the
        // support staff generated below and every later hire draw around them.
        player.faceID = template.faceID

        // #58: template veterans get a hometown too. Drawn from a DERIVED
        // sub-stream (seed ^ constant), never the main seeded stream — adding a
        // draw there would shift every attribute rolled after it and churn the
        // determinism fingerprint for no reason.
        var hometownRNG = SeededLeagueRandom(seed: seed ^ 0x48_6F_6D_65_74_6F_77_6E)
        let hometown = HometownGenerator.randomHometown(using: &hometownRNG)
        player.hometownState = hometown.state
        player.hometownCity = hometown.city

        return player
    }

    // MARK: - Jerseys

    /// Enforces one number per roster: **the first holder keeps it**, and any
    /// later duplicate is reassigned to the lowest free number in its position's
    /// legal NFL band (falling back to the lowest free number on the roster).
    ///
    /// The transform already resolves the two collisions its source data had
    /// (QA carry-in #2), so in practice this is a guard rather than a fixer —
    /// but it is the guard that makes the invariant hold for any future template.
    private static func assignJerseyNumbers(_ roster: [Player]) {
        var taken = Set<Int>()
        var unresolved: [Player] = []

        for player in roster {
            guard let number = player.jerseyNumber, (0...99).contains(number) else {
                unresolved.append(player)
                continue
            }
            if taken.contains(number) {
                unresolved.append(player)
            } else {
                taken.insert(number)
            }
        }

        for player in unresolved {
            let band = jerseyBand(for: player.position)
            let replacement = band.first { !taken.contains($0) }
                ?? (0...99).first { !taken.contains($0) }
            if let replacement {
                taken.insert(replacement)
                player.jerseyNumber = replacement
            } else {
                player.jerseyNumber = nil
            }
        }
    }

    /// Legal NFL number bands per position (2023 uniform rule), lowest first.
    private static func jerseyBand(for position: Position) -> [Int] {
        switch position {
        case .QB:                       return Array(1...19)
        case .RB, .FB, .WR, .TE:        return Array(1...49) + Array(80...89)
        case .LT, .LG, .C, .RG, .RT:    return Array(50...79)
        case .DE, .DT:                  return Array(50...79) + Array(90...99)
        case .OLB, .MLB:                return Array(1...59) + Array(90...99)
        case .CB, .FS, .SS:             return Array(1...49)
        case .K, .P:                    return Array(1...49) + Array(90...99)
        }
    }

    // MARK: - Cap sheet

    /// The cap sheet one team's roster is normalised onto, in thousands —
    /// 80-95 % of the $265M cap, the same band `LeagueGenerator.generateRoster`
    /// draws for the random league.
    ///
    /// It runs on its OWN seed stream (`globalSeed + fnv1a("<key>|cap")`) rather
    /// than off the shared team RNG so that the number is a pure function of
    /// (template, team): the new-career league browser calls this very function
    /// to show a template team's cap space **before** anything is imported, and
    /// cannot replay the team's whole random sequence to get there.
    static func capTarget(teamKey: String, globalSeed: UInt64) -> Int {
        var rng = SeededLeagueRandom(seed: globalSeed &+ fnv1a(teamKey + "|cap"))
        return Int.random(in: LeagueGenerator.rosterCapTargetBand, using: &rng)
    }

    /// Scales a roster's approximated salaries onto `capUsage` (thousands),
    /// exactly as `LeagueGenerator.generateRoster` does for the random league.
    /// The $750K floor can lift the final total a little above the target.
    private static func normalizeRosterSalaries(_ roster: [Player], toCapUsage capUsage: Int) {
        let currentTotal = roster.reduce(0) { $0 + $1.annualSalary }
        guard currentTotal > 0 else { return }
        let ratio = Double(capUsage) / Double(currentTotal)
        for player in roster {
            player.annualSalary = max(750, Int((Double(player.annualSalary) * ratio).rounded()))
        }
    }

    // MARK: - Coaches

    /// Builds a full 16-role staff for one team.
    ///
    /// HC / OC / DC come from the template (anonymized names, tenure, and the
    /// scheme identity — the fact `ANONYMIZATION_SPEC.md` §4 deliberately
    /// keeps). The remaining thirteen roles are generated by the SAME
    /// `LeagueGenerator.generateCoach` rules the random league uses, seeded per
    /// role, with names recombined from the template's own name tokens (see
    /// `SupportStaffNamePool`) so a template staff reads like template people.
    private static func makeStaff(
        _ teamTemplate: LeagueTemplate.TeamTemplate,
        teamID: UUID,
        season: Int,
        globalSeed: UInt64,
        namePool: SupportStaffNamePool
    ) -> [Coach] {
        let key = teamTemplate.identity.key
        let offScheme = teamTemplate.staff.offScheme.flatMap(OffensiveScheme.init(rawValue:))
        let defScheme = teamTemplate.staff.defScheme.flatMap(DefensiveScheme.init(rawValue:))

        var staff: [Coach] = []
        for role in staffRoles {
            var rng = SeededLeagueRandom(seed: globalSeed &+ fnv1a("\(key)|\(role.rawValue)"))

            let member: LeagueTemplate.StaffMember?
            switch role {
            case .headCoach:            member = teamTemplate.staff.hc
            case .offensiveCoordinator: member = teamTemplate.staff.oc
            case .defensiveCoordinator: member = teamTemplate.staff.dc
            default:                    member = nil
            }

            let name: (first: String, last: String)
            if let member {
                name = splitFullName(member.name)
            } else {
                name = namePool.name(using: &rng)
            }

            // COUPLING — `make_templates.py::template_coach_age` replays the
            // FIRST draw of this exact stream to pick an age-appropriate face
            // for the three named coaches, and `generateCoach`'s first draw is
            // `Int.random(in: 35...68)` only because a non-nil `nameOverride`
            // short-circuits the two name-pool draws. Inserting an RNG draw
            // ahead of the age would silently push template coach portraits
            // onto the wrong age band (make_templates gate 19 measures it).
            let coach = LeagueGenerator.generateCoach(
                role: role,
                teamID: teamID,
                nameOverride: name,
                schemeOverride: (offScheme, defScheme),
                using: &rng
            )
            // Tenure: the template's `sinceYear` for the three named coaches
            // (jittered ±1 in the publish profile), otherwise "already on staff
            // when the career opens", matching the random league's convention.
            coach.hireSeasonYear = min(season, member?.sinceYear ?? (season - 1))
            // Phase-4 portrait: baked for hc/oc/dc, `nil` for the thirteen
            // generated support-staff roles — `FaceLibrary.backfill` gives
            // those a face after the whole league exists.
            coach.faceID = member?.faceID
            staff.append(coach)
        }
        return staff
    }

    /// The 16 roles a team carries — mirrors `LeagueGenerator.coachingStaffRoles`
    /// (which is private to the random path).
    private static let staffRoles: [CoachRole] = [
        .headCoach, .assistantHeadCoach, .offensiveCoordinator, .defensiveCoordinator,
        .specialTeamsCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach,
        .lbCoach, .dbCoach, .strengthCoach, .teamDoctor, .physio, .headTrainer
    ]

    /// First / last name tokens harvested from the template itself.
    ///
    /// The halves are drawn INDEPENDENTLY, so the reachable name space is the
    /// whole cross product (241 × 385 ≈ 93k), not the pairs the template happens
    /// to spell out. `ANONYMIZATION_SPEC.md` §1 guard 1 is a Levenshtein ≥ 3
    /// rule on the full name, and "no real surname is in the pool" only rules out
    /// EXACT hits — `Cedric` + `Skillman` is two edits from a real player, and
    /// nothing here could ever have caught it, because these 417 names are made
    /// at runtime where no bundle scan reaches them.
    ///
    /// So the guarantee is moved to where it can be checked: `make_templates.py`
    /// gate 16 (`publish-name-recombination>=3`) asserts that EVERY combination
    /// of the shipped `firstName` / `lastName` tokens clears the guard, and the
    /// transform's `NameFactory` refuses to emit a token that would break it.
    /// The app's own `RandomNameGenerator` pool is still not used here — it is
    /// checked against the same blocklist (`scan_bundle.py` gate E) but it is a
    /// much smaller pool, and template staff should read like template people.
    struct SupportStaffNamePool {
        private let firstNames: [String]
        private let lastNames: [String]
        /// Full names the template already uses, so a generated assistant does
        /// not turn up wearing a rostered player's name.
        private let taken: Set<String>

        init(template: LeagueTemplate) {
            var first: Set<String> = []
            var last: Set<String> = []
            var used: Set<String> = []
            for team in template.teams {
                for player in team.players {
                    let split = LeagueTemplateImporter.splitName(player)
                    first.insert(split.first)
                    last.insert(split.last)
                    used.insert("\(split.first) \(split.last)")
                }
                for member in [team.staff.hc, team.staff.oc, team.staff.dc] {
                    if let member { used.insert(member.name) }
                }
            }
            // Sorted so the pool order — and therefore every draw from it — is
            // independent of dictionary iteration order.
            self.firstNames = first.sorted()
            self.lastNames = last.sorted()
            self.taken = used
        }

        /// Draws a name, re-rolling while the pair happens to reproduce somebody
        /// the template already names. The taken-names set is immutable, so the
        /// result still depends only on `rng` — no iteration-order coupling.
        func name<G: RandomNumberGenerator>(using rng: inout G) -> (first: String, last: String) {
            for _ in 0..<16 {
                let first = firstNames.randomElement(using: &rng) ?? Self.fallback.first
                let last = lastNames.randomElement(using: &rng) ?? Self.fallback.last
                if !taken.contains("\(first) \(last)") {
                    return (first, last)
                }
            }
            return Self.fallback
        }

        /// Only reachable if the template carries no usable names at all. Both
        /// halves come from the blocklist-checked pool in `RandomNameGenerator`
        /// — the previous `("Alex", "Monroe")` put a real NFL surname in the
        /// product as a literal.
        private static let fallback = (first: "Alaric", last: "Abernathy")
    }

    // MARK: - Draft picks

    /// Imports 2026 pick ownership, trades included.
    ///
    /// A pick lives in the `picks2026` array of the team that OWNS it today;
    /// `originalTeam` names where it came from. That maps one-to-one onto
    /// `DraftPick.currentTeamID` / `originalTeamID`, so a traded pick shows the
    /// right provenance in the war room without any extra bookkeeping.
    private static func draftPicks(
        template: LeagueTemplate,
        season: Int,
        teamsByKey: [String: Team]
    ) -> [DraftPick] {
        var picks: [DraftPick] = []
        for teamTemplate in template.teams {
            guard let owner = teamsByKey[teamTemplate.identity.key] else { continue }
            for pick in teamTemplate.picks2026 {
                let origin = teamsByKey[pick.originalTeam] ?? owner
                picks.append(DraftPick(
                    seasonYear: season,
                    round: pick.round,
                    pickNumber: pick.overallPick,
                    originalTeamID: origin.id,
                    currentTeamID: owner.id,
                    teamAbbreviation: owner.abbreviation
                ))
            }
        }
        return picks.sorted { $0.pickNumber < $1.pickNumber }
    }

    // MARK: - Career history

    /// Turns a player's `careerArc` into `PlayerSeasonHistory` rows, statline
    /// included.
    ///
    /// Two sources, in priority order:
    ///
    /// 1. **Dev profile** — `statLines` carries the real per-season production,
    ///    which is folded straight into the row (`statLine(from:)`). Exact
    ///    careers, no modelling.
    /// 2. **Publish profile** — ships OVR arcs only (`ANONYMIZATION_SPEC.md` §3):
    ///    `{year, team, ovr, role}`, with `gp`/`gs` stripped by the
    ///    `publish-ovr-arcs-only` gate. Participation AND production are
    ///    therefore modelled by `SeasonStatSynthesizer` from exactly the four
    ///    inputs the spec names — position, OVR, role, era (age) — which is what
    ///    §3 already prescribes ("displayable stat lines are generated by the
    ///    game's own stat model").
    ///
    /// Determinism: every draw runs on `SeededLeagueRandom(seed: playerSeed +
    /// statSeedOffset + year)`, so the whole statline is a pure function of the
    /// template. Two imports of the same file stay byte-identical — asserted by
    /// TVAL check 1, whose history fingerprint hashes the stat columns.
    private static func seasonHistory(
        for player: Player,
        arcs: [LeagueTemplate.ArcRow],
        statLines: [LeagueTemplate.StatLine]?,
        playerSeed: UInt64,
        snapshotYear: Int,
        teamsByKey: [String: Team]
    ) -> [PlayerSeasonHistory] {
        var linesByYear: [Int: LeagueTemplate.StatLine] = [:]
        for line in statLines ?? [] { linesByYear[line.year] = line }

        return arcs.map { arc in
            let line = linesByYear[arc.year]
            let age = max(18, player.age - (snapshotYear - arc.year))
            // Per-(player, year) seed: SplitMix64 is built to be seeded from a
            // counter, so neighbouring years decorrelate and row ORDER cannot
            // influence any draw.
            var rng = SeededLeagueRandom(
                seed: playerSeed &+ statSeedOffset &+ UInt64(bitPattern: Int64(arc.year))
            )

            // A season not spent on an NFL roster (227 such arc rows ship in the
            // template) is a real zero, not a missing measurement.
            let onRoster = arc.team != nil
            var gamesPlayed = arc.gp ?? line?.gp ?? 0
            var gamesStarted = arc.gs ?? line?.gs ?? 0
            if onRoster, arc.gp == nil, line?.gp == nil {
                let drawn = SeasonStatSynthesizer.participation(
                    position: player.position, role: arc.role,
                    overall: arc.ovr, using: &rng
                )
                gamesPlayed = drawn.gamesPlayed
                gamesStarted = drawn.gamesStarted
            }
            if !onRoster {
                gamesPlayed = 0
                gamesStarted = 0
            }

            // Synthesis is keyed on the ABSENCE of a stat line — i.e. exactly the
            // publish profile. A dev row is trusted even when it folds to all
            // zeros: a receiver who dressed for three games and caught nothing
            // really did produce nothing, and inventing numbers over a real
            // career would be worse than showing the zero.
            let stats: SeasonStatLine
            let synthesized: Bool
            if let line {
                stats = statLine(from: line)
                synthesized = false
            } else {
                stats = SeasonStatSynthesizer.line(
                    position: player.position,
                    overall: arc.ovr,
                    gamesPlayed: gamesPlayed,
                    gamesStarted: gamesStarted,
                    age: age,
                    using: &rng
                )
                synthesized = true
            }

            let entry = PlayerSeasonHistory(
                playerID: player.id,
                season: arc.year,
                overallAtEndOfSeason: arc.ovr,
                gamesPlayed: gamesPlayed,
                gamesStarted: gamesStarted,
                ageAtEndOfSeason: age,
                teamID: arc.team.flatMap { teamsByKey[$0]?.id },
                position: player.position,
                statLine: stats,
                statsAreSynthesized: synthesized
            )

            // #20: the postseason bag, when the source carries one. Dev profile
            // only and only on the seasons that actually reached the playoffs —
            // every other row keeps the "no postseason" default.
            //
            // Never synthesized: a missing `post` means the player's team did not
            // play in January, which is a real zero, not a gap to be filled. (The
            // live season's playoff lines ARE modelled for the 13 clubs the sim
            // does not box-score — but there the game count is known, and here it
            // is precisely what is absent.) The fold goes through the same ONE
            // key→category table the regular line uses, so the two can never
            // drift apart.
            if let post = line?.post {
                let postGames = post.gp ?? 0
                let postLine = statLine(from: post.asRegularShapedLine(year: arc.year))
                if postGames > 0 || !postLine.isEmpty {
                    entry.postGamesPlayed = postGames
                    entry.postStatLine = postLine
                }
            }

            return entry
        }
    }

    /// Folds a dev-profile stat line into the game's own `SeasonStatLine`.
    ///
    /// Reads the whole key bag unconditionally: the source only ever carries the
    /// categories that apply to the player's position family, and no two families
    /// share a key with a different meaning (a QB's sacks-taken is `sacked`, a
    /// pass rusher's sacks-made is `sacks`). Categories the game does not model —
    /// `tfl`, `ff`, `fum`, `pen`, `xpm`, `long`, `in20`, `rating` — are dropped.
    /// Returns an empty line for the publish profile, where `statLines` is nil.
    static func statLine(from line: LeagueTemplate.StatLine) -> SeasonStatLine {
        func int(_ key: String) -> Int { Int((line.stat(key) ?? 0).rounded()) }
        func double(_ key: String) -> Double { line.stat(key) ?? 0 }

        var stats = SeasonStatLine()
        stats.passYards = int("yds")
        stats.passTDs = int("td")
        stats.passInts = int("int")
        stats.rushYards = int("rushYds")
        stats.rushTDs = int("rushTd")
        stats.receptions = int("rec")
        stats.recYards = int("recYds")
        stats.recTDs = int("recTd")
        stats.tackles = int("tackles")
        stats.sacks = double("sacks")
        stats.defInts = int("defInt")
        stats.passesDefended = int("pd")
        stats.fieldGoalsMade = int("fgm")
        stats.fieldGoalsAttempted = int("fga")
        stats.punts = int("punts")
        stats.puntAverage = double("avg")
        stats.snapsPlayed = int("snaps")
        return stats
    }

    // MARK: - Names

    private static func splitName(_ template: LeagueTemplate.PlayerTemplate) -> (first: String, last: String) {
        if let first = template.firstName, let last = template.lastName,
           !first.isEmpty, !last.isEmpty {
            return (first, last)
        }
        return splitFullName(template.name)
    }

    private static func splitFullName(_ name: String) -> (first: String, last: String) {
        let parts = name.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            // "Monroe" used to sit here — a real NFL surname, as a literal, in
            // the shipped binary. The stand-in comes from the checked pool.
            return (String(parts.first ?? "Alaric"), "Abernathy")
        }
        return (parts.dropLast().joined(separator: " "), String(parts[parts.count - 1]))
    }

    // MARK: - Seeds

    /// Parses the transform's 16-hex-char player id into the 64-bit seed
    /// component. Falls back to a hash for any id that is not plain hex, so an
    /// id-format change degrades to "still deterministic" instead of "all
    /// players share a seed".
    private static func entitySeed(_ identifier: String) -> UInt64 {
        if identifier.count <= 16, let value = UInt64(identifier, radix: 16) {
            return value
        }
        return fnv1a(identifier)
    }

    /// FNV-1a 64. Stable across runs and platforms — unlike `Hasher`, which is
    /// randomly seeded per process and would silently break determinism.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01B3
        }
        return hash
    }
}
