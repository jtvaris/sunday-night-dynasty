import Foundation
import SwiftData

/// Tracks the personal career milestones that shape a free agent's signing
/// demands (FA Drama brief, B7).
///
/// Stat-driven wherever the career record reaches: every milestone that names a
/// number (career sacks, a 1,000-yard season, a Hall-of-Fame case) is decided
/// from `PlayerSeasonHistory` — the real per-season production the career-stats
/// wave persists for every player in the league. The age/position/`yearsPro`
/// proxies are still there, but only as the fallback for a caller that has no
/// history rows to hand (see `activeMilestones(player:history:)`).
///
/// The `milestoneRaw` field on `Player` is used as the persistence handle when
/// the engine layer wants to lock in a milestone tag.
///
/// Note: a separate `CareerMilestone` already lives on `CareerArcState` for
/// rookie-development outcomes. We deliberately use `FAMilestone` here to keep
/// the two concerns from colliding.
enum FAMilestone: String, Codable, CaseIterable {
    case oneSackFromHistoric        // 1 sack from career #50/100 — DL/edge ages 30+
    case approaching1000Yards       // 1 game from career 1000+ yards — RB nearing benchmark
    case lastChance                 // veteran 33+, 1 yr proving deal
    case comeback                   // retired in past, returning
    case proBowlPush                // approaching 4th All-Star selection (HOF lock)
}

enum MilestoneTracker {

    // MARK: - Thresholds

    /// The round career-sack numbers that make a headline. A pass rusher within
    /// `sackMilestoneWindow` of one of these is chasing history for real, and
    /// crossing one is worth a news item (`careerCrossings`).
    static let sackMilestones: [Double] = [50, 100, 150, 200]

    /// How close counts as "one sack away" — a sack and a half, because the game
    /// records half-sacks.
    static let sackMilestoneWindow: Double = 1.5

    /// A back who cleared this in his last season played is a genuine
    /// 1,000-yard threat next year.
    static let thousandYardChaseFloor = 850

    // MARK: - Career facts

    /// The career numbers the milestones ask about, summed from the persisted
    /// season rows.
    ///
    /// Regular season only — deliberately, now that the playoffs ARE persisted
    /// (`PlayerSeasonHistory.postStatLine`, #20). No record book mixes the two,
    /// and a milestone that counted January would put a perennial contender's
    /// back past 10 000 yards a season ahead of an equally good one who never
    /// made the bracket.
    struct CareerFacts {
        /// Seasons with at least one appearance.
        var seasons = 0
        /// Regular-season games played across the whole career.
        var gamesPlayed = 0
        var sacks: Double = 0
        var tackles = 0
        var rushYards = 0
        var recYards = 0
        var receptions = 0
        var passYards = 0
        var passTDs = 0
        var defInts = 0
        var fieldGoalsMade = 0
        /// Best end-of-season overall across the career.
        var peakOverall = 0
        /// Rushing yards in the most recent season he actually played.
        var lastSeasonRushYards = 0

        /// True when the caller handed over no usable history — the signal to
        /// fall back on the age/rating proxies.
        var isEmpty: Bool { seasons == 0 }
    }

    /// Folds a player's season-history rows into the facts the milestones need.
    /// Seasons he was not on a roster for (`gamesPlayed == 0`) are skipped: a
    /// year out of football is not a season of production.
    ///
    /// - Parameter through: Ignore every season AFTER this year. Passing the
    ///   season that just ended and the one before it gives the two totals a
    ///   round-number crossing is measured between (`careerCrossings`).
    static func careerFacts(
        history: [PlayerSeasonHistory],
        through season: Int? = nil
    ) -> CareerFacts {
        var facts = CareerFacts()
        for row in history.sorted(by: { $0.season < $1.season }) {
            if let season, row.season > season { continue }
            facts.peakOverall = max(facts.peakOverall, row.overallAtEndOfSeason)
            guard row.gamesPlayed > 0 else { continue }
            facts.seasons += 1
            facts.gamesPlayed += row.gamesPlayed
            facts.sacks += row.sacks
            facts.tackles += row.tackles
            facts.rushYards += row.rushYards
            facts.recYards += row.recYards
            facts.receptions += row.receptions
            facts.passYards += row.passYards
            facts.passTDs += row.passTDs
            facts.defInts += row.defInts
            facts.fieldGoalsMade += row.fieldGoalsMade
            facts.lastSeasonRushYards = row.rushYards
        }
        return facts
    }

