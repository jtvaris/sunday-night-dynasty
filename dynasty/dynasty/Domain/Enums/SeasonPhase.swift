import Foundation

enum SeasonPhase: String, Codable, CaseIterable {
    case proBowl         = "ProBowl"
    case superBowl       = "SuperBowl"
    case coachingChanges = "CoachingChanges"
    case reviewRoster    = "ReviewRoster"
    case combine         = "Combine"
    case freeAgency      = "FreeAgency"
    case proDays         = "ProDays"
    case draft           = "Draft"
    case otas            = "OTAs"
    case trainingCamp    = "TrainingCamp"
    case preseason       = "Preseason"
    case rosterCuts      = "RosterCuts"
    case regularSeason   = "RegularSeason"
    case tradeDeadline   = "TradeDeadline"
    case playoffs        = "Playoffs"
}

// MARK: - Phase Groups

/// Top-level groupings of `SeasonPhase` for UI structure (sidebar timeline,
/// phase-aware dashboards, quick action bar). Each group maps 1:N to sub-phases.
enum SeasonPhaseGroup: String, CaseIterable, Codable {
    case postseason         // proBowl, superBowl
    case offseason          // coachingChanges, reviewRoster
    case preDraft           // combine, freeAgency, proDays, draft
    case preSeason          // otas, trainingCamp, preseason, rosterCuts
    case regularSeason      // regularSeason, tradeDeadline, playoffs

    var displayName: String {
        switch self {
        case .postseason:    return "Postseason"
        case .offseason:     return "Offseason"
        case .preDraft:      return "Pre-Draft"
        case .preSeason:     return "Pre Season"
        case .regularSeason: return "Regular Season"
        }
    }

    /// SF Symbol icon used by the group header.
    var icon: String {
        switch self {
        case .postseason:    return "trophy.fill"
        case .offseason:     return "leaf.fill"
        case .preDraft:      return "magnifyingglass.circle.fill"
        case .preSeason:     return "figure.american.football"
        case .regularSeason: return "sportscourt.fill"
        }
    }

    /// Sub-phases that belong to this group, in chronological order.
    var subPhases: [SeasonPhase] {
        switch self {
        case .postseason:    return [.proBowl, .superBowl]
        case .offseason:     return [.coachingChanges, .reviewRoster]
        case .preDraft:      return [.combine, .freeAgency, .proDays, .draft]
        case .preSeason:     return [.otas, .trainingCamp, .preseason, .rosterCuts]
        case .regularSeason: return [.regularSeason, .tradeDeadline, .playoffs]
        }
    }
}

extension SeasonPhase {
    /// Human-readable name for player-facing copy.
    var displayName: String {
        switch self {
        case .proBowl:         return "Pro Bowl"
        case .superBowl:       return "Super Bowl"
        case .coachingChanges: return "Coaching Changes"
        case .reviewRoster:    return "Review Roster"
        case .combine:         return "NFL Combine"
        case .freeAgency:      return "Free Agency"
        case .proDays:         return "Pro Days"
        case .draft:           return "NFL Draft"
        case .otas:            return "OTAs"
        case .trainingCamp:    return "Training Camp"
        case .preseason:       return "Preseason"
        case .rosterCuts:      return "Roster Cuts"
        case .regularSeason:   return "Regular Season"
        case .tradeDeadline:   return "Trade Deadline"
        case .playoffs:        return "Playoffs"
        }
    }

    /// The top-level phase group this sub-phase belongs to.
    var group: SeasonPhaseGroup {
        switch self {
        case .proBowl, .superBowl:                              return .postseason
        case .coachingChanges, .reviewRoster:                   return .offseason
        case .combine, .freeAgency, .proDays, .draft:           return .preDraft
        case .otas, .trainingCamp, .preseason, .rosterCuts:     return .preSeason
        case .regularSeason, .tradeDeadline, .playoffs:         return .regularSeason
        }
    }

    /// Ordinal index of this sub-phase within its group (0-based).
    var orderInGroup: Int {
        group.subPhases.firstIndex(of: self) ?? 0
    }

    /// Overall ordinal across all phases (0..14). Used for UI progress bars.
    var overallOrdinal: Int {
        SeasonPhase.allCases.firstIndex(of: self) ?? 0
    }

    /// Group's progress within itself: (1-based current sub-phase, total sub-phases).
    /// Suitable for "Step X / Y" UI strings.
    var groupProgress: (current: Int, total: Int) {
        let total = group.subPhases.count
        let current = (group.subPhases.firstIndex(of: self) ?? 0) + 1
        return (current, total)
    }
}
