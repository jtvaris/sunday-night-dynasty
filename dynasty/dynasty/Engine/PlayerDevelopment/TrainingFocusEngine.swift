import Foundation
import SwiftData

// MARK: - Training Focus Area (R26)

/// A weekly per-player training emphasis. Each area maps to a small set of
/// attributes relevant to the player's position; the weekly focus tick can
/// bump one of them by +1 (capped by the player's potential ceiling).
enum TrainingFocusArea: String, Codable, CaseIterable, Identifiable {
    case accuracy        = "Accuracy"
    case armTalent       = "Arm Talent"
    case pocketWork      = "Pocket Work"
    case ballCarrying    = "Ball Carrying"
    case receiving       = "Receiving"
    case routeRunning    = "Route Running"
    case hands           = "Hands"
    case runBlocking     = "Run Blocking"
    case passProtection  = "Pass Protection"
    case passRush        = "Pass Rush"
    case runDefense      = "Run Defense"
    case coverage        = "Coverage"
    case ballSkills      = "Ball Skills"
    case tackling        = "Tackling"
    case kickingCraft    = "Kicking Craft"
    case conditioning    = "Conditioning"
    case filmStudy       = "Film Study"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// SF Symbol used in focus chips and report rows.
    var icon: String {
        switch self {
        case .accuracy, .armTalent, .pocketWork:      return "target"
        case .ballCarrying, .receiving:               return "figure.run"
        case .routeRunning, .hands:                   return "point.topleft.down.curvedto.point.bottomright.up"
        case .runBlocking, .passProtection:           return "shield.lefthalf.filled"
        case .passRush, .runDefense, .tackling:       return "bolt.fill"
        case .coverage, .ballSkills:                  return "eye.fill"
        case .kickingCraft:                           return "figure.kickboxing"
        case .conditioning:                           return "figure.strengthtraining.traditional"
        case .filmStudy:                              return "play.rectangle.fill"
        }
    }

    /// The focus areas that make sense for a given position.
    /// Every position also gets the universal Conditioning / Film Study drills.
    static func areas(for position: Position) -> [TrainingFocusArea] {
        let specific: [TrainingFocusArea]
        switch position {
        case .QB:                       specific = [.accuracy, .armTalent, .pocketWork]
        case .RB, .FB:                  specific = [.ballCarrying, .receiving]
        case .WR:                       specific = [.routeRunning, .hands]
        case .TE:                       specific = [.routeRunning, .hands, .runBlocking]
        case .LT, .LG, .C, .RG, .RT:    specific = [.passProtection, .runBlocking]
        case .DE, .DT:                  specific = [.passRush, .runDefense]
        case .OLB, .MLB:                specific = [.tackling, .coverage, .passRush]
        case .CB, .FS, .SS:             specific = [.coverage, .ballSkills]
        case .K, .P:                    specific = [.kickingCraft]
        }
        return specific + [.conditioning, .filmStudy]
    }

    /// Default auto-pick: the first position-specific area.
    ///
    /// Kept for callers that have no club or player in hand. AI assignment goes
    /// through ``autoArea(for:teamID:playerID:)`` instead — see why there.
    static func defaultArea(for position: Position) -> TrainingFocusArea {
        areas(for: position).first ?? .filmStudy
    }

    /// The area an AI club puts a given young player on.
    ///
    /// F-24's secondary defect: every AI club called `defaultArea` and so always
    /// took the FIRST listed area for the position. Thirty-one clubs developed
    /// every quarterback they ever drafted along one identical path.
    ///
    /// The pick is now drawn deterministically from the `(team, player)` pair,
    /// using the same seed machinery as the perception fog. That makes it
    /// **club-shaped and stable** — one room's idea of what this kid needs, the
    /// same answer every week for as long as he is there — which is D3's
    /// "coherent plan that can be wrong" rather than a die rolled per tick.
    ///
    /// **Honest limit**: this is not SITUATIONAL. A genuinely situational pick
    /// would develop the attribute the player is worst at, and there is no
    /// area→attribute reader to ask — the mapping lives inside the private
    /// `bump` switch keyed on the position-attribute enum. Exposing one is the
    /// better fix and is left open.
    static func autoArea(
        for position: Position,
        teamID: UUID?,
        playerID: UUID
    ) -> TrainingFocusArea {
        let specific = areas(for: position).filter { $0 != .conditioning && $0 != .filmStudy }
        guard !specific.isEmpty else { return defaultArea(for: position) }
        guard let teamID else { return specific[0] }
        var rng = SeededLeagueRandom(
            seed: AIDraftPerception.pairSeed(teamID: teamID, prospectID: playerID)
        )
        return specific[Int.random(in: 0..<specific.count, using: &rng)]
    }
}

// MARK: - TrainingFocusEngine (R26)