    /// One player's persisted season rows (#22).
    ///
    /// Every entry point here takes `history` and falls back to age/rating
    /// proxies without it, which means a call site that forgets to pass it gets
    /// the WEAKER answer silently — and the two free-agency call sites did
    /// exactly that. They hold a `ModelContext` but no history, so this is the
    /// one line that turns the proxy path into the stat path:
    ///
    ///     MilestoneTracker.activeMilestones(
    ///         player: player,
    ///         history: MilestoneTracker.history(
    ///             playerID: player.id, careerID: player.careerID, modelContext: modelContext
    ///         )
    ///     )
    ///
    /// Scoped by `careerID` like every other history query: unscoped it would
    /// read the OTHER save's career (multi-save isolation).
    static func history(
        playerID: UUID,
        careerID: UUID?,
        modelContext: ModelContext
    ) -> [PlayerSeasonHistory] {
        let descriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { row in
                row.playerID == playerID && row.careerID == careerID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// The whole regular-season career as one stat line — what a Hall of Fame
    /// entry snapshots and what a retirement headline quotes (#21).
    ///
    /// Lives here rather than on `SeasonStatLine` because this is the career
    /// layer's job, and the engine layer must not reach into the UI's
    /// `CareerStatTotals` for it. Every category is additive except
    /// `puntAverage`, which is a RATE: averaging averages would let a 4-punt
    /// season outweigh an 80-punt one, so it is re-derived punt-weighted.
    ///
    /// Regular season only, like everything else in this type — the postseason
    /// columns (#20) are a separate line and no record book mixes the two.
    static func careerLine(history: [PlayerSeasonHistory]) -> SeasonStatLine {
        var total = SeasonStatLine()
        var puntYards = 0.0
        for row in history {
            let line = row.statLine
            total.passYards += line.passYards
            total.passTDs += line.passTDs
            total.passInts += line.passInts
            total.rushYards += line.rushYards
            total.rushTDs += line.rushTDs
            total.receptions += line.receptions
            total.recYards += line.recYards
            total.recTDs += line.recTDs
            total.tackles += line.tackles
            total.sacks += line.sacks
            total.defInts += line.defInts
            total.passesDefended += line.passesDefended
            total.fieldGoalsMade += line.fieldGoalsMade
            total.fieldGoalsAttempted += line.fieldGoalsAttempted
            total.punts += line.punts
            total.snapsPlayed += line.snapsPlayed
            puntYards += Double(line.punts) * line.puntAverage
        }
        total.puntAverage = total.punts > 0 ? puntYards / Double(total.punts) : 0
        return total
    }

    /// How strong this career looks as a Hall-of-Fame case, 0...1.
    ///
    /// Career production against the enshrinement-worthy total for the position,
    /// blended with peak overall so a short brilliant career and a long
    /// productive one can both qualify. Peak alone can carry a player at most
    /// halfway — a bust with a 94 rating and no numbers is not a Hall of Famer.
    static func hallOfFameCase(position: Position, facts: CareerFacts) -> Double {
        let productionShare: Double
        switch position {
        case .QB:
            productionShare = max(
                Double(facts.passYards) / 45_000,
                Double(facts.passTDs) / 300
            )
        case .RB, .FB:
            productionShare = Double(facts.rushYards) / 10_000
        case .WR, .TE:
            productionShare = max(
                Double(facts.recYards) / 12_000,
                Double(facts.receptions) / 800
            )
        case .DE, .DT, .OLB, .MLB:
            productionShare = facts.sacks / 100
        case .CB, .FS, .SS:
            productionShare = Double(facts.defInts) / 40
        case .LT, .LG, .C, .RG, .RT, .K, .P, .LS, .H:
            // No counting stat the game tracks makes a case at these spots, so
            // the peak/longevity half is the whole story.
            productionShare = 0
        }
        // Peak half: 88 is the bottom of the Hall-of-Fame band the retirement
        // engine uses (`PlayerRetirementEngine.qualifiesForHallOfFame`), 95 tops
        // it out, and ten seasons of it is what "sustained" means.
        let peakShare = Double(facts.peakOverall - 88) / 7.0
        let longevityShare = Double(facts.seasons) / 12.0
        let pedigree = (min(1, max(0, peakShare)) * 0.6 + min(1, longevityShare) * 0.4)
        return min(1, min(1, max(0, productionShare)) * 0.5 + pedigree * 0.5)
    }

    // MARK: - Career round numbers (#23)

    /// A round career number a player went past during one season.
    struct CareerCrossing {
        /// Plural, lower-case category name for copy ("passing yards").
        let category: String
        /// The round number he crossed.
        let milestone: Double
        /// Where the career total stood when the season ended.
        let total: Double
        /// True for the categories the game records in halves (sacks), which
        /// print with one decimal instead of as a whole number.
        let isFractional: Bool
    }

    /// The Hall-of-Fame case score at which a career stops being good and starts
    /// being an argument. Below `activeMilestones`' own 0.55 gate on purpose: a
    /// free agent's asking price and a "he is going to Canton" headline are not
    /// the same claim, and the headline should be the rarer one.
    static let hallOfFameWatchThreshold = 0.70

    /// Every round career number this player passed between two career totals.
    ///
    /// Measured as a CROSSING rather than a threshold so each milestone fires
    /// exactly once in a career: pass the same before/after pair twice and the
    /// second call still reports it, but pass next season's pair and it is gone.
    /// A monster year that clears two levels at once reports both, loudest first.
    ///
    /// Positions with no counting stat the game tracks (the offensive line)
    /// return nothing — inventing a milestone for them would mean inventing the
    /// stat first.
    static func careerCrossings(
        position: Position,
        before: CareerFacts,
        after: CareerFacts
    ) -> [CareerCrossing] {
        var crossings: [CareerCrossing] = []
        for track in careerTracks(for: position) {
            let start = track.value(before)
            let end = track.value(after)
            guard end > start else { continue }
            for milestone in track.milestones where start < milestone && end >= milestone {
                crossings.append(CareerCrossing(
                    category: track.category,
                    milestone: milestone,
                    total: end,
                    isFractional: track.isFractional
                ))
            }
        }
        return crossings.sorted { $0.milestone > $1.milestone }
    }

    /// One category's round numbers, plus how to read it off a career.
    private struct CareerTrack {
        let category: String
        let milestones: [Double]
        let isFractional: Bool
        let value: (CareerFacts) -> Double
    }

    /// The categories that carry a milestone at this position.
    ///
    /// Deliberately the same shortlist `hallOfFameSummary` argues from — one
    /// number per position family, the one a record book would print. The rungs
    /// are spaced so a good career hits two or three of them and a great one hits
    /// five, rather than a headline every other season.
    private static func careerTracks(for position: Position) -> [CareerTrack] {
        switch position {
        case .QB:
            return [
                CareerTrack(category: "passing yards",
                            milestones: [10_000, 20_000, 30_000, 40_000, 50_000, 60_000],
                            isFractional: false) { Double($0.passYards) },
                CareerTrack(category: "touchdown passes",
                            milestones: [100, 200, 300, 400, 500],
                            isFractional: false) { Double($0.passTDs) },
            ]
        case .RB, .FB:
            return [
                CareerTrack(category: "rushing yards",
                            milestones: [2_500, 5_000, 7_500, 10_000, 12_500, 15_000],
                            isFractional: false) { Double($0.rushYards) },
            ]
        case .WR, .TE:
            return [
                CareerTrack(category: "receiving yards",
                            milestones: [2_500, 5_000, 7_500, 10_000, 12_500, 15_000],
                            isFractional: false) { Double($0.recYards) },
                CareerTrack(category: "receptions",
                            milestones: [250, 500, 750, 1_000],
                            isFractional: false) { Double($0.receptions) },
            ]
        case .DE, .DT, .OLB, .MLB:
            return [
                CareerTrack(category: "sacks",
                            milestones: sackMilestones,
                            isFractional: true) { $0.sacks },
                CareerTrack(category: "tackles",
                            milestones: [500, 1_000, 1_500],
                            isFractional: false) { Double($0.tackles) },
            ]
        case .CB, .FS, .SS:
            return [
                CareerTrack(category: "interceptions",
                            milestones: [20, 40, 60],
                            isFractional: false) { Double($0.defInts) },
                CareerTrack(category: "tackles",
                            milestones: [500, 1_000, 1_500],
                            isFractional: false) { Double($0.tackles) },
            ]
        case .K:
            return [
                CareerTrack(category: "field goals",
                            milestones: [100, 200, 300, 400],
                            isFractional: false) { Double($0.fieldGoalsMade) },
            ]
        case .LT, .LG, .C, .RG, .RT, .P, .LS, .H:
            return []
        }
    }

    // MARK: - Detection

    /// Detects active milestones for a player. Multiple milestones may apply.
    ///
    /// - Parameters:
    ///   - player: The free agent being evaluated.
    ///   - history: His `PlayerSeasonHistory` rows. Pass them whenever the caller
    ///     has them: with real career numbers the stat milestones mean what they
    ///     say. Without them the old age/position/rating proxies decide.
    static func activeMilestones(
        player: Player,
        history: [PlayerSeasonHistory] = []
    ) -> [FAMilestone] {
        var milestones: [FAMilestone] = []
        let facts = careerFacts(history: history)

        // Persistent override -> highest priority.
        if let raw = player.milestoneRaw,
           let stored = FAMilestone(rawValue: raw) {
            milestones.append(stored)
        }

        // Last chance: 33+ year-old veteran on a short deal. No stat involved —
        // this one really is about age and contract.
        if player.age >= 33 && player.contractYearsRemaining <= 1 {
            if !milestones.contains(.lastChance) {
                milestones.append(.lastChance)
            }
        }

        // All-Star / Hall of Fame push: a real career case where the numbers
        // exist, the old rating-and-age proxy where they do not. The age window
        // stays either way — this milestone is about a player still adding to the
        // résumé, and a 36-year-old is chasing a different story (`lastChance`).
        let hasHallOfFameCase = facts.isEmpty
            ? (player.overall >= 88 && player.age >= 28 && player.age <= 32)
            : (hallOfFameCase(position: player.position, facts: facts) >= 0.55
                && player.age >= 27 && player.age <= 34)
        if hasHallOfFameCase, !milestones.contains(.proBowlPush) {
            milestones.append(.proBowlPush)
        }

        // Position-driven historic markers.
        switch player.position {
        case .DE, .DT, .OLB, .MLB:
            // Edge/DL veteran chasing a round career-sack number.
            let chasing = facts.isEmpty
                ? (player.age >= 30 && player.yearsPro >= 8 && player.overall >= 80)
                : isChasingSackMilestone(careerSacks: facts.sacks)
            if chasing, !milestones.contains(.oneSackFromHistoric) {
                milestones.append(.oneSackFromHistoric)
            }
        case .RB, .FB:
            // The veteran gate stays: this is the back with one more 1,000-yard
            // season left in him, not the 24-year-old who is expected to run for
            // 1,200 every year. What the numbers replace is the OVR guess about
            // whether he can still do it — now it is what he actually ran for.
            let chasing = facts.isEmpty
                ? (player.age >= 28 && player.yearsPro >= 6 && player.overall >= 78)
                : (player.age >= 27 && facts.lastSeasonRushYards >= thousandYardChaseFloor)
            if chasing, !milestones.contains(.approaching1000Yards) {
                milestones.append(.approaching1000Yards)
            }
        default:
            break
        }

        return milestones
    }

    /// True when the career total sits just short of one of the round numbers.
    static func isChasingSackMilestone(careerSacks: Double) -> Bool {
        sackMilestones.contains { target in
            careerSacks < target && target - careerSacks <= sackMilestoneWindow
        }
    }

    /// The next round sack number in reach, if any.
    static func nextSackMilestone(careerSacks: Double) -> Double? {
        sackMilestones.first { careerSacks < $0 && $0 - careerSacks <= sackMilestoneWindow }
    }

    // MARK: - Contract effects

    /// Required salary multiplier for milestone players.
    /// E.g. a All-Star-push veteran demands 1.10x; a last-chance vet accepts 0.85x.
    static func milestoneSalaryMultiplier(milestone: FAMilestone) -> Double {
        switch milestone {
        case .lastChance:           return 0.85
        case .comeback:             return 0.90
        case .oneSackFromHistoric:  return 1.05
        case .approaching1000Yards: return 1.05
        case .proBowlPush:          return 1.10
        }
    }

    /// Required years-on-deal range for milestone players.
    /// Last-chance + comeback only sign 1-yr proving deals. HOF chasers want longer.
    static func milestoneRequiredYears(milestone: FAMilestone) -> ClosedRange<Int> {
        switch milestone {
        case .lastChance:           return 1...1
        case .comeback:             return 1...2
        case .oneSackFromHistoric:  return 1...2
        case .approaching1000Yards: return 1...2
        case .proBowlPush:          return 2...4
        }
    }

    // MARK: - Storyline

    /// Generates a press storyline event for the milestone signing.
    ///
    /// - Parameters:
    ///   - season: League season the signing happened in. Defaults to the
    ///     wall-clock year only because two call sites do not pass one yet —
    ///     always pass the real season where it is known.
    ///   - history: His season rows. Supplied, the body quotes the actual career
    ///     numbers ("1.5 sacks from 100") instead of gesturing at them.
    static func generateMilestoneEvent(
        player: Player,
        milestone: FAMilestone,
        teamID: UUID,
        season: Int? = nil,
        history: [PlayerSeasonHistory] = []
    ) -> FAStorylineEvent? {
        let facts = careerFacts(history: history)
        let headline: String
        let body: String
        switch milestone {
        case .lastChance:
            headline = "\(player.fullName) on a last-chance prove-it deal"
            let career = facts.isEmpty ? "" : " \(facts.seasons) seasons in,"
            body = "At \(player.age),\(career) \(player.lastName) signs a 1-year deal to prove there's still gas in the tank."
        case .comeback:
            headline = "\(player.fullName) comes out of retirement"
            body = "The comeback is on. \(player.lastName) returns to the field with something to prove."
        case .oneSackFromHistoric:
            headline = "\(player.fullName) chases historic sack milestone"
            if let target = nextSackMilestone(careerSacks: facts.sacks) {
                let needed = target - facts.sacks
                body = String(
                    format: "%@ sits on %.1f career sacks — %.1f from %.0f. One more puts him in the record book, and defensive coordinators know it.",
                    player.lastName, facts.sacks, needed, target
                )
            } else {
                body = "One more sack puts \(player.lastName) in the record book. Defensive coordinators take note."
            }
        case .approaching1000Yards:
            headline = "\(player.fullName) eyes 1,000-yard finish"
            if facts.lastSeasonRushYards > 0 {
                body = "Veteran back \(player.lastName) ran for \(facts.lastSeasonRushYards) yards last season and \(facts.rushYards) in his career. He signs with a fresh playbook and one more 1,000-yard season in mind."
            } else {
                body = "Veteran back \(player.lastName) signs with a fresh playbook and one more 1,000-yard season in mind."
            }
        case .proBowlPush:
            headline = "\(player.fullName) eyes All-Star + HOF lock"
            if facts.isEmpty {
                body = "Another All-Star nod likely cements \(player.lastName)'s Hall of Fame case. Stakes are high."
            } else {
                body = "\(facts.seasons) seasons, a peak of \(facts.peakOverall) overall, and \(hallOfFameSummary(position: player.position, facts: facts)) — another All-Star nod likely cements \(player.lastName)'s Hall of Fame case. Stakes are high."
            }
        }
        let seasonYear = season ?? Calendar.current.component(.year, from: Date())
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .milestone,
            playerID: player.id,
            teamID: teamID,
            headline: headline,
            body: body
        )
    }

    /// The one career number that carries a player's Hall of Fame argument at
    /// his position, phrased for a news body.
    static func hallOfFameSummary(position: Position, facts: CareerFacts) -> String {
        switch position {
        case .QB:
            return "\(facts.passYards) passing yards with \(facts.passTDs) touchdowns"
        case .RB, .FB:
            return "\(facts.rushYards) career rushing yards"
        case .WR, .TE:
            return "\(facts.receptions) catches for \(facts.recYards) yards"
        case .DE, .DT, .OLB, .MLB:
            return String(format: "%.1f career sacks", facts.sacks)
        case .CB, .FS, .SS:
            return "\(facts.defInts) career interceptions"
        case .LT, .LG, .C, .RG, .RT, .K, .P, .LS, .H:
            return "\(facts.seasons) seasons of starter-level play"
        }
    }
}
