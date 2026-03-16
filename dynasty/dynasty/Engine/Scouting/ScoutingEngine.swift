import Foundation

enum ScoutingEngine {

    // MARK: - College List

    static let colleges = [
        "Alabama", "Ohio State", "Georgia", "Michigan", "Clemson",
        "LSU", "Oklahoma", "Texas", "USC", "Oregon",
        "Penn State", "Florida", "Tennessee", "Auburn", "Notre Dame",
        "Wisconsin", "Miami", "Florida State", "Texas A&M", "Washington",
        "UCLA", "Stanford", "Iowa", "Michigan State", "North Carolina",
        "Virginia Tech", "Baylor", "TCU", "Ole Miss", "Arkansas",
        "Kentucky", "Pittsburgh", "Utah", "Arizona State", "Colorado",
        "Minnesota", "Illinois", "Boston College", "Wake Forest", "Duke"
    ]

    // MARK: - Position Distribution

    /// Target distribution for a ~250-player draft class.
    private static let positionDistribution: [(Position, Int)] = [
        (.QB, 30), (.RB, 20), (.FB, 5), (.WR, 35), (.TE, 15),
        (.LT, 10), (.LG, 10), (.C, 8), (.RG, 8), (.RT, 10),
        (.DE, 18), (.DT, 16), (.OLB, 14), (.MLB, 12),
        (.CB, 16), (.FS, 10), (.SS, 8),
        (.K, 6), (.P, 5)
    ]

    // MARK: - Height/Weight Ranges per Position (inches, pounds)

    private static func heightWeightRange(for position: Position) -> (height: ClosedRange<Int>, weight: ClosedRange<Int>) {
        switch position {
        case .QB:  return (73...77, 205...240)
        case .RB:  return (68...73, 195...230)
        case .FB:  return (71...74, 235...260)
        case .WR:  return (69...76, 175...215)
        case .TE:  return (74...78, 235...265)
        case .LT, .RT: return (76...80, 295...340)
        case .LG, .RG: return (74...78, 295...335)
        case .C:   return (73...77, 290...320)
        case .DE:  return (74...79, 250...285)
        case .DT:  return (73...77, 280...330)
        case .OLB: return (73...77, 230...260)
        case .MLB: return (72...76, 235...260)
        case .CB:  return (69...74, 180...205)
        case .FS:  return (71...75, 195...215)
        case .SS:  return (71...75, 200...225)
        case .K:   return (71...75, 185...215)
        case .P:   return (72...76, 200...225)
        }
    }

    // MARK: - Prospect Generation

    /// Generates a full draft class of college prospects.
    static func generateDraftClass(count: Int = 250) -> [CollegeProspect] {
        var prospects: [CollegeProspect] = []

        // Scale distribution to requested count
        let totalTarget = positionDistribution.reduce(0) { $0 + $1.1 }
        let scale = Double(count) / Double(totalTarget)

        for (position, baseCount) in positionDistribution {
            let posCount = max(1, Int((Double(baseCount) * scale).rounded()))
            for _ in 0..<posCount {
                let prospect = generateProspect(position: position)
                prospects.append(prospect)
            }
        }

        // Trim or pad to exact count
        while prospects.count > count {
            prospects.removeLast()
        }
        while prospects.count < count {
            let randomPos = positionDistribution.randomElement()!.0
            prospects.append(generateProspect(position: randomPos))
        }

        // Assign draft projections based on true overall
        prospects.sort { $0.trueOverall > $1.trueOverall }
        for i in prospects.indices {
            let fraction = Double(i) / Double(prospects.count)
            if fraction < 0.12 {
                prospects[i].draftProjection = 1
            } else if fraction < 0.24 {
                prospects[i].draftProjection = 2
            } else if fraction < 0.38 {
                prospects[i].draftProjection = 3
            } else if fraction < 0.52 {
                prospects[i].draftProjection = 4
            } else if fraction < 0.66 {
                prospects[i].draftProjection = 5
            } else if fraction < 0.82 {
                prospects[i].draftProjection = 6
            } else {
                prospects[i].draftProjection = 7
            }
        }

        prospects.shuffle()
        return prospects
    }

