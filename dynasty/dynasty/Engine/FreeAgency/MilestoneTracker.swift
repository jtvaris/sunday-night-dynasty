import Foundation

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
    case proBowlPush                // approaching 4th Pro Bowl (HOF lock)
}

enum MilestoneTracker {

    // MARK: - Thresholds

    /// The round career-sack numbers that make a headline. A pass rusher within
    /// `sackMilestoneWindow` of one of these is chasing history for real.
    static let sackMilestones: [Double] = [50, 100, 150]

    /// How close counts as "one sack away" — a sack and a half, because the game
    /// records half-sacks.
    static let sackMilestoneWindow: Double = 1.5

    /// A back who cleared this in his last season played is a genuine
    /// 1,000-yard threat next year.
    static let thousandYardChaseFloor = 850

    // MARK: - Career facts

    /// The career numbers the milestones ask about, summed from the persisted
    /// season rows. Regular season only — playoff production is not persisted.
    struct CareerFacts {
        /// Seasons with at least one appearance.
        var seasons = 0
        var sacks: Double = 0
        var rushYards = 0
        var recYards = 0
        var receptions = 0
        var passYards = 0
        var passTDs = 0
        var defInts = 0
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
    static func careerFacts(history: [PlayerSeasonHistory]) -> CareerFacts {
        var facts = CareerFacts()
        for row in history.sorted(by: { $0.season < $1.season }) {
            facts.peakOverall = max(facts.peakOverall, row.overallAtEndOfSeason)
            guard row.gamesPlayed > 0 else { continue }
            facts.seasons += 1
            facts.sacks += row.sacks
            facts.rushYards += row.rushYards
            facts.recYards += row.recYards
            facts.receptions += row.receptions
            facts.passYards += row.passYards
            facts.passTDs += row.passTDs
            facts.defInts += row.defInts
            facts.lastSeasonRushYards = row.rushYards
        }
        return facts
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
        case .LT, .LG, .C, .RG, .RT, .K, .P:
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

        // Pro Bowl / Hall of Fame push: a real career case where the numbers
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
    /// E.g. a Pro Bowl-push veteran demands 1.10x; a last-chance vet accepts 0.85x.
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
            headline = "\(player.fullName) eyes Pro Bowl + HOF lock"
            if facts.isEmpty {
                body = "Another Pro Bowl nod likely cements \(player.lastName)'s Hall of Fame case. Stakes are high."
            } else {
                body = "\(facts.seasons) seasons, a peak of \(facts.peakOverall) overall, and \(hallOfFameSummary(position: player.position, facts: facts)) — another Pro Bowl nod likely cements \(player.lastName)'s Hall of Fame case. Stakes are high."
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
        case .LT, .LG, .C, .RG, .RT, .K, .P:
            return "\(facts.seasons) seasons of starter-level play"
        }
    }
}
