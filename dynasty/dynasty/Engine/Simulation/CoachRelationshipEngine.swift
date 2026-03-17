import Foundation

// MARK: - CoachRelationshipEngine

/// Stateless engine that drives HC-GM relationship dynamics and coaching tree tracking
/// in Sunday Night Dynasty. All methods are pure functions or mutate only their
/// explicit inout parameters.
enum CoachRelationshipEngine {

    // MARK: - HC-GM Relationship

    /// The current state of the working relationship between a GM and their Head Coach.
    ///
    /// Harmony represents how well the two align on roster construction, scheme philosophy,
    /// and day-to-day decision-making. Low harmony surfaces as media stories and owner concern.
    struct HCGMRelationship: Codable {
        /// Overall relationship health on a 0–100 scale.
        /// 80–100: Strong alignment. 50–79: Workable tension. 0–49: Fractured relationship.
        var harmony: Int

        /// Count of recent disagreements (trades, draft picks, FA signings) this season.
        var disagreements: Int

        /// Count of disagreements that spilled into the media (press conferences, leaks).
        var publicConflicts: Int

        init(harmony: Int = 70, disagreements: Int = 0, publicConflicts: Int = 0) {
            self.harmony = harmony
            self.disagreements = disagreements
            self.publicConflicts = publicConflicts
        }
    }

    // MARK: calculateHarmony

    /// Evaluates the starting-point harmony between a GM and their Head Coach based on
    /// personality compatibility, scheme philosophy alignment, and recent win context.
    ///
    /// - Parameters:
    ///   - career: The player's current career (must be `.gm` role).
    ///   - headCoach: The team's Head Coach.
    ///   - teamWins: Wins so far this season (smooths over conflicts when high).
    /// - Returns: A freshly calculated `HCGMRelationship`.
    static func calculateHarmony(
        career: Career,
        headCoach: Coach,
        teamWins: Int = 0
    ) -> HCGMRelationship {
        var baseHarmony = 60  // Neutral starting point

        // MARK: Personality Compatibility
        // Some personality pairings are naturally collaborative; others create friction.
        let personalityBonus = personalityHarmonyBonus(
            gmPersonalityProxy: career.reputation,
            hcPersonality: headCoach.personality
        )
        baseHarmony += personalityBonus

        // MARK: Scheme Alignment
        // GMs who draft and sign players that fit the HC's scheme avoid friction.
        // Represented here as a function of HC adaptability—a flexible coach cares less
        // about roster mismatch than an inflexible one.
        let schemeTension = schemeMismatchPenalty(headCoach: headCoach)
        baseHarmony -= schemeTension

        // MARK: Winning Smooths Over Conflicts
        // A successful season gives both parties reason to overlook differences.
        let winBonus: Int
        switch teamWins {
        case 12...: winBonus = 10
        case 9...11: winBonus = 5
        case 6...8:  winBonus = 0
        default:     winBonus = -5
        }
        baseHarmony += winBonus

        // MARK: HC Personality Stability
        // Drama-prone HCs are inherently more volatile to work with.
        let volatilityPenalty = hcVolatilityPenalty(headCoach.personality)
        baseHarmony -= volatilityPenalty

        let clamped = min(100, max(0, baseHarmony))
        return HCGMRelationship(harmony: clamped)
    }

    // MARK: hcDisagreesWithDecision

    /// Determines whether the Head Coach publicly voices disagreement with a GM decision.
    ///
    /// Higher-meddling personalities (fiery competitor, drama queen) are more likely to
    /// speak out. The HC's reputation also matters—a high-rep HC has more political capital
    /// to push back.
    ///
    /// - Parameters:
    ///   - headCoach: The team's Head Coach.
    ///   - decisionType: A human-readable string describing the decision
    ///                   (e.g. "draft pick", "trade", "free agency signing").
    ///   - currentHarmony: The current harmony score (lower harmony → more likely to disagree).
    /// - Returns: `true` if the HC voices public disagreement.
    static func hcDisagreesWithDecision(
        headCoach: Coach,
        decisionType: String,
        currentHarmony: Int = 70
    ) -> Bool {
        // Base disagreement probability driven by harmony deficit
        let harmonyDeficit = max(0, 70 - currentHarmony)
        var disagreementChance = Double(harmonyDeficit) / 70.0 * 0.30   // 0–30% from harmony

        // Personality modifier: meddling personalities push back more
        let personalityModifier = hcMeddlingFactor(headCoach.personality)
        disagreementChance += personalityModifier

        // Reputation modifier: high-rep coaches have the leverage to speak out
        let repFactor = Double(headCoach.reputation) / 99.0 * 0.10     // up to +10%
        disagreementChance += repFactor

        // Decision type sensitivity: draft picks and roster cuts generate the most friction
        let decisionSensitivity: Double
        switch decisionType.lowercased() {
        case let d where d.contains("draft"):       decisionSensitivity = 0.10
        case let d where d.contains("trade"):       decisionSensitivity = 0.08
        case let d where d.contains("free agency"): decisionSensitivity = 0.06
        case let d where d.contains("cut"):         decisionSensitivity = 0.07
        default:                                     decisionSensitivity = 0.03
        }
        disagreementChance += decisionSensitivity

        return Double.random(in: 0.0..<1.0) < min(0.85, disagreementChance)
    }

