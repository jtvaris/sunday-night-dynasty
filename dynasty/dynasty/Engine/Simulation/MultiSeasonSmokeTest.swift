#if DEBUG
import Foundation
import SwiftData

// MARK: - Multi-Season Smoke Test (R32 verification harness)
//
// Simulates N complete seasons programmatically against an ISOLATED in-memory
// store (never touches the user's saved careers): advanceWeek loop through
// regular season + playoffs + every offseason phase, with AI stand-ins for the
// user's decisions (draft picks, FA fallback, roster floor). Prints one summary
// row per season:
//   points/team/game, roster min/max, retirements, drafted count, HC changes,
//   league average OVR (decay watch), plus anomaly lines.
//
// Call temporarily from app launch, read the output via
// `simctl launch --console-pty`, then REMOVE the call — never ship it.
@MainActor
enum MultiSeasonSmokeTest {

    static func run(seasons: Int = 5, fantasy: Bool = false) {
        print("SMOKE: ===== multi-season smoke test, \(seasons) seasons\(fantasy ? " (FANTASY DRAFT career)" : "") =====")

        // Isolated in-memory container (same schema as DataContainer).
        let schema = Schema([
            Career.self, League.self, Team.self, Player.self, Owner.self,
            Coach.self, Season.self, Game.self, Schedule.self, Contract.self,
            Scout.self, CollegeProspect.self, DraftPick.self, DraftEvent.self,
            DraftPickGrade.self, DraftReputation.self, CareerArcState.self,
            PlayerSeasonHistory.self, FABid.self, FAVisit.self,
            FAStorylineEvent.self, Holdout.self, TrainingPlan.self,
            WorkloadEvent.self, PositionBattle.self, RosterCut.self,
            OpponentPrepWeek.self, VoluntaryWorkout.self, HardKnocksEvent.self,
        ])
        guard let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ) else {
            print("SMOKE: FAILED to create in-memory container")
            return
        }
        let context = container.mainContext

        // Reset WeekAdvancer static state so a fresh cycle starts clean.
        WeekAdvancer.currentDraftClass = []
        WeekAdvancer.currentDraftPicks = []
        WeekAdvancer.draftClassGenerated = false
        WeekAdvancer.udfaStageCompletedSeasons = []

        // League + career bootstrap (mirrors TeamSelectionView.startCareer,
        // except the user's team KEEPS its generated coaching staff — the
        // harness plays a fully AI-managed franchise).
        let career = Career(playerName: "Smoke Bot", role: .gm, capMode: .simple)
        let generated = LeagueGenerator.generate(startYear: career.currentSeason)
        career.leagueID = generated.league.id
        career.teamID = generated.teams.first?.id
        career.hasCompletedIntro = true

        // R40 — optional fantasy-draft career: pool every generated player and
        // snake-draft all 32 rosters headlessly (mirrors FantasyDraftView's
        // auto-fill + TeamSelectionView.completeFantasyDraft) BEFORE insertion.
        if fantasy {
            career.gameMode = .fantasyDraft
            applyFantasyDraft(generated: generated)
        }

        context.insert(career)
        context.insert(generated.league)
        generated.teams.forEach { context.insert($0) }
        generated.players.forEach { context.insert($0) }
        generated.owners.forEach { context.insert($0) }
        generated.coaches.forEach { context.insert($0) }
        generated.draftPicks.forEach { context.insert($0) }
        try? context.save()

        // Baseline league metrics.
        let baselineOVR = leagueAverageOVR(context: context)
        let baseRosters = rosterSizes(context: context)
        print(String(format: "SMOKE: baseline avgOVR=%.2f rosters min=%d max=%d players=%d",
                     baselineOVR, baseRosters.min, baseRosters.max, baseRosters.total))

        // Per-cycle counters.
        var seasonsCompleted = 0
        var advances = 0
        var draftedThisCycle = 0
        var firedNotes = 0
        var retiredTotalPrev = 0
        var seenRetiredIDs = Set<UUID>()      // OVR-drift diag: newly retired per cycle
        var hcSnapshot = headCoachByTeam(context: context)
        let maxAdvances = seasons * 60 + 60   // watchdog: infinite-loop guard

        // R39: wall-clock timing — total run + slowest single advance.
        let runStart = CFAbsoluteTimeGetCurrent()
        var slowestAdvanceMs = 0.0
        var slowestAdvanceLabel = ""

