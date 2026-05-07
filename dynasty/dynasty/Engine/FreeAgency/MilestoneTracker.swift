import Foundation

/// Tracks the personal career milestones that shape a free agent's signing
/// demands (FA Drama brief, B7).
///
/// Heuristics use age + position + yearsPro proxies for stat thresholds since
/// long-tail career stats aren't yet stored on `Player`. The `milestoneRaw`
/// field on `Player` is used as the persistence handle when the engine layer
/// wants to lock in a milestone tag.
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

    /// Detects active milestones for a player. Stat-driven where data exists,
    /// heuristic age/position fallback otherwise. Multiple milestones may apply.
    static func activeMilestones(player: Player) -> [FAMilestone] {
        var milestones: [FAMilestone] = []

        // Persistent override -> highest priority.
        if let raw = player.milestoneRaw,
           let stored = FAMilestone(rawValue: raw) {
            milestones.append(stored)
        }

        // Last chance: 33+ year-old veteran on a short deal.
        if player.age >= 33 && player.contractYearsRemaining <= 1 {
            if !milestones.contains(.lastChance) {
                milestones.append(.lastChance)
            }
        }

        // Pro Bowl push: high overall, mid-career.
        if player.overall >= 88 && player.age >= 28 && player.age <= 32 {
            if !milestones.contains(.proBowlPush) {
                milestones.append(.proBowlPush)
            }
        }

        // Position-driven historic markers.
        switch player.position {
        case .DE, .DT, .OLB:
            // Edge/DL veteran chasing 50/100 career sacks.
            if player.age >= 30 && player.yearsPro >= 8 && player.overall >= 80 {
                if !milestones.contains(.oneSackFromHistoric) {
                    milestones.append(.oneSackFromHistoric)
                }
            }
        case .RB:
            if player.age >= 28 && player.yearsPro >= 6 && player.overall >= 78 {
                if !milestones.contains(.approaching1000Yards) {
                    milestones.append(.approaching1000Yards)
                }
            }
        default:
            break
        }

        return milestones
    }

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

    /// Generates a press storyline event for the milestone signing.
    static func generateMilestoneEvent(
        player: Player,
        milestone: FAMilestone,
        teamID: UUID
    ) -> FAStorylineEvent? {
        let headline: String
        let body: String
        switch milestone {
        case .lastChance:
            headline = "\(player.fullName) on a last-chance prove-it deal"
            body = "At \(player.age), \(player.lastName) signs a 1-year deal to prove there's still gas in the tank."
        case .comeback:
            headline = "\(player.fullName) comes out of retirement"
            body = "The comeback is on. \(player.lastName) returns to the field with something to prove."
        case .oneSackFromHistoric:
            headline = "\(player.fullName) chases historic sack milestone"
            body = "One more sack puts \(player.lastName) in the record book. Defensive coordinators take note."
        case .approaching1000Yards:
            headline = "\(player.fullName) eyes 1,000-yard finish"
            body = "Veteran back \(player.lastName) signs with a fresh playbook and one more 1,000-yard season in mind."
        case .proBowlPush:
            headline = "\(player.fullName) eyes Pro Bowl + HOF lock"
            body = "Another Pro Bowl nod likely cements \(player.lastName)'s Hall of Fame case. Stakes are high."
        }
        let seasonYear = Calendar.current.component(.year, from: Date())
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .milestone,
            playerID: player.id,
            teamID: teamID,
            headline: headline,
            body: body
        )
    }
}