    // MARK: applyDisagreement

    /// Updates a relationship record after a GM decision the HC disagreed with.
    ///
    /// - Parameters:
    ///   - relationship: The HC-GM relationship to mutate.
    ///   - isPublic: Whether the disagreement reached the media.
    static func applyDisagreement(
        relationship: inout HCGMRelationship,
        isPublic: Bool
    ) {
        relationship.disagreements += 1
        // Each disagreement erodes harmony; public spats hurt more.
        let harmonyLoss = isPublic ? 8 : 3
        relationship.harmony = max(0, relationship.harmony - harmonyLoss)

        if isPublic {
            relationship.publicConflicts += 1
        }
    }

    /// Applies a harmony boost after a shared success (win, playoff appearance, etc.).
    ///
    /// - Parameters:
    ///   - relationship: The HC-GM relationship to mutate.
    ///   - magnitude: Points of harmony to restore (default 5).
    static func applySharedSuccess(
        relationship: inout HCGMRelationship,
        magnitude: Int = 5
    ) {
        relationship.harmony = min(100, relationship.harmony + magnitude)
    }

    // MARK: - Coaching Tree

    /// A record of one coach who worked under the player during their career.
    struct CoachingTreeEntry: Codable, Identifiable {
        let id: UUID
        /// Full name of the coach (snapshot at time of entry).
        let coachName: String
        /// The role the coach held while working under the player.
        let role: CoachRole
        /// Season in which this coach joined the staff.
        let yearHired: Int
        /// Season in which this coach departed (nil if still active).
        var yearLeft: Int?
        /// Where the coach went (e.g. "HC at Dallas Cowboys", "Retired", "OC at Seattle").
        var destination: String?
        /// Whether the coach achieved measurable success at their next stop.
        var wasSuccessful: Bool

        init(
            id: UUID = UUID(),
            coachName: String,
            role: CoachRole,
            yearHired: Int,
            yearLeft: Int? = nil,
            destination: String? = nil,
            wasSuccessful: Bool = false
        ) {
            self.id = id
            self.coachName = coachName
            self.role = role
            self.yearHired = yearHired
            self.yearLeft = yearLeft
            self.destination = destination
            self.wasSuccessful = wasSuccessful
        }
    }

    // MARK: updateCoachingTree

    /// Records an event in the player's coaching tree.
    ///
    /// Typical events: `"hired"`, `"promoted"`, `"departed_hc"`, `"departed_coord"`, `"retired"`.
    ///
    /// - Parameters:
    ///   - tree: The player's coaching tree array (mutated in place).
    ///   - coach: The coach involved in the event.
    ///   - event: A string describing the event type.
    ///   - season: The current season year.
    ///   - destination: Optional destination description (used when the coach departs).
    static func updateCoachingTree(
        tree: inout [CoachingTreeEntry],
        coach: Coach,
        event: String,
        season: Int,
        destination: String? = nil
    ) {
        switch event.lowercased() {

        case "hired":
            // Only add a new entry if one doesn't already exist for this coach-season
            let alreadyTracked = tree.contains { $0.coachName == coach.fullName && $0.yearLeft == nil }
            guard !alreadyTracked else { return }
            let entry = CoachingTreeEntry(
                coachName: coach.fullName,
                role: coach.role,
                yearHired: season
            )
            tree.append(entry)

        case "departed_hc", "departed_coord", "departed_other", "retired":
            // Close out the open entry for this coach
            guard let idx = tree.firstIndex(where: { $0.coachName == coach.fullName && $0.yearLeft == nil }) else { return }
            tree[idx].yearLeft = season
            tree[idx].destination = destination

            // Departures to HC or coordinator roles flag potential future success
            // (wasSuccessful is updated later via markCoachingTreeSuccess)
            if event == "departed_hc" {
                tree[idx].destination = destination ?? "HC opportunity"
            } else if event == "retired" {
                tree[idx].destination = destination ?? "Retired"
            }

        default:
            break
        }
    }

    /// Marks a departed coaching tree alumnus as successful (or not) at their next stop.
    ///
    /// Call this at end-of-season when poached coordinators/coaches show results.
    ///
    /// - Parameters:
    ///   - tree: The player's coaching tree array (mutated in place).
    ///   - coachName: Full name of the coach to update.
    ///   - wasSuccessful: Whether the coach thrived in their new role.
    static func markCoachingTreeSuccess(
        tree: inout [CoachingTreeEntry],
        coachName: String,
        wasSuccessful: Bool
    ) {
        guard let idx = tree.firstIndex(where: { $0.coachName == coachName && $0.yearLeft != nil }) else { return }
        tree[idx].wasSuccessful = wasSuccessful
    }

