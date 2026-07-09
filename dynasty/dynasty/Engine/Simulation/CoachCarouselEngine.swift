import Foundation

// MARK: - CoachCarouselEngine (R30)

/// Stateless engine that drives the league-wide offseason coaching carousel:
/// "Black Monday" head-coach firings on struggling AI teams, HC hires from a
/// pool of rising coordinators and recycled head coaches, chain-filling of the
/// coordinator vacancies those promotions create, and interview requests for
/// the user's own in-demand coordinators.
///
/// Presentation side effects (news, feed entries) are returned to the caller;
/// the engine mutates only the `Coach` objects it is handed and returns any
/// freshly generated coaches for the caller to insert into the model context.
enum CoachCarouselEngine {

    // MARK: - Carousel Move (offseason feed model)

    /// One entry in the offseason carousel feed shown in the Staff view.
    struct CarouselMove: Codable, Identifiable {
        enum Kind: String, Codable {
            case firing            // AI team fires its head coach
            case hcHire            // AI team hires a new head coach
            case coordinatorHire   // AI team fills a coordinator seat
            case interviewRequest  // AI team requests to interview a user coordinator
            case departure         // user coordinator left for an HC job
            case blocked           // user blocked an interview request
        }

        let id: UUID
        let season: Int
        let kind: Kind
        /// Team the move happened at (display snapshot).
        let teamName: String
        let coachName: String
        /// One-line description, e.g. "Fired after a 3-14 season".
        let detail: String

        init(
            id: UUID = UUID(),
            season: Int,
            kind: Kind,
            teamName: String,
            coachName: String,
            detail: String
        ) {
            self.id = id
            self.season = season
            self.kind = kind
            self.teamName = teamName
            self.coachName = coachName
            self.detail = detail
        }
    }

    // MARK: - Interview Request

    /// A pending request from an AI team to interview one of the user's
    /// coordinators for their head-coach vacancy. Resolved by the user in
    /// the Staff view (allow / block); expires at the Combine if ignored.
    struct CoordinatorInterviewRequest: Codable {
        let id: UUID
        let coachID: UUID
        let coachName: String
        let coachRole: CoachRole
        let requestingTeamID: UUID
        let requestingTeamName: String
        let season: Int
        /// Blocking is only possible while the coach is under contract
        /// beyond the current year.
        let canBlock: Bool

        init(
            id: UUID = UUID(),
            coachID: UUID,
            coachName: String,
            coachRole: CoachRole,
            requestingTeamID: UUID,
            requestingTeamName: String,
            season: Int,
            canBlock: Bool
        ) {
            self.id = id
            self.coachID = coachID
            self.coachName = coachName
            self.coachRole = coachRole
            self.requestingTeamID = requestingTeamID
            self.requestingTeamName = requestingTeamName
            self.season = season
            self.canBlock = canBlock
        }
    }

    // MARK: - Black Monday Result

    struct BlackMondayResult {
        var news: [NewsItem] = []
        var moves: [CarouselMove] = []
        /// Freshly generated coaches (already assigned to teams) that the
        /// caller must insert into the model context.
        var newCoaches: [Coach] = []
        /// Interview request for one of the user's coordinators, if an AI
        /// team came calling this offseason. The requesting team's HC seat
        /// is intentionally left open until the request resolves.
        var interviewRequest: CoordinatorInterviewRequest?
        var firedHeadCoaches: Int = 0
    }

    // MARK: - Black Monday

