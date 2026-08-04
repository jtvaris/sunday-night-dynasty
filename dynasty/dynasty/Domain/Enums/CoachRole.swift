import Foundation

enum CoachRole: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }

    case headCoach               = "HeadCoach"
    case assistantHeadCoach      = "AssistantHeadCoach"
    case offensiveCoordinator    = "OffensiveCoordinator"
    case defensiveCoordinator    = "DefensiveCoordinator"
    case specialTeamsCoordinator = "SpecialTeamsCoordinator"
    case qbCoach                 = "QBCoach"
    case rbCoach                 = "RBCoach"
    case wrCoach                 = "WRCoach"
    case olCoach                 = "OLCoach"
    case dlCoach                 = "DLCoach"
    case lbCoach                 = "LBCoach"
    case dbCoach                 = "DBCoach"
    case strengthCoach           = "StrengthCoach"
    case teamDoctor              = "TeamDoctor"
    case physio                  = "Physio"
    /// R28: leads the rehab program — better trainers speed recovery,
    /// reduce setbacks, and lower re-injury risk after early returns.
    case headTrainer             = "HeadTrainer"

    // MARK: - Staff Families (task #96)

    /// The corner of a staff a role belongs to. Used by the hiring market to
    /// decide who is a plausible body for an open seat: a club that loses its
    /// receivers coach looks at out-of-work position coaches first, and would
    /// sooner slide a coordinator back down than invent a man from nowhere — but
    /// it never asks the physio to coach the linebackers.
    enum StaffFamily {
        /// Head coach and assistant head coach — the seats that run a building.
        case command
        /// The three coordinators.
        case coordinator
        /// Position rooms plus strength, i.e. the on-field teaching staff.
        case position
        /// Doctor / physio / head trainer. Never crosses into a coaching seat.
        case medical

        /// Where the family sits on the ladder a coaching career climbs.
        /// `medical` is deliberately off the ladder (`nil`): a physio moving to
        /// head trainer is a sideways move inside a profession of its own, not a
        /// promotion, and it must never compare against a coordinator seat.
        var seniority: Int? {
            switch self {
            case .position:    return 0
            case .coordinator: return 1
            case .command:     return 2
            case .medical:     return nil
            }
        }
    }

    var family: StaffFamily {
        switch self {
        case .headCoach, .assistantHeadCoach:
            return .command
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return .coordinator
        case .qbCoach, .rbCoach, .wrCoach, .olCoach,
             .dlCoach, .lbCoach, .dbCoach, .strengthCoach:
            return .position
        case .teamDoctor, .physio, .headTrainer:
            return .medical
        }
    }

    /// Whether moving from `previous` into this role is a step UP the ladder.
    ///
    /// This is the test for `Coach.promotedInSeason`, i.e. for whether a man pays
    /// the one-season adjustment penalty (`Coach.isInAdjustmentPeriod` → −0.05 HC
    /// / −0.03 coordinator on player development, and no scheme-continuity
    /// bonus). Task #96 made that distinction matter at volume: the AI staff
    /// refill now recycles ~90 out-of-work coaches a season, and stamping every
    /// seat change would have charged the penalty for LATERAL moves (a fired WR
    /// coach taking another WR room) and for DEMOTIONS (a fired coordinator
    /// taking a position room) — neither of which the generated stranger he
    /// replaced would ever have paid. Only the genuine promotion pays.
    ///
    /// A move into or out of the medical family is never a promotion: `seniority`
    /// is `nil` there, so the comparison is false in both directions.
    func isPromotion(from previous: CoachRole) -> Bool {
        guard let to = family.seniority, let from = previous.family.seniority else {
            return false
        }
        return to > from
    }

    /// Families this role could plausibly be hired out of, best fit first, when
    /// nobody with the exact title is on the market.
    ///
    /// Medical roles list only their own family on purpose — a team doctor is a
    /// licensed physician, not a spare position coach — so a medical seat with an
    /// empty bench still falls through to a fresh hire.
    var hiringFamilies: [StaffFamily] {
        switch family {
        case .command:     return [.command, .coordinator]
        case .coordinator: return [.coordinator, .command, .position]
        case .position:    return [.position, .coordinator]
        case .medical:     return [.medical]
        }
    }

    /// Real NFL salary range for this role, in thousands per year.
    /// E.g. (min: 2000, max: 20000) means $2M–$20M.
    var salaryRange: (min: Int, avg: Int, max: Int) {
        switch self {
        case .headCoach:               return (min: 3_000, avg: 16_000, max: 32_000)
        case .assistantHeadCoach:      return (min: 1_300, avg: 2_400,  max: 7_000)
        case .offensiveCoordinator:    return (min: 800,   avg: 2_400,  max: 9_500)
        case .defensiveCoordinator:    return (min: 800,   avg: 2_400,  max: 7_000)
        case .specialTeamsCoordinator: return (min: 650,   avg: 1_300,  max: 3_500)
        case .qbCoach:                 return (min: 400,   avg: 800,    max: 2_000)
        case .rbCoach:                 return (min: 250,   avg: 500,    max: 1_100)
        case .wrCoach:                 return (min: 300,   avg: 550,    max: 1_300)
        case .olCoach:                 return (min: 300,   avg: 650,    max: 1_600)
        case .dlCoach:                 return (min: 300,   avg: 650,    max: 1_600)
        case .lbCoach:                 return (min: 300,   avg: 550,    max: 1_300)
        case .dbCoach:                 return (min: 300,   avg: 550,    max: 1_300)
        case .strengthCoach:           return (min: 250,   avg: 500,    max: 1_100)
        case .teamDoctor:              return (min: 300,   avg: 650,    max: 1_300)
        case .physio:                  return (min: 250,   avg: 500,    max: 1_000)
        case .headTrainer:             return (min: 250,   avg: 550,    max: 1_100)
        }
    }

    /// Attributes that grow fastest for this role (weighted 2x in XP distribution)
    var focusAttributes: [String] {
        switch self {
        case .headCoach:               return ["motivation", "discipline", "adaptability"]
        case .assistantHeadCoach:      return ["playerDevelopment", "motivation", "gamePlanning"]
        case .offensiveCoordinator:    return ["playCalling", "gamePlanning", "adaptability"]
        case .defensiveCoordinator:    return ["playCalling", "gamePlanning", "adaptability"]
        case .specialTeamsCoordinator: return ["playCalling", "discipline"]
        case .qbCoach:                 return ["playCalling", "playerDevelopment", "gamePlanning"]
        case .rbCoach, .wrCoach:       return ["playerDevelopment", "motivation"]
        case .olCoach, .dlCoach:       return ["playerDevelopment", "discipline"]
        case .lbCoach, .dbCoach:       return ["playerDevelopment", "gamePlanning"]
        case .strengthCoach:           return ["playerDevelopment", "discipline", "motivation"]
        case .teamDoctor, .physio, .headTrainer: return ["playerDevelopment"]
        }
    }

    /// Roles this coach can be promoted to
    var promotionTargets: [CoachRole] {
        switch self {
        case .qbCoach, .rbCoach, .wrCoach, .olCoach:
            return [.offensiveCoordinator]
        case .dlCoach, .lbCoach, .dbCoach:
            return [.defensiveCoordinator]
        case .strengthCoach:
            return [.specialTeamsCoordinator]
        case .offensiveCoordinator, .defensiveCoordinator:
            return [.assistantHeadCoach]
        case .specialTeamsCoordinator:
            return [.assistantHeadCoach]
        case .assistantHeadCoach:
            return [.headCoach]
        default:
            return []
        }
    }

    /// Roles this coach can be demoted to
    var demotionTargets: [CoachRole] {
        switch self {
        case .offensiveCoordinator:
            return [.qbCoach, .rbCoach, .wrCoach, .olCoach]
        case .defensiveCoordinator:
            return [.dlCoach, .lbCoach, .dbCoach]
        case .assistantHeadCoach:
            return [.offensiveCoordinator, .defensiveCoordinator]
        default:
            return []
        }
    }
}