/// Weekly micro-development driven by per-player training focus.
///
/// Rules:
/// - Up to 3 players per team hold a focus slot (user picks; AI auto-picks
///   its best young players so the user gains no free edge).
/// - Each week a focused player rolls one chance at +1 to a random attribute
///   inside the focus area, capped by the same potential ceiling the
///   offseason development engine uses (`truePotential * 0.65 + 35`).
/// - The gain chance scales DOWN with age (pre-peak > peak > post-peak) and
///   up/down with work ethic, position-coach quality, and morale — so
///   focusing youngsters is clearly the best use of the slots.
/// - This layer is additive micro-development; it does not touch the
///   existing offseason `PlayerDevelopmentEngine` pipeline.
enum TrainingFocusEngine {

    // MARK: - Tuning

    /// Maximum simultaneous focus players per team.
    static let maxFocusPlayersPerTeam = 3

    /// Hard cap of breakout events per team per season.
    static let maxBreakoutsPerSeason = 2

    /// Weekly league-wide roll for one breakout candidate per team
    /// (~1 expected breakout per team per season, capped at 2).
    private static let weeklyBreakoutChance = 0.06

    /// Breakouts consumed per "season|team" key. Write-through cache of the
    /// Career-persisted counts (`Career.seasonBreakoutCounts`) so the
    /// 2/season/team cap survives app restarts.
    private static var breakoutCounts: [String: Int] = [:]

    /// teamID → careerID cache for multi-save stores, so the career lookup's
    /// league walk runs at most once per team.
    private static var careerIDByTeamID: [UUID: UUID] = [:]

    /// Both caches above are process-global and keyed by ids that only mean
    /// something inside one save, so a career switch must empty them.
    /// Called from `WeekAdvancer.resetProcessStateForCareerSwitch()`.
    static func resetProcessState() {
        breakoutCounts = [:]
        careerIDByTeamID = [:]
    }

    // MARK: - Breakout Cap Persistence

    /// Season-scoped per-team breakout usage, JSON-persisted on the Career
    /// (`Career.breakoutCountsData`). The payload carries its season: when
    /// the stored season differs from the season being played, the engine
    /// treats it as empty and overwrites — a new season therefore starts
    /// from zero automatically, with no explicit `startNewSeason` hook
    /// (covers the R32 season-reset audit for this counter).
    nonisolated struct SeasonBreakoutCounts: Codable {
        /// Season year the counts belong to; any other season reads as empty.
        var season: Int
        /// `teamID.uuidString` → breakouts consumed this season.
        var counts: [String: Int]
    }

    // MARK: - Result Type

    /// One concrete attribute gain produced by the weekly focus tick.
    struct FocusGain {
        let playerID: UUID
        let playerName: String
        let position: Position
        let area: TrainingFocusArea
        let attributeName: String
        let points: Int
        /// True when high morale (≥ 80) boosted this week's roll.
        let moraleBoosted: Bool
    }

    // MARK: - Weekly Tick

    /// Runs the weekly focus roll for a single team's roster.
    /// Injured and holdout players never gain; the 3-slot cap is enforced
    /// here too in case stale focus flags linger after trades/cuts.
    ///
    /// §5.3: this is also where position conversions land. The weekly pass
    /// runs for all 32 clubs, which is exactly the coverage a conversion needs
    /// — the familiarity itself is banked by the in-season and offseason
    /// training passes, and this only decides when a man has banked enough to
    /// change positions for good.
    ///
    /// The conversions this tick completed are handed back through `conversions`
    /// rather than the return value, so the existing `[FocusGain]` contract (and
    /// every caller that only wants the attribute bumps) is untouched. A
    /// completed conversion is a permanent, visible change to a man's job title
    /// — `WeekAdvancer` publishes each one as league news — so it must not stay
    /// a silent side effect of a development pass.
    static func applyWeeklyFocusTick(
        roster: [Player],
        coaches: [Coach],
        conversions: inout [VersatilityDevelopmentEngine.CompletedConversion]
    ) -> [FocusGain] {
        conversions.append(contentsOf:
            VersatilityDevelopmentEngine.tickConversions(roster: roster, coaches: coaches))

        var gains: [FocusGain] = []

        let focused = roster
            .filter { $0.trainingFocusArea != nil && !$0.isInjured && !$0.isHoldingOut }
            .sorted { $0.age < $1.age }
            .prefix(maxFocusPlayersPerTeam)

        for player in focused {
            guard let area = player.trainingFocusArea else { continue }
            let chance = weeklyGainChance(player: player, coaches: coaches)
            guard Double.random(in: 0.0..<1.0) < chance else { continue }

            let ceiling = potentialCeiling(for: player)
            if let attributeName = applyFocusPoint(player: player, area: area, ceiling: ceiling) {
                gains.append(FocusGain(
                    playerID: player.id,
                    playerName: player.fullName,
                    position: player.position,
                    area: area,
                    attributeName: attributeName,
                    points: 1,
                    moraleBoosted: player.morale >= 80
                ))
            }
        }
        return gains
    }

    /// Convenience overload for callers with nothing to announce (the balance
    /// harness, and any future pass that only wants the attribute bumps).
    /// Identical behaviour — the conversions still run, they are just dropped.
    static func applyWeeklyFocusTick(roster: [Player], coaches: [Coach]) -> [FocusGain] {
        var ignored: [VersatilityDevelopmentEngine.CompletedConversion] = []
        return applyWeeklyFocusTick(roster: roster, coaches: coaches, conversions: &ignored)
    }