    /// Runs the league's offseason coaching carousel. Call once per season
    /// during the `.coachingChanges` phase, after poaching and retirements.
    ///
    /// - Parameters:
    ///   - teams: All 32 teams (records still hold last season's results).
    ///   - allCoaches: Every coach in the store (attached and unattached).
    ///   - userTeamID: The user's team — exempt from AI firings/hires.
    ///   - userTeamWins: The user team's win total last season.
    ///   - hotSeatTeamIDs: Teams whose hot-seat story ran during the season
    ///     (R29 narrative state) — they fire first.
    ///   - season: Current season year.
    static func runBlackMonday(
        teams: [Team],
        allCoaches: [Coach],
        userTeamID: UUID?,
        userTeamWins: Int,
        hotSeatTeamIDs: Set<UUID>,
        season: Int
    ) -> BlackMondayResult {
        var result = BlackMondayResult()

        let aiTeams = teams.filter { $0.id != userTeamID }
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        func headCoach(of team: Team) -> Coach? {
            allCoaches.first { $0.teamID == team.id && $0.role == .headCoach }
        }

        // MARK: 1. Firings — struggling AI teams cut their head coach loose.

        struct FiringCandidate {
            let team: Team
            let coach: Coach
            let score: Double
        }

        var candidates: [FiringCandidate] = []
        for team in aiTeams {
            guard let hc = headCoach(of: team) else { continue }
            let deficit = team.losses - team.wins
            guard deficit >= 3 else { continue }   // needs a clearly losing season

            var score = Double(deficit)
            if hotSeatTeamIDs.contains(team.id) { score += 3.0 }          // media pressure
            let tenure = season - max(hc.hireSeasonYear, season - 12)
            if tenure >= 4 { score += 1.0 }                               // long leash used up
            score -= Double(CoachingEngine.coachOverallRating(hc) - 60) / 15.0
            score += Double.random(in: -1.0...1.0)                        // front-office noise
            candidates.append(FiringCandidate(team: team, coach: hc, score: score))
        }
        candidates.sort { $0.score > $1.score }

        // Moderate churn: 3–6 firings per season (fewer if the league is healthy).
        let target = min(Int.random(in: 3...6), candidates.count)
        var vacancyTeams: [Team] = []

        for firing in candidates.prefix(target) {
            firing.coach.teamID = nil
            firing.coach.reputation = max(1, firing.coach.reputation - 4)
            result.firedHeadCoaches += 1
            vacancyTeams.append(firing.team)

            result.moves.append(CarouselMove(
                season: season,
                kind: .firing,
                teamName: firing.team.fullName,
                coachName: firing.coach.fullName,
                detail: "Fired after a \(firing.team.record) season"
            ))
            result.news.append(NewsItem(
                headline: "Black Monday: \(firing.team.fullName) part ways with \(firing.coach.fullName)",
                body: "After a \(firing.team.record) season that fell far short of expectations, the \(firing.team.fullName) have fired head coach \(firing.coach.fullName). The search for a replacement begins immediately.",
                category: .coachingChange,
                week: 0,
                season: season,
                relatedTeamID: firing.team.id,
                sentiment: .negative
            ))
        }

        // Pre-existing AI HC vacancies (retirements, prior departures) also
        // enter the carousel so no AI team stays headless.
        for team in aiTeams where headCoach(of: team) == nil {
            if !vacancyTeams.contains(where: { $0.id == team.id }) {
                vacancyTeams.append(team)
            }
        }

        // MARK: 2. Interview request — the user's success makes their
        // coordinators hot names. One AI team with a vacancy may come calling.

        if let userTeamID, userTeamWins >= 9, !vacancyTeams.isEmpty {
            let userCoordinators = allCoaches
                .filter {
                    $0.teamID == userTeamID &&
                    [.offensiveCoordinator, .defensiveCoordinator,
                     .assistantHeadCoach, .specialTeamsCoordinator].contains($0.role)
                }
                .sorted { CoachingEngine.coachOverallRating($0) > CoachingEngine.coachOverallRating($1) }

            for coach in userCoordinators {
                let ovr = CoachingEngine.coachOverallRating(coach)
                guard ovr >= 68 else { continue }

                var chance = Double(ovr - 62) / 40.0 * 0.45
                if userTeamWins >= 11 { chance += 0.10 }
                if userTeamWins >= 13 { chance += 0.10 }
                chance += Double(coach.motivation - 50) / 50.0 * 0.05

                guard Double.random(in: 0...1) < max(0, chance) else { continue }

                // The most attractive open job comes calling (best record).
                let requesting = vacancyTeams.max { $0.wins < $1.wins } ?? vacancyTeams[0]
                result.interviewRequest = CoordinatorInterviewRequest(
                    coachID: coach.id,
                    coachName: coach.fullName,
                    coachRole: coach.role,
                    requestingTeamID: requesting.id,
                    requestingTeamName: requesting.fullName,
                    season: season,
                    canBlock: coach.contractYearsRemaining >= 2
                )
                // Reserve the seat until the user answers.
                vacancyTeams.removeAll { $0.id == requesting.id }

                result.moves.append(CarouselMove(
                    season: season,
                    kind: .interviewRequest,
                    teamName: requesting.fullName,
                    coachName: coach.fullName,
                    detail: "Requested permission to interview your \(coach.role.abbreviation) for their HC vacancy"
                ))
                break
            }
        }

        // MARK: 3. HC hires — rising coordinators + recycled head coaches.

        // Attractive jobs pick first.
        vacancyTeams.sort { $0.wins > $1.wins }

        var chainVacancies: [(team: Team, role: CoachRole)] = []

        func hcCandidateScore(_ coach: Coach) -> Double {
            Double(CoachingEngine.coachOverallRating(coach))
                + Double(coach.potential) * 0.25
                + Double(coach.reputation) * 0.15
                + Double.random(in: 0...4)
        }

        for vacancyTeam in vacancyTeams {
            // Pool rebuilt per vacancy — earlier hires leave the market.
            let recycledHCs = allCoaches.filter {
                $0.teamID == nil && $0.role == .headCoach && $0.age < 64
            }
            let unattachedCoordinators = allCoaches.filter {
                $0.teamID == nil
                    && [.offensiveCoordinator, .defensiveCoordinator, .assistantHeadCoach].contains($0.role)
                    && CoachingEngine.coachOverallRating($0) >= 66
            }
            let risingCoordinators = allCoaches.filter {
                $0.teamID != nil
                    && $0.teamID != userTeamID          // user coordinators only leave via interviews
                    && $0.teamID != vacancyTeam.id
                    && [.offensiveCoordinator, .defensiveCoordinator, .assistantHeadCoach].contains($0.role)
                    && CoachingEngine.coachOverallRating($0) >= 70
            }

            let pool = (recycledHCs + unattachedCoordinators + risingCoordinators)
                .sorted { hcCandidateScore($0) > hcCandidateScore($1) }

            let hired: Coach
            var originNote = ""
            if let pick = pool.prefix(3).randomElement() ?? pool.first {
                hired = pick
                if let oldTeamID = pick.teamID, let oldTeam = teamsByID[oldTeamID] {
                    // Promotion out of a coordinator seat — the chain begins.
                    originNote = "former \(oldTeam.fullName) \(pick.role.abbreviation)"
                    chainVacancies.append((team: oldTeam, role: pick.role))
                } else if pick.role == .headCoach {
                    originNote = "veteran head coach"
                } else {
                    originNote = "former \(pick.role.abbreviation)"
                }
            } else {
                // Market is empty — a fresh face enters the league.
                guard let generated = CoachingEngine.generateCoachCandidates(role: .headCoach, count: 1).first else { continue }
                hired = generated
                originNote = "surprise outside hire"
                result.newCoaches.append(generated)
            }

            hired.teamID = vacancyTeam.id
            if hired.role != .headCoach {
                hired.role = .headCoach
                hired.promotedInSeason = season
            }
            hired.hireSeasonYear = season
            hired.contractYearsRemaining = 4
            let ovr = CoachingEngine.coachOverallRating(hired)
            hired.salary = max(hired.salary, LeagueGenerator.salaryForCoach(
                role: .headCoach, ovr: ovr, yearsExperience: hired.yearsExperience
            ))

            result.moves.append(CarouselMove(
                season: season,
                kind: .hcHire,
                teamName: vacancyTeam.fullName,
                coachName: hired.fullName,
                detail: "Named head coach (\(originNote))"
            ))
            result.news.append(NewsItem(
                headline: "\(vacancyTeam.fullName) name \(hired.fullName) head coach",
                body: "The \(vacancyTeam.fullName) have hired \(hired.fullName), \(originNote), as their next head coach. The new regime takes over a roster that finished \(vacancyTeam.record) last season.",
                category: .coachingChange,
                week: 0,
                season: season,
                relatedTeamID: vacancyTeam.id,
                sentiment: .neutral
            ))
        }

        // MARK: 4. Coordinator chain — promotions leave seats that fill in turn.

        // Include pre-existing AI coordinator vacancies (poaching never
        // backfilled them before R30).
        let coordinatorRoles: [CoachRole] = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
        for team in aiTeams {
            for role in coordinatorRoles {
                let seatFilled = allCoaches.contains { $0.teamID == team.id && $0.role == role }
                let alreadyQueued = chainVacancies.contains { $0.team.id == team.id && $0.role == role }
                if !seatFilled && !alreadyQueued {
                    chainVacancies.append((team: team, role: role))
                }
            }
        }

        var coordinatorNewsBudget = 4    // keep the news feed readable
        for vacancy in chainVacancies {
            // Seat may have been filled earlier in this same loop.
            let stillOpen = !allCoaches.contains { $0.teamID == vacancy.team.id && $0.role == vacancy.role }
                && !result.newCoaches.contains { $0.teamID == vacancy.team.id && $0.role == vacancy.role }
            guard stillOpen else { continue }

            var originNote = ""
            var filled: Coach?

            // 1) Best unattached coach already carrying the role.
            if let free = allCoaches
                .filter({ $0.teamID == nil && $0.role == vacancy.role && $0.age < 64 })
                .max(by: { CoachingEngine.coachOverallRating($0) < CoachingEngine.coachOverallRating($1) }) {
                filled = free
                originNote = "veteran \(vacancy.role.abbreviation)"
            }
            // 2) Internal promotion from the position-coach room.
            else if let internalPick = allCoaches
                .filter({ $0.teamID == vacancy.team.id && $0.role.promotionTargets.contains(vacancy.role) })
                .max(by: { CoachingEngine.coachOverallRating($0) < CoachingEngine.coachOverallRating($1) }) {
                internalPick.role = vacancy.role
                internalPick.promotedInSeason = season
                filled = internalPick
                originNote = "promoted internally"
            }
            // 3) Fresh hire from outside the league's tracked pool.
            else if let generated = CoachingEngine.generateCoachCandidates(role: vacancy.role, count: 1).first {
                result.newCoaches.append(generated)
                filled = generated
                originNote = "outside hire"
            }

            guard let coach = filled else { continue }
            coach.teamID = vacancy.team.id
            coach.hireSeasonYear = season
            coach.contractYearsRemaining = 3

            result.moves.append(CarouselMove(
                season: season,
                kind: .coordinatorHire,
                teamName: vacancy.team.fullName,
                coachName: coach.fullName,
                detail: "New \(vacancy.role.displayName) (\(originNote))"
            ))
            if coordinatorNewsBudget > 0 {
                coordinatorNewsBudget -= 1
                result.news.append(NewsItem(
                    headline: "\(vacancy.team.fullName) hire \(coach.fullName) as \(vacancy.role.abbreviation)",
                    body: "The coaching carousel keeps spinning: the \(vacancy.team.fullName) have filled their \(vacancy.role.displayName.lowercased()) vacancy with \(coach.fullName) (\(originNote)).",
                    category: .coachingChange,
                    week: 0,
                    season: season,
                    relatedTeamID: vacancy.team.id,
                    sentiment: .neutral
                ))
            }
        }

        return result
    }

    // MARK: - Hiring Market 2.0: Candidate Demand

    /// How hotly a hiring-market candidate is pursued by other clubs.
    enum CoachDemandLevel: String, Codable {
        case high, moderate, low
    }

    /// Deterministic market demand for a candidate: elite or high-upside
    /// coaches draw multiple rival suitors and can be lost during
    /// negotiations; journeymen draw none.
    static func demand(for coach: Coach) -> (level: CoachDemandLevel, rivalTeams: Int) {
        let ovr = CoachingEngine.coachOverallRating(coach)
        let seed = stableSeed(coach.id)
        if ovr >= 76 || (ovr >= 70 && coach.potential >= 80) {
            return (.high, 2 + Int(seed % 3))          // 2–4 rival teams
        } else if ovr >= 68 {
            return (.moderate, 1 + Int(seed % 2))      // 1–2 rival teams
        }
        return (.low, 0)
    }

    /// FNV-1a over the UUID string — stable across launches (Hasher is not).
    static func stableSeed(_ uuid: UUID) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in uuid.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
