import Foundation

// MARK: - CoachingEngine

/// Stateless engine that drives all coaching-related calculations in Sunday Night Dynasty.
/// All methods are pure functions or mutate only their explicit inout / reference parameters.
enum CoachingEngine {

    // MARK: - Scheme Fit

    /// Returns a 0.0–1.0 rating representing how well a player fits the given offensive
    /// and/or defensive schemes. A higher score means the player's position-specific
    /// attributes are strongly aligned with what the scheme demands.
    ///
    /// - Parameters:
    ///   - player: The player being evaluated.
    ///   - offensiveScheme: The team's current offensive scheme, if any.
    ///   - defensiveScheme: The team's current defensive scheme, if any.
    /// - Returns: Scheme fit score clamped to `0.0...1.0`.
    static func schemeFit(
        player: Player,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        var rawScore: Double = 0.5         // Neutral baseline
        var evaluated = false              // Did any scheme clause apply?

        // MARK: Offensive Scheme Evaluation

        if let scheme = offensiveScheme {
            switch scheme {

            // Air Raid: pass-heavy; values QB accuracy and WR route running
            case .airRaid:
                switch player.positionAttributes {
                case .quarterback(let attr):
                    let accuracy = Double(attr.accuracyShort + attr.accuracyMid + attr.accuracyDeep) / 3.0
                    rawScore = normalize(accuracy)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.routeRunning))
                    evaluated = true
                case .tightEnd(let attr):
                    // TEs used as safety valves; route running matters more than blocking
                    rawScore = normalize(Double(attr.routeRunning + attr.catching) / 2.0)
                    evaluated = true
                default: break
                }

            // West Coast: timing routes, short/mid accuracy, receiving backs
            case .westCoast:
                switch player.positionAttributes {
                case .quarterback(let attr):
                    let shortMid = Double(attr.accuracyShort + attr.accuracyMid) / 2.0
                    rawScore = normalize(Double(attr.pocketPresence) * 0.4 + shortMid * 0.6)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.routeRunning + attr.catching) / 2.0)
                    evaluated = true
                case .runningBack(let attr):
                    // Receiving back is a core piece
                    rawScore = normalize(Double(attr.receiving + attr.elusiveness) / 2.0)
                    evaluated = true
                default: break
                }

            // Spread: pace, scrambling QBs, speed at all skill positions
            case .spread:
                switch player.positionAttributes {
                case .quarterback(let attr):
                    rawScore = normalize(Double(attr.scrambling) * 0.5 + Double(attr.accuracyShort) * 0.5)
                    evaluated = true
                case .wideReceiver(let attr):
                    let speedBonus = normalize(Double(player.physical.speed))
                    let route = normalize(Double(attr.routeRunning))
                    rawScore = speedBonus * 0.4 + route * 0.6
                    evaluated = true
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.elusiveness + attr.receiving) / 2.0)
                    evaluated = true
                default: break
                }

            // Power Run: physical OL and powerful backs; deep-ball threats as play-action window dressers
            case .powerRun:
                switch player.positionAttributes {
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.breakTackle) * 0.5 + Double(player.physical.strength) * 0.5)
                    evaluated = true
                case .offensiveLine(let attr):
                    rawScore = normalize(Double(attr.runBlock + attr.anchor) / 2.0)
                    evaluated = true
                case .quarterback(let attr):
                    // QB mostly hands off; pocket presence is what matters
                    rawScore = normalize(Double(attr.pocketPresence))
                    evaluated = true
                default: break
                }

            // Shanahan (Outside Zone): athletic OL, vision backs, TE as pass-catchers
            case .shanahan:
                switch player.positionAttributes {
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.vision) * 0.5 + Double(player.physical.agility) * 0.5)
                    evaluated = true
                case .offensiveLine(let attr):
                    rawScore = normalize(Double(attr.runBlock + attr.pull) / 2.0)
                    evaluated = true
                case .tightEnd(let attr):
                    rawScore = normalize(Double(attr.catching + attr.routeRunning) / 2.0)
                    evaluated = true
                default: break
                }

            // Pro Passing: traditional drop-back; arm strength, pocket QBs, big WRs
            case .proPassing:
                switch player.positionAttributes {
                case .quarterback(let attr):
                    let deepAccuracy = Double(attr.accuracyDeep + attr.armStrength) / 2.0
                    rawScore = normalize(deepAccuracy * 0.5 + Double(attr.pocketPresence) * 0.5)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.catching + attr.spectacularCatch) / 2.0)
                    evaluated = true
                case .offensiveLine(let attr):
                    rawScore = normalize(Double(attr.passBlock + attr.anchor) / 2.0)
                    evaluated = true
                default: break
                }

            // RPO: dual-threat QBs, quick-twitch RBs and slot WRs
            case .rpo:
                switch player.positionAttributes {
                case .quarterback(let attr):
                    rawScore = normalize(Double(attr.scrambling + attr.pocketPresence) / 2.0)
                    evaluated = true
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.vision + attr.elusiveness) / 2.0)
                    evaluated = true
                case .wideReceiver(let attr):
                    rawScore = normalize(Double(attr.routeRunning + attr.release) / 2.0)
                    evaluated = true
                default: break
                }

            // Option: mobile QBs and powerful fullback-style RBs
            case .option:
                switch player.positionAttributes {
                case .quarterback(let attr):
                    let mobility = Double(player.physical.speed + player.physical.agility) / 2.0
                    rawScore = normalize(Double(attr.scrambling) * 0.5 + normalize(mobility) * 0.5)
                    evaluated = true
                case .runningBack(let attr):
                    rawScore = normalize(Double(attr.breakTackle + attr.elusiveness) / 2.0)
                    evaluated = true
                default: break
                }
            }
        }

        // MARK: Defensive Scheme Evaluation

        if let scheme = defensiveScheme {
            switch scheme {

            // 3-4 Base: bigger DEs that can two-gap; OLBs as pass rushers/blitzers
            case .base34:
                switch player.positionAttributes {
                case .defensiveLine(let attr):
                    rawScore = normalize(Double(attr.blockShedding + attr.powerMoves) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.blitzing + attr.tackling) / 2.0)
                    evaluated = true
                default: break
                }

            // 4-3 Base: one-gap penetrating DEs, athletic MLBs
            case .base43:
                switch player.positionAttributes {
                case .defensiveLine(let attr):
                    rawScore = normalize(Double(attr.passRush + attr.finesseMoves) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.tackling + attr.zoneCoverage) / 2.0)
                    evaluated = true
                default: break
                }

            // Cover 3: zone CBs, range-covering safeties
            case .cover3:
                switch player.positionAttributes {
                case .defensiveBack(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage + attr.ballSkills) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage))
                    evaluated = true
                default: break
                }

            // Press Man: physical press-capable CBs with man coverage skills
            case .pressMan:
                switch player.positionAttributes {
                case .defensiveBack(let attr):
                    rawScore = normalize(Double(attr.press + attr.manCoverage) / 2.0)
                    evaluated = true
                default: break
                }

            // Tampa 2: zone-heavy; CBs with zone IQ, LBs that can drop into coverage
            case .tampa2:
                switch player.positionAttributes {
                case .defensiveBack(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage + attr.ballSkills) / 2.0)
                    evaluated = true
                case .linebacker(let attr):
                    rawScore = normalize(Double(attr.zoneCoverage + attr.manCoverage) / 2.0)
                    evaluated = true
                default: break
                }

            // Multiple: versatile players who can play several techniques
            case .multiple:
                // Reward high awareness and physical versatility across all defensive positions
                let mentalFlex = normalize(Double(player.mental.awareness + player.mental.decisionMaking) / 2.0)
                let physFlex = normalize(Double(player.physical.agility + player.physical.speed) / 2.0)
                switch player.positionAttributes {
                case .defensiveBack, .linebacker, .defensiveLine:
                    rawScore = mentalFlex * 0.5 + physFlex * 0.5
                    evaluated = true
                default: break
                }

            // Hybrid: speed/athleticism on every level of the defense
            case .hybrid:
                let athleticism = normalize(Double(player.physical.speed + player.physical.agility + player.physical.acceleration) / 3.0)
                switch player.positionAttributes {
                case .defensiveBack, .linebacker, .defensiveLine:
                    rawScore = athleticism
                    evaluated = true
                default: break
                }
            }
        }

        // MARK: Adaptability Bonus

        // A player with high adaptability gets up to +0.05 added to their fit score,
        // regardless of scheme—they learn any system faster.
        let adaptabilityBonus = Double(player.mental.awareness) / 99.0 * 0.05

        // MARK: Non-evaluated Positions

        // If neither scheme clause applied (e.g., a kicker in an offensive scheme context),
        // return a neutral 0.5 with only the adaptability bonus applied.
        if !evaluated {
            return min(1.0, 0.5 + adaptabilityBonus)
        }

        return min(1.0, max(0.0, rawScore + adaptabilityBonus))
    }

    // MARK: - Coach Development

    /// Ages a coach by one year and applies end-of-season attribute changes.
    ///
    /// - Parameters:
    ///   - coach: The coach to develop (mutated in place).
    ///   - teamWins: The team's win total for the just-completed season (0–17).
    static func developCoach(_ coach: Coach, teamWins: Int) {
        // Age and experience
        coach.age += 1
        coach.yearsExperience += 1

        // MARK: Young/Mid-Career Growth (< 15 years experience)
        if coach.yearsExperience < 15 {
            // Randomly improve 1–3 attributes each offseason
            let improvementCount = Int.random(in: 1...3)
            var attributes = [
                \Coach.playCalling,
                \Coach.playerDevelopment,
                \Coach.adaptability
            ]
            attributes.shuffle()
            for i in 0..<improvementCount {
                let kp = attributes[i]
                let current = coach[keyPath: kp]
                let gain = Int.random(in: 1...3)
                coach[keyPath: kp] = min(99, current + gain)
            }
        }

        // MARK: Veteran Decline (20+ years experience)
        // Experienced coaches may lose a step mentally—primarily in adaptability.
        if coach.yearsExperience >= 20 {
            let declineChance = Double(coach.yearsExperience - 20) * 0.04  // 4% per year past 20
            if Double.random(in: 0.0..<1.0) < declineChance {
                coach.adaptability = max(1, coach.adaptability - Int.random(in: 1...2))
                coach.playCalling  = max(1, coach.playCalling  - Int.random(in: 0...1))
            }
        }

        // MARK: Reputation Change Based on Win Total
        // Win total context: 0–4 poor, 5–8 average, 9–11 good, 12–17 elite
        let reputationDelta: Int
        switch teamWins {
        case 14...17: reputationDelta = Int.random(in: 3...6)
        case 11...13: reputationDelta = Int.random(in: 1...3)
        case 8...10:  reputationDelta = Int.random(in: -1...1)
        case 5...7:   reputationDelta = Int.random(in: -3...(-1))
        default:      reputationDelta = Int.random(in: -6...(-3))
        }
        coach.reputation = min(99, max(1, coach.reputation + reputationDelta))
    }

    // MARK: - Hiring Market

    /// Generates a pool of coaching candidates available for the given role.
    ///
    /// - Parameters:
    ///   - role: The coaching role being filled.
    ///   - count: How many candidates to generate.
    /// - Returns: An array of freshly created `Coach` objects not yet attached to any team.
    static func generateCoachCandidates(role: CoachRole, count: Int) -> [Coach] {
        (0..<count).map { _ in
            let name = RandomNameGenerator.randomName()

            // Age distribution: young assistants skew lower, coordinators/HC skew older
            let ageRange: ClosedRange<Int>
            let expRange: ClosedRange<Int>
            switch role {
            case .headCoach:
                ageRange = 40...65
                expRange = 12...30
            case .offensiveCoordinator, .defensiveCoordinator:
                ageRange = 35...58
                expRange = 8...22
            case .specialTeamsCoordinator:
                ageRange = 33...55
                expRange = 6...20
            default: // position coaches
                ageRange = 28...52
                expRange = 2...15
            }

            let age = Int.random(in: ageRange)
            let exp = Int.random(in: expRange)

            // Attribute ceilings correlated with experience
            let baseCeiling = min(99, 45 + exp * 2)
            let baseFloor   = max(30, baseCeiling - 30)

            func randAttr() -> Int { Int.random(in: baseFloor...baseCeiling) }

            // Scheme assignment: offensive roles get offensive schemes, defensive get defensive
            let offScheme: OffensiveScheme? = offensiveRole(role) ? OffensiveScheme.allCases.randomElement() : nil
            let defScheme: DefensiveScheme? = defensiveRole(role) ? DefensiveScheme.allCases.randomElement() : nil

            // Head coaches may know both
            let finalOffScheme: OffensiveScheme?
            let finalDefScheme: DefensiveScheme?
            if role == .headCoach {
                finalOffScheme = Bool.random() ? OffensiveScheme.allCases.randomElement() : nil
                finalDefScheme = Bool.random() ? DefensiveScheme.allCases.randomElement() : nil
            } else {
                finalOffScheme = offScheme
                finalDefScheme = defScheme
            }

            return Coach(
                firstName: name.first,
                lastName: name.last,
                age: age,
                role: role,
                offensiveScheme: finalOffScheme,
                defensiveScheme: finalDefScheme,
                playCalling: randAttr(),
                playerDevelopment: randAttr(),
                reputation: randAttr(),
                adaptability: randAttr(),
                personality: PersonalityArchetype.allCases.randomElement() ?? .quietProfessional,
                teamID: nil,
                yearsExperience: exp
            )
        }
    }

    // MARK: - Coordinator Poaching

    /// Evaluates a coaching staff and returns the subset of coordinators or position coaches
    /// who may receive head-coaching offers based on their reputation and the team's success.
    ///
    /// - Parameters:
    ///   - coaches: The full coaching staff to evaluate.
    ///   - teamWins: The team's win total for the season.
    /// - Returns: Coaches currently being targeted with HC offers (may be empty).
    static func checkCoordinatorPoaching(coaches: [Coach], teamWins: Int) -> [Coach] {
        // Only non-HC roles are eligible for poaching
        let candidates = coaches.filter { $0.role != .headCoach }

        // Win bonus: teams on winning records attract more HC searches
        let winBonus: Double
        switch teamWins {
        case 12...: winBonus = 0.15
        case 9...11: winBonus = 0.07
        case 6...8:  winBonus = 0.0
        default:     winBonus = -0.05
        }

        return candidates.filter { coach in
            // Base probability driven by reputation (0–99 mapped to 0.0–0.40)
            let reputationFactor = Double(coach.reputation) / 99.0 * 0.40

            // Coordinators are far more visible than position coaches
            let rolePremium: Double
            switch coach.role {
            case .offensiveCoordinator, .defensiveCoordinator:
                rolePremium = 0.15
            case .specialTeamsCoordinator, .qbCoach:
                rolePremium = 0.05
            default:
                rolePremium = 0.0
            }

            let poachChance = max(0.0, reputationFactor + rolePremium + winBonus)
            return Double.random(in: 0.0..<1.0) < poachChance
        }
    }

    // MARK: - Player Development Bonus

    /// Calculates a multiplier applied to a player's development rate under a given coach.
    ///
    /// - Parameters:
    ///   - coach: The coach overseeing this player's development.
    ///   - player: The player being developed.
    /// - Returns: Multiplier in the range `0.8...1.5`.
    static func coachDevelopmentBonus(coach: Coach, player: Player) -> Double {
        var multiplier: Double = 1.0

        // MARK: Coach playerDevelopment Attribute
        // 50 is neutral; each point above/below shifts the multiplier by ~0.004
        let devAttributeBonus = (Double(coach.playerDevelopment) - 50.0) / 50.0 * 0.2
        multiplier += devAttributeBonus

        // MARK: Position Role Match
        // A coach who specializes in this player's position group provides an extra boost
        let positionMatch = positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
        multiplier += positionMatch ? 0.15 : 0.0

        // MARK: Scheme Fit Contribution
        // Players in a good scheme fit develop faster because reps translate to real growth
        let fit = schemeFit(
            player: player,
            offensiveScheme: coach.offensiveScheme,
            defensiveScheme: coach.defensiveScheme
        )
        // Scheme fit of 0.5 is neutral; range contributes −0.05 to +0.10
        let schemeFitBonus = (fit - 0.5) * 0.20
        multiplier += schemeFitBonus

        // MARK: Personality Compatibility
        multiplier += personalityCompatibility(coachPersonality: coach.personality, playerPersonality: player.personality)

        // MARK: Player Coachability
        // High coachability amplifies coaching; low coachability diminishes it
        let coachabilityFactor = (Double(player.mental.coachability) - 50.0) / 50.0 * 0.10
        multiplier += coachabilityFactor

        // MARK: Player Work Ethic
        let workEthicFactor = (Double(player.mental.workEthic) - 50.0) / 50.0 * 0.05
        multiplier += workEthicFactor

        return min(1.5, max(0.8, multiplier))
    }

    // MARK: - Position Role Matching

    /// Returns `true` if the coach's role is a direct position-group match for the player.
    static func positionRoleMatch(coachRole: CoachRole, playerPosition: Position) -> Bool {
        switch coachRole {
        case .qbCoach:
            return playerPosition == .QB
        case .rbCoach:
            return playerPosition == .RB || playerPosition == .FB
        case .wrCoach:
            return playerPosition == .WR || playerPosition == .TE
        case .olCoach:
            return [.LT, .LG, .C, .RG, .RT].contains(playerPosition)
        case .dlCoach:
            return [.DE, .DT].contains(playerPosition)
        case .lbCoach:
            return [.MLB, .OLB].contains(playerPosition)
        case .dbCoach:
            return [.CB, .FS, .SS].contains(playerPosition)
        case .strengthCoach:
            return true  // Strength coach benefits every player equally
        default:
            return false
        }
    }
}

