import Foundation
import SwiftData

// MARK: - CareerScoped

/// Every population `@Model` in the store carries the id of the save slot
/// (`Career.id`) it belongs to, so two careers can coexist in one SwiftData
/// store without seeing each other's teams, players, staff or history.
///
/// `nil` means "legacy row" — written before this wave existed. `CareerScope`
/// stamps those exactly once, on the first launch after the update.
protocol CareerScoped: AnyObject {
    var careerID: UUID? { get set }
}

extension League: CareerScoped {}
extension Team: CareerScoped {}
extension Player: CareerScoped {}
extension Owner: CareerScoped {}
extension Coach: CareerScoped {}
extension Game: CareerScoped {}
extension Contract: CareerScoped {}
extension Scout: CareerScoped {}
extension CollegeProspect: CareerScoped {}
extension DraftPick: CareerScoped {}
extension DraftEvent: CareerScoped {}
extension DraftPickGrade: CareerScoped {}
extension CareerArcState: CareerScoped {}
extension PlayerSeasonHistory: CareerScoped {}
extension FABid: CareerScoped {}
extension FAVisit: CareerScoped {}
extension FAStorylineEvent: CareerScoped {}
extension Holdout: CareerScoped {}
extension TrainingPlan: CareerScoped {}
extension WorkloadEvent: CareerScoped {}
extension PositionBattle: CareerScoped {}
extension RosterCut: CareerScoped {}
extension OpponentPrepWeek: CareerScoped {}
extension VoluntaryWorkout: CareerScoped {}
extension HardKnocksEvent: CareerScoped {}
extension TradeRecord: CareerScoped {}
extension TeamSeasonArchive: CareerScoped {}

// MARK: - CareerScope

/// Multi-save isolation: stamping, one-time adoption of legacy rows,
/// cascade delete, and the DEBUG population audit.
///
/// `DraftReputation` is deliberately absent from `CareerScoped`: it shipped with
/// a **non-optional** `careerID` in its `init` and has been correct since day
/// one, so it never needs adoption. It IS covered by `cascadeDelete` and
/// `debugCounts`, which handle it explicitly.
///
/// `TeamSeasonArchive` (TODO §5.2) is `CareerScoped` but likewise absent from
/// the adoption pass: the table was born after this wave, so an unstamped row
/// cannot exist in any store. It is covered by `cascadeDelete` and both audits,
/// which is where a forgotten stamp would actually show up.
enum CareerScope {

    /// Schema version written to `Career.schemaBackfillVersion` once a save's
    /// rows have all been stamped.
    static let currentBackfillVersion = 1

    // MARK: - Stamping

    /// Stamps one row. Use at every insert site.
    static func stamp<T: CareerScoped>(_ row: T, careerID: UUID) {
        row.careerID = careerID
    }

    /// Stamps a whole collection (league generation, template import).
    static func stamp<T: CareerScoped>(_ rows: [T], careerID: UUID) {
        for row in rows { row.careerID = careerID }
    }

    // MARK: - Adoption of legacy rows