        while seasonsCompleted < seasons && advances < maxAdvances {
            let phaseBefore = career.currentPhase
            let seasonBefore = career.currentSeason

            let advStart = CFAbsoluteTimeGetCurrent()
            WeekAdvancer.advanceWeek(career: career, modelContext: context)
            let advMs = (CFAbsoluteTimeGetCurrent() - advStart) * 1000
            if advMs > slowestAdvanceMs {
                slowestAdvanceMs = advMs
                slowestAdvanceLabel = "\(phaseBefore) wk\(career.currentWeek) s\(seasonBefore)"
            }
            advances += 1

            if WeekAdvancer.wasFired {
                firedNotes += 1
                print("SMOKE: note season=\(seasonBefore) owner verdict FIRED (loop continues for sim integrity)")
            }

            // Entered the draft phase → the user would draft now. AI drafts
            // for every team (including the user's) exactly like the war room.
            if career.currentPhase == .draft && phaseBefore != .draft {
                draftedThisCycle = runAIDraft(career: career, context: context)
            }

            // A new regular season just started → the previous cycle is fully
            // closed (offseason ran). Emit the summary row for it.
            if career.currentPhase == .regularSeason && phaseBefore != .regularSeason {
                // AI stand-in for the user's offseason roster management runs
                // FIRST (cutdown to 53 + refill to 46) so the row below
                // measures a managed league: refillAIRosters skips the user's
                // team by design, and FA/no-resign flows are the user's job.
                refillUserRoster(career: career, context: context)

                let finishedSeason = seasonBefore   // year label of the cycle that just ended
                let retiredNow = retiredCount(context: context)
                let pts = averagePointsPerTeam(seasonYear: finishedSeason, context: context)
                let sizes = rosterSizes(context: context)
                let ovr = leagueAverageOVR(context: context)
                let hcNow = headCoachByTeam(context: context)
                let hcChanges = hcNow.filter { hcSnapshot[$0.key] != $0.value }.count

                seasonsCompleted += 1
                print(String(
                    format: "SMOKE: season=%d pts/team=%.1f roster min=%d max=%d retired=%d drafted=%d hcChanges=%d avgOVR=%.2f (Δ%+.2f) advances=%d",
                    finishedSeason, pts, sizes.min, sizes.max,
                    retiredNow - retiredTotalPrev, draftedThisCycle, hcChanges,
                    ovr, ovr - baselineOVR, advances
                ))

                retiredTotalPrev = retiredNow
                draftedThisCycle = 0
                hcSnapshot = hcNow

                // OVR-drift diagnostics: who left, who arrived, and how the
                // yearsPro cohorts are trending.
                printDriftDiagnostics(
                    seasonLabel: finishedSeason,
                    seenRetiredIDs: &seenRetiredIDs,
                    context: context
                )
            }

            try? context.save()
        }

        if advances >= maxAdvances {
            print("SMOKE: FAILED — watchdog tripped after \(advances) advances (phase=\(career.currentPhase) week=\(career.currentWeek) season=\(career.currentSeason))")
        }
        let finalOVR = leagueAverageOVR(context: context)
        print(String(format: "SMOKE: ===== done: %d seasons, %d advances, firedNotes=%d, final avgOVR=%.2f (baseline %.2f) =====",
                     seasonsCompleted, advances, firedNotes, finalOVR, baselineOVR))

