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
        .physio
    ]

    // MARK: - Owner Names

    private static let ownerFirstNames: [String] = [
        "Robert", "Jerry", "Arthur", "Stephen", "Virginia",
        "Terry", "Jim", "Mark", "Jeffrey", "David",
        "Steve", "Woody", "Cal", "Jed", "Shahid",
        "Michael", "Dan", "Clark", "Zygi", "Dean",
        "Kim", "Gayle", "Amy", "Janice", "Stan",
        "Tony", "Jimmy", "Walter", "Roger", "Bill",
        "Kenneth", "Christopher"
    ]

    private static let ownerLastNames: [String] = [
        "Kraft", "Jones", "Blank", "Ross", "Halas",
        "Pegula", "Irsay", "Davis", "Lurie", "Tepper",
        "Bisciotti", "Brown", "Johnson", "York", "Khan",
        "Bidwill", "Snyder", "Hunt", "Wilf", "Spanos",
        "Pegula", "Benson", "Adams", "McNair", "Kroenke",
        "Allen", "Glazer", "Ford", "Goodell", "Walton",
        "Haslem", "Ballard"
    ]

    private static let coachFirstNames: [String] = [
        "Mike", "Sean", "Andy", "Kevin", "Dan",
        "Matt", "Kyle", "Nick", "Brian", "Robert",
        "Todd", "Dennis", "Frank", "Ron", "John",
        "Bill", "Jim", "Pete", "Doug", "Bruce",
        "Vic", "Zac", "Brandon", "Dave", "Josh",
        "Arthur", "Nathaniel", "Jonathan", "DeMeco", "Raheem"
    ]

    private static let coachLastNames: [String] = [
        "McCarthy", "McVay", "Reid", "Stefanski", "Campbell",
        "LaFleur", "Shanahan", "Sirianni", "Daboll", "Saleh",
        "Bowles", "Allen", "Reich", "Rivera", "Harbaugh",
        "Belichick", "Tomlin", "Carroll", "Pederson", "Arians",
        "Fangio", "Taylor", "Staley", "Canales", "McDaniel",
        "Smith", "Hackett", "Gannon", "Ryans", "Morris"
    ]

    // MARK: - 2026 NFL Draft Order (First Round)

    /// Real 2026 NFL first-round draft order by team abbreviation.
    /// Teams appearing multiple times have extra first-round picks from trades.
    private static let firstRoundDraftOrder: [String] = [
        "LV", "NYJ", "ARI", "TEN", "NYG", "CLE", "WAS", "NO",
        "KC", "CIN", "MIA", "DAL", "LAR", "BAL", "TB", "NYJ",
        "DET", "MIN", "CAR", "DAL", "PIT", "LAC", "PHI", "CLE",
        "CHI", "BUF", "SF", "HOU", "KC", "DEN", "NE", "SEA"
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

        for teamDef in NFLTeamData.allTeams {
            // Create owner
            let owner = generateOwner()
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

        let league = League(
            teams: allTeams,
            currentSeason: startYear
        )

        // Bug fix #3: Generate draft picks for all teams
        let draftPicks = generateInitialDraftPicks(teams: allTeams, seasonYear: startYear)

        return (league, allTeams, allPlayers, allOwners, allCoaches, draftPicks)
    }

    // MARK: - Draft Pick Generation

    /// Generates 7 rounds of draft picks for each team using the real 2026 first-round order.
    /// Teams with extra first-round picks (from trades) receive bonus picks.
    /// Rounds 2-7 use the same base order (simplified).
    /// - Parameters:
    ///   - teams: All 32 generated teams.
    ///   - seasonYear: The draft year.
    /// - Returns: An array of all draft picks.
    static func generateInitialDraftPicks(teams: [Team], seasonYear: Int) -> [DraftPick] {
        // Build abbreviation -> Team lookup
        var teamsByAbbreviation: [String: Team] = [:]
        for team in teams {
            teamsByAbbreviation[team.abbreviation] = team
        }

        var picks: [DraftPick] = []
        var overallPick = 1

        // Round 1: Use the real 2026 draft order (32 picks, some teams appear twice)
        for (index, abbreviation) in firstRoundDraftOrder.enumerated() {
            guard let team = teamsByAbbreviation[abbreviation] else { continue }
            let pick = DraftPick(
                seasonYear: seasonYear,
                round: 1,
                pickNumber: overallPick,
                originalTeamID: team.id,
                currentTeamID: team.id,
                teamAbbreviation: abbreviation
            )
            _ = index // suppress unused warning
            picks.append(pick)
            overallPick += 1
        }

        // Rounds 2-7: Each of the 32 teams gets one pick per round.
        // Use the same first-round base order (deduplicated) for simplicity.
        // Teams that had extra round-1 picks do NOT get extra picks in later rounds.
        var baseOrder: [String] = []
        var seen = Set<String>()
        for abbreviation in firstRoundDraftOrder {
            if !seen.contains(abbreviation) {
                baseOrder.append(abbreviation)
                seen.insert(abbreviation)
            }
        }
        // Fill in any teams not in the first round order (IND, JAX, GB, ATL)
        for team in teams {
            if !seen.contains(team.abbreviation) {
                baseOrder.append(team.abbreviation)
                seen.insert(team.abbreviation)
            }
        }

        for round in 2...7 {
            for abbreviation in baseOrder {
                guard let team = teamsByAbbreviation[abbreviation] else { continue }
                let pick = DraftPick(
                    seasonYear: seasonYear,
                    round: round,
                    pickNumber: overallPick,
                    originalTeamID: team.id,
                    currentTeamID: team.id,
                    teamAbbreviation: abbreviation
                )
                picks.append(pick)
                overallPick += 1
            }
        }

        return picks
    }

    // MARK: - Private Generators

    private static func generateOwner() -> Owner {
        let first = ownerFirstNames.randomElement()!
        let last = ownerLastNames.randomElement()!
        let avatarID = OwnerAvatars.allIDs.randomElement()!
        let spending = Int.random(in: 20...95)

        // Coaching budget scales with spending willingness:
        // Low spender (20) -> ~$23M, average (50) -> ~$35M, high spender (95) -> ~$53M
        let coachingBudget = 15_000 + Int(Double(spending) / 99.0 * 40_000.0)

        return Owner(
            name: "\(first) \(last)",
            avatarID: avatarID,
            patience: Int.random(in: 2...9),
            spendingWillingness: spending,
            meddling: Int.random(in: 5...80),
            prefersWinNow: Bool.random(),
            coachingBudget: coachingBudget
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

        // Adjust total salary to target 80-95% of $255,000 cap (~$204K-$242K in thousands)
        let targetCap = Int.random(in: 204_000...235_000)
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

    private static func generatePlayer(position: Position, teamID: UUID, depthIndex: Int) -> Player {
        let name = RandomNameGenerator.randomName()
        let age = randomAge(for: position)
        let yearsPro = max(0, age - Int.random(in: 21...23))
        let posAttrs = randomPositionAttributes(for: position)
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement()!,
            motivation: Motivation.allCases.randomElement()!
        )
        let salary = realisticSalary(for: position, yearsPro: yearsPro, depthIndex: depthIndex)
        let contractYears = realisticContractYears(yearsPro: yearsPro, age: age)
        let morale = initialMorale(
            personality: personality.archetype,
            age: age,
            depthIndex: depthIndex,
            contractYears: contractYears,
            salary: salary,
            position: position
        )

        return Player(
            firstName: name.first,
            lastName: name.last,
            position: position,
            age: age,
            yearsPro: yearsPro,
            positionAttributes: posAttrs,
            personality: personality,
            morale: morale,
            teamID: teamID,
            contractYearsRemaining: contractYears,
            annualSalary: salary
        )
    }

    /// Creates the starting QB using the name and target overall from TeamPreview.
    /// The preview name format is "F. Last" (e.g., "P. Mahomes") or "C.J. Stroud".
    private static func generateNamedQB(previewName: String, targetOverall: Int, teamID: UUID) -> Player {
        // Parse the preview name: split on last space to get firstName and lastName.
        // Examples: "P. Mahomes" -> ("P.", "Mahomes"), "C.J. Stroud" -> ("C.J.", "Stroud")
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
        // Overall = physical.average * 0.6 + mental.average * 0.4
        // We generate attributes centered around the target with some variance.
        let physical = attributesForTarget(target: targetOverall, count: 6, variance: 5)
        let mental = attributesForTarget(target: targetOverall, count: 6, variance: 5)

        let physicalAttrs = PhysicalAttributes(
            speed: physical[0], acceleration: physical[1], strength: physical[2],
            agility: physical[3], stamina: physical[4], durability: physical[5]
        )
        let mentalAttrs = MentalAttributes(
            awareness: mental[0], decisionMaking: mental[1], clutch: mental[2],
            workEthic: mental[3], coachability: mental[4], leadership: mental[5]
        )

        let posAttrs = randomPositionAttributes(for: .QB)
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
        let salary = realisticSalary(for: .QB, yearsPro: yearsPro, depthIndex: 0)
        let contractYears = realisticContractYears(yearsPro: yearsPro, age: age)
        let morale = initialMorale(
            personality: personality.archetype,
            age: age,
            depthIndex: 0,
            contractYears: contractYears,
            salary: salary,
            position: .QB
        )

        return Player(
            firstName: firstName,
            lastName: lastName,
            position: .QB,
            age: age,
            yearsPro: yearsPro,
            physical: physicalAttrs,
            mental: mentalAttrs,
            positionAttributes: posAttrs,
            personality: personality,
            morale: morale,
            teamID: teamID,
            contractYearsRemaining: contractYears,
            annualSalary: salary
        )
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
        let first = coachFirstNames.randomElement()!
        let last = coachLastNames.randomElement()!
        let age = Int.random(in: 35...68)
        let potential = CoachDevelopmentEngine.generatePotential(forAge: age)
        let experience = max(0, age - Int.random(in: 28...40))

        let offScheme: OffensiveScheme? = (role == .headCoach || role == .offensiveCoordinator || role == .assistantHeadCoach)
            ? OffensiveScheme.allCases.randomElement()!
            : nil
        let defScheme: DefensiveScheme? = (role == .headCoach || role == .defensiveCoordinator || role == .assistantHeadCoach)
            ? DefensiveScheme.allCases.randomElement()!
            : nil

        let personality = PersonalityArchetype.allCases.randomElement()!

        // Temporary attributes to compute OVR for salary calculation
        let tmpPlayCalling = Int.random(in: 35...90)
        let tmpPlayerDev   = Int.random(in: 35...90)
        let tmpReputation  = Int.random(in: 30...85)
        let tmpAdaptability = Int.random(in: 30...85)
        let tmpGamePlanning = Int.random(in: 35...90)
        let tmpScouting     = Int.random(in: 30...85)
        let tmpRecruiting   = Int.random(in: 30...85)
        let tmpMotivation   = Int.random(in: 35...90)
        let tmpDiscipline   = Int.random(in: 30...85)
        let tmpMedia        = Int.random(in: 30...85)
        let tmpContract     = Int.random(in: 30...80)
        let tmpMorale       = Int.random(in: 35...85)

        let ovr = (tmpPlayCalling + tmpPlayerDev + tmpReputation + tmpAdaptability
            + tmpGamePlanning + tmpScouting + tmpRecruiting + tmpMotivation
            + tmpDiscipline + tmpMedia + tmpContract + tmpMorale) / 12

        let salary = Self.salaryForCoach(role: role, ovr: ovr, yearsExperience: experience)

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
        coach.background = CoachingEngine.generateBackground(for: coach)
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
        position: Position
    ) -> Int {
        // Base morale: 65-75 (not a flat 70)
        var morale = Int.random(in: 65...75)

        // Contract situation
        if contractYears <= 1 {
            // Expiring contract: anxious = lower morale
            morale -= Int.random(in: 5...10)
        }

        // Salary perception (rough market value check)
        let marketAvg = averageMarketSalary(for: position, depthIndex: depthIndex)
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
            morale -= Int.random(in: 5...10)
        }

        // Personality variance
        switch personality {
        case .teamLeader, .mentor, .steadyPerformer:
            morale += Int.random(in: 0...5)
        case .dramaQueen:
            morale -= Int.random(in: 3...8)
        case .loneWolf:
            morale -= Int.random(in: 0...5)
        case .fieryCompetitor:
            morale += Int.random(in: -3...3)
        case .classClown:
            morale += Int.random(in: -2...4)
        case .quietProfessional, .feelPlayer:
            morale += Int.random(in: -2...2)
        }

        return min(99, max(30, morale))
    }

    /// Rough average market salary for starter vs backup at a position (in thousands).
    private static func averageMarketSalary(for position: Position, depthIndex: Int) -> Int {
        if depthIndex >= 2 { return 1_500 }
        if depthIndex == 1 {
            return position == .QB ? 3_000 : 2_500
        }
        // Starter averages
        switch position {
        case .QB:            return 35_000
        case .DE, .OLB:      return 20_000
        case .CB:            return 18_000
        case .WR:            return 20_000
        case .LT, .RT:       return 16_000
        case .DT:            return 14_000
        case .FS, .SS:       return 11_000
        case .TE:            return 11_000
        case .MLB:           return 11_000
        case .LG, .RG, .C:  return 11_000
        case .RB:            return 8_000
        case .FB:            return 2_500
        case .K, .P:         return 3_500
        }
    }

    // MARK: - Helpers

    private static func randomAge(for position: Position) -> Int {
        switch position {
        case .QB:
            return Int.random(in: 22...38)
        case .RB, .FB:
            return Int.random(in: 21...31)
        case .WR:
            return Int.random(in: 21...34)
        case .TE:
            return Int.random(in: 22...33)
        case .LT, .LG, .C, .RG, .RT:
            return Int.random(in: 22...35)
        case .DE, .DT:
            return Int.random(in: 22...34)
        case .OLB, .MLB:
            return Int.random(in: 22...33)
        case .CB:
            return Int.random(in: 21...33)
        case .FS, .SS:
            return Int.random(in: 22...33)
        case .K, .P:
            return Int.random(in: 22...40)
        }
    }

    // MARK: - Coach Salary from OVR + Experience

    /// Computes a realistic coach salary (in thousands) based on role ranges, OVR, and experience.
    /// Higher OVR coaches command salaries toward the top of their role's range.
    /// Experience adds a slight bump (up to ~10% of the range).
    static func salaryForCoach(role: CoachRole, ovr: Int, yearsExperience: Int) -> Int {
        let range = role.salaryRange
        let spread = range.max - range.min

        // OVR drives most of the salary: map 30-90 OVR onto 0.0-1.0
        let ovrFraction = Double(min(max(ovr, 30), 90) - 30) / 60.0

        // Experience bonus: up to 10% of spread for 25+ years
        let expFraction = min(Double(yearsExperience) / 25.0, 1.0) * 0.10

        let rawSalary = Double(range.min) + Double(spread) * (ovrFraction * 0.90 + expFraction)

        // Add +-5% noise so coaches with identical OVR don't all cost the same
        let noise = rawSalary * Double.random(in: -0.05...0.05)
        let final = Int((rawSalary + noise).rounded())

        return min(range.max, max(range.min, final))
    }

    // MARK: - Realistic Salary (Bug Fix #5)

    /// Returns a salary in thousands that reflects the player's position tier and depth.
    /// - depthIndex 0 = starter, 1 = backup, 2+ = deep depth
    private static func realisticSalary(for position: Position, yearsPro: Int, depthIndex: Int) -> Int {
        // Rookies / deep backups
        if yearsPro <= 1 || depthIndex >= 2 {
            return Int.random(in: 750...2_000)
        }

        // Backup tier (depthIndex == 1)
        if depthIndex == 1 {
            switch position {
            case .QB:
                return Int.random(in: 1_000...5_000)
            default:
                return Int.random(in: 1_000...4_000)
            }
        }

        // Starter tier (depthIndex == 0)
        switch position {
        case .QB:
            // Franchise QBs are the most expensive
            return Int.random(in: 25_000...45_000)
        case .DE, .OLB:
            // Premium pass rushers / EDGE
            return Int.random(in: 15_000...25_000)
        case .CB:
            // Top corners
            return Int.random(in: 15_000...22_000)
        case .WR:
            // WR1 tier
            return Int.random(in: 15_000...25_000)
        case .LT, .RT:
            // Franchise tackles
            return Int.random(in: 12_000...20_000)
        case .DT:
            return Int.random(in: 10_000...18_000)
        case .FS, .SS:
            return Int.random(in: 8_000...15_000)
        case .TE:
            return Int.random(in: 8_000...15_000)
        case .MLB:
            return Int.random(in: 8_000...15_000)
        case .LG, .RG, .C:
            return Int.random(in: 8_000...14_000)
        case .RB:
            return Int.random(in: 5_000...12_000)
        case .FB:
            return Int.random(in: 1_500...3_500)
        case .K, .P:
            return Int.random(in: 2_000...5_500)
        }
    }

    // MARK: - Realistic Contract Years (Bug Fix #6)

    /// Returns contract years remaining based on career stage.
    /// - Veteran stars (7+ years): 1-2 years (expiring = interesting decisions)
    /// - Mid-career (3-6 years pro): 2-4 years
    /// - Young players on rookie deals (0-2 years pro): 3-4 years
    private static func realisticContractYears(yearsPro: Int, age: Int) -> Int {
        if yearsPro <= 2 {
            // Young players on rookie deals
            return Int.random(in: 3...4)
        } else if yearsPro <= 6 {
            // Mid-career players
            return Int.random(in: 2...4)
        } else {
            // Veteran stars — expiring contracts create drama
            return Int.random(in: 1...2)
        }
    }

    // MARK: - Player Familiarity Initialization

    /// Sets initial position and scheme familiarity for generated players.
    private static func initializePlayerFamiliarity(players: [Player], coaches: [Coach]) {
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
                    let startFam = Int.random(in: 10...min(maxFam, 20 + player.yearsPro * 5))
                    player.positionFamiliarity[pos.rawValue] = startFam
                }
            }

            // Scheme familiarity from team's current coordinator schemes
            if let offScheme = oc?.offensiveScheme, player.position.side == .offense {
                player.schemeFamiliarity[offScheme.rawValue] = Int.random(in: 55...85)
            }
            if let defScheme = dc?.defensiveScheme, player.position.side == .defense {
                player.schemeFamiliarity[defScheme.rawValue] = Int.random(in: 55...85)
            }
        }
    }

    // MARK: - Coach Scheme Expertise Initialization

    /// Sets initial scheme expertise for generated coaches.
    private static func initializeSchemeExpertise(for coaches: [Coach]) {
        for coach in coaches {
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

    private static func randomPositionAttributes(for position: Position) -> PositionAttributes {
        switch position {
        case .QB:
            return .quarterback(QBAttributes(
                armStrength: Int.random(in: 40...99),
                accuracyShort: Int.random(in: 40...99),
                accuracyMid: Int.random(in: 40...99),
                accuracyDeep: Int.random(in: 40...99),
                pocketPresence: Int.random(in: 40...99),
                scrambling: Int.random(in: 40...99)
            ))

        case .WR:
            return .wideReceiver(WRAttributes(
                routeRunning: Int.random(in: 40...99),
                catching: Int.random(in: 40...99),
                release: Int.random(in: 40...99),
                spectacularCatch: Int.random(in: 40...99)
            ))

        case .RB, .FB:
            return .runningBack(RBAttributes(
                vision: Int.random(in: 40...99),
                elusiveness: Int.random(in: 40...99),
                breakTackle: Int.random(in: 40...99),
                receiving: Int.random(in: 40...99)
            ))

        case .TE:
            return .tightEnd(TEAttributes(
                blocking: Int.random(in: 40...99),
                catching: Int.random(in: 40...99),
                routeRunning: Int.random(in: 40...99),
                speed: Int.random(in: 40...99)
            ))

        case .LT, .LG, .C, .RG, .RT:
            return .offensiveLine(OLAttributes(
                runBlock: Int.random(in: 40...99),
                passBlock: Int.random(in: 40...99),
                pull: Int.random(in: 40...99),
                anchor: Int.random(in: 40...99)
            ))

        case .DE, .DT:
            return .defensiveLine(DLAttributes(
                passRush: Int.random(in: 40...99),
                blockShedding: Int.random(in: 40...99),
                powerMoves: Int.random(in: 40...99),
                finesseMoves: Int.random(in: 40...99)
            ))

        case .OLB, .MLB:
            return .linebacker(LBAttributes(
                tackling: Int.random(in: 40...99),
                zoneCoverage: Int.random(in: 40...99),
                manCoverage: Int.random(in: 40...99),
                blitzing: Int.random(in: 40...99)
            ))

        case .CB, .FS, .SS:
            return .defensiveBack(DBAttributes(
                manCoverage: Int.random(in: 40...99),
                zoneCoverage: Int.random(in: 40...99),
                press: Int.random(in: 40...99),
                ballSkills: Int.random(in: 40...99)
            ))

        case .K, .P:
            return .kicking(KickingAttributes(
                kickPower: Int.random(in: 40...99),
                kickAccuracy: Int.random(in: 40...99)
            ))
        }
    }
}
