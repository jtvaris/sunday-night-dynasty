import Foundation

enum PersonalityArchetype: String, Codable, CaseIterable {
    case teamLeader       = "TeamLeader"
    case loneWolf         = "LoneWolf"
    case feelPlayer       = "FeelPlayer"
    case steadyPerformer  = "SteadyPerformer"
    case dramaQueen       = "DramaQueen"
    case quietProfessional = "QuietProfessional"
    case mentor           = "Mentor"
    case fieryCompetitor  = "FieryCompetitor"
    case classClown       = "ClassClown"

    var displayName: String {
        switch self {
        case .teamLeader:        return "Team Leader"
        case .loneWolf:          return "Lone Wolf"
        case .feelPlayer:        return "Feel Player"
        case .steadyPerformer:   return "Steady Performer"
        case .dramaQueen:        return "Drama Queen"
        case .quietProfessional: return "Quiet Professional"
        case .mentor:            return "Mentor"
        case .fieryCompetitor:   return "Fiery Competitor"
        case .classClown:        return "Class Clown"
        }
    }

    /// #148: Short label for cramped table rows.
    var shortLabel: String {
        switch self {
        case .teamLeader:        return "Leader"
        case .loneWolf:          return "Lone Wolf"
        case .feelPlayer:        return "Instinct"
        case .steadyPerformer:   return "Steady"
        case .dramaQueen:        return "Drama"
        case .quietProfessional: return "Quiet Pro"
        case .mentor:            return "Mentor"
        case .fieryCompetitor:   return "Fiery"
        case .classClown:        return "Clown"
        }
    }

    /// What the archetype actually DOES for the club, in one sentence.
    ///
    /// The name alone was the whole read: a card printed "Mentor" in a tinted
    /// capsule and left the user to guess whether that was worth a round. Every
    /// clause below is a real term somewhere in the engine —
    /// `LockerRoomEngine.calculateChemistry` (leadership / toxicity),
    /// `updateSeasonalMorale` and `updateWeeklyMorale` (the swing multipliers),
    /// `LockerRoomEngine.activeMentorships` (who tutors whom),
    /// `activeConflicts` (the hothead pair) and
    /// `ContractNegotiationEngine`'s archetype term (the discount or premium).
    /// Nothing here promises an effect the simulation does not carry.
    var effectSummary: String {
        switch self {
        case .teamLeader:
            return "Lifts team chemistry every week his morale holds up, and re-signs for under market with the club he already plays for."
        case .loneWolf:
            return "Barely moves with the room's morale, wants his money in full, and pulls against your leaders and mentors."
        case .feelPlayer:
            return "Rides form hard \u{2014} a hot streak lifts him further than anyone, a cold one costs him more."
        case .steadyPerformer:
            return "Immune to streaks: his morale hardly moves in either direction, and he signs a little under market."
        case .dramaQueen:
            return "Adds toxicity when he is unhappy, amplifies every bad week, and charges the largest premium on the board to sign."
        case .quietProfessional:
            return "Absorbs the volatility around him, pairs best with a mentor, and signs slightly under market."
        case .mentor:
            return "Tutors a young teammate at his position \u{2014} the protege develops faster \u{2014} and takes a discount to stay."
        case .fieryCompetitor:
            return "Rides form, wants his touches, and can set a position room alight beside another hothead."
        case .classClown:
            return "Loosens the room but swings with form, and grates on the mentors trying to run a professional position group."
        }
    }

    /// Personality tier for badge coloring: positive, risky, or neutral.
    var tier: PersonalityTier {
        switch self {
        case .teamLeader, .steadyPerformer, .quietProfessional, .mentor:
            return .positive
        case .dramaQueen, .fieryCompetitor:
            return .risky
        case .loneWolf, .feelPlayer, .classClown:
            return .neutral
        }
    }

    /// Personality score contribution for interview grading (-10 to +10).
    var interviewScoreContribution: Int {
        switch tier {
        case .positive: return 10
        case .neutral:  return 0
        case .risky:    return -10
        }
    }

    // MARK: - Mental Game (#36B)

    /// Rides form hard (mech 1): competitors and free spirits catch fire on a
    /// hot streak and press when cold.
    var isFormSensitive: Bool {
        switch self {
        case .fieryCompetitor, .feelPlayer, .dramaQueen, .classClown: return true
        default: return false
        }
    }

    /// Immune to streaks (mech 1): the metronome pros play the same every snap.
    var isFormImmune: Bool {
        self == .steadyPerformer || self == .quietProfessional
    }

    /// Me-first temperaments prone to ego frustration when starved of touches
    /// (mech 2) — the fiery star, the diva, and the lone wolf.
    var isEgoArchetype: Bool {
        switch self {
        case .fieryCompetitor, .dramaQueen, .loneWolf: return true
        default: return false
        }
    }
}

enum PersonalityTier {
    case positive, neutral, risky
}