    /// Probability (0-0.6) that a focused player converts this week's extra
    /// reps into a +1 attribute point. Age is the dominant factor.
    static func weeklyGainChance(player: Player, coaches: [Coach]) -> Double {
        let peak = player.position.peakAgeRange
        let base: Double
        if player.age < peak.lowerBound {
            base = 0.32          // pre-peak: focus reps convert well
        } else if player.age <= peak.upperBound {
            base = 0.18          // at peak: maintenance-plus
        } else {
            base = 0.06          // post-peak: rare, mostly wasted slot
        }

        // Work ethic 1-99 → 0.75-1.25
        let workEthicFactor = 0.75 + Double(player.mental.workEthic) / 99.0 * 0.5

        // Position coach (coordinator fallback) sharpens the drills: ±15 %.
        let coach = coaches.first {
            CoachingEngine.positionRoleMatch(coachRole: $0.role, playerPosition: player.position)
        } ?? coaches.first {
            ($0.role == .offensiveCoordinator && player.position.side == .offense) ||
            ($0.role == .defensiveCoordinator && player.position.side == .defense)
        }
        let coachDev = Double(coach?.playerDevelopment ?? 50)
        let coachFactor = 1.0 + (coachDev - 50.0) / 99.0 * 0.3

        var chance = base * workEthicFactor * coachFactor

        // R18/R25 tie-in: locker-room mood moves the needle a little.
        if player.morale >= 80 {
            chance *= 1.15
        } else if player.morale <= 35 {
            chance *= 0.7
        }

        // Phase 2 (plan §2.3): the offseason motivation state carries into the
        // weekly reps — ×1.20 driven … ×0.70 discouraged. It COMPOSES with the
        // morale factor above rather than replacing it (morale is this week's
        // mood, motivation is the season's headspace), and the 0.6 hard cap is
        // unchanged so a driven high-work-ethic youngster still cannot exceed
        // the designed ceiling.
        chance *= player.motivationState.focusGainMultiplier

        return min(0.6, chance)
    }

    // MARK: - AI Auto-Focus

