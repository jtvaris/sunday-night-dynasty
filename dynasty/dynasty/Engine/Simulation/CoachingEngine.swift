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
            // Pair of getter/setter closures so we can mutate @Model properties without WritableKeyPath subscript
            var attributes: [(get: () -> Int, set: (Int) -> Void)] = [
                ({ coach.playCalling },        { coach.playCalling = $0 }),
                ({ coach.playerDevelopment },   { coach.playerDevelopment = $0 }),
                ({ coach.adaptability },        { coach.adaptability = $0 }),
                ({ coach.gamePlanning },        { coach.gamePlanning = $0 }),
                ({ coach.scoutingAbility },     { coach.scoutingAbility = $0 }),
                ({ coach.recruiting },          { coach.recruiting = $0 }),
                ({ coach.motivation },          { coach.motivation = $0 }),
                ({ coach.discipline },          { coach.discipline = $0 }),
                ({ coach.mediaHandling },       { coach.mediaHandling = $0 }),
                ({ coach.moraleInfluence },     { coach.moraleInfluence = $0 })
            ]
            attributes.shuffle()
            for i in 0..<min(improvementCount, attributes.count) {
                let attr = attributes[i]
                let current = attr.get()
                let gain = Int.random(in: 1...3)
                attr.set(min(99, current + gain))
            }
        }

        // MARK: Veteran Decline (20+ years experience)
        // Experienced coaches may lose a step mentally—primarily in adaptability.
        if coach.yearsExperience >= 20 {
            let declineChance = Double(coach.yearsExperience - 20) * 0.04  // 4% per year past 20
            if Double.random(in: 0.0..<1.0) < declineChance {
                coach.adaptability = max(1, coach.adaptability - Int.random(in: 1...2))
                coach.playCalling  = max(1, coach.playCalling  - Int.random(in: 0...1))
                coach.gamePlanning = max(1, coach.gamePlanning  - Int.random(in: 0...1))
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
    /// Produces 20–30 candidates per search to populate a market of 50+ total coaches.
    ///
    /// - Parameters:
    ///   - role: The coaching role being filled.
    ///   - count: How many candidates to generate (defaults to 25).
    /// - Returns: An array of freshly created `Coach` objects not yet attached to any team.
    static func generateCoachCandidates(role: CoachRole, count: Int = 25) -> [Coach] {
        let actualCount = max(count, 20) // Floor of 20 candidates per search
        return (0..<actualCount).map { _ in
            let name = RandomNameGenerator.randomName()

            // Age distribution: young assistants skew lower, coordinators/HC skew older
            let ageRange: ClosedRange<Int>
            let expRange: ClosedRange<Int>
            switch role {
            case .headCoach:
                ageRange = 40...65
                expRange = 12...30
            case .assistantHeadCoach:
                ageRange = 38...60
                expRange = 10...25
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

            // Head coaches and assistant HCs may know both
            let finalOffScheme: OffensiveScheme?
            let finalDefScheme: DefensiveScheme?
            if role == .headCoach || role == .assistantHeadCoach {
                finalOffScheme = Bool.random() ? OffensiveScheme.allCases.randomElement() : nil
                finalDefScheme = Bool.random() ? DefensiveScheme.allCases.randomElement() : nil
            } else {
                finalOffScheme = offScheme
                finalDefScheme = defScheme
            }

            // Salary tiers by role (in thousands)
            let salary: Int
            switch role {
            case .headCoach:               salary = Int.random(in: 5_000...12_000)
            case .assistantHeadCoach:      salary = Int.random(in: 2_000...5_000)
            case .offensiveCoordinator,
                 .defensiveCoordinator:    salary = Int.random(in: 2_500...6_000)
            case .specialTeamsCoordinator: salary = Int.random(in: 1_000...2_500)
            default:                       salary = Int.random(in: 500...2_000)
            }

            let personality = PersonalityArchetype.allCases.randomElement() ?? .quietProfessional

            let coach = Coach(
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
                gamePlanning: randAttr(),
                scoutingAbility: randAttr(),
                recruiting: randAttr(),
                motivation: randAttr(),
                discipline: randAttr(),
                mediaHandling: randAttr(),
                contractNegotiation: randAttr(),
                moraleInfluence: randAttr(),
                salary: salary,
                background: "",
                personality: personality,
                teamID: nil,
                yearsExperience: exp
            )
            coach.background = generateBackground(for: coach)
            return coach
        }
    }

    // MARK: - Background Generation

    /// Generates an auto-generated coaching background / history blurb based on the coach's
    /// attributes, experience, personality, age, and scheme preferences.
    static func generateBackground(for coach: Coach) -> String {
        var parts: [String] = []

        // Experience-based opening
        let expOpeners: [String]
        switch coach.yearsExperience {
        case 0...5:
            expOpeners = [
                "A rising talent with \(coach.yearsExperience) years in the league.",
                "Young and hungry, still building his coaching resume.",
                "Fresh face on the coaching circuit with raw potential.",
                "Recently transitioned from a quality control role."
            ]
        case 6...12:
            expOpeners = [
                "Spent \(coach.yearsExperience) years climbing the coaching ladder.",
                "A mid-career coach with a growing reputation around the league.",
                "Has been steadily building his resume over \(coach.yearsExperience) seasons.",
                "Proven himself as a reliable coordinator over the past decade."
            ]
        case 13...20:
            expOpeners = [
                "A seasoned veteran with \(coach.yearsExperience) years of NFL experience.",
                "Well-respected throughout the league after nearly two decades of coaching.",
                "One of the more experienced coaches available, with \(coach.yearsExperience) years under his belt.",
                "A veteran presence who has seen it all in his \(coach.yearsExperience)-year career."
            ]
        default:
            expOpeners = [
                "A grizzled coaching lifer with \(coach.yearsExperience) years in the business.",
                "Has been coaching longer than some of his players have been alive.",
                "An old-school football mind with over two decades of experience.",
                "One of the longest-tenured coaches in professional football."
            ]
        }
        parts.append(expOpeners.randomElement()!)

        // Attribute-based flavor (pick the highest attribute for emphasis)
        let attrMap: [(String, Int)] = [
            ("play-calling", coach.playCalling),
            ("player development", coach.playerDevelopment),
            ("game planning", coach.gamePlanning),
            ("scouting", coach.scoutingAbility),
            ("recruiting", coach.recruiting),
            ("motivation", coach.motivation),
            ("discipline", coach.discipline),
            ("media handling", coach.mediaHandling),
            ("contract negotiation", coach.contractNegotiation),
            ("morale building", coach.moraleInfluence)
        ]

        if let topAttr = attrMap.max(by: { $0.1 < $1.1 }) {
            let attrPhrases: [String]
            switch topAttr.0 {
            case "play-calling":
                attrPhrases = [
                    "Known for creative play-calling that keeps defenses guessing.",
                    "His game-day play-calling is considered among the best in the league.",
                    "Offensive coordinators around the league study his play sheets."
                ]
            case "player development":
                attrPhrases = [
                    "Known for developing raw talent into starters.",
                    "Has a track record of turning late-round picks into Pro Bowlers.",
                    "Players who work under him consistently improve year over year."
                ]
            case "game planning":
                attrPhrases = [
                    "Meticulous game planner who leaves no stone unturned.",
                    "His game plans are legendary for exploiting opponent weaknesses.",
                    "Spends 18-hour days during the week perfecting his game plan."
                ]
            case "scouting":
                attrPhrases = [
                    "Has an exceptional eye for talent that others overlook.",
                    "Former scouts credit him with finding several hidden gems.",
                    "Known for spending extra hours in the film room evaluating prospects."
                ]
            case "recruiting":
                attrPhrases = [
                    "Free agents consistently cite him as a reason they signed.",
                    "His recruiting pitch is considered one of the best in the league.",
                    "Players want to play for him — it's that simple."
                ]
            case "motivation":
                attrPhrases = [
                    "His halftime speeches are the stuff of locker room legend.",
                    "Players run through walls for him on game day.",
                    "Known for getting the absolute maximum out of his roster."
                ]
            case "discipline":
                attrPhrases = [
                    "Runs a tight ship — his teams are among the least penalized in the league.",
                    "Demands accountability from every player, coach, and staff member.",
                    "His attention to detail borders on obsessive, in the best way."
                ]
            case "media handling":
                attrPhrases = [
                    "A natural in front of the cameras who shields his players from distractions.",
                    "His press conferences are masterclasses in saying nothing and everything.",
                    "The media respects him, and he uses that to protect his locker room."
                ]
            case "contract negotiation":
                attrPhrases = [
                    "Has a keen understanding of the salary cap and player value.",
                    "Works closely with the front office on roster construction.",
                    "Known for identifying value signings in free agency."
                ]
            case "morale building":
                attrPhrases = [
                    "His locker rooms are consistently described as tight-knit families.",
                    "Creates an environment where players genuinely enjoy coming to work.",
                    "Team chemistry has never been an issue under his leadership."
                ]
            default:
                attrPhrases = ["A well-rounded coaching mind."]
            }
            parts.append(attrPhrases.randomElement()!)
        }

        // Personality flavor
        switch coach.personality {
        case .fieryCompetitor:
            parts.append(["Brings an intense, fiery energy to every practice.", "His competitive fire is contagious in the building."].randomElement()!)
        case .quietProfessional:
            parts.append(["Prefers to let the results speak for themselves.", "A quiet operator who avoids the spotlight."].randomElement()!)
        case .mentor:
            parts.append(["Players describe him as a father figure in the locker room.", "Young coaches seek him out for career advice."].randomElement()!)
        case .teamLeader:
            parts.append(["A natural leader who commands respect from Day 1.", "His leadership style unites entire organizations."].randomElement()!)
        case .dramaQueen:
            parts.append(["Not afraid of controversy — thrives in the spotlight.", "His bold personality makes headlines, for better or worse."].randomElement()!)
        case .loneWolf:
            parts.append(["Keeps his inner circle small and his playbook close.", "A football hermit who lives and breathes the game in isolation."].randomElement()!)
        case .feelPlayer:
            parts.append(["Trusts his gut instincts over analytics.", "Makes decisions by feel — and his feel is usually right."].randomElement()!)
        case .classClown:
            parts.append(["Keeps the locker room loose with his sense of humor.", "Players love his lighthearted approach to a grueling season."].randomElement()!)
        case .steadyPerformer:
            parts.append(["Consistent and reliable — never the highest high or lowest low.", "His steady hand has guided teams through turbulent stretches."].randomElement()!)
        }

        // Scheme reference if applicable
        if let offScheme = coach.offensiveScheme {
            let schemePhrases = [
                "Runs a \(offScheme.displayName) offense.",
                "His offensive philosophy centers on the \(offScheme.displayName) system.",
                "Brings a \(offScheme.displayName) scheme that he's refined over the years."
            ]
            parts.append(schemePhrases.randomElement()!)
        }
        if let defScheme = coach.defensiveScheme {
            let schemePhrases = [
                "Favors a \(defScheme.displayName) defense.",
                "Built a top-tier defense using his \(defScheme.displayName) scheme.",
                "His \(defScheme.displayName) defensive system has been widely imitated."
            ]
            parts.append(schemePhrases.randomElement()!)
        }

        // Cap at 2-3 sentences for readability
        let selected = Array(parts.prefix(3))
        return selected.joined(separator: " ")
    }

    // MARK: - Coach Chemistry

    /// Evaluates the personality chemistry between two coaches.
    /// Returns a value: positive = good fit, zero = neutral, negative = conflict.
    ///
    /// Range: roughly -1.0 (conflict) to +1.0 (excellent fit).
    static func coachChemistry(
        coachA: PersonalityArchetype,
        coachB: PersonalityArchetype
    ) -> Double {
        // Same personality = generally good synergy
        if coachA == coachB {
            return coachA == .dramaQueen ? -0.3 : 0.6
        }

        switch (coachA, coachB) {
        // Excellent pairings
        case (.mentor, .quietProfessional), (.quietProfessional, .mentor):
            return 0.8
        case (.teamLeader, .steadyPerformer), (.steadyPerformer, .teamLeader):
            return 0.7
        case (.mentor, .teamLeader), (.teamLeader, .mentor):
            return 0.7
        case (.quietProfessional, .steadyPerformer), (.steadyPerformer, .quietProfessional):
            return 0.6
        case (.teamLeader, .fieryCompetitor), (.fieryCompetitor, .teamLeader):
            return 0.5

        // Good pairings
        case (.mentor, .steadyPerformer), (.steadyPerformer, .mentor):
            return 0.5
        case (.feelPlayer, .fieryCompetitor), (.fieryCompetitor, .feelPlayer):
            return 0.4
        case (.classClown, .teamLeader), (.teamLeader, .classClown):
            return 0.3

        // Tension pairings
        case (.fieryCompetitor, .quietProfessional), (.quietProfessional, .fieryCompetitor):
            return -0.3
        case (.dramaQueen, .quietProfessional), (.quietProfessional, .dramaQueen):
            return -0.4
        case (.loneWolf, .teamLeader), (.teamLeader, .loneWolf):
            return -0.4
        case (.classClown, .mentor), (.mentor, .classClown):
            return -0.3
        case (.loneWolf, .mentor), (.mentor, .loneWolf):
            return -0.3

        // Conflict pairings
        case (.dramaQueen, .fieryCompetitor), (.fieryCompetitor, .dramaQueen):
            return -0.8
        case (.dramaQueen, .loneWolf), (.loneWolf, .dramaQueen):
            return -0.7
        case (.classClown, .loneWolf), (.loneWolf, .classClown):
            return -0.5
        case (.dramaQueen, .classClown), (.classClown, .dramaQueen):
            return -0.5

        // Default: mildly positive (most people can work together)
        default:
            return 0.1
        }
    }

    /// Returns a chemistry label string for display in the UI.
    static func chemistryLabel(score: Double) -> String {
        switch score {
        case 0.3...:   return "Good fit"
        case -0.29...0.29: return "Tension"
        default:        return "Conflict"
        }
    }

    /// Returns a chemistry symbol for compact display.
    static func chemistrySymbol(score: Double) -> String {
        switch score {
        case 0.3...:   return "\u{2713}"  // checkmark
        case -0.29...0.29: return "\u{26A0}"  // warning
        default:        return "\u{2717}"  // X mark
        }
    }

    // MARK: - Star Ratings

    /// Maps a 1-99 attribute value to a 1-5 star rating.
    /// 1-20 = 1 star, 21-40 = 2 stars, 41-60 = 3 stars, 61-80 = 4 stars, 81-99 = 5 stars.
    static func starRating(for attribute: Int) -> Int {
        switch attribute {
        case 81...99: return 5
        case 61...80: return 4
        case 41...60: return 3
        case 21...40: return 2
        default:      return 1
        }
    }

    /// Returns a string of star characters for the given attribute.
    static func starString(for attribute: Int) -> String {
        let stars = starRating(for: attribute)
        let filled = String(repeating: "\u{2605}", count: stars)    // ★
        let empty  = String(repeating: "\u{2606}", count: 5 - stars) // ☆
        return filled + empty
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
        let candidates = coaches.filter { $0.role != .headCoach && $0.role != .assistantHeadCoach }

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

        // MARK: Motivation bonus
        // A highly motivating coach squeezes extra effort out of players
        let motivationBonus = (Double(coach.motivation) - 50.0) / 50.0 * 0.05
        multiplier += motivationBonus

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

    // MARK: - Scout Candidate Generation

    /// Generates a pool of scout candidates available for the given scout role.
    ///
    /// - Parameters:
    ///   - role: The scouting role being filled.
    ///   - count: How many candidates to generate (defaults to 20).
    /// - Returns: An array of freshly created `Scout` objects not yet attached to any team.
    static func generateScoutCandidates(role: ScoutRole, count: Int = 20) -> [Scout] {
        (0..<count).map { _ in
            let name = RandomNameGenerator.randomName()

            let expRange: ClosedRange<Int>
            let salaryRange: ClosedRange<Int>
            if role.isChief {
                expRange = 8...25
                salaryRange = 400...1_200
            } else {
                expRange = 1...15
                salaryRange = 100...600
            }

            let experience = Int.random(in: expRange)
            let baseCeiling = min(99, 40 + experience * 3)
            let baseFloor = max(25, baseCeiling - 35)

            return Scout(
                firstName: name.first,
                lastName: name.last,
                teamID: nil,
                positionSpecialization: role.isChief ? nil : Position.allCases.randomElement(),
                accuracy: Int.random(in: baseFloor...baseCeiling),
                personalityRead: Int.random(in: baseFloor...baseCeiling),
                potentialRead: Int.random(in: baseFloor...baseCeiling),
                experience: experience,
                salary: Int.random(in: salaryRange),
                scoutRole: role
            )
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