    /// One-shot, idempotent adoption pass. Runs when at least one `Career` is
    /// still at `schemaBackfillVersion == 0`, i.e. on the first launch after
    /// the `careerID` wave lands on an existing save.
    ///
    /// Attribution: every career's own league graph (`Career.leagueID` ->
    /// `League.teams`) identifies the teams that belong to it, and every row
    /// carrying a team or player id is routed through that map. Rows with no
    /// usable linkage (free agents, prospects, position battles) go to the
    /// *primary* career — the one owning the most teams. A store with a single
    /// career (the only shape that could exist before multi-save) collapses to
    /// "stamp everything with that career's id".
    @discardableResult
    static func adoptLegacyRowsIfNeeded(context: ModelContext) -> String? {
        let careers = (try? context.fetch(FetchDescriptor<Career>())) ?? []
        guard !careers.isEmpty else { return nil }
        // Only a save that predates this wave can own unscoped rows; a career
        // created after it stamps everything at insert time and is born at
        // `currentBackfillVersion`.
        let legacyCareers = careers.filter { $0.schemaBackfillVersion < currentBackfillVersion }
        guard !legacyCareers.isEmpty else { return nil }

        // ---- Build the attribution map -------------------------------------
        let leagues = (try? context.fetch(FetchDescriptor<League>())) ?? []
        let leaguesByID = Dictionary(leagues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var careerIDByLeagueID: [UUID: UUID] = [:]
        var careerIDByTeamID: [UUID: UUID] = [:]
        var careerIDByOwnerID: [UUID: UUID] = [:]
        var teamCountByCareer: [UUID: Int] = [:]

        for career in careers {
            guard let leagueID = career.leagueID, let league = leaguesByID[leagueID] else { continue }
            careerIDByLeagueID[league.id] = career.id
            for team in league.teams {
                careerIDByTeamID[team.id] = career.id
                if let owner = team.owner { careerIDByOwnerID[owner.id] = career.id }
            }
            teamCountByCareer[career.id] = league.teams.count
        }
        // The user's own team is authoritative even if the relationship is stale.
        for career in careers {
            if let teamID = career.teamID { careerIDByTeamID[teamID] = career.id }
        }

        // Rows with no usable team/player linkage (free agents, prospects,
        // position battles) belong to a LEGACY career by definition — a career
        // created after this wave never leaves a row unstamped. So the fallback
        // bucket is picked from `legacyCareers`, never from an already-adopted
        // save; the biggest league wins, ties broken by the deeper dynasty.
        let primary: UUID = {
            if legacyCareers.count == 1 { return legacyCareers[0].id }
            let ranked = legacyCareers.sorted {
                let a = teamCountByCareer[$0.id] ?? 0
                let b = teamCountByCareer[$1.id] ?? 0
                if a != b { return a > b }
                return $0.currentSeason > $1.currentSeason
            }
            return ranked[0].id
        }()
        // Exactly one save needs adopting (the only shape that could exist
        // before multi-save, and the overwhelmingly common one): every unscoped
        // row is its, so the attribution map is not consulted at all.
        let singleCareer: UUID? = legacyCareers.count == 1 ? legacyCareers[0].id : nil

        func team(_ id: UUID?) -> UUID? {
            guard let id else { return nil }
            return careerIDByTeamID[id]
        }

        var log: [String] = []
        func record(_ label: String, _ n: Int) { if n > 0 { log.append("\(label)=\(n)") } }

        // ---- Order matters: players first, so the playerID map is usable ----
        record("League", adopt(League.self, context) { singleCareer ?? careerIDByLeagueID[$0.id] ?? primary })
        record("Team", adopt(Team.self, context) { singleCareer ?? careerIDByTeamID[$0.id] ?? primary })
        record("Player", adopt(Player.self, context) {
            singleCareer ?? team($0.teamID) ?? team($0.draftedByTeamID) ?? primary
        })

        // Player -> career map for the rows that only carry a playerID.
        var careerIDByPlayerID: [UUID: UUID] = [:]
        if singleCareer == nil {
            let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
            for p in players { if let cid = p.careerID { careerIDByPlayerID[p.id] = cid } }
        }
        func player(_ id: UUID?) -> UUID? {
            guard let id else { return nil }
            return careerIDByPlayerID[id]
        }

        record("Owner", adopt(Owner.self, context) { singleCareer ?? careerIDByOwnerID[$0.id] ?? primary })
        record("Coach", adopt(Coach.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("Game", adopt(Game.self, context) {
            singleCareer ?? team($0.homeTeamID) ?? team($0.awayTeamID) ?? primary
        })
        record("Contract", adopt(Contract.self, context) {
            singleCareer ?? team($0.teamID) ?? player($0.playerID) ?? primary
        })
        record("Scout", adopt(Scout.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("CollegeProspect", adopt(CollegeProspect.self, context) { _ in singleCareer ?? primary })
        record("DraftPick", adopt(DraftPick.self, context) {
            singleCareer ?? team($0.currentTeamID) ?? team($0.originalTeamID) ?? primary
        })
        record("DraftEvent", adopt(DraftEvent.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("DraftPickGrade", adopt(DraftPickGrade.self, context) {
            singleCareer ?? team($0.teamID) ?? primary
        })
        record("CareerArcState", adopt(CareerArcState.self, context) {
            singleCareer ?? player($0.playerID) ?? primary
        })
        record("PlayerSeasonHistory", adopt(PlayerSeasonHistory.self, context) {
            singleCareer ?? team($0.teamID) ?? player($0.playerID) ?? primary
        })
        record("FABid", adopt(FABid.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("FAVisit", adopt(FAVisit.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("FAStorylineEvent", adopt(FAStorylineEvent.self, context) {
            singleCareer ?? team($0.teamID) ?? player($0.playerID) ?? primary
        })
        record("Holdout", adopt(Holdout.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("TrainingPlan", adopt(TrainingPlan.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("WorkloadEvent", adopt(WorkloadEvent.self, context) {
            singleCareer ?? player($0.playerID) ?? primary
        })
        record("PositionBattle", adopt(PositionBattle.self, context) {
            singleCareer ?? $0.competitorIDs.compactMap { careerIDByPlayerID[$0] }.first ?? primary
        })
        record("RosterCut", adopt(RosterCut.self, context) { singleCareer ?? team($0.teamID) ?? primary })
        record("OpponentPrepWeek", adopt(OpponentPrepWeek.self, context) {
            singleCareer ?? team($0.teamID) ?? primary
        })
        record("VoluntaryWorkout", adopt(VoluntaryWorkout.self, context) {
            singleCareer ?? team($0.teamID) ?? primary
        })
        record("HardKnocksEvent", adopt(HardKnocksEvent.self, context) {
            singleCareer ?? player($0.playerID) ?? primary
        })
        record("TradeRecord", adopt(TradeRecord.self, context) {
            singleCareer ?? team($0.initiatorTeamID) ?? team($0.partnerTeamID) ?? primary
        })

        for career in legacyCareers { career.schemaBackfillVersion = currentBackfillVersion }
        try? context.save()

        let summary = log.isEmpty
            ? "careerID adoption: nothing to stamp (\(legacyCareers.count) legacy career(s) marked v\(currentBackfillVersion))"
            : "careerID adoption (\(legacyCareers.count)/\(careers.count) legacy career(s), primary=\(primary.uuidString.prefix(8))): "
              + log.joined(separator: " ")
        print("[CareerScope] \(summary)")
        return summary
    }

    /// Fetches every row of `type`, stamps the unscoped ones via `resolve`,
    /// and returns how many were stamped.
    private static func adopt<T: PersistentModel & CareerScoped>(
        _ type: T.Type,
        _ context: ModelContext,
        _ resolve: (T) -> UUID
    ) -> Int {
        guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return 0 }
        var n = 0
        for row in rows where row.careerID == nil {
            row.careerID = resolve(row)
            n += 1
        }
        return n
    }

    // MARK: - Cascade delete

    /// Deletes every row belonging to `careerID` and then the `Career` row
    /// itself. `Career` has no SwiftData relationships, so without this a
    /// deleted save leaves its entire league permanently orphaned in the store.
    ///
    /// Returns per-model deleted counts, newest-first-order irrelevant.
    /// Every predicate below is written against a CONCRETE model type on
    /// purpose. A generic `#Predicate<T> { $0.careerID == cid }` over the
    /// `CareerScoped` requirement compiles but hands SwiftData a
    /// protocol-witness key path it cannot translate to SQL, so it would fail
    /// at runtime instead of at build time.
    @discardableResult
    static func cascadeDelete(career: Career, context: ModelContext) -> [(String, Int)] {
        let cid = career.id
        var counts: [(String, Int)] = []
        var deletes: [() -> Void] = []

        func plan<T: PersistentModel>(_ type: T.Type, _ label: String, _ pred: Predicate<T>) {
            let n = (try? context.fetchCount(FetchDescriptor<T>(predicate: pred))) ?? 0
            guard n > 0 else { return }
            counts.append((label, n))
            // Batch delete: never materialises the rows.
            deletes.append { try? context.delete(model: type, where: pred) }
        }

        // Count EVERY table before deleting anything: `League.teams` is a
        // cascade relationship, so deleting leagues first would zero the team
        // count and make the report lie about what was removed.
        plan(League.self, "League", #Predicate { $0.careerID == cid })
        plan(Team.self, "Team", #Predicate { $0.careerID == cid })
        plan(Player.self, "Player", #Predicate { $0.careerID == cid })
        plan(Owner.self, "Owner", #Predicate { $0.careerID == cid })
        plan(Coach.self, "Coach", #Predicate { $0.careerID == cid })
        plan(Game.self, "Game", #Predicate { $0.careerID == cid })
        plan(Contract.self, "Contract", #Predicate { $0.careerID == cid })
        plan(Scout.self, "Scout", #Predicate { $0.careerID == cid })
        plan(CollegeProspect.self, "CollegeProspect", #Predicate { $0.careerID == cid })
        plan(DraftPick.self, "DraftPick", #Predicate { $0.careerID == cid })
        plan(DraftEvent.self, "DraftEvent", #Predicate { $0.careerID == cid })
        plan(DraftPickGrade.self, "DraftPickGrade", #Predicate { $0.careerID == cid })
        plan(DraftReputation.self, "DraftReputation", #Predicate { $0.careerID == cid })
        plan(CareerArcState.self, "CareerArcState", #Predicate { $0.careerID == cid })
        plan(PlayerSeasonHistory.self, "PlayerSeasonHistory", #Predicate { $0.careerID == cid })
        plan(FABid.self, "FABid", #Predicate { $0.careerID == cid })
        plan(FAVisit.self, "FAVisit", #Predicate { $0.careerID == cid })
        plan(FAStorylineEvent.self, "FAStorylineEvent", #Predicate { $0.careerID == cid })
        plan(Holdout.self, "Holdout", #Predicate { $0.careerID == cid })
        plan(TrainingPlan.self, "TrainingPlan", #Predicate { $0.careerID == cid })
        plan(WorkloadEvent.self, "WorkloadEvent", #Predicate { $0.careerID == cid })
        plan(PositionBattle.self, "PositionBattle", #Predicate { $0.careerID == cid })
        plan(RosterCut.self, "RosterCut", #Predicate { $0.careerID == cid })
        plan(OpponentPrepWeek.self, "OpponentPrepWeek", #Predicate { $0.careerID == cid })
        plan(VoluntaryWorkout.self, "VoluntaryWorkout", #Predicate { $0.careerID == cid })
        plan(HardKnocksEvent.self, "HardKnocksEvent", #Predicate { $0.careerID == cid })
        plan(TradeRecord.self, "TradeRecord", #Predicate { $0.careerID == cid })
        plan(TeamSeasonArchive.self, "TeamSeasonArchive", #Predicate { $0.careerID == cid })

        for run in deletes { run() }

        // Per-career UserDefaults namespace (roster notes, prospect board, …).
        CareerScopedDefaults.purge(careerID: cid)

        context.delete(career)
        counts.append(("Career", 1))
        try? context.save()

        let total = counts.reduce(0) { $0 + $1.1 }
        print("[CareerScope] cascadeDelete \(cid.uuidString.prefix(8)): \(total) rows — "
              + counts.map { "\($0.0)=\($0.1)" }.joined(separator: " "))
        return counts
    }

    /// Human-readable preview of what a cascade delete will remove, for the
    /// confirmation dialog.
    static func deletionSummary(career: Career, context: ModelContext) -> String {
        let cid = career.id
        func n<T: PersistentModel>(_ pred: Predicate<T>) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>(predicate: pred))) ?? 0
        }
        let teams: Int = n(#Predicate<Team> { $0.careerID == cid })
        let players: Int = n(#Predicate<Player> { $0.careerID == cid })
        let coaches: Int = n(#Predicate<Coach> { $0.careerID == cid })
        let scouts: Int = n(#Predicate<Scout> { $0.careerID == cid })
        let games: Int = n(#Predicate<Game> { $0.careerID == cid })
        return "\(teams) teams, \(players) players, \(coaches + scouts) staff and \(games) games"
    }

    // MARK: - DEBUG audit

    #if DEBUG
    /// Rows that reached the store without a `careerID`, per model.
    ///
    /// This is THE tripwire for the whole wave: an unstamped row is invisible
    /// to every scoped fetch — no crash, no log, it simply stops existing for
    /// the engine — so the only way to catch a forgotten insert site is to
    /// count. Empty string means clean.
    static func debugUnscopedRows(context: ModelContext) -> String {
        var parts: [String] = []
        func count<T: PersistentModel>(_ label: String, _ pred: Predicate<T>) {
            let n = (try? context.fetchCount(FetchDescriptor<T>(predicate: pred))) ?? 0
            if n > 0 { parts.append("\(label)=\(n)") }
        }
        count("League", #Predicate<League> { $0.careerID == nil })
        count("Team", #Predicate<Team> { $0.careerID == nil })
        count("Player", #Predicate<Player> { $0.careerID == nil })
        count("Owner", #Predicate<Owner> { $0.careerID == nil })
        count("Coach", #Predicate<Coach> { $0.careerID == nil })
        count("Game", #Predicate<Game> { $0.careerID == nil })
        count("Contract", #Predicate<Contract> { $0.careerID == nil })
        count("Scout", #Predicate<Scout> { $0.careerID == nil })
        count("CollegeProspect", #Predicate<CollegeProspect> { $0.careerID == nil })
        count("DraftPick", #Predicate<DraftPick> { $0.careerID == nil })
        count("DraftEvent", #Predicate<DraftEvent> { $0.careerID == nil })
        count("DraftPickGrade", #Predicate<DraftPickGrade> { $0.careerID == nil })
        count("CareerArcState", #Predicate<CareerArcState> { $0.careerID == nil })
        count("PlayerSeasonHistory", #Predicate<PlayerSeasonHistory> { $0.careerID == nil })
        count("FABid", #Predicate<FABid> { $0.careerID == nil })
        count("FAVisit", #Predicate<FAVisit> { $0.careerID == nil })
        count("FAStorylineEvent", #Predicate<FAStorylineEvent> { $0.careerID == nil })
        count("Holdout", #Predicate<Holdout> { $0.careerID == nil })
        count("TrainingPlan", #Predicate<TrainingPlan> { $0.careerID == nil })
        count("WorkloadEvent", #Predicate<WorkloadEvent> { $0.careerID == nil })
        count("PositionBattle", #Predicate<PositionBattle> { $0.careerID == nil })
        count("RosterCut", #Predicate<RosterCut> { $0.careerID == nil })
        count("OpponentPrepWeek", #Predicate<OpponentPrepWeek> { $0.careerID == nil })
        count("VoluntaryWorkout", #Predicate<VoluntaryWorkout> { $0.careerID == nil })
        count("HardKnocksEvent", #Predicate<HardKnocksEvent> { $0.careerID == nil })
        count("TradeRecord", #Predicate<TradeRecord> { $0.careerID == nil })
        count("TeamSeasonArchive", #Predicate<TeamSeasonArchive> { $0.careerID == nil })
        return parts.joined(separator: " ")
    }

    /// Per-model row counts split by careerID, plus the unscoped (`nil`) count.
    /// The `nil` column is the tripwire: a row born without a careerID is
    /// invisible to every scoped fetch, with no crash and no log, so the audit
    /// asserts on it.
    ///
    /// Printed by the multi-save QA path; grep for `CAREERID-AUDIT`.
    @discardableResult
    static func debugAuditCounts(context: ModelContext, label: String) -> String {
        let careers = (try? context.fetch(FetchDescriptor<Career>())) ?? []
        let order = careers.map(\.id)
        var names: [UUID: String] = [:]
        for c in careers { names[c.id] = "\(c.playerName)/\(c.currentSeason)" }

        var lines: [String] = []
        var nilTotal = 0

        func audit<T: PersistentModel & CareerScoped>(_ type: T.Type, _ label: String) {
            guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
            guard !rows.isEmpty else { return }
            var byCareer: [UUID: Int] = [:]
            var unscoped = 0
            for r in rows {
                if let cid = r.careerID { byCareer[cid, default: 0] += 1 } else { unscoped += 1 }
            }
            nilTotal += unscoped
            var parts = order.map { "\(names[$0] ?? "?")=\(byCareer[$0] ?? 0)" }
            // Rows pointing at a career that no longer exists = leak.
            let orphaned = byCareer.filter { !order.contains($0.key) }.values.reduce(0, +)
            if orphaned > 0 { parts.append("ORPHANED=\(orphaned)") }
            if unscoped > 0 { parts.append("NIL=\(unscoped)") }
            lines.append("  \(label.padding(toLength: 20, withPad: " ", startingAt: 0)) total=\(rows.count)  \(parts.joined(separator: "  "))")
        }

        audit(League.self, "League")
        audit(Team.self, "Team")
        audit(Player.self, "Player")
        audit(Owner.self, "Owner")
        audit(Coach.self, "Coach")
        audit(Game.self, "Game")
        audit(Contract.self, "Contract")
        audit(Scout.self, "Scout")
        audit(CollegeProspect.self, "CollegeProspect")
        audit(DraftPick.self, "DraftPick")
        audit(DraftEvent.self, "DraftEvent")
        audit(DraftPickGrade.self, "DraftPickGrade")
        audit(CareerArcState.self, "CareerArcState")
        audit(PlayerSeasonHistory.self, "PlayerSeasonHistory")
        audit(FABid.self, "FABid")
        audit(FAVisit.self, "FAVisit")
        audit(FAStorylineEvent.self, "FAStorylineEvent")
        audit(Holdout.self, "Holdout")
        audit(TrainingPlan.self, "TrainingPlan")
        audit(WorkloadEvent.self, "WorkloadEvent")
        audit(PositionBattle.self, "PositionBattle")
        audit(RosterCut.self, "RosterCut")
        audit(OpponentPrepWeek.self, "OpponentPrepWeek")
        audit(VoluntaryWorkout.self, "VoluntaryWorkout")
        audit(HardKnocksEvent.self, "HardKnocksEvent")
        audit(TradeRecord.self, "TradeRecord")
        audit(TeamSeasonArchive.self, "TeamSeasonArchive")

        let header = "CAREERID-AUDIT [\(label)] careers=\(careers.count) "
            + careers.map { "\($0.playerName)/\($0.currentSeason)" }.joined(separator: ", ")
        let out = ([header] + lines).joined(separator: "\n")
        print(out)
        if nilTotal > 0 {
            print("CAREERID-AUDIT [\(label)] FAIL: \(nilTotal) unscoped row(s) — an insert site is missing its careerID stamp")
        }
        return out
    }
    #endif
}

// MARK: - CareerScopedDefaults

/// `UserDefaults` keys that hold **career state** rather than app settings
/// (roster notes, prospect board, per-phase "reviewed" flags). Before this
/// wave they were global: creating a second career wiped the first one's
/// notes, and both saves shared one watchlist.
///
/// Every key is suffixed with the career's uuid. `migrateGlobalKeys` moves the
/// legacy un-suffixed values into the adopting career once, so an existing
/// save keeps its notes.
enum CareerScopedDefaults {

    /// Career state, not settings. Order is irrelevant; the set is the contract.
    static let keys: [String] = [
        "scoutsSentToCombine",
        "combineResultsReviewed",
        // Scouting budget already committed to this cycle's combine trip, in
        // thousands. Reset with the other two at the start of every combine.
        "combineTripSpend",
        // Per-prospect scout evaluations (`ScoutEvaluationBudget`): slots spent
        // this draft cycle, thousands of the scouting pot they cost, and the
        // season the two belong to — a stamp from an older cycle reads as zero,
        // which is how the pool refills with the new class.
        "scoutEvaluationsUsed",
        "scoutEvaluationSpend",
        "scoutEvaluationCycle",
        "interviewReportReviewed",
        "rosterEvaluationConfirmed",
        "franchiseTagVisited",
        "rosterNotes",
        "rosterPriorities",
        "rosterOwnAssessments",
        "rosterSortHintSeen",
        "rosterCapScenario",
        "prospectWatchlist",
        "prospectOwnAssessments",
        "prospectCustomBoard",
        "prospectNotes",
        "userProspectGrades",
        "userProspectStars",
        "originalBoardPositions",
        // Legacy: the second workout economy (a 10-cap counter the pro-day
        // screen kept in parallel with `career.workoutsUsed` / 30) is gone, but
        // the key stays on this list so deleting a save still purges the value
        // an old save wrote. Nothing reads it.
        "personalWorkoutsUsed",
        // `WeekAdvancer.sendDraftCycleHeartbeat` — "<season>-<phase>" keys the
        // scouting department's cycle letter has already been mailed for. The
        // in-memory set is a process static and a relaunch therefore re-sent
        // every letter for the phase being re-entered.
        "draftCycleHeartbeatsSent",
        // `RookieClassReveal.flagBase` — the season whose "Rookies Report to
        // Camp" cover is still owed. Career state, and it was missing from this
        // list: the flag is written with a career-scoped key but was never in
        // the purge set, so it outlived the save that armed it and a brand new
        // career could open on the previous one's reveal.
        "rookieClassRevealPendingSeason",
        "scoutingPendingTab",
        "negotiationLockedPlayerIDs",
        // TODO §5.5 — `ContractIncentiveRegistry.defaultsKey`. Listed so a
        // deleted save purges its incentive packages with everything else.
        "contractIncentivePackages",
        // `NegotiationThreadStore.defaultsKey` — the Contact Agent transcripts.
        // Listed for the same reason: a deleted save must take its contract
        // conversations with it.
        "contractNegotiationThreads",
        // `NegotiationLedger.defaultsKey` — the GM's negotiating reputation
        // (lowball insults, broken-off talks, clean signings). Career state, so
        // a deleted save must not hand its hardball reputation to the next one.
        "negotiationHistoryLedger",
        // `ProveItRegistry.defaultsKey` — who bet on himself, and in which
        // league year. Listed so a deleted save cannot hand a new career a
        // bounce-back premium for a contract it never wrote.
        "proveItDealSeasons",
        // `TradeRequestRegistry.defaultsKey` — standing "trade me" demands. Same
        // reason: a new career must not open with somebody else's disgruntled
        // star already on the block.
        "tradeRequestSeasons",
        // `PayCutRegistry` — who has already answered the pay-cut question this
        // league year, and whose "then release me" has already been charged its
        // morale. Career state: a new save must not open with the previous
        // one's veterans already settled, or unable to be asked at all.
        "payCutSettledSeasons",
        "payCutReleaseDemandSeasons",
        // `CommittedCapLedger.defaultsKey` — cap the user has promised through
        // outstanding free-agency offers but not yet spent. Career money state,
        // so a deleted save must not hand a new career somebody else's
        // commitments and silently shrink its cap room.
        "committedCapReservations",
    ]

    /// Every read of a key above goes through `CareerScopedDefaults.scopedKey`
    /// (see `CareerScopedStorage.swift`) or `@CareerScopedStorage`.
    ///
    /// **Nothing may read these bare.** `migrateGlobalKeys` moves the legacy
    /// global value onto the scoped key and then DELETES the global, so a bare
    /// read is not merely unscoped — it returns nothing at all from the first
    /// launch after this wave, which is how the roster notes, prospect board,
    /// watchlist and priorities all read as empty. `@AppStorage` cannot be used
    /// on these keys for the same reason: its key is fixed at declaration time,
    /// when the open career is not yet known.

    /// `"rosterNotes"` -> `"rosterNotes.<career-uuid>"`.
    static func key(_ base: String, careerID: UUID) -> String {
        "\(base).\(careerID.uuidString)"
    }

    /// Drops every scoped value for a deleted save.
    static func purge(careerID: UUID) {
        let defaults = UserDefaults.standard
        for base in keys {
            defaults.removeObject(forKey: key(base, careerID: careerID))
        }
    }

    // MARK: - Per-prospect user data

    /// Scoped keys holding an ORDERED list of prospect uuid strings. Order is
    /// meaning here (`prospectCustomBoard` IS the board), so these are decoded
    /// as `[String]` and filtered in place rather than round-tripped through a
    /// dictionary.
    private static let prospectIDListKeys = [
        "prospectWatchlist",
        "prospectCustomBoard",
        "userProspectStars",
    ]

    /// Scoped keys holding a dictionary KEYED by prospect uuid string. The value
    /// shape differs per key (`String` grades and notes, `Int` board slots), so
    /// the filter goes through `JSONSerialization` and stays shape-agnostic.
    private static let prospectIDMapKeys = [
        "prospectNotes",
        "prospectOwnAssessments",
        "userProspectGrades",
        "originalBoardPositions",
    ]

    /// Drops every per-prospect entry whose prospect no longer exists.
    ///
    /// The seven stores above are keyed by `CollegeProspect.id` and **nothing
    /// ever pruned them**. A draft class is ~350 men and every one of them stops
    /// existing at the season rollover (`WeekAdvancer.purgeStaleSeasonData`
    /// deletes the rows), so each concluded cycle left behind up to 350 dead
    /// uuids per store — for the life of the save, growing without bound. The
    /// Big Board pruned exactly one of them (`prospectCustomBoard`, in
    /// `syncBoardOrder`) and only while that screen was open, which is why the
    /// board order was the one that looked fine.
    ///
    /// Called from the rollover, immediately after the prospect rows are
    /// deleted, with the ids that survive — an empty set today, but expressed as
    /// "keep what still exists" so a future partial purge cannot orphan a live
    /// prospect's notes.
    ///
    /// - Returns: how many entries were dropped (diagnostics only).
    @discardableResult
    static func pruneProspectUserData(keeping liveProspectIDs: Set<UUID>, careerID: UUID) -> Int {
        let defaults = UserDefaults.standard
        let live = Set(liveProspectIDs.map(\.uuidString))
        var dropped = 0

        func write(_ json: String?, to scopedKey: String) {
            if let json {
                defaults.set(json, forKey: scopedKey)
            } else {
                defaults.removeObject(forKey: scopedKey)
            }
        }

        for base in prospectIDListKeys {
            let scoped = key(base, careerID: careerID)
            guard let raw = defaults.string(forKey: scoped),
                  let ids = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)),
                  !ids.isEmpty
            else { continue }
            let kept = ids.filter { live.contains($0) }
            guard kept.count != ids.count else { continue }
            dropped += ids.count - kept.count
            if kept.isEmpty {
                write(nil, to: scoped)
            } else if let data = try? JSONEncoder().encode(kept) {
                write(String(decoding: data, as: UTF8.self), to: scoped)
            }
        }

        for base in prospectIDMapKeys {
            let scoped = key(base, careerID: careerID)
            guard let raw = defaults.string(forKey: scoped),
                  let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)),
                  let dict = object as? [String: Any],
                  !dict.isEmpty
            else { continue }
            let kept = dict.filter { live.contains($0.key) }
            guard kept.count != dict.count else { continue }
            dropped += dict.count - kept.count
            if kept.isEmpty {
                write(nil, to: scoped)
            } else if let data = try? JSONSerialization.data(withJSONObject: kept) {
                write(String(decoding: data, as: UTF8.self), to: scoped)
            }
        }

        guard dropped > 0 else { return 0 }
        // Both observers, for the two families of reader: `@CareerScopedStorage`
        // views (notes, assessments, board) and `UserProspectGradeStore` views
        // (grades, stars, original slots).
        CareerScopedDefaultsStore.shared.notifyChanged()
        UserProspectGradeStore.notifyPruned()
        return dropped
    }

    /// Hands the legacy global values to `careerID` (once), then clears the
    /// globals so a second career starts from defaults instead of inheriting.
    static func migrateGlobalKeys(into careerID: UUID) {
        let defaults = UserDefaults.standard
        let flag = "careerScopedDefaultsMigrated.\(careerID.uuidString)"
        guard !defaults.bool(forKey: flag) else { return }
        for base in keys {
            guard let value = defaults.object(forKey: base) else { continue }
            let scoped = key(base, careerID: careerID)
            if defaults.object(forKey: scoped) == nil {
                defaults.set(value, forKey: scoped)
            }
            defaults.removeObject(forKey: base)
        }
        defaults.set(true, forKey: flag)
    }
}