    /// AI counterpart of the user's manual selection: keeps up to 3 focus
    /// slots filled with the team's best young players (highest potential,
    /// then youngest). Recycles slots held by players past their peak.
    ///
    /// §5.3: also the AI's conversion desk. This is the only weekly hook that
    /// runs for the other 31 clubs and NOT for the user's, which is what a
    /// conversion decision needs — the user makes his own on the development
    /// screen, and an AI pass that also moved his players would be reaching
    /// over his shoulder.
    /// ## F-24 / D3: the desk no longer reads a number the user is denied
    ///
    /// This sorted on `truePotential` — the hidden ceiling the engine uses to
    /// develop the player years later, and the exact number
    /// `DevelopmentReportView` tells the user it will not show him. Every AI
    /// club therefore picked the three genuinely-highest-ceiling youngsters on
    /// its roster, every week, for all 31 clubs, while the user worked off the
    /// noisy `assessedPotential` label. D3 closes that as "pure information
    /// unrealism".
    ///
    /// The read now goes through `AIDraftPerception.ownRosterLens` — the same
    /// deterministic, persona-shaped fog the draft already uses, narrowed for
    /// familiarity (a club knows its own players far better than a prospect;
    /// see `ownRosterSigmaScale`). Consequences that are the POINT, not side
    /// effects: a club can spend a season developing the wrong kid, two clubs
    /// can rate the same player differently, and the same club is wrong about
    /// the same man consistently rather than re-rolling every week.
    ///
    /// This is deliberately a fog on the READ only. The queue's note is right
    /// that the system is otherwise good — symmetric, weekly, all 31 clubs,
    /// value reaching the simulator through real attributes — so nothing about
    /// how the focus works is weakened.
    static func autoAssignFocus(roster: [Player]) {
        // No staff in hand here (the caller keeps coaches for the focus tick),
        // which only costs the offer's week estimate — a display field the AI
        // never reads.
        VersatilityDevelopmentEngine.aiConsiderConversion(roster: roster, coaches: [])

        // Free slots wasted on post-peak players.
        for player in roster where player.trainingFocusArea != nil
            && player.age > player.position.peakAgeRange.upperBound {
            player.trainingFocusAreaRaw = nil
        }

        var focused = roster.filter { $0.trainingFocusArea != nil }

        // The club's own read on its own men. Built once per pass rather than
        // per comparison: `read` is pure, but a sort calls it O(n log n) times
        // and the lens lookup goes through `GMPersona`.
        let teamID = roster.first(where: { $0.teamID != nil })?.teamID
        let lens = teamID.map { AIDraftPerception.ownRosterLens(forTeam: $0) }
        let perceivedCeiling: (Player) -> Double = { player in
            guard let teamID, let lens else { return Double(player.truePotential) }
            return AIDraftPerception.read(
                teamID: teamID,
                prospectID: player.id,
                trueOverall: player.overall,
                truePotential: player.truePotential,
                lens: lens
            ).potential
        }
        let ceilingByPlayer = Dictionary(
            roster.map { ($0.id, perceivedCeiling($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let ceiling: (Player) -> Double = { ceilingByPlayer[$0.id] ?? Double($0.truePotential) }

        // Trim overflow (e.g. an already-focused player arrived via trade).
        if focused.count > maxFocusPlayersPerTeam {
            let keep = focused
                .sorted { ceiling($0) > ceiling($1) }
                .prefix(maxFocusPlayersPerTeam)
            let keepIDs = Set(keep.map(\.id))
            for player in focused where !keepIDs.contains(player.id) {
                player.trainingFocusAreaRaw = nil
            }
            focused = Array(keep)
        }

        guard focused.count < maxFocusPlayersPerTeam else { return }

        let candidates = roster
            .filter {
                $0.trainingFocusArea == nil
                && !$0.isInjured && !$0.isHoldingOut
                && $0.yearsPro <= 3
                && $0.age < $0.position.peakAgeRange.upperBound
            }
            .sorted {
                if ceiling($0) != ceiling($1) {
                    return ceiling($0) > ceiling($1)
                }
                return $0.age < $1.age
            }

        for player in candidates.prefix(maxFocusPlayersPerTeam - focused.count) {
            player.trainingFocusAreaRaw = TrainingFocusArea
                .autoArea(for: player.position, teamID: teamID, playerID: player.id)
                .rawValue
        }
    }

    // MARK: - Breakout Events

    /// Rare, newsworthy leap for a high-potential youngster: a one-time
    /// 4-6 point jump inside his position skill set (plus +1 awareness).
    /// Hard-capped at `maxBreakoutsPerSeason` per team per season.
    static func rollBreakout(
        roster: [Player],
        season: Int,
        teamID: UUID
    ) -> (player: Player, pointsGained: Int)? {
        let key = "\(season)|\(teamID.uuidString)"
        let career = resolveCareer(roster: roster, teamID: teamID)
        hydrateBreakoutCount(from: career, season: season, teamID: teamID)
        guard breakoutCounts[key, default: 0] < maxBreakoutsPerSeason else { return nil }
        guard Double.random(in: 0.0..<1.0) < weeklyBreakoutChance else { return nil }

        let candidates = roster.filter {
            $0.yearsPro <= 3 && $0.age <= 25
            && $0.truePotential >= 82
            && $0.morale >= 60
            && !$0.isInjured && !$0.isHoldingOut
        }
        guard let star = candidates.randomElement() else { return nil }

        let ceiling = potentialCeiling(for: star)
        let attempts = Int.random(in: 4...6)
        var applied = 0
        let areaPool = TrainingFocusArea.areas(for: star.position).dropLast(2) // position-specific only
        for _ in 0..<attempts {
            let area = star.trainingFocusArea ?? areaPool.randomElement() ?? .filmStudy
            if applyFocusPoint(player: star, area: area, ceiling: ceiling) != nil {
                applied += 1
            }
        }
        // The game slows down for him — small awareness bump on top.
        if star.mental.awareness < min(99, ceiling) {
            star.mental.awareness += 1
            applied += 1
        }
        guard applied > 0 else { return nil }

        breakoutCounts[key, default: 0] += 1
        persistBreakoutCount(
            to: career,
            season: season,
            teamID: teamID,
            count: breakoutCounts[key, default: 0]
        )
        return (star, applied)
    }

    // MARK: - Breakout Cap Persistence Helpers

    /// Finds the `Career` that owns this roster's league so the breakout cap
    /// can be persisted. Fast path: a store with a single career (the normal
    /// case, and the R32 smoke-test's isolated store). With multiple save
    /// slots in one store the career is matched through its league's team
    /// list (`career.leagueID` → `League.teams`), cached per teamID.
    /// Returns `nil` when the roster isn't in a SwiftData context (unit-style
    /// callers) — the cap then falls back to in-memory-only, as before.
    private static func resolveCareer(roster: [Player], teamID: UUID) -> Career? {
        guard let context = roster.first?.modelContext else { return nil }
        let careers = (try? context.fetch(FetchDescriptor<Career>())) ?? []
        guard careers.count > 1 else { return careers.first }

        if let cachedID = careerIDByTeamID[teamID],
           let cached = careers.first(where: { $0.id == cachedID }) {
            return cached
        }
        // Every roster row names its own save now, so the league walk this used
        // to do (career.leagueID -> League.teams) collapses to one lookup.
        if let cid = roster.first(where: { $0.careerID != nil })?.careerID,
           let career = careers.first(where: { $0.id == cid }) {
            careerIDByTeamID[teamID] = career.id
            return career
        }
        return nil
    }

    /// Merges the persisted count for this team+season into the in-memory
    /// cache (max-wins, so neither a restart nor an unsaved context can
    /// lower an already-consumed count). Idempotent — safe to call weekly.
    private static func hydrateBreakoutCount(from career: Career?, season: Int, teamID: UUID) {
        guard let stored = career?.seasonBreakoutCounts,
              stored.season == season,
              let persisted = stored.counts[teamID.uuidString] else { return }
        let key = "\(season)|\(teamID.uuidString)"
        breakoutCounts[key] = max(breakoutCounts[key, default: 0], persisted)
    }

    /// Writes the new count through to the Career. A payload from an older
    /// season is discarded wholesale — the season rollover reset. The caller
    /// (WeekAdvancer's weekly tick) saves the model context.
    private static func persistBreakoutCount(to career: Career?, season: Int, teamID: UUID, count: Int) {
        guard let career else { return }
        var stored = career.seasonBreakoutCounts ?? SeasonBreakoutCounts(season: season, counts: [:])
        if stored.season != season {
            stored = SeasonBreakoutCounts(season: season, counts: [:])
        }
        stored.counts[teamID.uuidString] = count
        career.seasonBreakoutCounts = stored
    }

    // MARK: - Attribute Application

    /// Shared ceiling formula — delegates to the single source of truth in
    /// `PlayerDevelopmentEngine.developmentCeiling(for:)` so the two engines
    /// can never drift apart.
    static func potentialCeiling(for player: Player) -> Int {
        PlayerDevelopmentEngine.developmentCeiling(for: player)
    }

    /// Applies a single +1 point inside the given focus area, respecting the
    /// potential ceiling. Returns the display name of the bumped attribute,
    /// or nil when every attribute in the area is already capped (or the
    /// area doesn't match the player's position kind).
    @discardableResult
    static func applyFocusPoint(player: Player, area: TrainingFocusArea, ceiling: Int) -> String? {
        let cap = min(99, ceiling)

        // Universal drills first — they work for every position.
        switch area {
        case .conditioning:
            var physical = player.physical
            let options: [(String, WritableKeyPath<PhysicalAttributes, Int>)] = [
                ("Speed", \.speed), ("Acceleration", \.acceleration),
                ("Agility", \.agility), ("Stamina", \.stamina)
            ]
            guard let name = bump(&physical, options, cap: cap) else { return nil }
            player.physical = physical
            return name
        case .filmStudy:
            var mental = player.mental
            let options: [(String, WritableKeyPath<MentalAttributes, Int>)] = [
                ("Awareness", \.awareness), ("Decision Making", \.decisionMaking)
            ]
            guard let name = bump(&mental, options, cap: cap) else { return nil }
            player.mental = mental
            return name
        default:
            break
        }

        // Position-specific drills.
        switch player.positionAttributes {
        case .quarterback(var qb):
            let options: [(String, WritableKeyPath<QBAttributes, Int>)]
            switch area {
            case .accuracy:
                options = [("Short Accuracy", \.accuracyShort),
                           ("Mid Accuracy", \.accuracyMid),
                           ("Deep Accuracy", \.accuracyDeep)]
            case .armTalent:
                options = [("Arm Strength", \.armStrength)]
            case .pocketWork:
                options = [("Pocket Presence", \.pocketPresence), ("Scrambling", \.scrambling)]
            default: return nil
            }
            guard let name = bump(&qb, options, cap: cap) else { return nil }
            player.positionAttributes = .quarterback(qb)
            return name

        case .runningBack(var rb):
            let options: [(String, WritableKeyPath<RBAttributes, Int>)]
            switch area {
            case .ballCarrying:
                options = [("Vision", \.vision), ("Elusiveness", \.elusiveness),
                           ("Break Tackle", \.breakTackle)]
            case .receiving:
                options = [("Receiving", \.receiving)]
            default: return nil
            }
            guard let name = bump(&rb, options, cap: cap) else { return nil }
            player.positionAttributes = .runningBack(rb)
            return name

        case .wideReceiver(var wr):
            let options: [(String, WritableKeyPath<WRAttributes, Int>)]
            switch area {
            case .routeRunning:
                options = [("Route Running", \.routeRunning), ("Release", \.release)]
            case .hands:
                options = [("Catching", \.catching), ("Spectacular Catch", \.spectacularCatch)]
            default: return nil
            }
            guard let name = bump(&wr, options, cap: cap) else { return nil }
            player.positionAttributes = .wideReceiver(wr)
            return name

        case .tightEnd(var te):
            let options: [(String, WritableKeyPath<TEAttributes, Int>)]
            switch area {
            case .routeRunning:
                options = [("Route Running", \.routeRunning)]
            case .hands:
                options = [("Catching", \.catching)]
            case .runBlocking:
                options = [("Blocking", \.blocking)]
            default: return nil
            }
            guard let name = bump(&te, options, cap: cap) else { return nil }
            player.positionAttributes = .tightEnd(te)
            return name

        case .offensiveLine(var ol):
            let options: [(String, WritableKeyPath<OLAttributes, Int>)]
            switch area {
            case .passProtection:
                options = [("Pass Block", \.passBlock), ("Anchor", \.anchor)]
            case .runBlocking:
                options = [("Run Block", \.runBlock), ("Pull", \.pull)]
            default: return nil
            }
            guard let name = bump(&ol, options, cap: cap) else { return nil }
            player.positionAttributes = .offensiveLine(ol)
            return name

        case .defensiveLine(var dl):
            let options: [(String, WritableKeyPath<DLAttributes, Int>)]
            switch area {
            case .passRush:
                options = [("Pass Rush", \.passRush), ("Finesse Moves", \.finesseMoves)]
            case .runDefense:
                options = [("Block Shedding", \.blockShedding), ("Power Moves", \.powerMoves)]
            default: return nil
            }
            guard let name = bump(&dl, options, cap: cap) else { return nil }
            player.positionAttributes = .defensiveLine(dl)
            return name

        case .linebacker(var lb):
            let options: [(String, WritableKeyPath<LBAttributes, Int>)]
            switch area {
            case .tackling:
                options = [("Tackling", \.tackling)]
            case .coverage:
                options = [("Zone Coverage", \.zoneCoverage), ("Man Coverage", \.manCoverage)]
            case .passRush:
                options = [("Blitzing", \.blitzing)]
            default: return nil
            }
            guard let name = bump(&lb, options, cap: cap) else { return nil }
            player.positionAttributes = .linebacker(lb)
            return name

        case .defensiveBack(var db):
            let options: [(String, WritableKeyPath<DBAttributes, Int>)]
            switch area {
            case .coverage:
                options = [("Man Coverage", \.manCoverage),
                           ("Zone Coverage", \.zoneCoverage),
                           ("Press", \.press)]
            case .ballSkills:
                options = [("Ball Skills", \.ballSkills)]
            default: return nil
            }
            guard let name = bump(&db, options, cap: cap) else { return nil }
            player.positionAttributes = .defensiveBack(db)
            return name

        case .kicking(var k):
            guard area == .kickingCraft else { return nil }
            let options: [(String, WritableKeyPath<KickingAttributes, Int>)] = [
                ("Kick Power", \.kickPower), ("Kick Accuracy", \.kickAccuracy)
            ]
            guard let name = bump(&k, options, cap: cap) else { return nil }
            player.positionAttributes = .kicking(k)
            return name
        }
    }

    /// Bumps one random viable attribute (+1) inside a struct. Returns the
    /// display name of the attribute, or nil when all options are capped.
    private static func bump<T>(
        _ attrs: inout T,
        _ options: [(String, WritableKeyPath<T, Int>)],
        cap: Int
    ) -> String? {
        let viable = options.filter { attrs[keyPath: $0.1] < cap }
        guard let choice = viable.randomElement() else { return nil }
        attrs[keyPath: choice.1] += 1
        return choice.0
    }
}

// MARK: - DevelopmentReportBuilder (R26)

/// Assembles the user-facing weekly Development Report from the focus tick
/// results, the R25 mentorship pairs, and roster status (holdouts, injuries,
/// morale, age curve).
enum DevelopmentReportBuilder {

    /// Builds the weekly report for the user's roster.
    static func buildWeeklyReport(
        roster: [Player],
        focusGains: [TrainingFocusEngine.FocusGain],
        breakout: (player: Player, pointsGained: Int)?,
        week: Int,
        season: Int
    ) -> DevelopmentReport {
        var report = DevelopmentReport(season: season, week: week)

        // --- Risers: concrete focus gains ---
        for gain in focusGains {
            var detail = "+\(gain.points) \(gain.attributeName)"
            if gain.moraleBoosted { detail += " — riding high morale" }
            report.risers.append(DevelopmentReport.Entry(
                playerID: gain.playerID,
                playerName: gain.playerName,
                positionRaw: gain.position.rawValue,
                detail: detail,
                reasonRaw: DevelopmentReport.Reason.focus.rawValue
            ))
        }

        // --- Breakout ---
        if let breakout {
            report.breakouts.append(DevelopmentReport.Entry(
                playerID: breakout.player.id,
                playerName: breakout.player.fullName,
                positionRaw: breakout.player.position.rawValue,
                detail: "+\(breakout.pointsGained) attribute points — breakout leap",
                reasonRaw: DevelopmentReport.Reason.breakout.rawValue
            ))
        }

        // --- Mentorships (R25): protégés develop +10 % faster ---
        for pairing in LockerRoomEngine.activeMentorships(players: roster) {
            report.mentorships.append(DevelopmentReport.MentorLine(
                mentorName: pairing.mentor.fullName,
                protegeName: pairing.protege.fullName,
                positionRaw: pairing.protege.position.rawValue,
                boostText: "+10% development speed"
            ))
        }

        // --- Stalled / falling ---
        for player in roster where player.isHoldingOut {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Holding out — development paused",
                reasonRaw: DevelopmentReport.Reason.holdout.rawValue
            ))
        }
        for player in roster where player.isInjured {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Injured (\(max(1, player.injuryWeeksRemaining)) wk left) — development paused",
                reasonRaw: DevelopmentReport.Reason.injury.rawValue
            ))
        }
        for player in roster where !player.isInjured && !player.isHoldingOut
            && player.morale <= 35
            && player.age <= player.position.peakAgeRange.upperBound {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Low morale is dragging his development",
                reasonRaw: DevelopmentReport.Reason.morale.rawValue
            ))
        }
        // A focus slot spent on a post-peak veteran is flagged so the user
        // understands why the gains never come.
        for player in roster where player.trainingFocusArea != nil
            && player.age > player.position.peakAgeRange.upperBound {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Past his physical peak — focus gains are rare",
                reasonRaw: DevelopmentReport.Reason.ageCurve.rawValue
            ))
        }

        // --- Season-opening motivation check (plan §2.10) ---
        // The state was decided at camp and does not move in-season, so it is
        // reported once, in week 1, rather than repeated for eighteen weeks.
        if week == seasonOpeningWeek {
            for player in roster.filter({ $0.motivationState == .driven })
                .sorted(by: { $0.overall > $1.overall })
                .prefix(campReportGroupCap) {
                report.risers.append(DevelopmentReport.Entry(
                    playerID: player.id,
                    playerName: player.fullName,
                    positionRaw: player.position.rawValue,
                    detail: player.motivationState.summary,
                    reasonRaw: DevelopmentReport.Reason.motivation.rawValue
                ))
            }
            for player in roster.filter({
                $0.motivationState == .complacent || $0.motivationState == .discouraged
            })
                .sorted(by: { $0.overall > $1.overall })
                .prefix(campReportGroupCap) {
                report.stalled.append(DevelopmentReport.Entry(
                    playerID: player.id,
                    playerName: player.fullName,
                    positionRaw: player.position.rawValue,
                    detail: player.motivationState.summary,
                    reasonRaw: DevelopmentReport.Reason.motivation.rawValue
                ))
            }
        }

        return report
    }

    /// Week the regular season opens — the one week the motivation states are
    /// worth repeating outside the camp report.
    static let seasonOpeningWeek = 1

    // MARK: - Camp Report (phase 2 — plan §2.10)

    /// `week` value that marks a report as the training-camp edition rather
    /// than a regular-season week. Regular-season reports are always week ≥ 1.
    static let campReportWeek = 0

    /// How many players each phase-2 narrative group may contribute. The camp
    /// report covers a whole roster in one card, so every group is capped —
    /// a 53-man list of "focused" nobodies is not a story.
    static let campReportGroupCap = 4

    /// The offseason digest, filed at training camp: who showed up driven, who
    /// eased off after payday, who has settled into his role, who finally broke
    /// out, and who is a step slow inside a brand-new playbook.
    ///
    /// Deliberately built from the same `DevelopmentReport` shape as the weekly
    /// edition — the entries just carry the phase-2 `Reason` cases, so
    /// `DevelopmentReportView` renders it with no special casing.
    ///
    /// - Parameters:
    ///   - roster: The user's post-camp roster (used for the install-year
    ///     lines, which need live scheme familiarity).
    ///   - outcomes: The realization verdicts `processOffseason` handed back
    ///     for this roster.
    ///   - installedSchemes: Raw values of the schemes this team installed this
    ///     offseason (the same keys `Player.schemeFamiliarity` uses); empty
    ///     when the playbook did not change.
    ///   - season: The season the camp belongs to.
    static func buildCampReport(
        roster: [Player],
        outcomes: [PlayerDevelopmentEngine.OffseasonOutcome],
        installedSchemes: [String],
        season: Int
    ) -> DevelopmentReport {
        var report = DevelopmentReport(season: season, week: campReportWeek)

        func entry(
            _ outcome: PlayerDevelopmentEngine.OffseasonOutcome,
            _ detail: String,
            _ reason: DevelopmentReport.Reason
        ) -> DevelopmentReport.Entry {
            DevelopmentReport.Entry(
                playerID: outcome.playerID,
                playerName: outcome.playerName,
                positionRaw: outcome.position.rawValue,
                detail: detail,
                reasonRaw: reason.rawValue
            )
        }

        // --- Late bloomers: the headline of any camp they happen in ---
        for outcome in outcomes.filter({ $0.lateBloomerBreakout })
            .sorted(by: { $0.overallDelta > $1.overallDelta })
            .prefix(campReportGroupCap) {
            let detail = outcome.overallDelta > 0
                ? String(localized: "+\(outcome.overallDelta) OVR — the light finally came on")
                : String(localized: "Something clicked in the offseason program")
            report.breakouts.append(entry(outcome, detail, .lateBloomer))
        }

        // --- Driven: the fighters who answered a bad season ---
        for outcome in outcomes.filter({ $0.motivation == .driven && !$0.lateBloomerBreakout })
            .sorted(by: { $0.overallAfter > $1.overallAfter })
            .prefix(campReportGroupCap) {
            report.risers.append(entry(outcome, outcome.motivation.summary, .motivation))
        }

        // --- Complacent / discouraged: the training output that went missing ---
        for outcome in outcomes.filter({ $0.motivation == .complacent || $0.motivation == .discouraged })
            .sorted(by: { $0.overallAfter > $1.overallAfter })
            .prefix(campReportGroupCap) {
            report.stalled.append(entry(outcome, outcome.motivation.summary, .motivation))
        }

        // --- Plateaued: "he is what he is" ---
        for outcome in outcomes.filter({ $0.plateaued && !$0.lateBloomerBreakout })
            .sorted(by: { $0.overallAfter > $1.overallAfter })
            .prefix(campReportGroupCap) {
            report.stalled.append(entry(
                outcome,
                String(localized: "Has settled into his role — two years without a step forward"),
                .plateau
            ))
        }

        // --- Install year: the players furthest behind the new language ---
        //
        // Scored and labelled PER SIDE. A player only ever carries a
        // familiarity entry for his own unit's scheme (`DraftEngine`
        // `initializeRookieFamiliarity`, `LeagueGenerator`, and both weekly
        // learning paths all switch on `position.side`), so scoring a defender
        // against the new offensive playbook reads 0 for everyone: the sort
        // became arbitrary, every line printed "familiarity 0", and half the
        // entries named a playbook the player is not in. A club that changes
        // both coordinators now gets one section per unit.
        let outcomesByID = Dictionary(outcomes.map { ($0.playerID, $0) }) { first, _ in first }
        for installed in installedSchemes {
            guard let side = schemeSide(installed) else { continue }
            let schemeName = schemeDisplayName(installed)
            let laggards = roster
                .filter { $0.position.side == side && outcomesByID[$0.id] != nil }
                .sorted { schemeFamiliarity($0, scheme: installed) < schemeFamiliarity($1, scheme: installed) }
                .prefix(campReportGroupCap)
            for player in laggards {
                guard let outcome = outcomesByID[player.id] else { continue }
                let familiarity = schemeFamiliarity(player, scheme: installed)
                report.stalled.append(entry(
                    outcome,
                    String(localized: "Learning the new \(schemeName) playbook — install year (familiarity \(familiarity))"),
                    .schemeChange
                ))
            }
        }

        return report
    }

    /// How far behind THIS playbook the player is.
    private static func schemeFamiliarity(_ player: Player, scheme: String) -> Int {
        player.schemeFamiliarity[scheme] ?? 0
    }

    /// Which unit a stored scheme raw value belongs to — `nil` for anything
    /// unrecognised (a legacy save's stale key).
    private static func schemeSide(_ rawValue: String) -> PositionSide? {
        if OffensiveScheme(rawValue: rawValue) != nil { return .offense }
        if DefensiveScheme(rawValue: rawValue) != nil { return .defense }
        return nil
    }

    /// Human-readable name for a stored scheme raw value ("WestCoast" → "West
    /// Coast"). Falls back to the raw value for anything unrecognised.
    static func schemeDisplayName(_ rawValue: String) -> String {
        if let offense = OffensiveScheme(rawValue: rawValue) { return offense.displayName }
        if let defense = DefensiveScheme(rawValue: rawValue) { return defense.displayName }
        return rawValue
    }

    /// Weekly inbox digest linking to the Development Report screen. A report
    /// stamped `campReportWeek` is the offseason edition and is titled as such.
    static func inboxMessage(report: DevelopmentReport, focusedCount: Int) -> InboxMessage {
        var lines: [String] = []
        let isCamp = report.week == campReportWeek

        if !report.risers.isEmpty {
            let names = report.risers.prefix(3)
                .map { "\($0.playerName) (\($0.detail))" }
                .joined(separator: ", ")
            lines.append(isCamp ? "Reported in the best shape of the room: \(names)." : "Trending up: \(names).")
        }
        if let breakoutEntry = report.breakouts.first {
            lines.append(
                isCamp
                    ? "LATE BLOOMER: \(breakoutEntry.playerName) has finally put it together — the staff say this is a different player."
                    : "BREAKOUT: \(breakoutEntry.playerName) took a massive developmental leap this week — the game has slowed down for him."
            )
        }
        if !report.mentorships.isEmpty {
            let pairs = report.mentorships.prefix(2)
                .map { "\($0.mentorName) → \($0.protegeName)" }
                .joined(separator: ", ")
            lines.append("Mentorships paying off (\(pairs)): protégés develop +10% faster.")
        }
        if !report.stalled.isEmpty {
            lines.append("\(report.stalled.count) player\(report.stalled.count == 1 ? " is" : "s are") developing slowly or not at all — details in the full report.")
        }
        if focusedCount == 0 {
            lines.append("Reminder: no training-focus players are set. Assign up to \(TrainingFocusEngine.maxFocusPlayersPerTeam) in the Development hub — young players benefit the most.")
        }

        return InboxMessage(
            sender: .developmentStaff,
            subject: isCamp
                ? "Development Report — Training Camp"
                : "Development Report — Week \(report.week)",
            body: lines.joined(separator: "\n\n"),
            date: isCamp
                ? "Training Camp, Season \(report.season)"
                : "Week \(report.week), Season \(report.season)",
            category: .rosterAnalysis,
            attachments: [
                MessageAttachment(title: "Development Report", destination: .developmentReport)
            ]
        )
    }
}
