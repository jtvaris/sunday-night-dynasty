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

    /// All 13 coaching roles, one per staff member.
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
        .strengthCoach
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

            // Create 53-man roster with realistic salary tiers
            let teamPlayers = generateRoster(teamID: team.id)
            team.players = teamPlayers

            // Bug fix #1: Set cap usage to sum of all player salaries
            team.currentCapUsage = teamPlayers.reduce(0) { $0 + $1.annualSalary }

            allPlayers.append(contentsOf: teamPlayers)

            // Create coaching staff (12 coaches)
            for role in coachingStaffRoles {
                let coach = generateCoach(role: role, teamID: team.id)
                allCoaches.append(coach)
            }

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
        // Low spender (20) -> ~$15M, high spender (95) -> ~$35M
        let coachingBudget = 12_000 + Int(Double(spending) / 99.0 * 23_000.0)

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
    /// Total salary targets ~$200-230M (80-90% of $255M cap).
    private static func generateRoster(teamID: UUID) -> [Player] {
        var players: [Player] = []
        var depthChart: [Position: Int] = [:]

        for (position, count) in rosterBlueprint {
            for _ in 0..<count {
                let depthIndex = depthChart[position, default: 0]
                let player = generatePlayer(position: position, teamID: teamID, depthIndex: depthIndex)
                players.append(player)
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

        return Player(
            firstName: name.first,
            lastName: name.last,
            position: position,
            age: age,
            yearsPro: yearsPro,
            positionAttributes: posAttrs,
            personality: personality,
            teamID: teamID,
            contractYearsRemaining: contractYears,
            annualSalary: salary
        )
    }

    private static func generateCoach(role: CoachRole, teamID: UUID) -> Coach {
        let first = coachFirstNames.randomElement()!
        let last = coachLastNames.randomElement()!
        let age = Int.random(in: 35...68)
        let experience = max(0, age - Int.random(in: 28...40))

        let offScheme: OffensiveScheme? = (role == .headCoach || role == .offensiveCoordinator || role == .assistantHeadCoach)
            ? OffensiveScheme.allCases.randomElement()!
            : nil
        let defScheme: DefensiveScheme? = (role == .headCoach || role == .defensiveCoordinator || role == .assistantHeadCoach)
            ? DefensiveScheme.allCases.randomElement()!
            : nil

        let personality = PersonalityArchetype.allCases.randomElement()!

        // Salary tiers by role (in thousands)
        let salary: Int
        switch role {
        case .headCoach:               salary = Int.random(in: 5_000...12_000)
        case .assistantHeadCoach:      salary = Int.random(in: 2_000...5_000)
        case .offensiveCoordinator,
             .defensiveCoordinator:    salary = Int.random(in: 2_500...6_000)
        case .specialTeamsCoordinator: salary = Int.random(in: 1_000...2_500)
        default:                       salary = Int.random(in: 500...2_000)
        }

        let coach = Coach(
            firstName: first,
            lastName: last,
            age: age,
            role: role,
            offensiveScheme: offScheme,
            defensiveScheme: defScheme,
            playCalling: Int.random(in: 35...90),
            playerDevelopment: Int.random(in: 35...90),
            reputation: Int.random(in: 30...85),
            adaptability: Int.random(in: 30...85),
            gamePlanning: Int.random(in: 35...90),
            scoutingAbility: Int.random(in: 30...85),
            recruiting: Int.random(in: 30...85),
            motivation: Int.random(in: 35...90),
            discipline: Int.random(in: 30...85),
            mediaHandling: Int.random(in: 30...85),
            contractNegotiation: Int.random(in: 30...80),
            moraleInfluence: Int.random(in: 35...85),
            salary: salary,
            background: "",
            personality: personality,
            teamID: teamID,
            yearsExperience: experience
        )
        coach.background = CoachingEngine.generateBackground(for: coach)
        return coach
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
