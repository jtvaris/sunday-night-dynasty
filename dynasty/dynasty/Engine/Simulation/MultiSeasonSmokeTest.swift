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

    /// - Parameters:
    ///   - seasons: How many complete cycles to run.
    ///   - fantasy: Snake-draft every roster before the first season (R40).
    ///   - source: Which league the run starts from. `.generated` is the classic
    ///     random path; `.fixed2026` / `.fixed2026Dev` import a baked template
    ///     (`docs/REALISTIC_LEAGUE_PLAN.md` phase 3) so the same three-season
    ///     drift / roster / watchdog gates can be measured on the fixed league.
    ///     Driven by `PERF_SMOKE_LEAGUE=<LeagueSource rawValue>`.
    static func run(seasons: Int = 5, fantasy: Bool = false, source: LeagueSource = .generated) {
        print("SMOKE: ===== multi-season smoke test, \(seasons) seasons\(fantasy ? " (FANTASY DRAFT career)" : "") league=\(source.rawValue) =====")

        // Isolated in-memory container (same schema as DataContainer).
        let schema = Schema([
            Career.self, League.self, Team.self, Player.self, Owner.self,
            Coach.self, Game.self, Contract.self,
            Scout.self, CollegeProspect.self, DraftPick.self, DraftEvent.self,
            DraftPickGrade.self, DraftReputation.self, CareerArcState.self,
            PlayerSeasonHistory.self, FABid.self, FAVisit.self,
            FAStorylineEvent.self, Holdout.self, TrainingPlan.self,
            WorkloadEvent.self, PositionBattle.self, RosterCut.self,
            OpponentPrepWeek.self, VoluntaryWorkout.self, HardKnocksEvent.self,
            TradeRecord.self, TeamSeasonArchive.self,
        ])
        guard let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ) else {
            print("SMOKE: FAILED to create in-memory container")
            return
        }
        let context = container.mainContext

        // Reset WeekAdvancer static state so a fresh cycle starts clean. Shares
        // one list with the app's career-switch reset, so a newly added static
        // can never be wiped in one place and forgotten in the other.
        WeekAdvancer.resetProcessStateForCareerSwitch()

        // Task #51: per-source development ledger, plus the per-run pyramid
        // reference readings the 90+ / 33+ drift verdicts are taken against.
        // Only this harness ever turns the ledger on — see
        // `DevelopmentSourceDiag`.
        DevelopmentSourceDiag.reset()
        DevelopmentSourceDiag.isEnabled = true
        // Task #53: the OTHER half of the drift question — see `ChurnDiag`.
        ChurnDiag.reset()
        ChurnDiag.isEnabled = true
        resetPyramidBaselines()

        // League + career bootstrap (mirrors TeamSelectionView.startCareer,
        // except the user's team KEEPS its generated coaching staff — the
        // harness plays a fully AI-managed franchise).
        let career = Career(playerName: "Smoke Bot", role: .gm, capMode: .simple)

        // Phase 4 faces: same ordering as `TeamSelectionView.startCareer` —
        // bind the library to the fresh career before the league exists, so a
        // repeated harness run never inherits the previous run's registry.
        FaceLibrary.shared.beginNewCareer(career)

        // League source: random roll, or an imported fixed template. The
        // template path mirrors `TeamSelectionView.startCareer` — same importer,
        // same career-history insertion — so what runs here is what a real
        // template career runs. A missing/malformed template is a hard failure,
        // not a silent fall-back to the random path: a green run must never be
        // able to mean "the template never loaded".
        let generated: LeagueGenerator.GeneratedLeague
        var seasonHistory: [PlayerSeasonHistory] = []
        if let profile = source.templateProfile {
            do {
                let imported = try LeagueGenerator.generateFromTemplate(
                    profile: profile, startYear: career.currentSeason
                )
                generated = imported.generated
                seasonHistory = imported.seasonHistory
                career.leagueSource = source
                print("SMOKE: template imported profile=\(profile.rawValue) teams=\(imported.teams.count) "
                      + "players=\(imported.players.count) coaches=\(imported.coaches.count) "
                      + "picks=\(imported.draftPicks.count) historyRows=\(imported.seasonHistory.count)")
            } catch {
                print("SMOKE: FAILED — template \(profile.rawValue) could not be imported: \(error)")
                return
            }
        } else {
            generated = LeagueGenerator.generate(startYear: career.currentSeason)
            // Same career backstory a real random career now opens with, so the
            // harness keeps simulating what the app actually ships.
            seasonHistory = LeagueGenerator.syntheticCareerHistory(
                players: generated.players, startYear: career.currentSeason
            )
        }

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

        // Multi-save isolation: stamp exactly like `finalizeCareer` does, so the
        // harness exercises the same scoped fetches the app runs. Without this
        // every careerID-filtered fetch would return nothing and the run would
        // go silently green-but-empty.
        career.schemaBackfillVersion = CareerScope.currentBackfillVersion
        CareerScope.stamp(generated.league, careerID: career.id)
        CareerScope.stamp(generated.teams, careerID: career.id)
        CareerScope.stamp(generated.players, careerID: career.id)
        CareerScope.stamp(generated.owners, careerID: career.id)
        CareerScope.stamp(generated.coaches, careerID: career.id)
        CareerScope.stamp(generated.draftPicks, careerID: career.id)
        CareerScope.stamp(seasonHistory, careerID: career.id)

        context.insert(career)
        context.insert(generated.league)
        generated.teams.forEach { context.insert($0) }
        generated.players.forEach { context.insert($0) }
        generated.owners.forEach { context.insert($0) }
        generated.coaches.forEach { context.insert($0) }
        generated.draftPicks.forEach { context.insert($0) }
        seasonHistory.forEach { context.insert($0) }
        try? context.save()

        // Baseline league metrics.
        let baselineOVR = leagueAverageOVR(context: context)
        let baseRosters = rosterSizes(context: context)
        let baselineRostered = ((try? context.fetch(FetchDescriptor<Player>())) ?? [])
            .filter { $0.teamID != nil && !$0.isRetired }
        let baselinePot = baselineRostered.isEmpty ? 0 :
            Double(baselineRostered.reduce(0) { $0 + $1.truePotential }) / Double(baselineRostered.count)
        print(String(format: "SMOKE: baseline avgOVR=%.2f leaguePot=%.2f rosters min=%d max=%d players=%d",
                     baselineOVR, baselinePot, baseRosters.min, baseRosters.max, baseRosters.total))
        printPyramidDiagnostics(seasonLabel: "base", rostered: baselineRostered, unsignedCount: 0)

        // Per-cycle counters.
        var seasonsCompleted = 0
        var advances = 0
        var draftedThisCycle = 0
        var firedNotes = 0
        var retiredTotalPrev = 0
        var seenRetiredIDs = Set<UUID>()      // OVR-drift diag: newly retired per cycle
        var offersGeneratedPrev = 0           // Wave 0 trade diag: per-season delta
        var offseasonOffersPrev = 0           // Wave 2: the offseason half of that delta
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

            // The stand-in GM has to work in the OFFSEASON too, not only at
            // kickoff.
            //
            // Every offseason strips the user's franchise of its expiring
            // contracts and nothing re-signs for him until the next kickoff, so by
            // the third cycle the harness was running the offseason trade market
            // against a ~25-man roster of minimum-salary depth. That is not a
            // market condition, it is a measurement artifact, and it silently
            // zeroed §5's "2-5 offseason offers reaching the user" band in every
            // run: `SMOKE: diag tradeOfferFunnel` showed all 7-9 offseason rolls
            // dying with `buy(noTarget=<rolls × clubs>)` — nobody wanted anybody
            // because there was nobody to want. Refilling at the top of the
            // offseason and again before the pre-draft window keeps the franchise
            // as plausible as the 31 clubs `refillAIRosters` looks after.
            if career.currentPhase != phaseBefore,
               career.currentPhase == .reviewRoster
                || career.currentPhase == .freeAgency
                || career.currentPhase == .proDays {
                refillUserRoster(career: career, context: context)
            }

            // A new regular season just started → the previous cycle is fully
            // closed (offseason ran). Emit the summary row for it.
            //
            // Keyed on the SEASON YEAR, not on "the phase changed to
            // regularSeason": the trade deadline is now a real phase for one week
            // (`.regularSeason` → `.tradeDeadline` → `.regularSeason`), and the
            // phase test would have counted that mid-season flip back as a whole
            // new season — a bogus summary row and an early end to the run.
            // `startNewSeason` is the only thing that increments the year.
            if career.currentPhase == .regularSeason && career.currentSeason != seasonBefore {
                // AI stand-in for the user's offseason roster management runs
                // FIRST (cutdown to 53 + refill to 53) so the row below
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

                // Phase 4 faces: the portrait invariant is a MULTI-SEASON
                // property and used to be measured only at career creation —
                // where it is trivially true. The pool (3 584 ids: 2 048
                // generated + 512 reserve + the 1 024-id female range) is
                // smaller than a career's population growth (224 draft picks +
                // up to ~124 AI UDFAs every offseason against 40-90
                // retirements), so this is the only place the reuse ladder is
                // exercised at all. `free=0` in the line below means the catalog
                // is genuinely full and reuse is arithmetic; a duplicate WITH a
                // same-gender id still free is a real defect and trips the
                // assertion inside the audit.
                //
                // The female sub-pool is the tight one: 35 female faces against
                // the ~31 female coaches a 0.06 hiring share produces, so
                // `freeFemale=0` with within-gender reuse shows up here long
                // before the male half runs out.
                auditFaces(seasonLabel: finishedSeason, context: context)
                auditCareerScope(seasonLabel: finishedSeason, context: context)

                // Wave 0 instrumentation, Wave 2 band asserts.
                printTradeDiagnostics(
                    seasonLabel: finishedSeason,
                    seasonIndex: seasonsCompleted,
                    userTeamID: career.teamID,
                    offersGeneratedPrev: &offersGeneratedPrev,
                    offseasonOffersPrev: &offseasonOffersPrev,
                    context: context
                )

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
        // S3: sizes from the draft result, not `Team.players` (that relationship
        // is the creation-time hand-off assigned just above — see its doc).
        let sizes = generated.teams.map { (rosters[$0.id] ?? []).count }
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
        // Coordinator staff per team — rookies need their drafting team's schemes
        // to start with non-zero scheme familiarity.
        let coachesByTeam = Dictionary(
            grouping: ((try? context.fetch(FetchDescriptor<Coach>())) ?? [])
                .filter { $0.teamID != nil },
            by: { $0.teamID! }
        )
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
                pickNumber: pick.pickNumber,
                draftSeason: pick.seasonYear,
                salaryCap: team.salaryCap
            )
            DraftEngine.initializeRookieFamiliarity(
                player: player,
                prospect: chosen,
                coaches: coachesByTeam[pick.currentTeamID] ?? []
            )
            draftedOVRSum += player.overall
            draftedPotSum += player.truePotential
            player.careerID = career.id
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

    // MARK: - Trade diagnostics (Wave 0 — docs/TRADE_OVERHAUL_PLAN.md §6)

    /// One `SMOKE: diag trades` line per completed season, aggregated from the
    /// `TradeRecord` ledger.
    ///
    /// WHY this exists: `grep -i trade audit_smoke.log` returned 0 matches in
    /// 672 lines / 3 seasons, and that silence had TWO causes — the harness
    /// measured nothing, and the code paths genuinely produce nothing (plan
    /// finding S9). This line separates those two forever.
    ///
    /// EXPECTED WAVE 0 BASELINE: **all counters zero**. That is the point, not
    /// a bug — it is the proof of findings S1 (no future-year `DraftPick` rows
    /// exist, so `guard !packagePicks.isEmpty` / `guard !askPicks.isEmpty` kill
    /// the deadline pass and every rebuilder sell-offer) and S5 (a 15 %/week
    /// roll over weeks 1-8 ≈ 1.2 attempts/season, both productive sub-paths
    /// dead). `userOffers` is the only counter that may be non-zero, and only
    /// via the filler-player fallback.
    ///
    /// WAVE 1 CHANGES THAT BASELINE. Future-year `DraftPick` rows now exist from
    /// league creation and the deadline is a real week, so `aiVsAi` / `deadline` /
    /// `picksMoved` / `futurePickShare` are expected OFF zero from season 1 (the
    /// deadline pass finally clears its `guard !packagePicks.isEmpty`). A run that
    /// still prints all zeros means the pick pool never reached the deadline pass.
    ///
    /// WAVE 2 ADDS THE BAND ASSERTS (plan §5 / §8). Each §5 band is checked and
    /// a miss prints one `SMOKE: ANOMALY` line naming the band, the number and
    /// what is binding — the same shape as the face-pool audit, so a run's log
    /// says WHICH season the market fell out of NFL range and why.
    ///
    /// Season 1 is WARN-level on purpose (`SMOKE: warn trades …`): the league is
    /// generated with every team 0-0 and no last-season record, so the stance
    /// model has only talent and cap room to read, and the first cycle's
    /// offseason windows run on rosters that have never been through a draft.
    /// From season 2 the same misses are anomalies.
    private static func printTradeDiagnostics(
        seasonLabel: Int,
        seasonIndex: Int,
        userTeamID: UUID?,
        offersGeneratedPrev: inout Int,
        offseasonOffersPrev: inout Int,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<TradeRecord>(
            predicate: #Predicate<TradeRecord> { $0.season == seasonLabel }
        )
        let rows = (try? context.fetch(descriptor)) ?? []

        // AI-vs-AI offers to the user are counted at GENERATION, not execution:
        // the harness has no UI and never accepts one, so the ledger cannot see
        // them (see `WeekAdvancer.aiTradeOffersGenerated`). The offseason subtotal
        // is tracked separately because §5 bands the two halves of the league year
        // apart (3-8 in-season + 2-5 offseason).
        let offersTotal = WeekAdvancer.aiTradeOffersGenerated
        let offseasonTotal = WeekAdvancer.aiTradeOffersOffseasonGenerated
        let offersThisCycle = offersTotal - offersGeneratedPrev
        let offseasonOffers = offseasonTotal - offseasonOffersPrev
        let inSeasonOffers = max(0, offersThisCycle - offseasonOffers)
        offersGeneratedPrev = offersTotal
        offseasonOffersPrev = offseasonTotal

        // `futurePickShare` is the share of PICK-INVOLVING trades that include at
        // least one future-year pick — the shape §5 states its band in ("~60-70 %
        // of player trades", target ≥50 %), not a share of the picks themselves.
        // Measured over the pick-involving subset so a league year full of
        // straight player-for-player swaps cannot dilute it into a false miss.
        let picksMoved = rows.reduce(0) { $0 + $1.picksMovedCount }
        let pickTrades = rows.filter { $0.picksMovedCount > 0 }
        let withFuturePick = pickTrades.filter { $0.futurePicksCount > 0 }.count
        let futureShare = pickTrades.isEmpty
            ? 0
            : Double(withFuturePick) / Double(pickTrades.count) * 100

        let inSeasonRows = rows.filter(\.isInSeason)
        let offseasonRows = rows.filter { !$0.isInSeason && $0.kind != .draftDay }
        let deadlineRows = rows.filter { $0.kind == .aiDeadline }
        let deadlineWeek = WeekAdvancer.tradeDeadlineWeek
        let lateRows = inSeasonRows.filter { $0.week >= deadlineWeek - 2 }
        let lateShare = inSeasonRows.isEmpty
            ? 0
            : Double(lateRows.count) / Double(inSeasonRows.count) * 100
        let packageTrades = rows.filter { $0.playersMovedCount > 0 && $0.picksMovedCount > 0 }
        let packageShare = rows.isEmpty
            ? 0
            : Double(packageTrades.count) / Double(rows.count) * 100

        print(String(
            format: "SMOKE: diag trades season=%d total=%d aiVsAi=%d inSeason=%d deadline=%d "
                  + "offseason=%d userOffers=%d userOffersOff=%d draftSwaps=%d playersMoved=%d "
                  + "picksMoved=%d futurePickShare=%.1f%% last3Share=%.1f%% pkgShare=%.1f%%",
            seasonLabel,
            rows.count,
            rows.filter { $0.isAIvsAI(userTeamID: userTeamID) }.count,
            inSeasonRows.count,
            deadlineRows.count,
            offseasonRows.count,
            inSeasonOffers,
            offseasonOffers,
            rows.filter { $0.kind == .draftDay }.count,
            rows.reduce(0) { $0 + $1.playersMovedCount },
            picksMoved,
            futureShare,
            lateShare,
            packageShare
        ))

        // League cap headroom. The market's hardest wall is the buyer's cap room —
        // it was vetoing 1 240 of the 1 530 deals a year that had already cleared
        // both GMs' value bars — so the state of the league's books belongs next to
        // the funnel that reports those vetoes, and it is the number that says
        // whether a quiet market is the market's fault or the economy's.
        let capTeams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        if !capTeams.isEmpty {
            let shares = capTeams.map { Double($0.availableCap) / Double(max(1, $0.salaryCap)) * 100 }
            let underCap = shares.filter { $0 >= 0 }.count
            print(String(
                format: "SMOKE: diag capRoom season=%d underCap=%d/%d avgRoom=%.1f%% min=%.1f%% max=%.1f%%",
                seasonLabel, underCap, capTeams.count,
                shares.reduce(0, +) / Double(shares.count),
                shares.min() ?? 0, shares.max() ?? 0
            ))

            // --- capRoom band (task #27) ---
            //
            // The stock number above was informational, and that is how the league
            // quietly ran itself broke: room fell 22.9 % → 0.7 % → -1.9 % across
            // three seasons with every other band green, because nothing asserted
            // that a league has to be able to afford itself.
            //
            // The band is set from what the money is FOR. A club's cap has to
            // cover a rookie class (~8 picks), in-season injury replacements and
            // a deadline move; the NFL's own clubs open a league year around
            // 6-12 % effective room after the first FA wave. `avgRoom >= 8` is the
            // low end of that, and `underCap >= 24/32` (three quarters) allows the
            // handful of genuinely all-in clubs the trade market needs without
            // letting insolvency become the league's normal state.
            //
            // Season 1 is exempt for the same reason the trade bands are: the
            // rollover economy has not run a full cycle yet.
            if seasonIndex > 1 {
                var capMisses: [String] = []
                let avgRoom = shares.reduce(0, +) / Double(shares.count)
                if underCap < 24 { capMisses.append("underCap=\(underCap)/32 below 24") }
                if avgRoom < 8.0 { capMisses.append(String(format: "avgRoom=%.1f%% below 8 %%", avgRoom)) }
                if !capMisses.isEmpty {
                    print("SMOKE: ANOMALY season=\(seasonLabel) capRoom bands missed: "
                          + capMisses.joined(separator: ", ")
                          + " — see FreeAgencyEngine.marketPressure / capReservePercent")
                }
            }
        }

        // WHERE the money went (task #27). `capRoom` is a stock; this is the flow
        // that moves it. The wage bill the free-agent market wrote this league
        // year, against what the same men were paid on the deals that just
        // expired — if `wageBillDelta` outruns the 5-8 % cap growth, the league is
        // inflating and no amount of trade tuning can hold the books.
        //
        // `mktDemand` is the same question asked of the WHOLE roster: what the
        // league would cost if everyone were re-priced at market today, as a share
        // of the league's total cap. It is structurally above 100 % (rookie deals
        // are the discount that makes an NFL roster affordable), and watching it
        // climb is what tells drift in player quality apart from drift in prices.
        let salaryPlayers = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        let rosteredPaid = salaryPlayers.filter { $0.teamID != nil && !$0.isRetired }
        if !capTeams.isEmpty && !rosteredPaid.isEmpty {
            let capTotal = capTeams.reduce(0) { $0 + $1.salaryCap }
            let avgCap = capTotal / capTeams.count
            let payroll = rosteredPaid.reduce(0) { $0 + $1.annualSalary }
            let demand = rosteredPaid.reduce(0) {
                $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: avgCap)
            }
            let rookieDeal = rosteredPaid.filter { $0.yearsPro <= 3 }
            let rookiePay = rookieDeal.reduce(0) { $0 + $1.annualSalary }
            print(String(
                format: "SMOKE: diag salaryInflation season=%d cap=%d payroll=%.1f%% mktDemand=%.1f%% "
                      + "yp0to3Pay=%.1f%%ofPayroll avgSal=%d %@",
                seasonLabel, avgCap,
                Double(payroll) / Double(max(1, capTotal)) * 100,
                Double(demand) / Double(max(1, capTotal)) * 100,
                Double(rookiePay) / Double(max(1, payroll)) * 100,
                payroll / rosteredPaid.count,
                FreeAgencyEngine.signingLedger.summary
            ))

            // WHO the money went to (task #87 / F7). Every gate above this line
            // is a league AGGREGATE — `underCap >= 24/32` and `avgRoom >= 8 %`
            // are satisfied perfectly by a league that pays twenty men 22 % of
            // the cap each and fills the other 1 676 slots at the minimum. The
            // #87 audit's central unmeasured risk was exactly that: a
            // position-level shift in who gets paid, invisible to every
            // instrument in the repo. This is the instrument.
            var payByGroup: [String: Int] = [:]
            for p in rosteredPaid {
                payByGroup[salaryGroup(p.position), default: 0] += p.annualSalary
            }
            let groupLine = payByGroup
                .sorted { $0.value > $1.value }
                .map { String(format: "%@=%.1f%%", $0.key, Double($0.value) / Double(max(1, payroll)) * 100) }
                .joined(separator: " ")
            print("SMOKE: diag salaryByPosition season=\(seasonLabel) \(groupLine)")

            // ONE sanity gate on the shape. A position group taking more than
            // 30 % of a league's payroll is not a balance preference, it is a
            // broken multiplier: the fattest group a real NFL payroll produces is
            // the offensive line at ~18-20 %, and the game's own roster blueprint
            // puts no group above nine of fifty-three slots.
            if let (fattest, fattestPay) = payByGroup.max(by: { $0.value < $1.value }) {
                let share = Double(fattestPay) / Double(max(1, payroll)) * 100
                if share > 30.0 {
                    print(String(
                        format: "SMOKE: ANOMALY season=%d salaryByPosition %@ takes %.1f%% of league payroll (>30 %%) "
                              + "— see ContractEngine.positionMultiplier",
                        seasonLabel, fattest, share
                    ))
                }
            }
        }
        FreeAgencyEngine.signingLedger = FreeAgencyEngine.SigningLedger()
        FreeAgencyEngine.priorSalaryByPlayerID.removeAll()

        // WHERE the league market's candidate deals died this cycle, and why the
        // user's phone did or did not ring. Printed next to the volume line because
        // the two are only readable together: "total=18" says a band was missed,
        // these say whether the cause was seller supply, affordability, a GM's
        // value bar, a league rule, or (twice during the tuning pass) the harness
        // itself. Reset per season so each line is exactly one league year.
        print("SMOKE: diag tradeFunnel season=\(seasonLabel) \(TradeValueEngine.funnel.summary)")
        print("SMOKE: diag tradeOfferFunnel season=\(seasonLabel) \(TradeValueEngine.funnel.offerSummary)")
        TradeValueEngine.funnel = TradeValueEngine.MarketFunnel()

        // --- §5 bands ---
        var misses: [String] = []
        func check(_ ok: Bool, _ message: @autoclosure () -> String) {
            if !ok { misses.append(message()) }
        }

        check(rows.count >= 30 && rows.count <= 70,
              "total=\(rows.count) outside 30-70 (§5 player trades/year)")
        check(inSeasonRows.count >= 8 && inSeasonRows.count <= 25,
              "inSeason=\(inSeasonRows.count) outside 8-25")
        check(deadlineRows.count >= 5 && deadlineRows.count <= 15,
              "deadlineWeek=\(deadlineRows.count) outside 5-15")
        check(offseasonRows.count >= 15 && offseasonRows.count <= 40,
              "offseason=\(offseasonRows.count) outside 15-40")
        check(inSeasonRows.isEmpty || lateShare >= 60,
              String(format: "last3Share=%.1f%% below 60 %% (deadline back-loading)", lateShare))
        check(pickTrades.isEmpty || futureShare >= 50,
              String(format: "futurePickShare=%.1f%% below 50 %%", futureShare))
        check(rows.isEmpty || packageShare >= 25,
              String(format: "pkgShare=%.1f%% below 25 %% (player+pick packages)", packageShare))
        check(inSeasonOffers >= 3 && inSeasonOffers <= 8,
              "userOffers=\(inSeasonOffers) outside 3-8 in-season")
        check(offseasonOffers >= 2 && offseasonOffers <= 5,
              "userOffersOff=\(offseasonOffers) outside 2-5")

        guard !misses.isEmpty else { return }
        let detail = misses.joined(separator: "; ")
        // Capacity-style hint: a market can only trade what the league is willing
        // to move, so the two structural causes are named rather than left to be
        // rediscovered — an under-delivering pass is nearly always one of them.
        let hint = "— check seller supply (stance mix / untouchables) and cap room "
                 + "(`validationErrors` vetoes a deal the buyer cannot absorb) before retuning the targets"
        if seasonIndex <= 1 {
            print("SMOKE: warn trades season=\(seasonLabel) \(detail) — season-1 league has no prior-year records (expected, hard from season 2)")
        } else {
            print("SMOKE: ANOMALY season=\(seasonLabel) trade bands missed: \(detail) \(hint)")
        }
    }

    // MARK: - OVR-drift diagnostics

    /// Prints, once per completed cycle: the quality of the players who just
    /// retired (what the league lost), and the rostered yearsPro cohorts
    /// (whether young classes climb fast enough to replace them).
    ///
    /// ## `leaguePot` is the line that explains the quality pyramid (task #32)
    ///
    /// The intake ratchet this line was added to expose is FIXED (see
    /// `DraftClassBuilder.drawUpside`); what is left of the pyramid drift is a
    /// different, still-open thing and this note names both so a future run is
    /// not re-diagnosed from scratch.
    ///
    /// **The ratchet, as measured before the fix.** Every draft class entered at
    /// ~81 mean true potential into a league averaging ~75, so ~15 % of the
    /// roster was replaced each spring by men with ~6-10 more points of ceiling
    /// than the men they displaced, and `leaguePot` marched:
    ///
    /// | season | leaguePot (old intake) | leaguePot (this wave) |
    /// |---|---|---|
    /// | base | 73.3 | 73.1 |
    /// | 1 | 75.0 | 74.1 |
    /// | 2 | 77.4 | 75.9 |
    /// | 3 | 78.8 | 76.4 |
    /// | 4 | 78.7 | 75.8 |
    ///
    /// (right column measured at the maximum intake correction; the shipped
    /// calibration sits between the two — see the sweep on `drawUpside`).
    /// The march is a march no longer: `leaguePot` now approaches its
    /// equilibrium instead of climbing +1.5 a season, and `tools/balance-harness`'s
    /// `career` scenario measures that equilibrium directly on the same line
    /// (`leaguePot: first -> last`, +0.03/season over 21 seasons).
    ///
    /// **Do NOT read `leaguePot ≈ league mean OVR` as the health target.** The
    /// equilibrium sits ~3-4 points ABOVE the class it is fed, because the men
    /// who leave the league are the ones who did not realise: the `career`
    /// harness measures class 78.0 → equilibrium `leaguePot` 82.4 with the §8
    /// ability pyramid green (6.9a-g). A `leaguePot` that stops rising is the
    /// signal; its level is not.
    ///
    /// **What is still open.** Two things this wave measured and did not fix,
    /// both outside the intake:
    ///
    ///  1. **The 90+ band is inside the generator's own sampling spread.**
    ///     `diag pyramid season=base` has measured 1.8 / 2.2 / 2.7 % across runs
    ///     — before a single week is simulated, on a band whose ceiling is 2.5.
    ///     One 1 696-man league is a ±0.5 pp sample there (`leaguegen` pools 400
    ///     leagues to get 1.77 %). A season-4 reading of 3.1 % is therefore ~1 pp
    ///     of real drift on top of a start that is already half a band high, and
    ///     no draft-intake change can move season 0 at all.
    ///  2. **The shipped season pipeline develops ~2 OVR more than the harness.**
    ///     At identical intake the `career` scenario settles at mean 70.7 /
    ///     80+ 15.9 % while this smoke reaches 71.7 / 20.0 % in four seasons and
    ///     is still climbing. That gap is in `WeekAdvancer`'s camp / training /
    ///     coaching passes, not in `PlayerDevelopmentEngine`'s constants — the
    ///     two scenarios call the same `processOffseason`.
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

        // Task #51: which pass developed the league this season, in the same
        // league-mean OVR points the drift gate is stated in.
        if let devSources = DevelopmentSourceDiag.report(
            seasonLabel: seasonLabel, rosteredCount: rostered.count
        ) {
            print(devSources)
        }

        let unsigned = players.filter { $0.teamID == nil && !$0.isRetired }

        // Task #53: the roster-churn funnel — WHICH stage selects the league's
        // age/quality composition. Printed next to `devsource` because the two
        // are the complete answer between them: development moves ratings,
        // churn moves WHO the ratings are averaged over, and task #51 already
        // proved it is not the first one.
        if let churn = ChurnDiag.report(seasonLabel: seasonLabel, pool: unsigned) {
            print(churn)
        }

        printPyramidDiagnostics(
            seasonLabel: "\(seasonLabel)",
            rostered: rostered,
            unsignedCount: unsigned.count
        )
        printMoraleDiagnostics(seasonLabel: seasonLabel, rostered: rostered)
    }

    /// `DEVELOPMENT_NFL_REFERENCE.md` §8 quality + age pyramid. The stage-6
    /// drift gate is a statement about the league MEAN, and a mean can be held
    /// still by two errors cancelling — this line is what makes that visible.
    /// `faPool` is the unsigned, unretired population: inflow that the league
    /// took in but never cycled out.
    ///
    /// **The P1 quality-pyramid wave (2026-07-30) turned this from a print into a
    /// GATE.** It was informational, and that is exactly how the shipped league
    /// drifted to a 90+ share of 9.5 % by season 3 with every other smoke band
    /// green: the mean drifted only +1.0 (inside the ≤1.5 gate) while the shape
    /// underneath it inverted. Each band now prints `SMOKE: ANOMALY` on a miss,
    /// the same idiom the trade and face-pool audits use, so a log says WHICH
    /// season the pyramid fell out of NFL range and by how much.
    ///
    /// Band derivation — this is the app's whole league, so it is bracketed by the
    /// two sources that feed it, both measured:
    ///
    /// | band | §8 | LeagueGenerator t=0 | dev-stack equilibrium | gate |
    /// |---|---|---|---|---|
    /// | 90+   | 1-2 %  | 1.7 %  | 2.0 %  | 0.8-2.5 % |
    /// | 80+   | 12-16 %| 16.8 % | 17.3 % | 12-19 % |
    /// | 75+   | 30-40 %| 35.2 % | 30.6 % | 28-40 % |
    /// | sub-65| ~25 %  | 23.2 % | 19.0 % | 15-30 % |
    /// | 33+   | ≤ ~2 % | 3.1 %  | 3.4 %  | ≤ 4 % (retirement follow-up) |
    ///
    /// The generator numbers come from `tools/league-data/make_templates.py`'s
    /// verbatim mirror (400-league Monte-Carlo); the equilibrium numbers from
    /// `tools/balance-harness` `career` (20 leagues × 30 seasons, asserts 6.9a-g).
    /// Where the gate is wider than §8 the reason is named at the band.
    ///
    /// ## Two of the bands are SAMPLING gates, not level gates (task #51)
    ///
    /// The 90+ and 33+ shares are counts of a few dozen men in ONE 1 696-man
    /// league, and an absolute band on a count that small is a coin flip. The
    /// binomial standard error is the whole argument:
    ///
    ///     90+ : p = 0.0177 (leaguegen's 400-league pool) → σ = √(n·p·(1−p)) / n
    ///                                                        = 5.43 / 1696 = 0.32 pp
    ///     33+ : p = 0.024                                  → σ = 6.30 / 1696 = 0.37 pp
    ///
    /// The 90+ number is not a theory: `season=base` has measured 1.8 / 2.0 /
    /// 2.2 / 2.2 / 2.7 % across runs — sample sd 0.33 pp, i.e. exactly the
    /// binomial σ — **before a single week is simulated**, against an absolute
    /// ceiling of 2.5. That band fires on ~1 run in 5 for no reason at all, and
    /// a gate that cries wolf on season 0 teaches a reader to ignore it by
    /// season 3, which is the failure mode the P1 wave was trying to close.
    ///
    /// So both are re-stated as DRIFT gates against this run's own `base`
    /// reading, which removes the generator's roll from the comparison. Two
    /// readings from one run are not independent, but ~half the population has
    /// turned over by season 4, so σ_diff ≈ σ·√2 (0.45 pp for 90+, 0.53 pp for
    /// 33+) and the allowances below are ≈3σ_diff one-sided. Each keeps a hard
    /// ABSOLUTE ceiling as well, set where no amount of sampling can reach: 4 %
    /// of a 1 696-man league is 68 blue chips, double §8's 25-35, which is a
    /// shape failure and not a roll. The historical pathology these gates exist
    /// for — 90+ drifting to 9.5 % — is +7.5 pp of drift, 17σ, and is caught by
    /// the drift form far more sharply than by the absolute one.
    ///
    /// ## The DENOMINATOR moves between `base` and season 4 — read `faPool` (task #51)
    ///
    /// Every share here is over ROSTERED players, which is right (§8 describes
    /// 53-man rosters). But `season=base` is measured at `faPool = 0` — the
    /// generator emits exactly 32×53 bodies and nothing else exists — while by
    /// season 4 the league also carries ~570 unsigned, unretired men that the
    /// reading excludes. The rostered slice is therefore 100 % of the
    /// population at base and ~75 % of it by season 4, and it is the TOP 75 %.
    ///
    /// Rebasing season 4 onto the base's whole-population denominator is an
    /// upper bound on the correction (it assumes no unsigned man clears the
    /// threshold, which is nearly true): 80+ 22.0 % → 16.5 %, 75+ 42.6 % →
    /// 31.9 %, i.e. BOTH land inside band. So most of the apparent 80+ / 75+
    /// drift is the slice narrowing, not extra development — the per-source
    /// ledger says the same thing from the other direction, with every weekly
    /// development pass summing to +0.07 mean OVR a season.
    ///
    /// This is left as a note rather than a change because it is a design
    /// question, not an arithmetic one: whoever calibrates next has to decide
    /// which population §8's bands describe before moving any constant. What is
    /// NOT open is that a constant in `PlayerDevelopmentEngine` cannot be the
    /// answer — `tools/balance-harness` `career` asserts sub-65 ≤ 25 % and
    /// measures 24.94 %, so any shared constant that develops the league less
    /// breaks 6.9d on its first run.
    ///
    /// ## `80+` and `yp0to3` pull against each other — read them as a pair (task #53)
    ///
    /// A 53-man league is 1 696 roster spots and nothing else. Every man the
    /// market prefers because he is young is a man it did not prefer because he
    /// is good, so the two bands sit at opposite ends of ONE dial, and a run can
    /// be pushed off either edge by tuning the same constant in either
    /// direction. The five-iteration sweep behind the shipped calibration
    /// measured exactly that trade (season 4 of a 4-season run):
    ///
    /// | market age discount | 80+ | yp0to3 (seasons 1-3) | mean drift |
    /// |---|---|---|---|
    /// | none (pre-#53)      | 23.2 % | 58 / 54 / 49 | +0.67 |
    /// | 2.0/yr from 26      | 21.6 % | 58 / 56 / 56 | +1.32 |
    /// | 3.2/yr from 25, cap 14 | 19.8 % | 58 / 58 / 59 | +0.80 |
    ///
    /// So the shipped setting is a CHOICE, not a solved optimum: it takes the
    /// 80+ / 75+ / 90+ / 33+ bands green-or-close and pays for it with a
    /// mid-season `yp0to3` that runs 3-4 pp hot. Anyone re-tuning should move
    /// the dial knowing which band they are buying and which they are selling.
    ///
    /// **The residual is not on that dial.** `leaguePot` climbs 73.0 → 78.4
    /// across four seasons while realised headroom (`leaguePot − mean`) goes
    /// 2.1 → 6.2, because the two things that populate the league disagree
    /// about headroom: `LeagueGenerator` hands over a cross-section of nearly
    /// maxed-out veterans (its own `leaguegen` gate 8.hea asserts headroom
    /// ≤ 4.0 and measures 2.04) while `DraftClassBuilder` feeds in classes with
    /// 8-11 points of it. A four-season window sits in the middle of that
    /// transition, so league quality rises whatever the market does — and the
    /// sweep above shows churning HARDER makes it rise faster, since churn is
    /// the mechanism that swaps generator veterans for pipeline rookies. The
    /// balance harness never sees this: its `career` scenario builds its league
    /// from the same pipeline it then runs, so it starts AT the equilibrium
    /// (`leaguePot` 81.6 → 82.3 over 21 seasons) and measures 80+ at 15.8 %.
    /// Closing this properly is a `LeagueGenerator`-vs-`DraftClassBuilder`
    /// headroom reconciliation, not a churn or development constant.
    private static func printPyramidDiagnostics(
        seasonLabel: String,
        rostered: [Player],
        unsignedCount: Int
    ) {
        guard !rostered.isEmpty else { return }
        let total = Double(rostered.count)
        func share(_ predicate: (Player) -> Bool) -> Double {
            Double(rostered.filter(predicate).count) / total * 100
        }
        let ages = rostered.map(\.age).sorted()
        let medianAge = ages[ages.count / 2]
        let meanAge = Double(ages.reduce(0, +)) / total
        let s90 = share { $0.overall >= 90 }
        let s80 = share { $0.overall >= 80 }
        let s75 = share { $0.overall >= 75 }
        let sub65 = share { $0.overall < 65 }
        let a33 = share { $0.age >= 33 }
        let yp03 = share { $0.yearsPro <= 3 }
        // Task #51: the veteran end of the AGE pyramid, which is where the
        // shipped league's excess quality actually sits. The per-source ledger
        // (`DevelopmentSourceDiag`) put every weekly development pass at
        // +0.07 mean OVR a season combined, i.e. nowhere near the ~2 OVR gap to
        // the balance harness — what moves is this share, 6.8 % at t=0 and
        // 23.8 % by season 4, because the men the league sheds average OVR 66
        // at age 26 and the men it keeps average 78 at 31.
        let yp8 = share { $0.yearsPro >= 8 }
        let blueChips = Int((s90 / 100.0 * total).rounded())
        // Task #28: WHICH rooms the 33+ crowd is sitting in. The share alone
        // could not tell "the league ages evenly" from "two position rooms never
        // retire", and it was the second one — quarterbacks and specialists peak
        // to 35/38, so the mid-thirties wall never applied to them at all.
        let old = rostered.filter { $0.age >= 33 }
        let oldQB = old.filter { $0.position == .QB }.count
        let oldSpec = old.filter { $0.position == .K || $0.position == .P }.count
        let oldOL = old.filter {
            [.LT, .LG, .C, .RG, .RT].contains($0.position)
        }.count
        // The first call of a run is `season=base` — keep its 90+ / 33+ readings
        // so every later season is graded against THIS league's own roll rather
        // than against a band the roll alone can miss.
        if seasonLabel == "base" {
            baseline90Plus = s90
            baselineAge33Plus = a33
        }

        // The two drift-graded shares print their drift on the LINE, not only
        // when the gate fires. A ~3σ noise gate that stays quiet is not the
        // same statement as "this share did not move", and the 33+ drift in
        // particular has measured +1.0 / +1.2 / +1.4 pp across runs — real, and
        // sitting just inside the gate. Hiding that behind a green verdict is
        // exactly the reporting failure the drift form was meant to fix.
        func versus(_ value: Double, _ base: Double) -> String {
            guard base > 0, seasonLabel != "base" else { return "" }
            return String(format: " (base %.1f, %+.1fpp)", base, value - base)
        }
        print(String(
            format: "SMOKE: diag pyramid season=%@ 90+=%.1f%%%@ (=%d blue chips) 80+=%.1f%% [12-19] "
                  + "75+=%.1f%% [28-40] sub65=%.1f%% [15-30] "
                  + "ageMed=%d ageMean=%.1f a33plus=%.1f%%%@ (n=%d qb=%d spec=%d ol=%d) "
                  + "yp0to3=%.1f%% [45-55] yp8plus=%.1f%% faPool=%d",
            seasonLabel, s90, versus(s90, baseline90Plus), blueChips, s80, s75, sub65,
            medianAge, meanAge, a33, versus(a33, baselineAge33Plus),
            old.count, oldQB, oldSpec, oldOL, yp03, yp8, unsignedCount
        ))

        var misses: [String] = []
        func band(_ name: String, _ value: Double, _ lo: Double, _ hi: Double) {
            guard value < lo || value > hi else { return }
            misses.append(String(format: "%@=%.1f%% (band %.1f-%.1f)", name, value, lo, hi))
        }
        /// A share whose single-league sampling error is the same size as the
        /// band anyone would write for it: graded as DRIFT from this run's own
        /// `base` reading, with a hard absolute ceiling behind it. See the
        /// binomial arithmetic in the doc comment above.
        func driftBand(
            _ name: String,
            _ value: Double,
            base: Double,
            maxDrift: Double,
            absoluteCeiling: Double,
            absoluteFloor: Double
        ) {
            if value > absoluteCeiling || value < absoluteFloor {
                misses.append(String(
                    format: "%@=%.1f%% (absolute %.1f-%.1f)",
                    name, value, absoluteFloor, absoluteCeiling
                ))
                return
            }
            guard base > 0, seasonLabel != "base" else { return }
            let drift = value - base
            guard drift > maxDrift else { return }
            misses.append(String(
                format: "%@=%.1f%% drift %+.1fpp from base %.1f%% (max %+.1fpp)",
                name, value, drift, base, maxDrift
            ))
        }
        // 90+ : σ = 0.32 pp on one league, so σ_diff ≈ 0.45 pp — the allowance
        // is ≈3σ_diff. The absolute ceiling of 4.0 % (68 blue chips, double
        // §8's 25-35) is the shape failure no roll reaches; the 0.8 % floor is
        // still a level gate, because a league with no blue chips at all is
        // broken however it got there.
        driftBand("90+", s90, base: baseline90Plus,
                  maxDrift: 1.3, absoluteCeiling: 4.0, absoluteFloor: 0.8)
        // 80+ / 75+ : §8 12-16 / 30-40, widened to the interval spanned by the two
        // measured sources (t=0 16.8/35.2 and equilibrium 17.3/30.6) plus sampling.
        // These two count 300-700 men, so their sampling error is ~0.9 pp on a
        // 7 pp band — level gates, as written.
        band("80+", s80, 12.0, 19.0)
        band("75+", s75, 28.0, 40.0)
        // sub-65 : §8 ~25 %. The floor is what catches the pathology this wave
        // fixed — a league with NO depth tier, which is what 7.9 % meant.
        band("sub65", sub65, 15.0, 30.0)
        // 33+ : §8 wants ≤2 %; both feeding sources sit at ~3.1-3.4 %, so the
        // LEVEL is a retirement calibration nobody has run yet and an absolute
        // band on it only ever re-reports that. What this run can own is
        // whether the league AGES on top of that, which is the drift term
        // (σ = 0.37 pp → σ_diff ≈ 0.53 pp, allowance ≈3σ_diff).
        driftBand("a33plus", a33, base: baselineAge33Plus,
                  maxDrift: 1.5, absoluteCeiling: 6.0, absoluteFloor: 0.0)
        band("yp0to3", yp03, 45.0, 55.0)
        if !misses.isEmpty {
            print("SMOKE: ANOMALY season=\(seasonLabel) §8 pyramid bands missed: "
                  + misses.joined(separator: ", ")
                  + " — the 90+ and 33+ verdicts are DRIFT from this run's own"
                  + " `season=base` reading (binomial σ 0.32/0.37pp on one"
                  + " 1696-man league makes an absolute band on either a coin"
                  + " flip — see the doc comment). Read `diag churn` and"
                  + " `diag devsource` together before touching a constant:"
                  + " task #51 ruled out the development passes (camp+focus+"
                  + "breakout+gameXP total +0.07 mean OVR a season) and task"
                  + " #53 fixed the churn asymmetry they pointed at (the market"
                  + " signed on raw `overall` while cutdown day cut on"
                  + " age-discounted `keepScore`). What is LEFT is neither:"
                  + " `leaguePot` climbs 73 → 78 over four seasons because"
                  + " LeagueGenerator ships a cross-section with ~2 points of"
                  + " potential headroom (its own gate 8.hea asserts ≤ 4) while"
                  + " DraftClassBuilder ships classes with 8-11, so the league"
                  + " necessarily gains quality until the intake's equilibrium"
                  + " is reached — and churning HARDER accelerates it, because"
                  + " churn is what swaps generator veterans for pipeline"
                  + " rookies. See the `80+ vs yp0to3` note above")
        }
    }

    /// `season=base` 90+ share for this run — the reference the drift verdict
    /// is taken against. Reset per run by `resetPyramidBaselines`.
    private static var baseline90Plus: Double = 0
    /// `season=base` 33+ age share for this run.
    private static var baselineAge33Plus: Double = 0

    /// Clears the per-run pyramid reference readings. A second `run` in the same
    /// process must not grade its seasons against the previous league's roll.
    private static func resetPyramidBaselines() {
        baseline90Plus = 0
        baselineAge33Plus = 0
    }

    /// Phase-2 §5 stage-6 gate: the league morale distribution must sit in a
    /// healthy band (mean 60-75, p05 ≥ 35) — the activated `LockerRoomEngine`
    /// loop must not spiral a whole league into misery. Motivation-state shares
    /// ride along on the same line because they are the input that moves morale.
    private static func printMoraleDiagnostics(seasonLabel: Int, rostered: [Player]) {
        guard !rostered.isEmpty else { return }
        let morales = rostered.map(\.morale).sorted()
        let mean = Double(morales.reduce(0, +)) / Double(morales.count)
        func percentile(_ fraction: Double) -> Int {
            let index = min(morales.count - 1, max(0, Int(fraction * Double(morales.count))))
            return morales[index]
        }
        var states: [MotivationState: Int] = [:]
        for player in rostered { states[player.motivationState, default: 0] += 1 }
        let total = Double(rostered.count)
        func share(_ state: MotivationState) -> String {
            String(format: "%.0f%%", Double(states[state] ?? 0) / total * 100)
        }
        print(String(
            format: "SMOKE: diag morale season=%d n=%d mean=%.2f p05=%d p25=%d median=%d p95=%d min=%d max=%d",
            seasonLabel, morales.count, mean,
            percentile(0.05), percentile(0.25), percentile(0.50),
            percentile(0.95), morales.first ?? 0, morales.last ?? 0
        ))
        print("SMOKE: diag motivation season=\(seasonLabel) "
              + "driven=\(share(.driven)) focused=\(share(.focused)) "
              + "complacent=\(share(.complacent)) discouraged=\(share(.discouraged))")
    }

    // MARK: - AI stand-in for user roster management

    private static func refillUserRoster(career: Career, context: ModelContext) {
        guard let teamID = career.teamID else { return }
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        var roster = players.filter { $0.teamID == teamID && !$0.isRetired }

        // AI stand-in for the user's cutdown day: trim to the 53-man ceiling.
        // Same keep-score the AI clubs use (`trimAIRosters`), so the harness's
        // franchise is not the one team in the league that cuts every rookie.
        if roster.count > 53 {
            let sorted = roster.sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
            for player in sorted.suffix(roster.count - 53) {
                ChurnDiag.record(ChurnDiag.cut, player)
                player.teamID = nil
                player.annualSalary = 0
                player.contractYearsRemaining = 0
            }
            roster = Array(sorted.prefix(53))
        }

        guard roster.count < 53 else { return }
        var pool = players
            .filter { $0.teamID == nil && !$0.isRetired && !$0.isInjured }
            .sorted { $0.overall > $1.overall }
        while roster.count < 53 {
            let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 3)
            let signing: Player
            if !pool.isEmpty {
                let index = pool.firstIndex { needs.contains($0.position) } ?? 0
                signing = pool.remove(at: index)
                ChurnDiag.record(ChurnDiag.refill, signing)
            } else {
                // Pool dry — street free agent, same as refillAIRosters.
                signing = LeagueGenerator.generatePlayer(
                    position: needs.first ?? .WR,
                    teamID: teamID,
                    depthIndex: 2
                )
                signing.careerID = career.id
                context.insert(signing)
                ChurnDiag.record(ChurnDiag.street, signing)
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

    /// One portrait-uniqueness sweep of the whole league, per completed season.
    ///
    /// Emits the standard `FACEQA:` line (persons / distinct / duplicated /
    /// free / reserve / crossRole) plus a `SMOKE: ANOMALY` line when the pool
    /// runs dry, so a run's output shows exactly WHICH season the library
    /// stopped being able to give everyone their own face — the number that
    /// decides whether more images have to be generated.
    /// Multi-save tripwire: a row that reached the store without a `careerID`
    /// is invisible to every scoped fetch — the sim silently stops seeing it —
    /// so an unstamped insert site must fail the harness, not drift the bands.
    private static func auditCareerScope(seasonLabel: Int, context: ModelContext) {
        let unscoped = CareerScope.debugUnscopedRows(context: context)
        if unscoped.isEmpty {
            print("SMOKE: careerID scope season=\(seasonLabel) OK — every row stamped")
        } else {
            print("SMOKE: ANOMALY season=\(seasonLabel) careerID unscoped rows: \(unscoped) "
                  + "— an insert site is missing its careerID stamp")
        }
    }

    private static func auditFaces(seasonLabel: Int, context: ModelContext) {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        let coaches = (try? context.fetch(FetchDescriptor<Coach>())) ?? []
        let audit = FaceLibrary.shared.debugAuditActiveFaces(
            players: players, coaches: coaches, label: "smoke/season-\(seasonLabel)"
        )
        if audit.duplicated > 0 {
            // `isRegression` is judged per gender (see `FaceLibrary.FaceAudit`):
            // the 35-id female sub-pool empties several seasons before the male
            // half, and within-gender reuse there is capacity, not a defect.
            print("SMOKE: ANOMALY season=\(seasonLabel) faces duplicated=\(audit.duplicated) "
                  + "(f:\(audit.duplicatedFemale)) "
                  + "onTeamDuplicates=\(audit.duplicatedOnTeam) free=\(audit.free) "
                  + "freeFemale=\(audit.freeFemale) — "
                  + (audit.isRegression
                     ? "REGRESSION: the picker shared a portrait with unused same-gender ids available"
                     : "pool exhausted (capacity, not a bug — generate more faces to fix)"))
        }
        let deadCoaches = coaches.filter { $0.isRetired }.count
        let livingFemaleCoaches = coaches.filter { !$0.isRetired && $0.gender == "female" }.count
        print("SMOKE: faces season=\(seasonLabel) livingCoaches=\(coaches.count - deadCoaches) "
              + "livingFemaleCoaches=\(livingFemaleCoaches) "
              + "retiredCoaches=\(deadCoaches) livingPlayers=\(players.filter { !$0.isRetired }.count)")
    }

    /// Position groups for the `salaryByPosition` diag (task #87 / F7). A share
    /// is only readable at group level: "RT" is one roster slot and "OL" is nine,
    /// so the question worth asking is never "what does the right tackle take"
    /// but "what does the offensive line take, against the defensive line".
    private static func salaryGroup(_ position: Position) -> String {
        switch position {
        case .QB:                       return "QB"
        case .RB, .FB:                  return "RB"
        case .WR, .TE:                  return "WR/TE"
        case .LT, .LG, .C, .RG, .RT:    return "OL"
        case .DE, .DT:                  return "DL"
        case .OLB, .MLB:                return "LB"
        case .CB, .FS, .SS:             return "DB"
        case .K, .P:                    return "ST"
        }
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
