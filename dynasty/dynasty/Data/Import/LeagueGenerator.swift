import Foundation

enum LeagueGenerator {

    // MARK: - Roster Blueprint

    /// Position counts for a standard 53-man roster.
    private static let rosterBlueprint: [(Position, Int)] = [
        (.QB, 3), (.RB, 3), (.FB, 1), (.WR, 6), (.TE, 3),
        (.LT, 1), (.LG, 1), (.C, 1), (.RG, 1), (.RT, 1),
        // Extra OL depth spread across interior/tackle spots
        (.LT, 1), (.LG, 1), (.C, 1),
        (.DE, 4), (.DT, 3), (.OLB, 4), (.MLB, 2),
        (.CB, 5), (.FS, 2), (.SS, 2),
        (.K, 1), (.P, 1)
    ]

    /// All 12 coaching roles, one per staff member.
    private static let coachingStaffRoles: [CoachRole] = [
        .headCoach,
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

    // MARK: - Public API

    typealias GeneratedLeague = (
        league: League,
        teams: [Team],
        players: [Player],
        owners: [Owner],
        coaches: [Coach]
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

            // Create 53-man roster
            var teamPlayers: [Player] = []
            for (position, count) in rosterBlueprint {
                for _ in 0..<count {
                    let player = generatePlayer(position: position, teamID: team.id)
                    teamPlayers.append(player)
                }
            }
            team.players = teamPlayers
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

        return (league, allTeams, allPlayers, allOwners, allCoaches)
    }

    // MARK: - Private Generators

    private static func generateOwner() -> Owner {
        let first = ownerFirstNames.randomElement()!
        let last = ownerLastNames.randomElement()!
        return Owner(
            name: "\(first) \(last)",
            patience: Int.random(in: 2...9),
            spendingWillingness: Int.random(in: 20...95),
            meddling: Int.random(in: 5...80),
            prefersWinNow: Bool.random()
        )
    }

    private static func generatePlayer(position: Position, teamID: UUID) -> Player {
        let name = RandomNameGenerator.randomName()
        let age = randomAge(for: position)
        let yearsPro = max(0, age - Int.random(in: 21...23))
        let posAttrs = randomPositionAttributes(for: position)
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement()!,
            motivation: Motivation.allCases.randomElement()!
        )
        let salary = randomSalary(for: position, yearsPro: yearsPro)

        return Player(
            firstName: name.first,
            lastName: name.last,
            position: position,
            age: age,
            yearsPro: yearsPro,
            positionAttributes: posAttrs,
            personality: personality,
            teamID: teamID,
            contractYearsRemaining: Int.random(in: 1...5),
            annualSalary: salary
        )
    }

    private static func generateCoach(role: CoachRole, teamID: UUID) -> Coach {
        let first = coachFirstNames.randomElement()!
        let last = coachLastNames.randomElement()!
        let age = Int.random(in: 35...68)
        let experience = max(0, age - Int.random(in: 28...40))

        let offScheme: OffensiveScheme? = (role == .headCoach || role == .offensiveCoordinator)
            ? OffensiveScheme.allCases.randomElement()!
            : nil
        let defScheme: DefensiveScheme? = (role == .headCoach || role == .defensiveCoordinator)
            ? DefensiveScheme.allCases.randomElement()!
            : nil

        return Coach(
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
            personality: PersonalityArchetype.allCases.randomElement()!,
            teamID: teamID,
            yearsExperience: experience
        )
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

    private static func randomSalary(for position: Position, yearsPro: Int) -> Int {
        // Base salary in thousands, scaled by position premium and experience
        let baseSalary: Int
        switch position {
        case .QB:
            baseSalary = Int.random(in: 800...35000)
        case .LT, .RT:
            baseSalary = Int.random(in: 700...20000)
        case .DE:
            baseSalary = Int.random(in: 700...22000)
        case .CB:
            baseSalary = Int.random(in: 700...18000)
        case .WR:
            baseSalary = Int.random(in: 700...20000)
        case .DT:
            baseSalary = Int.random(in: 700...16000)
        case .OLB, .MLB:
            baseSalary = Int.random(in: 700...15000)
        case .FS, .SS:
            baseSalary = Int.random(in: 700...14000)
        case .TE:
            baseSalary = Int.random(in: 700...14000)
        case .RB:
            baseSalary = Int.random(in: 700...12000)
        case .LG, .RG, .C:
            baseSalary = Int.random(in: 700...14000)
        case .FB:
            baseSalary = Int.random(in: 700...3000)
        case .K, .P:
            baseSalary = Int.random(in: 700...5000)
        }
        // Veterans command slightly more
        let experienceBonus = min(yearsPro * 200, 5000)
        return baseSalary + experienceBonus
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