    /// Generates a single college prospect at the given position with bell-curved attributes.
    private static func generateProspect(position: Position) -> CollegeProspect {
        let name = RandomNameGenerator.randomName()
        let college = colleges.randomElement()!
        let age = Int.random(in: 20...23)
        let hw = heightWeightRange(for: position)
        let height = Int.random(in: hw.height)
        let weight = Int.random(in: hw.weight)

        let physical = bellCurvePhysical()
        let mental = bellCurveMental()
        let posAttrs = randomPositionAttributes(for: position)
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement()!,
            motivation: Motivation.allCases.randomElement()!
        )
        let potential = bellCurveRating(min: 35, max: 99, center: 60)

        return CollegeProspect(
            firstName: name.first,
            lastName: name.last,
            college: college,
            position: position,
            age: age,
            height: height,
            weight: weight,
            truePhysical: physical,
            trueMental: mental,
            truePositionAttributes: posAttrs,
            truePersonality: personality,
            truePotential: potential
        )
    }

    // MARK: - Bell Curve Helpers

    /// Generates a rating with a bell-curve distribution centered on `center`.
    private static func bellCurveRating(min: Int, max: Int, center: Int) -> Int {
        // Average of 3 random values produces a rough bell curve
        let sum = Int.random(in: min...max) + Int.random(in: min...max) + Int.random(in: min...max)
        let raw = sum / 3
        // Bias toward center
        let biased = (raw + center) / 2
        return Swift.min(max, Swift.max(min, biased))
    }

    private static func bellCurvePhysical() -> PhysicalAttributes {
        PhysicalAttributes(
            speed: bellCurveRating(min: 40, max: 99, center: 62),
            acceleration: bellCurveRating(min: 40, max: 99, center: 62),
            strength: bellCurveRating(min: 40, max: 99, center: 62),
            agility: bellCurveRating(min: 40, max: 99, center: 62),
            stamina: bellCurveRating(min: 40, max: 99, center: 62),
            durability: bellCurveRating(min: 40, max: 99, center: 62)
        )
    }

    private static func bellCurveMental() -> MentalAttributes {
        MentalAttributes(
            awareness: bellCurveRating(min: 40, max: 99, center: 58),
            decisionMaking: bellCurveRating(min: 40, max: 99, center: 58),
            clutch: bellCurveRating(min: 40, max: 99, center: 58),
            workEthic: bellCurveRating(min: 40, max: 99, center: 58),
            coachability: bellCurveRating(min: 40, max: 99, center: 58),
            leadership: bellCurveRating(min: 40, max: 99, center: 58)
        )
    }

    private static func randomPositionAttributes(for position: Position) -> PositionAttributes {
        switch position {
        case .QB:
            return .quarterback(QBAttributes(
                armStrength: bellCurveRating(min: 40, max: 99, center: 65),
                accuracyShort: bellCurveRating(min: 40, max: 99, center: 65),
                accuracyMid: bellCurveRating(min: 40, max: 99, center: 60),
                accuracyDeep: bellCurveRating(min: 40, max: 99, center: 55),
                pocketPresence: bellCurveRating(min: 40, max: 99, center: 58),
                scrambling: bellCurveRating(min: 40, max: 99, center: 55)
            ))
        case .WR:
            return .wideReceiver(WRAttributes(
                routeRunning: bellCurveRating(min: 40, max: 99, center: 60),
                catching: bellCurveRating(min: 40, max: 99, center: 62),
                release: bellCurveRating(min: 40, max: 99, center: 58),
                spectacularCatch: bellCurveRating(min: 40, max: 99, center: 50)
            ))
        case .RB, .FB:
            return .runningBack(RBAttributes(
                vision: bellCurveRating(min: 40, max: 99, center: 60),
                elusiveness: bellCurveRating(min: 40, max: 99, center: 58),
                breakTackle: bellCurveRating(min: 40, max: 99, center: 58),
                receiving: bellCurveRating(min: 40, max: 99, center: 52)
            ))
        case .TE:
            return .tightEnd(TEAttributes(
                blocking: bellCurveRating(min: 40, max: 99, center: 58),
                catching: bellCurveRating(min: 40, max: 99, center: 60),
                routeRunning: bellCurveRating(min: 40, max: 99, center: 55),
                speed: bellCurveRating(min: 40, max: 99, center: 55)
            ))
        case .LT, .LG, .C, .RG, .RT:
            return .offensiveLine(OLAttributes(
                runBlock: bellCurveRating(min: 40, max: 99, center: 62),
                passBlock: bellCurveRating(min: 40, max: 99, center: 60),
                pull: bellCurveRating(min: 40, max: 99, center: 55),
                anchor: bellCurveRating(min: 40, max: 99, center: 60)
            ))
        case .DE, .DT:
            return .defensiveLine(DLAttributes(
                passRush: bellCurveRating(min: 40, max: 99, center: 60),
                blockShedding: bellCurveRating(min: 40, max: 99, center: 60),
                powerMoves: bellCurveRating(min: 40, max: 99, center: 58),
                finesseMoves: bellCurveRating(min: 40, max: 99, center: 55)
            ))
        case .OLB, .MLB:
            return .linebacker(LBAttributes(
                tackling: bellCurveRating(min: 40, max: 99, center: 62),
                zoneCoverage: bellCurveRating(min: 40, max: 99, center: 58),
                manCoverage: bellCurveRating(min: 40, max: 99, center: 52),
                blitzing: bellCurveRating(min: 40, max: 99, center: 55)
            ))
        case .CB, .FS, .SS:
            return .defensiveBack(DBAttributes(
                manCoverage: bellCurveRating(min: 40, max: 99, center: 60),
                zoneCoverage: bellCurveRating(min: 40, max: 99, center: 60),
                press: bellCurveRating(min: 40, max: 99, center: 55),
                ballSkills: bellCurveRating(min: 40, max: 99, center: 58)
            ))
        case .K, .P:
            return .kicking(KickingAttributes(
                kickPower: bellCurveRating(min: 40, max: 99, center: 65),
                kickAccuracy: bellCurveRating(min: 40, max: 99, center: 62)
            ))
        }
    }

    // MARK: - Scouting Process

    /// Has a scout evaluate a prospect, returning a scouting report and updating the prospect's scouted fields.
    static func scoutProspect(prospect: CollegeProspect, scout: Scout) -> ScoutingReport {
        // Determine accuracy modifier
        var accuracyBonus = 0
        if let spec = scout.positionSpecialization, spec == prospect.position {
            accuracyBonus = 10
        }
        let effectiveAccuracy = min(99, scout.accuracy + accuracyBonus)

        // Calculate scouted overall with error margin
        let maxError = max(1, 30 - (effectiveAccuracy * 30 / 100))
        let overallError = Int.random(in: -maxError...maxError)
        let scoutedOvr = min(99, max(1, prospect.trueOverall + overallError))
        prospect.scoutedOverall = scoutedOvr

        // Calculate scouted potential with error margin based on potentialRead
        let potentialMaxError = max(1, 30 - (scout.potentialRead * 30 / 100))
        let potentialError = Int.random(in: -potentialMaxError...potentialMaxError)
        let scoutedPot = min(99, max(1, prospect.truePotential + potentialError))
        prospect.scoutedPotential = scoutedPot

        // Personality read
        let personalityRoll = Int.random(in: 1...100)
        if personalityRoll <= scout.personalityRead {
            prospect.scoutedPersonality = prospect.truePersonality.archetype
        } else {
            // Wrong personality assessment
            let wrongArchetypes = PersonalityArchetype.allCases.filter { $0 != prospect.truePersonality.archetype }
            prospect.scoutedPersonality = wrongArchetypes.randomElement()
        }

        // Scout grade based on scouted overall
        let grade: String
        switch scoutedOvr {
        case 90...99: grade = "A+"
        case 85...89: grade = "A"
        case 80...84: grade = "A-"
        case 75...79: grade = "B+"
        case 70...74: grade = "B"
        case 65...69: grade = "B-"
        case 60...64: grade = "C+"
        case 55...59: grade = "C"
        case 50...54: grade = "C-"
        case 45...49: grade = "D+"
        case 40...44: grade = "D"
        default:      grade = "F"
        }
        prospect.scoutGrade = grade

        // Confidence level based on scout accuracy and experience
        let baseConfidence = Double(effectiveAccuracy) / 100.0
        let experienceBonus = min(0.15, Double(scout.experience) * 0.015)
        let confidence = min(1.0, baseConfidence + experienceBonus)

        // Generate notes
        let strengthNotes = generateStrengthNotes(for: prospect, accuracy: effectiveAccuracy)
        let weaknessNotes = generateWeaknessNotes(for: prospect, accuracy: effectiveAccuracy)
        let personalityNotes = generatePersonalityNotes(for: prospect, scout: scout)

        return ScoutingReport(
            prospectID: prospect.id,
            scoutID: scout.id,
            scoutName: scout.fullName,
            date: currentDateString(),
            overallGrade: scoutedOvr,
            potentialGrade: scoutedPot,
            strengthNotes: strengthNotes,
            weaknessNotes: weaknessNotes,
            personalityNotes: personalityNotes,
            confidenceLevel: confidence
        )
    }

    // MARK: - Combine Simulation

    /// Fills in combine results for all prospects based on true physical attributes plus variance.
    static func simulateCombine(prospects: inout [CollegeProspect]) {
        for i in prospects.indices {
            let phys = prospects[i].truePhysical

            // Determine if this prospect is a "combine warrior" or "bad tester"
            let combineModifier = combinePersonalityModifier()

            // 40-yard dash: faster speed = lower time. Range ~4.2 - 5.3
            let baseForty = 5.5 - (Double(phys.speed) * 0.013)
            let fortyVariance = Double.random(in: -0.06...0.06) + combineModifier * 0.05
            prospects[i].fortyTime = max(4.2, min(5.5, baseForty + fortyVariance))

            // Bench press: correlated with strength. Range ~10 - 40 reps
            let baseBench = Int(Double(phys.strength) * 0.35) - 5
            let benchVariance = Int.random(in: -3...3) + Int(combineModifier * 3.0)
            prospects[i].benchPress = max(8, min(45, baseBench + benchVariance))

            // Vertical jump: correlated with acceleration and agility. Range ~25 - 45 inches
            let baseVertical = 20.0 + Double(phys.acceleration + phys.agility) * 0.13
            let vertVariance = Double.random(in: -1.5...1.5) + combineModifier * 1.5
            prospects[i].verticalJump = max(24.0, min(46.0, baseVertical + vertVariance))

            // Broad jump: correlated with strength and acceleration. Range ~100 - 140 inches
            let baseBroad = 80 + Int(Double(phys.strength + phys.acceleration) * 0.3)
            let broadVariance = Int.random(in: -4...4) + Int(combineModifier * 3.0)
            prospects[i].broadJump = max(95, min(145, baseBroad + broadVariance))

            // Shuttle: correlated with agility. Range ~3.8 - 4.6 seconds
            let baseShuttle = 4.8 - (Double(phys.agility) * 0.01)
            let shuttleVariance = Double.random(in: -0.08...0.08) + combineModifier * 0.04
            prospects[i].shuttleTime = max(3.7, min(4.8, baseShuttle + shuttleVariance))

            // 3-cone drill: correlated with agility and acceleration. Range ~6.5 - 7.5 seconds
            let baseCone = 7.8 - (Double(phys.agility + phys.acceleration) * 0.007)
            let coneVariance = Double.random(in: -0.1...0.1) + combineModifier * 0.05
            prospects[i].coneDrill = max(6.4, min(7.6, baseCone + coneVariance))
        }
    }

    /// Returns a modifier: positive = combine warrior (tests better), negative = bad tester.
    /// Most prospects are neutral (0). ~10% are warriors, ~10% are bad testers.
    private static func combinePersonalityModifier() -> Double {
        let roll = Int.random(in: 1...100)
        if roll <= 10 {
            return Double.random(in: 0.5...1.0)   // Combine warrior
        } else if roll >= 91 {
            return Double.random(in: -1.0...(-0.5)) // Bad tester
        } else {
            return Double.random(in: -0.2...0.2)    // Neutral
        }
    }

    // MARK: - Pro Day Simulation

    /// Simulates a pro day for a single prospect. Slightly better results than combine (home field advantage).
    static func simulateProDay(prospect: inout CollegeProspect) {
        let phys = prospect.truePhysical
        let homefieldBoost = 0.3 // Slight positive modifier

        let baseForty = 5.5 - (Double(phys.speed) * 0.013)
        let fortyVariance = Double.random(in: -0.06...0.04) - homefieldBoost * 0.03
        let proDayForty = max(4.2, min(5.5, baseForty + fortyVariance))
        // Keep best result
        if let existing = prospect.fortyTime {
            prospect.fortyTime = min(existing, proDayForty)
        } else {
            prospect.fortyTime = proDayForty
        }

        let baseBench = Int(Double(phys.strength) * 0.35) - 5
        let benchVariance = Int.random(in: -2...4)
        let proDayBench = max(8, min(45, baseBench + benchVariance))
        if let existing = prospect.benchPress {
            prospect.benchPress = max(existing, proDayBench)
        } else {
            prospect.benchPress = proDayBench
        }

        let baseVertical = 20.0 + Double(phys.acceleration + phys.agility) * 0.13
        let vertVariance = Double.random(in: -1.0...2.0)
        let proDayVert = max(24.0, min(46.0, baseVertical + vertVariance))
        if let existing = prospect.verticalJump {
            prospect.verticalJump = max(existing, proDayVert)
        } else {
            prospect.verticalJump = proDayVert
        }

        let baseBroad = 80 + Int(Double(phys.strength + phys.acceleration) * 0.3)
        let broadVariance = Int.random(in: -2...5)
        let proDayBroad = max(95, min(145, baseBroad + broadVariance))
        if let existing = prospect.broadJump {
            prospect.broadJump = max(existing, proDayBroad)
        } else {
            prospect.broadJump = proDayBroad
        }

        let baseShuttle = 4.8 - (Double(phys.agility) * 0.01)
        let shuttleVariance = Double.random(in: -0.1...0.05)
        let proDayShuttle = max(3.7, min(4.8, baseShuttle + shuttleVariance))
        if let existing = prospect.shuttleTime {
            prospect.shuttleTime = min(existing, proDayShuttle)
        } else {
            prospect.shuttleTime = proDayShuttle
        }

        let baseCone = 7.8 - (Double(phys.agility + phys.acceleration) * 0.007)
        let coneVariance = Double.random(in: -0.12...0.06)
        let proDayCone = max(6.4, min(7.6, baseCone + coneVariance))
        if let existing = prospect.coneDrill {
            prospect.coneDrill = min(existing, proDayCone)
        } else {
            prospect.coneDrill = proDayCone
        }

        prospect.proDayCompleted = true
    }

    // MARK: - Interview

    /// Conducts an interview with a prospect, revealing personality traits based on scout ability.
    /// Returns interview notes as a string.
    static func conductInterview(prospect: inout CollegeProspect, scout: Scout) -> String {
        prospect.interviewCompleted = true

        let archetype = prospect.truePersonality.archetype
        let motivation = prospect.truePersonality.motivation

        var notes: [String] = []

        // Personality insight based on scout's personalityRead
        let readRoll = Int.random(in: 1...100)
        if readRoll <= scout.personalityRead {
            // Accurate read
            notes.append(accuratePersonalityNote(archetype: archetype))
            notes.append(accurateMotivationNote(motivation: motivation))
        } else if readRoll <= scout.personalityRead + 30 {
            // Partially accurate — gets one right
            if Bool.random() {
                notes.append(accuratePersonalityNote(archetype: archetype))
                notes.append("Motivation is unclear from the interview.")
            } else {
                notes.append("Personality was hard to pin down in the meeting.")
                notes.append(accurateMotivationNote(motivation: motivation))
            }
        } else {
            // Misleading read
            notes.append("Came across well in the interview but hard to get a true read.")
            notes.append("Seems like a standard prospect — nothing stood out.")
        }

        // Work ethic hint
        let workEthic = prospect.trueMental.workEthic
        if workEthic >= 80 && Int.random(in: 1...100) <= scout.personalityRead + 20 {
            notes.append("Shows excellent dedication to the craft. Film study and preparation are top-notch.")
        } else if workEthic < 50 && Int.random(in: 1...100) <= scout.personalityRead + 10 {
            notes.append("Some concerns about work habits. May need extra motivation from coaching staff.")
        }

        // Leadership hint
        let leadership = prospect.trueMental.leadership
        if leadership >= 80 && Int.random(in: 1...100) <= scout.personalityRead + 15 {
            notes.append("Natural leader. Teammates gravitate toward him.")
        }

        return notes.joined(separator: " ")
    }

    // MARK: - Scout Development

    /// Develops a scout over the offseason. Accuracy and reads improve with experience.
    static func developScout(_ scout: Scout) {
        scout.experience += 1

        // Early career scouts improve faster
        let improvementChance: Int
        if scout.experience <= 5 {
            improvementChance = 70
        } else if scout.experience <= 10 {
            improvementChance = 45
        } else {
            improvementChance = 20
        }

        if Int.random(in: 1...100) <= improvementChance {
            scout.accuracy = min(99, scout.accuracy + Int.random(in: 1...2))
        }
        if Int.random(in: 1...100) <= improvementChance {
            scout.personalityRead = min(99, scout.personalityRead + Int.random(in: 1...2))
        }
        if Int.random(in: 1...100) <= improvementChance {
            scout.potentialRead = min(99, scout.potentialRead + Int.random(in: 1...2))
        }
    }

    // MARK: - Note Generation Helpers

    private static func generateStrengthNotes(for prospect: CollegeProspect, accuracy: Int) -> String {
        var strengths: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental

        // Only mention strengths the scout can actually detect (accuracy-gated)
        let threshold = max(70, 95 - accuracy / 2) // Higher accuracy = notices lower-rated strengths

        if phys.speed >= threshold { strengths.append("Excellent speed") }
        if phys.acceleration >= threshold { strengths.append("Explosive first step") }
        if phys.strength >= threshold { strengths.append("Strong at the point of attack") }
        if phys.agility >= threshold { strengths.append("Very agile, changes direction well") }
        if phys.stamina >= threshold { strengths.append("High motor, plays all four quarters") }
        if phys.durability >= threshold { strengths.append("Durable, rarely misses time") }
        if mental.awareness >= threshold { strengths.append("High football IQ") }
        if mental.decisionMaking >= threshold { strengths.append("Makes good decisions under pressure") }
        if mental.clutch >= threshold { strengths.append("Performs well in big moments") }

        if strengths.isEmpty {
            strengths.append("Solid overall athlete with room to grow")
        }

        return strengths.joined(separator: ". ") + "."
    }

    private static func generateWeaknessNotes(for prospect: CollegeProspect, accuracy: Int) -> String {
        var weaknesses: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental

        let threshold = min(55, 40 + accuracy / 3) // Higher accuracy = catches higher-rated weaknesses

        if phys.speed <= threshold { weaknesses.append("Limited top-end speed") }
        if phys.acceleration <= threshold { weaknesses.append("Slow off the line") }
        if phys.strength <= threshold { weaknesses.append("Needs to add strength") }
        if phys.agility <= threshold { weaknesses.append("Stiff in the hips") }
        if phys.stamina <= threshold { weaknesses.append("Fades late in games") }
        if phys.durability <= threshold { weaknesses.append("Injury concerns") }
        if mental.awareness <= threshold { weaknesses.append("Can get lost on the field") }
        if mental.decisionMaking <= threshold { weaknesses.append("Questionable decision-making") }
        if mental.workEthic <= threshold { weaknesses.append("Work ethic is a concern") }

        if weaknesses.isEmpty {
            weaknesses.append("No major red flags at this time")
        }

        return weaknesses.joined(separator: ". ") + "."
    }

    private static func generatePersonalityNotes(for prospect: CollegeProspect, scout: Scout) -> String? {
        guard Int.random(in: 1...100) <= scout.personalityRead else { return nil }

        let archetype = prospect.truePersonality.archetype
        switch archetype {
        case .teamLeader:
            return "True team-first mentality. Well-respected in the locker room."
        case .loneWolf:
            return "Keeps to himself. Not a problem but won't be a vocal leader."
        case .feelPlayer:
            return "Performance can be streaky. When he's on, he's dominant."
        case .steadyPerformer:
            return "Consistent week to week. You know what you're getting."
        case .dramaQueen:
            return "Some character concerns. Has had issues with coaches in the past."
        case .quietProfessional:
            return "Low maintenance. Shows up, does his job, goes home."
        case .mentor:
            return "Great with younger players. Could be a locker room asset."
        case .fieryCompetitor:
            return "Intense competitor. Plays with an edge but occasionally crosses the line."
        case .classClown:
            return "Fun personality, keeps things light. Needs to know when to be serious."
        }
    }

    private static func accuratePersonalityNote(archetype: PersonalityArchetype) -> String {
        switch archetype {
        case .teamLeader:
            return "Clearly a leader — commands respect from his peers."
        case .loneWolf:
            return "Independent personality. Prefers to do his own thing."
        case .feelPlayer:
            return "Emotional player — highs are very high, lows can be low."
        case .steadyPerformer:
            return "Even-keeled demeanor. Very consistent personality."
        case .dramaQueen:
            return "High-maintenance personality. Will need careful management."
        case .quietProfessional:
            return "Quiet and focused. All business."
        case .mentor:
            return "Mature beyond his years. Natural teacher."
        case .fieryCompetitor:
            return "Extremely competitive. Hates losing more than he loves winning."
        case .classClown:
            return "Lighthearted and charismatic. Keeps the room loose."
        }
    }

    private static func accurateMotivationNote(motivation: Motivation) -> String {
        switch motivation {
        case .money:
            return "Clearly motivated by the financial opportunity."
        case .winning:
            return "Wants to win above all else. Will prioritize contenders."
        case .stats:
            return "Very aware of his numbers. Wants opportunities to produce."
        case .loyalty:
            return "Values loyalty and long-term commitment from an organization."
        case .fame:
            return "Drawn to the spotlight. Wants to be a star."
        }
    }

    private static func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