    // MARK: - Coaching Tree Legacy Score

    /// Calculates a 0–100 legacy score based on how many coaches the player developed
    /// and how successful those coaches went on to be.
    ///
    /// - Parameter tree: The full coaching tree history.
    /// - Returns: Legacy score clamped to `0...100`.
    static func legacyScore(for tree: [CoachingTreeEntry]) -> Int {
        guard !tree.isEmpty else { return 0 }

        let departed = tree.filter { $0.yearLeft != nil }
        guard !departed.isEmpty else { return 0 }

        // Coaches who left for HC jobs contribute the most to legacy
        let hcDepartures = departed.filter {
            $0.destination?.lowercased().contains("hc") == true ||
            $0.destination?.lowercased().contains("head coach") == true
        }
        let successfulDepartures = departed.filter { $0.wasSuccessful }

        // Scoring: each departed coach = 2 pts, each successful = +3 pts, each HC = +5 pts
        let baseScore = departed.count * 2
        let successBonus = successfulDepartures.count * 3
        let hcBonus = hcDepartures.count * 5

        return min(100, baseScore + successBonus + hcBonus)
    }
}

// MARK: - Private Helpers

private extension CoachRelationshipEngine {

    /// Returns a harmony bonus based on how well the HC's personality meshes with a GM's
    /// typical management style, proxied by reputation tier.
    ///
    /// Mentor and quiet professional HCs collaborate well with most GMs.
    /// Fiery competitor and drama queen HCs require high harmony to function.
    static func personalityHarmonyBonus(
        gmPersonalityProxy reputation: Int,
        hcPersonality: PersonalityArchetype
    ) -> Int {
        let isHighRepGM = reputation >= 65

        switch hcPersonality {
        case .quietProfessional: return  8   // Reliable, minimal friction
        case .steadyPerformer:   return  6   // Consistent, easy to plan around
        case .mentor:            return  5   // Collaborative; values long-term thinking
        case .teamLeader:        return  4   // Wants alignment; friction if ignored
        case .fieryCompetitor:   return isHighRepGM ?  2 : -4  // Needs a strong GM partner
        case .loneWolf:          return -3   // Prefers autonomy; clashes with active GMs
        case .feelPlayer:        return  0   // Variable; mood-dependent alignment
        case .dramaQueen:        return -6   // Media magnets; constant low-level tension
        case .classClown:        return  1   // Light tension, rarely serious conflicts
        }
    }

    /// Returns a harmony penalty based on how inflexible the HC is about scheme fit.
    ///
    /// Low adaptability + opinionated personality = higher tension when the GM builds
    /// a roster that doesn't match the HC's preferred scheme.
    static func schemeMismatchPenalty(headCoach: Coach) -> Int {
        let inflexibility = max(0, 60 - headCoach.adaptability)   // 0 if adaptable
        let schemeOpinion: Int
        switch headCoach.personality {
        case .fieryCompetitor, .loneWolf: schemeOpinion = 5       // Very scheme-opinionated
        case .mentor, .teamLeader:        schemeOpinion = 2
        default:                          schemeOpinion = 0
        }
        // Scale: 0 (fully flexible) → max ~14 pts of tension
        return min(14, inflexibility / 5 + schemeOpinion)
    }

    /// Returns the base probability modifier for how often a given HC personality
    /// voices disagreements with GM decisions (meddling factor).
    static func hcMeddlingFactor(_ personality: PersonalityArchetype) -> Double {
        switch personality {
        case .fieryCompetitor: return 0.18   // Loudest pushback
        case .dramaQueen:      return 0.15   // Always has opinions, loves conflict
        case .teamLeader:      return 0.10   // Speaks up when he feels ownership is necessary
        case .loneWolf:        return 0.08   // Doesn't want the GM involved at all
        case .mentor:          return 0.05   // Expresses concern diplomatically
        case .feelPlayer:      return 0.07   // Speaks up when something "doesn't feel right"
        case .classClown:      return 0.04   // Rarely serious enough to formally disagree
        case .steadyPerformer: return 0.03   // Trusts the process
        case .quietProfessional: return 0.02 // Keeps disagreements private
        }
    }

    /// Returns a harmony penalty for volatile HC personalities that inherently create
    /// media friction regardless of roster decisions.
    static func hcVolatilityPenalty(_ personality: PersonalityArchetype) -> Int {
        switch personality {
        case .dramaQueen:      return 8
        case .fieryCompetitor: return 5
        case .feelPlayer:      return 3
        case .loneWolf:        return 4
        case .classClown:      return 2
        default:               return 0
        }
    }
}