        // R39: wall-clock summary.
        let totalS = CFAbsoluteTimeGetCurrent() - runStart
        print(String(
            format: "PERF|multiseason_%dseasons|%.1f  (avg advance %.1f ms, slowest %.1f ms @ %@)",
            seasonsCompleted, totalS * 1000,
            advances > 0 ? totalS * 1000 / Double(advances) : 0,
            slowestAdvanceMs, slowestAdvanceLabel
        ))
    }

    // MARK: - Fantasy draft bootstrap (R40)

    /// Strips every generated roster, pools all players, and snake-drafts 53
    /// rounds with `FantasyDraftEngine.aiPickIndex` for every team, then
    /// assigns fantasy contracts + per-team salary normalization — the exact
    /// headless equivalent of Auto-Complete in `FantasyDraftView`.
    private static func applyFantasyDraft(generated: LeagueGenerator.GeneratedLeague) {
        for player in generated.players { player.teamID = nil }
        for team in generated.teams {
            team.players = []
            team.currentCapUsage = 0
        }

        var pool = generated.players
            .map(FantasyDraftEngine.PoolEntry.init(player:))
            .sorted { $0.overall > $1.overall }
        var rosters: [UUID: [FantasyDraftEngine.PoolEntry]] =
            Dictionary(uniqueKeysWithValues: generated.teams.map { ($0.id, []) })
        let baseOrder = generated.teams.map(\.id).shuffled()
        let teamCount = generated.teams.count
        let totalPicks = FantasyDraftEngine.rosterSize * teamCount

        var pickIndex = 0
        while pickIndex < totalPicks && !pool.isEmpty {
            let round = pickIndex / teamCount + 1
            let order = FantasyDraftEngine.order(forRound: round, baseOrder: baseOrder)
            let teamID = order[pickIndex % teamCount]
            let counts = (rosters[teamID] ?? []).reduce(into: [Position: Int]()) {
                $0[$1.position, default: 0] += 1
            }
            guard let index = FantasyDraftEngine.aiPickIndex(
                pool: pool, rosterCounts: counts, round: round
            ) else { break }
            rosters[teamID, default: []].append(pool[index])
            pool.remove(at: index)
            pickIndex += 1
        }

        for team in generated.teams {
            let drafted = (rosters[team.id] ?? []).map(\.player)
            for player in drafted {
                player.teamID = team.id
                let contract = FantasyDraftEngine.fantasyContract(
                    overall: player.overall,
                    age: player.age,
                    position: player.position
                )
                player.annualSalary = contract.salary
                player.contractYearsRemaining = contract.years
            }
            team.players = drafted
            team.currentCapUsage = FantasyDraftEngine.normalizeSalaries(
                for: drafted,
                cap: team.salaryCap
            )
        }
        let sizes = generated.teams.map { $0.players.count }
        print("SMOKE: fantasy draft complete — picks=\(pickIndex) roster min=\(sizes.min() ?? 0) max=\(sizes.max() ?? 0)")
    }

    // MARK: - AI draft (mirrors DraftDayCoordinator's AI path)

    /// Internal (not private) so the DEBUG dashboard skip can reuse it when
    /// fast-forwarding a real career through the draft phase (R39).
    @discardableResult
    static func runAIDraft(career: Career, context: ModelContext) -> Int {
        let season = career.currentSeason
        var descriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> { $0.seasonYear == season && !$0.isComplete },
            sortBy: [SortDescriptor(\.pickNumber)]
        )
        descriptor.includePendingChanges = true
        let picks = (try? context.fetch(descriptor)) ?? []
        guard !picks.isEmpty else {
            print("SMOKE: ANOMALY season=\(season) draft phase entered but NO incomplete DraftPicks exist — draft skipped")
            return 0
        }

        let teams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        var rosters = Dictionary(
            grouping: players.filter { $0.teamID != nil && !$0.isRetired },
            by: { $0.teamID! }
        )
        var available = WeekAdvancer.currentDraftClass.filter { $0.isDeclaringForDraft }
        guard !available.isEmpty else {
            print("SMOKE: ANOMALY season=\(season) draft phase entered but draft class is empty")
            return 0
        }

        var drafted = 0
        var draftedOVRSum = 0
        var draftedPotSum = 0
        for pick in picks {
            guard !available.isEmpty, let team = teamsByID[pick.currentTeamID] else { continue }
            let chosen = DraftEngine.aiMakePick(
                team: team,
                availableProspects: available,
                teamRoster: rosters[team.id] ?? []
            )
            let player = DraftEngine.convertToPlayer(
                prospect: chosen,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber
            )
            draftedOVRSum += player.overall
            draftedPotSum += player.truePotential
            context.insert(player)
            pick.playerID = player.id
            pick.playerName = chosen.fullName
            pick.playerPosition = chosen.position.rawValue
            pick.playerCollege = chosen.college
            pick.teamAbbreviation = team.abbreviation
            pick.isComplete = true
            rosters[team.id, default: []].append(player)
            chosen.isDeclaringForDraft = false   // consumed — keeps him out of the UDFA pool
            available.removeAll { $0.id == chosen.id }
            drafted += 1
        }
        if drafted > 0 {
            print(String(
                format: "SMOKE: diag draft season=%d drafted=%d avgOVR=%.2f avgPot=%.2f",
                season, drafted,
                Double(draftedOVRSum) / Double(drafted),
                Double(draftedPotSum) / Double(drafted)
            ))
        }
        try? context.save()
        return drafted
    }

    // MARK: - OVR-drift diagnostics

    /// Prints, once per completed cycle: the quality of the players who just
    /// retired (what the league lost), and the rostered yearsPro cohorts
    /// (whether young classes climb fast enough to replace them).
    private static func printDriftDiagnostics(
        seasonLabel: Int,
        seenRetiredIDs: inout Set<UUID>,
        context: ModelContext
    ) {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []

        // Newly retired since the previous cycle (attributes survive retire()).
        let newlyRetired = players.filter { $0.isRetired && !seenRetiredIDs.contains($0.id) }
        for player in newlyRetired { seenRetiredIDs.insert(player.id) }
        if !newlyRetired.isEmpty {
            let avgOVR = Double(newlyRetired.reduce(0) { $0 + $1.overall }) / Double(newlyRetired.count)
            let avgAge = Double(newlyRetired.reduce(0) { $0 + $1.age }) / Double(newlyRetired.count)
            let avgPot = Double(newlyRetired.reduce(0) { $0 + $1.truePotential }) / Double(newlyRetired.count)
            print(String(
                format: "SMOKE: diag retired season=%d count=%d avgOVR=%.2f avgAge=%.1f avgPot=%.2f",
                seasonLabel, newlyRetired.count, avgOVR, avgAge, avgPot
            ))
        }

        // Rostered cohorts by yearsPro (at this point the fresh draft class is yp1).
        let rostered = players.filter { $0.teamID != nil && !$0.isRetired }
        func cohort(_ range: ClosedRange<Int>) -> String {
            let group = rostered.filter { range.contains($0.yearsPro) }
            guard !group.isEmpty else { return "-" }
            let avg = Double(group.reduce(0) { $0 + $1.overall }) / Double(group.count)
            return String(format: "%.1f(n=%d)", avg, group.count)
        }
        let veterans = rostered.filter { $0.yearsPro >= 8 }
        let vetText: String
        if veterans.isEmpty {
            vetText = "-"
        } else {
            let avg = Double(veterans.reduce(0) { $0 + $1.overall }) / Double(veterans.count)
            vetText = String(format: "%.1f(n=%d)", avg, veterans.count)
        }
        let avgPot = rostered.isEmpty ? 0 :
            Double(rostered.reduce(0) { $0 + $1.truePotential }) / Double(rostered.count)
        print("SMOKE: diag cohorts season=\(seasonLabel) "
              + "yp1=\(cohort(1...1)) yp2=\(cohort(2...2)) yp3=\(cohort(3...3)) "
              + "yp4to7=\(cohort(4...7)) yp8plus=\(vetText) "
              + String(format: "leaguePot=%.2f", avgPot))
    }

    // MARK: - AI stand-in for user roster management

    private static func refillUserRoster(career: Career, context: ModelContext) {
        guard let teamID = career.teamID else { return }
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        var roster = players.filter { $0.teamID == teamID && !$0.isRetired }

        // AI stand-in for the user's cutdown day: trim to the 53-man ceiling.
        if roster.count > 53 {
            let sorted = roster.sorted { $0.overall > $1.overall }
            for player in sorted.suffix(roster.count - 53) {
                player.teamID = nil
                player.annualSalary = 0
                player.contractYearsRemaining = 0
            }
            roster = Array(sorted.prefix(53))
        }

        guard roster.count < 46 else { return }
        var pool = players
            .filter { $0.teamID == nil && !$0.isRetired && !$0.isInjured }
            .sorted { $0.overall > $1.overall }
        while roster.count < 46 {
            let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 3)
            let signing: Player
            if !pool.isEmpty {
                let index = pool.firstIndex { needs.contains($0.position) } ?? 0
                signing = pool.remove(at: index)
            } else {
                // Pool dry — street free agent, same as refillAIRosters.
                signing = LeagueGenerator.generatePlayer(
                    position: needs.first ?? .WR,
                    teamID: teamID,
                    depthIndex: 2
                )
                context.insert(signing)
            }
            signing.teamID = teamID
            signing.contractYearsRemaining = Int.random(in: 1...2)
            signing.annualSalary = max(750, min(signing.annualSalary, 1_500))
            roster.append(signing)
        }
    }

    // MARK: - Metrics

    private static func averagePointsPerTeam(seasonYear: Int, context: ModelContext) -> Double {
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> { $0.seasonYear == seasonYear && !$0.isPlayoff }
        )
        let games = ((try? context.fetch(descriptor)) ?? []).filter { $0.isPlayed }
        guard !games.isEmpty else { return 0 }
        let totalPoints = games.reduce(0) { $0 + ($1.homeScore ?? 0) + ($1.awayScore ?? 0) }
        return Double(totalPoints) / Double(games.count * 2)
    }

    private static func rosterSizes(context: ModelContext) -> (min: Int, max: Int, total: Int) {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        let teams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        var counts: [UUID: Int] = [:]
        for team in teams { counts[team.id] = 0 }
        for player in players where player.teamID != nil && !player.isRetired {
            counts[player.teamID!, default: 0] += 1
        }
        let values = counts.values
        return (values.min() ?? 0, values.max() ?? 0, values.reduce(0, +))
    }

    private static func leagueAverageOVR(context: ModelContext) -> Double {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        let rostered = players.filter { $0.teamID != nil && !$0.isRetired }
        guard !rostered.isEmpty else { return 0 }
        return Double(rostered.reduce(0) { $0 + $1.overall }) / Double(rostered.count)
    }

    private static func retiredCount(context: ModelContext) -> Int {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        return players.filter { $0.isRetired }.count
    }

    private static func headCoachByTeam(context: ModelContext) -> [UUID: UUID] {
        let coaches = (try? context.fetch(FetchDescriptor<Coach>())) ?? []
        var byTeam: [UUID: UUID] = [:]
        for coach in coaches where coach.role == .headCoach && coach.teamID != nil {
            byTeam[coach.teamID!] = coach.id
        }
        return byTeam
    }
}
#endif