// MARK: - Private Helpers

private extension CoachingEngine {

    /// Maps a raw attribute value (1–99) to a 0.0–1.0 normalized score.
    static func normalize(_ value: Double) -> Double {
        (value - 1.0) / 98.0
    }

    /// Returns `true` if the coach role is primarily offensive.
    static func offensiveRole(_ role: CoachRole) -> Bool {
        switch role {
        case .offensiveCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach:
            return true
        default:
            return false
        }
    }

    /// Returns `true` if the coach role is primarily defensive.
    static func defensiveRole(_ role: CoachRole) -> Bool {
        switch role {
        case .defensiveCoordinator, .dlCoach, .lbCoach, .dbCoach:
            return true
        default:
            return false
        }
    }

    /// Returns a bonus/penalty based on how well the coach and player personalities mesh.
    ///
    /// Range is roughly −0.10 to +0.10.
    static func personalityCompatibility(
        coachPersonality: PersonalityArchetype,
        playerPersonality: PlayerPersonality
    ) -> Double {
        let playerArch = playerPersonality.archetype

        switch coachPersonality {

        // Mentor coaches draw out the best in coachable, team-oriented players; clash with lone wolves
        case .mentor:
            switch playerArch {
            case .quietProfessional, .steadyPerformer, .teamLeader: return  0.08
            case .mentor:                                            return  0.04
            case .loneWolf:                                          return -0.06
            case .dramaQueen:                                        return -0.04
            default:                                                 return  0.02
            }

        // Team leaders inspire willing players but butt heads with dramatic or lone-wolf personalities
        case .teamLeader:
            switch playerArch {
            case .teamLeader, .steadyPerformer, .quietProfessional: return  0.06
            case .fieryCompetitor:                                   return  0.04
            case .dramaQueen, .loneWolf:                             return -0.06
            default:                                                 return  0.01
            }

        // Fiery competitors push feel-players and competitors hard; grate on quiet professionals
        case .fieryCompetitor:
            switch playerArch {
            case .fieryCompetitor:                                   return  0.06
            case .feelPlayer:                                        return  0.04
            case .quietProfessional, .mentor:                        return -0.04
            case .dramaQueen:                                        return -0.08
            default:                                                 return  0.01
            }

        // Quiet professionals work well with almost everyone; zero friction
        case .quietProfessional:
            switch playerArch {
            case .dramaQueen, .classClown:                           return -0.04
            default:                                                 return  0.03
            }

        // Steady performers are reliable coaches; modest bonuses across the board
        case .steadyPerformer:
            switch playerArch {
            case .steadyPerformer, .quietProfessional:               return  0.04
            case .dramaQueen:                                        return -0.03
            default:                                                 return  0.02
            }

        // Drama Queens can energize feel-players but distract class clowns and lone wolves
        case .dramaQueen:
            switch playerArch {
            case .feelPlayer, .fieryCompetitor:                      return  0.05
            case .classClown, .loneWolf:                             return -0.08
            case .quietProfessional:                                 return -0.04
            default:                                                 return  0.0
            }

        // Lone wolf coaches are detached; work with self-sufficient players, poor with team types
        case .loneWolf:
            switch playerArch {
            case .loneWolf:                                          return  0.04
            case .teamLeader, .mentor:                               return -0.06
            default:                                                 return  0.0
            }

        // Feel players rely on vibes; great match with similarly emotional players
        case .feelPlayer:
            switch playerArch {
            case .feelPlayer, .dramaQueen:                           return  0.06
            case .steadyPerformer, .quietProfessional:               return -0.02
            default:                                                 return  0.02
            }

        // Class clowns keep the mood light; works for most but can undermine serious players
        case .classClown:
            switch playerArch {
            case .classClown, .feelPlayer, .teamLeader:              return  0.04
            case .quietProfessional, .mentor, .steadyPerformer:      return -0.04
            default:                                                  return  0.01
            }
        }
    }
}

// MARK: - PositionAttributes Convenience Extension

private extension PositionAttributes {
    /// Provides a QB's mental decision-making proxy through the Player's mental attributes
    /// when scheme calculations need it (RPO reads, option execution, etc.).
    /// This avoids coupling PositionAttributes to Player directly inside the enum switch.
    func decisionMaking_equiv(player: Player) -> Int {
        player.mental.decisionMaking
    }
}
