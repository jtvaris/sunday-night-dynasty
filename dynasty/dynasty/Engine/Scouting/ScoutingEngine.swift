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

    /// Target distribution for a ~350-player draft class.
    private static let positionDistribution: [(Position, Int)] = [
        (.QB, 42), (.RB, 28), (.FB, 7), (.WR, 49), (.TE, 21),
        (.LT, 14), (.LG, 14), (.C, 11), (.RG, 11), (.RT, 14),
        (.DE, 25), (.DT, 22), (.OLB, 20), (.MLB, 17),
        (.CB, 22), (.FS, 14), (.SS, 11),
        (.K, 8), (.P, 7)
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

    // MARK: - Positional Draft Value

    /// Modifier that affects how high a position can realistically be drafted.
    /// 1.0 = highest value (QB), lower values push positions down in projected round.
    static func positionalDraftValue(for position: Position) -> Double {
        switch position {
        case .QB:              return 1.0
        case .LT, .RT:        return 0.95
        case .DE:              return 0.93
        case .WR:              return 0.90
        case .CB:              return 0.88
        case .DT:              return 0.85
        case .OLB, .MLB:      return 0.78
        case .TE:              return 0.75
        case .FS, .SS:        return 0.72
        case .RB:              return 0.65
        case .C, .LG, .RG:   return 0.60
        case .FB:              return 0.30
        case .K:               return 0.25
        case .P:               return 0.20
        }
    }

    /// Maximum first-round prospects allowed per position in a typical draft class.
    private static let maxFirstRounders: [Position: ClosedRange<Int>] = [
        .QB: 1...3, .WR: 3...5, .LT: 1...2, .RT: 1...2,
        .DE: 3...5, .CB: 2...4, .DT: 1...3, .OLB: 1...2, .MLB: 0...1,
        .TE: 0...2, .FS: 0...1, .SS: 0...1, .RB: 0...2,
        .C: 0...1, .LG: 0...1, .RG: 0...1,
        .FB: 0...0, .K: 0...0, .P: 0...0
    ]

    // MARK: - Draft Class Strength

    /// Picks 2-3 "strong" positions and 2-3 "weak" positions for the draft class.
    private struct DraftClassStrength {
        let strongPositions: Set<Position>
        let weakPositions: Set<Position>

        static func random() -> DraftClassStrength {
            // Eligible positions for strength variance (exclude K/P/FB)
            let eligible: [Position] = [.QB, .RB, .WR, .TE, .LT, .RT, .LG, .RG, .C,
                                        .DE, .DT, .OLB, .MLB, .CB, .FS, .SS]
            var shuffled = eligible.shuffled()
            let strongCount = Int.random(in: 2...3)
            let strong = Set(shuffled.prefix(strongCount))
            shuffled.removeFirst(strongCount)
            let weakCount = Int.random(in: 2...3)
            let weak = Set(shuffled.prefix(weakCount))
            return DraftClassStrength(strongPositions: strong, weakPositions: weak)
        }
    }

    // MARK: - Prospect Generation

    /// Generates a full draft class of college prospects with realistic position distribution
    /// and draft class strength variance.
    static func generateDraftClass(count: Int = 350) -> [CollegeProspect] {
        var prospects: [CollegeProspect] = []
        let classStrength = DraftClassStrength.random()

        // Scale distribution to requested count
        let totalTarget = positionDistribution.reduce(0) { $0 + $1.1 }
        let scale = Double(count) / Double(totalTarget)

        for (position, baseCount) in positionDistribution {
            var posCount = max(1, Int((Double(baseCount) * scale).rounded()))

            // Adjust count based on draft class strength
            if classStrength.strongPositions.contains(position) {
                posCount = Int(Double(posCount) * Double.random(in: 1.2...1.4))
            } else if classStrength.weakPositions.contains(position) {
                posCount = max(1, Int(Double(posCount) * Double.random(in: 0.6...0.8)))
            }

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

        // Assign draft projections using positional draft value modifier
        // Sort by a composite score: trueOverall * positionalDraftValue
        prospects.sort { a, b in
            let aScore = Double(a.trueOverall) * positionalDraftValue(for: a.position)
            let bScore = Double(b.trueOverall) * positionalDraftValue(for: b.position)
            return aScore > bScore
        }

        // Track first-rounders per position to enforce caps
        var firstRoundCount: [Position: Int] = [:]

        for i in prospects.indices {
            let fraction = Double(i) / Double(prospects.count)
            let position = prospects[i].position
            let posValue = positionalDraftValue(for: position)

            // Base round from ranking fraction
            let baseRound: Int
            if fraction < 0.09 {
                baseRound = 1
            } else if fraction < 0.18 {
                baseRound = 2
            } else if fraction < 0.32 {
                baseRound = 3
            } else if fraction < 0.46 {
                baseRound = 4
            } else if fraction < 0.60 {
                baseRound = 5
            } else if fraction < 0.78 {
                baseRound = 6
            } else {
                baseRound = 7
            }

            // Apply positional value penalty: low-value positions get pushed down
            let roundPenalty: Int
            if posValue >= 0.85 {
                roundPenalty = 0
            } else if posValue >= 0.70 {
                roundPenalty = baseRound <= 1 ? 1 : 0
            } else if posValue >= 0.50 {
                roundPenalty = baseRound <= 2 ? 1 : 0
            } else if posValue >= 0.30 {
                // FB: earliest Rd 4
                roundPenalty = max(0, 4 - baseRound)
            } else {
                // K/P: earliest Rd 4 (best ever), typically Rd 5+
                roundPenalty = max(0, 4 - baseRound)
            }

            var projectedRound = min(7, baseRound + roundPenalty)

            // Enforce first-round caps per position
            if projectedRound == 1 {
                let maxRange = maxFirstRounders[position] ?? (0...0)
                let currentCount = firstRoundCount[position, default: 0]

                // Strong positions get the upper bound, weak get lower bound
                let maxAllowed: Int
                if classStrength.strongPositions.contains(position) {
                    maxAllowed = maxRange.upperBound
                } else if classStrength.weakPositions.contains(position) {
                    maxAllowed = maxRange.lowerBound
                } else {
                    maxAllowed = Int.random(in: maxRange)
                }

                if currentCount >= maxAllowed {
                    projectedRound = 2  // Push to round 2
                } else {
                    firstRoundCount[position, default: 0] += 1
                }
            }

            prospects[i].draftProjection = projectedRound
        }

        // Now scale physical stats based on assigned draft projection (tier)
        for i in prospects.indices {
            let round = prospects[i].draftProjection ?? 7
            prospects[i].truePhysical = tieredPhysical(forRound: round)
        }

        // Generate medical/character risk profile for each prospect
        for i in prospects.indices {
            generateRiskProfile(for: &prospects[i])
        }

        prospects.shuffle()
        return prospects
    }

    /// Physical stat ranges per draft round tier.
    /// Draft-age athletes (20-23) are near physical peak — mental/technique develops more over career.
    private static func tieredPhysical(forRound round: Int) -> PhysicalAttributes {
        let range: ClosedRange<Int>
        switch round {
        case 1:  range = 82...96
        case 2:  range = 76...90
        case 3:  range = 70...85
        case 4, 5: range = 65...80
        default: range = 58...75
        }
        return PhysicalAttributes(
            speed: bellCurveRating(min: range.lowerBound, max: range.upperBound,
                                  center: (range.lowerBound + range.upperBound) / 2),
            acceleration: bellCurveRating(min: range.lowerBound, max: range.upperBound,
                                          center: (range.lowerBound + range.upperBound) / 2),
            strength: bellCurveRating(min: range.lowerBound, max: range.upperBound,
                                      center: (range.lowerBound + range.upperBound) / 2),
            agility: bellCurveRating(min: range.lowerBound, max: range.upperBound,
                                     center: (range.lowerBound + range.upperBound) / 2),
            stamina: bellCurveRating(min: range.lowerBound, max: range.upperBound,
                                     center: (range.lowerBound + range.upperBound) / 2),
            durability: bellCurveRating(min: range.lowerBound, max: range.upperBound,
                                        center: (range.lowerBound + range.upperBound) / 2)
        )
    }

    /// Generates a single college prospect at the given position with bell-curved attributes.
    /// Physical stats are assigned later by `generateDraftClass` based on draft tier.
    private static func generateProspect(position: Position) -> CollegeProspect {
        let name = RandomNameGenerator.randomName()
        let college = colleges.randomElement()!
        let age = Int.random(in: 20...23)
        let hw = heightWeightRange(for: position)
        let height = Int.random(in: hw.height)
        let weight = Int.random(in: hw.weight)

        // Placeholder physical — will be overwritten by tieredPhysical in generateDraftClass
        let physical = bellCurvePhysical()
        let mental = bellCurveMental()
        let posAttrs = randomPositionAttributes(for: position)
        let personality = PlayerPersonality(
            archetype: PersonalityArchetype.allCases.randomElement()!,
            motivation: Motivation.allCases.randomElement()!
        )
        let potential = bellCurveRating(min: 35, max: 99, center: 60)
        let anthro = generateAnthropometrics(for: position)

        let prospect = CollegeProspect(
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
        prospect.handSize = anthro.handSize
        prospect.armLength = anthro.armLength
        prospect.wingspan = anthro.wingspan
        return prospect
    }

    // MARK: - Anthropometrics (Hand Size / Arm Length / Wingspan)

    /// Generates position-appropriate hand size, arm length, and wingspan in inches.
    /// Heuristic distributions — premium positions skew larger.
    static func generateAnthropometrics(for position: Position) -> (handSize: Double, armLength: Double, wingspan: Double) {
        let handRange: ClosedRange<Double>
        let armRange: ClosedRange<Double>
        let wingspanRange: ClosedRange<Double>

        switch position {
        case .QB:
            // Large hands premium: 9.0-10.5 typical
            handRange = 8.75...10.5
            armRange = 31.0...33.5
            wingspanRange = 74.0...80.0
        case .LT, .RT, .LG, .RG, .C:
            // Long arms premium for OL: 33-36 elite tackles
            handRange = 9.25...10.75
            armRange = 32.5...36.0
            wingspanRange = 78.0...86.0
        case .DE, .DT:
            // DL: long arms + wingspan elite
            handRange = 9.0...10.5
            armRange = 32.0...35.5
            wingspanRange = 78.0...85.0
        case .CB, .FS, .SS:
            // DB: arm length 31-34, wingspan premium
            handRange = 8.5...10.0
            armRange = 30.5...34.0
            wingspanRange = 73.0...82.0
        case .WR:
            // WR: balanced, taller WRs benefit from longer arms
            handRange = 8.75...10.25
            armRange = 30.5...33.5
            wingspanRange = 72.0...80.0
        case .TE:
            // TE: longer arms aid blocking & catch radius
            handRange = 9.0...10.5
            armRange = 31.5...34.5
            wingspanRange = 76.0...83.0
        case .RB, .FB:
            // Average build
            handRange = 8.5...10.0
            armRange = 30.0...32.5
            wingspanRange = 72.0...78.0
        case .OLB, .MLB:
            // LB: balanced
            handRange = 9.0...10.25
            armRange = 31.0...34.0
            wingspanRange = 75.0...81.0
        case .K, .P:
            handRange = 8.0...9.5
            armRange = 30.0...32.5
            wingspanRange = 70.0...76.0
        }

        func roundToTwo(_ v: Double) -> Double {
            (v * 100).rounded() / 100
        }
        func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
            Swift.min(range.upperBound, Swift.max(range.lowerBound, v))
        }

        // Slight noise around the midpoint biased toward center for realism
        func rollInRange(_ range: ClosedRange<Double>) -> Double {
            let center = (range.lowerBound + range.upperBound) / 2.0
            let raw = Double.random(in: range)
            // Bias toward center via simple averaging
            return roundToTwo((raw + center) / 2.0)
        }

        let hand = rollInRange(handRange)
        let arm = rollInRange(armRange)
        // Wingspan is loosely correlated with arm length — add small jitter
        let wingBase = rollInRange(wingspanRange)
        let armCenter = (armRange.lowerBound + armRange.upperBound) / 2.0
        let wingspan = roundToTwo(wingBase + (arm - armCenter))

        return (
            handSize: clamp(hand, 8.0...11.5),
            armLength: clamp(arm, 30.0...37.0),
            wingspan: clamp(wingspan, 70.0...90.0)
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
            accuracyBonus += 10
        }
        // Focus position bonus: +15% accuracy when scout focuses on the prospect's position
        if let focusPos = scout.focusPosition, focusPos == prospect.position {
            accuracyBonus += 15
        }
        let effectiveAccuracy = min(99, scout.accuracy + accuracyBonus)

        // Calculate scouted overall with error margin
        let maxError = max(1, 30 - (effectiveAccuracy * 30 / 100))
        let overallError = Int.random(in: -maxError...maxError)
        let scoutedOvr = min(99, max(1, prospect.trueOverall + overallError))
        prospect.scoutedOverall = scoutedOvr

        // Calculate scouted potential with error margin based on potentialRead
        // Mental focus gives +15 bonus to potential read accuracy
        let mentalBonus = scout.focusAttribute == .mental ? 15 : 0
        let effectivePotentialRead = min(99, scout.potentialRead + mentalBonus)
        let potentialMaxError = max(1, 30 - (effectivePotentialRead * 30 / 100))
        let potentialError = Int.random(in: -potentialMaxError...potentialMaxError)
        let scoutedPot = min(99, max(1, prospect.truePotential + potentialError))
        prospect.scoutedPotential = scoutedPot

        // Personality read — character focus gives +20 bonus
        let characterBonus = scout.focusAttribute == .character ? 20 : 0
        let personalityRoll = Int.random(in: 1...100)
        if personalityRoll <= min(99, scout.personalityRead + characterBonus) {
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
        // Focus attribute bonus: physical/mental focus gives +10% confidence on overall/potential reads
        let focusAttrBonus: Double = (scout.focusAttribute == .physical || scout.focusAttribute == .mental) ? 0.10 : 0.0
        let confidence = min(1.0, baseConfidence + experienceBonus + focusAttrBonus)

        // Generate notes
        let strengthNotes = generateStrengthNotes(for: prospect, accuracy: effectiveAccuracy)
        let weaknessNotes = generateWeaknessNotes(for: prospect, accuracy: effectiveAccuracy)
        let personalityNotes = generatePersonalityNotes(for: prospect, scout: scout)

        // Generate per-attribute letter grades
        let mentalGrades = generateMentalGrades(
            mental: prospect.trueMental,
            accuracy: effectiveAccuracy,
            positionSpec: scout.positionSpecialization == prospect.position,
            mentalFocus: scout.focusAttribute == .mental
        )
        let positionGrades = generatePositionSkillGrades(
            attributes: prospect.truePositionAttributes,
            accuracy: effectiveAccuracy,
            positionSpec: scout.positionSpecialization == prospect.position,
            physicalFocus: scout.focusAttribute == .physical
        )
        let overallLetterGrade = LetterGrade.from(numericValue: scoutedOvr)
        let potentialLabel = PotentialLabel.from(
            potential: prospect.truePotential,
            noise: max(0, 3 - (effectivePotentialRead / 30))
        )

        return ScoutingReport(
            prospectID: prospect.id,
            scoutID: scout.id,
            scoutName: scout.fullName,
            date: currentDateString(),
            phase: .collegeSeason,
            overallGrade: scoutedOvr,
            potentialGrade: scoutedPot,
            strengthNotes: strengthNotes,
            weaknessNotes: weaknessNotes,
            personalityNotes: personalityNotes,
            confidenceLevel: confidence,
            mentalGrades: mentalGrades,
            positionSkillGrades: positionGrades,
            overallLetterGrade: overallLetterGrade,
            potentialLabel: potentialLabel
        )
    }

    // MARK: - Phase-Based Scout Report Generation

    /// Generate a scouting report for a prospect based on scout's abilities and the scouting phase.
    static func generateScoutReport(
        scout: Scout,
        prospect: CollegeProspect,
        phase: ScoutingPhase
    ) -> ScoutingReport {
        // 1. Noise range based on scout accuracy (with familiarity bonus)
        let familiarityBonus = scout.seasonsInRole >= 2 ? 5 : 0
        let effectiveBaseAccuracy = min(99, scout.accuracy + familiarityBonus)
        let errorRange = max(2, Int(15.0 * (1.0 - Double(effectiveBaseAccuracy) / 100.0)))

        // Position specialization bonus
        var accuracyBonus = 0
        if let spec = scout.positionSpecialization, spec == prospect.position {
            accuracyBonus += 3
        }
        // Focus position bonus: +15% accuracy when scout focuses on the prospect's position
        if let focusPos = scout.focusPosition, focusPos == prospect.position {
            accuracyBonus += 15
        }
        let adjustedError = max(1, errorRange - accuracyBonus)

        // 2. Scouted overall with noise
        let overallNoise = Int.random(in: -adjustedError...adjustedError)
        let scoutedOverall = min(99, max(1, prospect.trueOverall + overallNoise))

        // 3. Scouted potential with noise based on potentialRead
        // Mental focus gives +15 bonus to potential read accuracy
        let mentalBonus = scout.focusAttribute == .mental ? 15 : 0
        let effectivePotentialRead = min(99, scout.potentialRead + mentalBonus)
        let potentialError = max(2, Int(15.0 * (1.0 - Double(effectivePotentialRead) / 100.0)))
        let potentialNoise = Int.random(in: -potentialError...potentialError)
        let scoutedPotential = min(99, max(1, prospect.truePotential + potentialNoise))

        // 4. Personality assessment based on personalityRead
        // Character focus gives +20 bonus to personality read
        let characterBonus = scout.focusAttribute == .character ? 20 : 0
        let personalityNotes: String?
        let personalityRoll = Int.random(in: 1...100)
        if personalityRoll <= min(99, scout.personalityRead + characterBonus) {
            personalityNotes = accuratePersonalityNote(archetype: prospect.truePersonality.archetype)
        } else if personalityRoll <= min(99, scout.personalityRead + characterBonus) + 25 {
            personalityNotes = "Hard to get a clear read on personality. Seems fine on the surface."
        } else {
            personalityNotes = nil
        }

        // 5. Strength and weakness notes (position-appropriate, 2-3 each)
        let effectiveAccuracy = min(99, scout.accuracy + accuracyBonus)
        let strengthNotes = generatePositionStrengths(for: prospect, accuracy: effectiveAccuracy)
        let weaknessNotes = generatePositionWeaknesses(for: prospect, accuracy: effectiveAccuracy)

        // 6. Confidence level based on phase, with focus attribute bonus
        let baseConfidence = phase.confidenceLevel
        let focusAttrBonus: Double = (scout.focusAttribute == .physical || scout.focusAttribute == .mental) ? 0.10 : 0.0
        let confidenceLevel = min(1.0, baseConfidence + focusAttrBonus)

        // 7. Generate per-attribute letter grades for mental and position skills
        let mentalGrades = generateMentalGrades(
            mental: prospect.trueMental,
            accuracy: effectiveAccuracy,
            positionSpec: scout.positionSpecialization == prospect.position,
            mentalFocus: scout.focusAttribute == .mental
        )
        let positionGrades = generatePositionSkillGrades(
            attributes: prospect.truePositionAttributes,
            accuracy: effectiveAccuracy,
            positionSpec: scout.positionSpecialization == prospect.position,
            physicalFocus: scout.focusAttribute == .physical
        )
        let overallLetterGrade = LetterGrade.from(numericValue: scoutedOverall)
        let potentialLabel = PotentialLabel.from(
            potential: prospect.truePotential,
            noise: max(0, 3 - (effectivePotentialRead / 30))
        )

        // 8. Create and return the report
        return ScoutingReport(
            prospectID: prospect.id,
            scoutID: scout.id,
            scoutName: scout.fullName,
            date: currentDateString(),
            phase: phase,
            overallGrade: scoutedOverall,
            potentialGrade: scoutedPotential,
            strengthNotes: strengthNotes,
            weaknessNotes: weaknessNotes,
            personalityNotes: personalityNotes,
            confidenceLevel: confidenceLevel,
            mentalGrades: mentalGrades,
            positionSkillGrades: positionGrades,
            overallLetterGrade: overallLetterGrade,
            potentialLabel: potentialLabel
        )
    }

    // MARK: - Grade Generation Helpers

    /// Generates letter grades for each mental attribute with noise based on scout accuracy.
    private static func generateMentalGrades(mental: MentalAttributes, accuracy: Int, positionSpec: Bool, mentalFocus: Bool = false) -> [String: LetterGrade] {
        // Higher accuracy = less noise. Noise in grade steps: low acc → ±3, high acc → ±1
        // Mental focus reduces noise by 1 additional step
        let noiseSteps = max(0, 4 - accuracy / 25 - (positionSpec ? 1 : 0) - (mentalFocus ? 1 : 0))

        func gradeWithNoise(_ value: Int) -> LetterGrade {
            let trueGrade = LetterGrade.from(numericValue: value)
            let shift = Int.random(in: -noiseSteps...noiseSteps)
            return trueGrade.shifted(by: shift)
        }

        return [
            "AWR": gradeWithNoise(mental.awareness),
            "DEC": gradeWithNoise(mental.decisionMaking),
            "CLT": gradeWithNoise(mental.clutch),
            "WRK": gradeWithNoise(mental.workEthic),
            "COA": gradeWithNoise(mental.coachability),
            "LDR": gradeWithNoise(mental.leadership),
        ]
    }

    /// Generates letter grades for position-specific skills with noise.
    private static func generatePositionSkillGrades(attributes: PositionAttributes, accuracy: Int, positionSpec: Bool, physicalFocus: Bool = false) -> [String: LetterGrade] {
        // Physical focus reduces noise by 1 additional step
        let noiseSteps = max(0, 4 - accuracy / 25 - (positionSpec ? 1 : 0) - (physicalFocus ? 1 : 0))

        func gradeWithNoise(_ value: Int) -> LetterGrade {
            let trueGrade = LetterGrade.from(numericValue: value)
            let shift = Int.random(in: -noiseSteps...noiseSteps)
            return trueGrade.shifted(by: shift)
        }

        switch attributes {
        case .quarterback(let a):
            return ["ARM": gradeWithNoise(a.armStrength), "SAC": gradeWithNoise(a.accuracyShort),
                    "MAC": gradeWithNoise(a.accuracyMid), "DAC": gradeWithNoise(a.accuracyDeep),
                    "PKT": gradeWithNoise(a.pocketPresence), "SCR": gradeWithNoise(a.scrambling)]
        case .wideReceiver(let a):
            return ["RTE": gradeWithNoise(a.routeRunning), "CTH": gradeWithNoise(a.catching),
                    "RLS": gradeWithNoise(a.release), "SPC": gradeWithNoise(a.spectacularCatch)]
        case .runningBack(let a):
            return ["VIS": gradeWithNoise(a.vision), "ELU": gradeWithNoise(a.elusiveness),
                    "BTK": gradeWithNoise(a.breakTackle), "RCV": gradeWithNoise(a.receiving)]
        case .tightEnd(let a):
            return ["BLK": gradeWithNoise(a.blocking), "CTH": gradeWithNoise(a.catching),
                    "RTE": gradeWithNoise(a.routeRunning), "SPD": gradeWithNoise(a.speed)]
        case .offensiveLine(let a):
            return ["RBK": gradeWithNoise(a.runBlock), "PBK": gradeWithNoise(a.passBlock),
                    "PUL": gradeWithNoise(a.pull), "ANC": gradeWithNoise(a.anchor)]
        case .defensiveLine(let a):
            return ["PRU": gradeWithNoise(a.passRush), "BSH": gradeWithNoise(a.blockShedding),
                    "PWR": gradeWithNoise(a.powerMoves), "FIN": gradeWithNoise(a.finesseMoves)]
        case .linebacker(let a):
            return ["TKL": gradeWithNoise(a.tackling), "ZCV": gradeWithNoise(a.zoneCoverage),
                    "MCV": gradeWithNoise(a.manCoverage), "BLZ": gradeWithNoise(a.blitzing)]
        case .defensiveBack(let a):
            return ["MCV": gradeWithNoise(a.manCoverage), "ZCV": gradeWithNoise(a.zoneCoverage),
                    "PRS": gradeWithNoise(a.press), "BSK": gradeWithNoise(a.ballSkills)]
        case .kicking(let a):
            return ["PWR": gradeWithNoise(a.kickPower), "ACC": gradeWithNoise(a.kickAccuracy)]
        }
    }

    /// Apply a scouting report to update prospect's visible attributes based on the best available report.
    static func applyReport(report: ScoutingReport, to prospect: CollegeProspect) {
        // Add report to the prospect's collection
        prospect.scoutingReports.append(report)

        // Find the report with the highest confidence
        guard let bestReport = prospect.scoutingReports.max(by: { $0.confidenceLevel < $1.confidenceLevel }) else {
            return
        }

        // Legacy: Update numeric scouted values (kept for backward compat)
        prospect.scoutedOverall = bestReport.overallGrade
        prospect.scoutedPotential = bestReport.potentialGrade

        // Scout grade based on best scouted overall
        let ovr = bestReport.overallGrade
        switch ovr {
        case 90...99: prospect.scoutGrade = "A+"
        case 85...89: prospect.scoutGrade = "A"
        case 80...84: prospect.scoutGrade = "A-"
        case 75...79: prospect.scoutGrade = "B+"
        case 70...74: prospect.scoutGrade = "B"
        case 65...69: prospect.scoutGrade = "B-"
        case 60...64: prospect.scoutGrade = "C+"
        case 55...59: prospect.scoutGrade = "C"
        case 50...54: prospect.scoutGrade = "C-"
        case 45...49: prospect.scoutGrade = "D+"
        case 40...44: prospect.scoutGrade = "D"
        default:      prospect.scoutGrade = "F"
        }

        // New: Update grade-based scouting fields
        applyGradeBasedFields(report: report, to: prospect)

        // Use personality from the highest-confidence report that has personality notes
        if let _ = prospect.scoutingReports
            .filter({ $0.personalityNotes != nil })
            .max(by: { $0.confidenceLevel < $1.confidenceLevel }) {
            let personalityRoll = Int.random(in: 1...100)
            if personalityRoll <= 70 {
                prospect.scoutedPersonality = prospect.truePersonality.archetype
            } else {
                let wrongArchetypes = PersonalityArchetype.allCases.filter { $0 != prospect.truePersonality.archetype }
                prospect.scoutedPersonality = wrongArchetypes.randomElement()
            }
        }
    }

    /// Aggregates grade data from all reports into progressive GradeRange fields.
    private static func applyGradeBasedFields(report: ScoutingReport, to prospect: CollegeProspect) {
        let reportCount = prospect.scoutingReports.count

        // Overall grade — narrow with each report
        if let letterGrade = report.overallLetterGrade {
            if var existing = prospect.scoutedOverallGrade {
                existing.incorporate(newGrade: letterGrade)
                prospect.scoutedOverallGrade = existing
            } else {
                // First report — wide range (±2 grades)
                let low = letterGrade.shifted(by: 2)   // 2 grades worse
                let high = letterGrade.shifted(by: -2)  // 2 grades better
                prospect.scoutedOverallGrade = GradeRange(low: low, high: high, reportCount: 1)
            }
        }

        // Mental grades — aggregate each attribute
        if let mentalGrades = report.mentalGrades {
            var existing = prospect.scoutedMentalGrades ?? [:]
            for (key, grade) in mentalGrades {
                if var range = existing[key] {
                    range.incorporate(newGrade: grade)
                    existing[key] = range
                } else {
                    let low = grade.shifted(by: 2)
                    let high = grade.shifted(by: -2)
                    existing[key] = GradeRange(low: low, high: high, reportCount: 1)
                }
            }
            prospect.scoutedMentalGrades = existing
        }

        // Position skill grades — same aggregation
        if let posGrades = report.positionSkillGrades {
            var existing = prospect.scoutedPositionGrades ?? [:]
            for (key, grade) in posGrades {
                if var range = existing[key] {
                    range.incorporate(newGrade: grade)
                    existing[key] = range
                } else {
                    let low = grade.shifted(by: 2)
                    let high = grade.shifted(by: -2)
                    existing[key] = GradeRange(low: low, high: high, reportCount: 1)
                }
            }
            prospect.scoutedPositionGrades = existing
        }

        // Potential label — use the latest report's assessment (most recent = most informed)
        if let label = report.potentialLabel {
            prospect.scoutedPotentialLabel = label
        }
    }

    // MARK: - Position-Specific Note Generators

    private static func generatePositionStrengths(for prospect: CollegeProspect, accuracy: Int) -> String {
        var pool: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental
        let threshold = max(65, 90 - accuracy / 3)

        if phys.speed >= threshold { pool.append("Elite speed") }
        if phys.acceleration >= threshold { pool.append("Explosive first step") }
        if phys.strength >= threshold { pool.append("Strong at the point of attack") }
        if phys.agility >= threshold { pool.append("Excellent lateral agility") }
        if phys.stamina >= threshold { pool.append("High motor, plays all four quarters") }
        if phys.durability >= threshold { pool.append("Durable, rarely misses time") }
        if mental.awareness >= threshold { pool.append("High football IQ") }
        if mental.decisionMaking >= threshold { pool.append("Makes good decisions under pressure") }
        if mental.clutch >= threshold { pool.append("Performs well in big moments") }
        if mental.leadership >= threshold { pool.append("Natural leader on the field") }

        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            if qb.armStrength >= threshold { pool.append("Cannon arm, can make all the throws") }
            if qb.accuracyDeep >= threshold { pool.append("Accurate deep-ball thrower") }
            if qb.pocketPresence >= threshold { pool.append("Calm in the pocket, great pocket awareness") }
            if qb.scrambling >= threshold { pool.append("Dangerous when he escapes the pocket") }
        case .wideReceiver(let wr):
            if wr.routeRunning >= threshold { pool.append("Crisp route runner") }
            if wr.catching >= threshold { pool.append("Reliable hands") }
            if wr.release >= threshold { pool.append("Gets off the line quickly") }
            if wr.spectacularCatch >= threshold { pool.append("Makes highlight-reel catches") }
        case .runningBack(let rb):
            if rb.vision >= threshold { pool.append("Excellent vision, finds the hole") }
            if rb.elusiveness >= threshold { pool.append("Elusive in the open field") }
            if rb.breakTackle >= threshold { pool.append("Hard to bring down") }
            if rb.receiving >= threshold { pool.append("Reliable receiver out of the backfield") }
        case .tightEnd(let te):
            if te.blocking >= threshold { pool.append("Strong inline blocker") }
            if te.catching >= threshold { pool.append("Sure hands in traffic") }
            if te.routeRunning >= threshold { pool.append("Runs routes like a receiver") }
        case .offensiveLine(let ol):
            if ol.passBlock >= threshold { pool.append("Elite pass protector") }
            if ol.runBlock >= threshold { pool.append("Dominant run blocker") }
            if ol.anchor >= threshold { pool.append("Great anchor against bull rushes") }
            if ol.pull >= threshold { pool.append("Athletic puller, effective on screens") }
        case .defensiveLine(let dl):
            if dl.passRush >= threshold { pool.append("Disruptive pass rusher") }
            if dl.blockShedding >= threshold { pool.append("Sheds blocks quickly") }
            if dl.powerMoves >= threshold { pool.append("Powerful bull rush") }
            if dl.finesseMoves >= threshold { pool.append("Refined pass-rush moves") }
        case .linebacker(let lb):
            if lb.tackling >= threshold { pool.append("Sure tackler") }
            if lb.zoneCoverage >= threshold { pool.append("Reads routes well in zone") }
            if lb.manCoverage >= threshold { pool.append("Can cover tight ends and backs") }
            if lb.blitzing >= threshold { pool.append("Effective as a blitzer") }
        case .defensiveBack(let db):
            if db.manCoverage >= threshold { pool.append("Lockdown man coverage skills") }
            if db.zoneCoverage >= threshold { pool.append("Reads the quarterback well in zone") }
            if db.press >= threshold { pool.append("Physical at the line of scrimmage") }
            if db.ballSkills >= threshold { pool.append("Ball hawk, creates turnovers") }
        case .kicking(let k):
            if k.kickPower >= threshold { pool.append("Strong leg, can hit from 55+") }
            if k.kickAccuracy >= threshold { pool.append("Accurate and consistent") }
        }

        if pool.isEmpty {
            pool.append("Solid overall athlete with room to grow")
        }

        pool.shuffle()
        let count = min(pool.count, Int.random(in: 2...3))
        return pool.prefix(count).joined(separator: ". ") + "."
    }

    private static func generatePositionWeaknesses(for prospect: CollegeProspect, accuracy: Int) -> String {
        var pool: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental
        let threshold = min(58, 45 + accuracy / 4)

        if phys.speed <= threshold { pool.append("Limited top-end speed") }
        if phys.acceleration <= threshold { pool.append("Slow off the snap") }
        if phys.strength <= threshold { pool.append("Needs to add strength") }
        if phys.agility <= threshold { pool.append("Stiff in the hips") }
        if phys.stamina <= threshold { pool.append("Fades late in games") }
        if phys.durability <= threshold { pool.append("Injury concerns") }
        if mental.awareness <= threshold { pool.append("Can get lost on the field") }
        if mental.decisionMaking <= threshold { pool.append("Questionable decision-making") }
        if mental.workEthic <= threshold { pool.append("Work ethic is a concern") }

        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            if qb.armStrength <= threshold { pool.append("Arm strength limits deep throws") }
            if qb.accuracyDeep <= threshold { pool.append("Struggles with accuracy downfield") }
            if qb.pocketPresence <= threshold { pool.append("Gets rattled under pressure") }
            if qb.scrambling <= threshold { pool.append("Limited mobility outside the pocket") }
        case .wideReceiver(let wr):
            if wr.routeRunning <= threshold { pool.append("Route tree needs refinement") }
            if wr.catching <= threshold { pool.append("Too many drops") }
            if wr.release <= threshold { pool.append("Struggles to get off press coverage") }
        case .runningBack(let rb):
            if rb.vision <= threshold { pool.append("Needs to improve vision") }
            if rb.elusiveness <= threshold { pool.append("Not elusive enough in space") }
            if rb.receiving <= threshold { pool.append("Limited as a pass catcher") }
        case .tightEnd(let te):
            if te.blocking <= threshold { pool.append("Blocking needs work") }
            if te.catching <= threshold { pool.append("Hands can be unreliable") }
            if te.routeRunning <= threshold { pool.append("Route running is raw") }
        case .offensiveLine(let ol):
            if ol.passBlock <= threshold { pool.append("Pass protection is inconsistent") }
            if ol.runBlock <= threshold { pool.append("Struggles to create movement in the run game") }
            if ol.anchor <= threshold { pool.append("Gets pushed back against power") }
        case .defensiveLine(let dl):
            if dl.passRush <= threshold { pool.append("Limited pass-rush arsenal") }
            if dl.blockShedding <= threshold { pool.append("Gets stuck on blocks") }
        case .linebacker(let lb):
            if lb.tackling <= threshold { pool.append("Misses too many tackles") }
            if lb.zoneCoverage <= threshold { pool.append("Liability in coverage") }
            if lb.blitzing <= threshold { pool.append("Not effective as a pass rusher") }
        case .defensiveBack(let db):
            if db.manCoverage <= threshold { pool.append("Gets beaten in man coverage") }
            if db.zoneCoverage <= threshold { pool.append("Loses discipline in zone") }
            if db.ballSkills <= threshold { pool.append("Does not create turnovers") }
        case .kicking(let k):
            if k.kickPower <= threshold { pool.append("Limited range") }
            if k.kickAccuracy <= threshold { pool.append("Inconsistent accuracy") }
        }

        if pool.isEmpty {
            pool.append("No major red flags at this time")
        }

        pool.shuffle()
        let count = min(pool.count, Int.random(in: 2...3))
        return pool.prefix(count).joined(separator: ". ") + "."
    }

    // MARK: - Combine Simulation

    /// Generate realistic combine results for invited prospects (~330 of the draft class).
    /// Top prospects by trueOverall are invited (`combineInvite = true`).
    /// K/P only get height/weight measured — no athletic drills.
    /// Drill results derive from true physical attributes with position-specific
    /// adjustments and ±2-5% random noise.
    static func generateCombineResults(for prospects: inout [CollegeProspect], scoutingAbility: Int = 50) {
        // 1. Select top ~330 prospects by trueOverall as combine invitees
        let inviteCount = min(330, prospects.count)
        let sortedIndices = prospects.indices.sorted { prospects[$0].trueOverall > prospects[$1].trueOverall }
        let invitedIndices = Set(sortedIndices.prefix(inviteCount))

        for i in invitedIndices {
            prospects[i].combineInvite = true
        }

        // 2. Generate drill results for each invitee using position-group benchmarks
        for i in invitedIndices {
            let position = prospects[i].position
            let phys = prospects[i].truePhysical

            // K/P only get height/weight measured, no combine drills
            if position == .K || position == .P { continue }

            let combineModifier = combinePersonalityModifier()
            let posGroup = positionGroup(for: position)
            let tiers = drillTiers(for: posGroup)

            // DE bonus: slightly faster than OL/DT on 40 and 3-cone
            let isDE = position == .DE

            // --- 40-yard dash ---
            // Position-based normal distribution + SPD attribute bias.
            var fortyResult = fortyTimeFromSpeed(speed: phys.speed, position: position, combineModifier: combineModifier)
            if isDE { fortyResult -= 0.03 }
            prospects[i].fortyTime = max(4.22, min(5.55, fortyResult))

            // --- Bench press (225 lb reps) ---
            let benchResult = drillResult(tiers: tiers.bench, attribute: phys.strength, combineModifier: combineModifier, lowerIsBetter: false)
            prospects[i].benchPress = max(3, min(45, Int(benchResult.rounded())))

            // --- Vertical jump ---
            let vertAttr = (phys.agility + phys.acceleration) / 2
            let vertResult = drillResult(tiers: tiers.vert, attribute: vertAttr, combineModifier: combineModifier, lowerIsBetter: false)
            prospects[i].verticalJump = max(20.0, min(46.0, vertResult))

            // --- Broad jump ---
            let broadAttr = (phys.strength + phys.acceleration) / 2
            let broadResult = drillResult(tiers: tiers.broad, attribute: broadAttr, combineModifier: combineModifier, lowerIsBetter: false)
            prospects[i].broadJump = max(84, min(146, Int(broadResult.rounded())))

            // --- 3-cone drill ---
            let coneAttr = (phys.agility + phys.acceleration) / 2
            var coneResult = drillResult(tiers: tiers.cone, attribute: coneAttr, combineModifier: combineModifier, lowerIsBetter: true)
            if isDE { coneResult -= 0.05 }
            prospects[i].coneDrill = max(6.30, min(8.30, coneResult))

            // --- Shuttle time ---
            let shuttleAttr = (phys.agility + phys.speed) / 2
            let shuttleResult = drillResult(tiers: tiers.shuttle, attribute: shuttleAttr, combineModifier: combineModifier, lowerIsBetter: true)
            prospects[i].shuttleTime = max(3.90, min(5.10, shuttleResult))

            // Position drill grade — imprecise estimate from position-specific attributes
            // Better scouting staff → more accurate grade
            prospects[i].positionDrillGrade = generatePositionDrillGrade(for: prospects[i], scoutingAbility: scoutingAbility)
        }
    }

    /// Generates a position drill grade (F through A+) based on the prospect's
    /// position-specific attributes. Noise varies by position (QB/DB hardest to
    /// evaluate, OL/DL most visible) and is reduced by better scouting staff.
    private static func generatePositionDrillGrade(for prospect: CollegeProspect, scoutingAbility: Int = 50) -> String {
        let baseAvg: Double
        switch prospect.truePositionAttributes {
        case .quarterback(let a):
            baseAvg = Double(a.armStrength + a.accuracyShort + a.accuracyMid + a.accuracyDeep + a.pocketPresence + a.scrambling) / 6.0
        case .wideReceiver(let a):
            baseAvg = Double(a.routeRunning + a.catching + a.release + a.spectacularCatch) / 4.0
        case .runningBack(let a):
            baseAvg = Double(a.vision + a.elusiveness + a.breakTackle + a.receiving) / 4.0
        case .tightEnd(let a):
            baseAvg = Double(a.blocking + a.catching + a.routeRunning + a.speed) / 4.0
        case .offensiveLine(let a):
            baseAvg = Double(a.runBlock + a.passBlock + a.pull + a.anchor) / 4.0
        case .defensiveLine(let a):
            baseAvg = Double(a.passRush + a.blockShedding + a.powerMoves + a.finesseMoves) / 4.0
        case .linebacker(let a):
            baseAvg = Double(a.tackling + a.zoneCoverage + a.manCoverage + a.blitzing) / 4.0
        case .defensiveBack(let a):
            baseAvg = Double(a.manCoverage + a.zoneCoverage + a.press + a.ballSkills) / 4.0
        case .kicking(let a):
            baseAvg = Double(a.kickPower + a.kickAccuracy) / 2.0
        }

        // Position-specific base noise — some positions are harder to evaluate in drills
        // QB: decision-making/reads can't be fully measured in drills
        // DB: coverage instincts hard to isolate in controlled drills
        // OL/DL: technique and power most visible in 1-on-1 drills
        let positionNoise: Double = {
            switch prospect.position {
            case .QB:                          return 16.0  // Hardest — intangibles dominate
            case .CB, .FS, .SS:                return 15.0  // Coverage instincts hard to measure
            case .WR, .TE:                     return 13.0  // Route running partially visible
            case .RB, .FB:                     return 12.0  // Vision/instincts vs measurables
            case .MLB, .OLB:                   return 11.0  // Tackling/blitzing fairly observable
            case .DE, .DT:                     return 9.0   // Pass rush moves very visible
            case .LT, .LG, .C, .RG, .RT:      return 8.0   // Technique most measurable in 1-on-1
            case .K, .P:                       return 6.0   // Accuracy directly measurable
            }
        }()

        // Scouting staff modifier: ability 1-99 maps to 1.4x (worst) down to 0.6x (best)
        // Average staff (50) = 1.0x (no change)
        let staffModifier = 1.4 - (Double(max(1, min(99, scoutingAbility))) - 1.0) / 98.0 * 0.8

        let adjustedNoise = positionNoise * staffModifier
        let noise = Double.random(in: -adjustedNoise...adjustedNoise)
        let drillScore = max(20, min(99, baseAvg + noise))

        // Convert to letter grade using percentile-based thresholds
        // Top 3%: A+, Top 5%: A, Top 15%: A-, Top 25%: B+, Top 35%: B
        // Top 50%: B-, Top 60%: C+, Top 70%: C, Top 80%: C-, Top 88%: D+, Top 94%: D, Top 97%: D-, Rest: F
        switch drillScore {
        case 93...:   return "A+"
        case 88..<93:  return "A"
        case 82..<88:  return "A-"
        case 76..<82:  return "B+"
        case 70..<76:  return "B"
        case 64..<70:  return "B-"
        case 58..<64:  return "C+"
        case 52..<58:  return "C"
        case 46..<52:  return "C-"
        case 40..<46:  return "D+"
        case 35..<40:  return "D"
        case 30..<35:  return "D-"
        default:       return "F"
        }
    }

    /// Legacy wrapper — calls generateCombineResults(for:).
    static func simulateCombine(prospects: inout [CollegeProspect], scoutingAbility: Int = 50) {
        generateCombineResults(for: &prospects, scoutingAbility: scoutingAbility)
    }

    // MARK: - Combine Position Groups & Drill Ranges

    private enum CombinePositionGroup {
        case speedster  // WR, CB, FS, SS, QB — fastest 40 times
        case bigman     // OL (LT, LG, C, RG, RT), DL (DE, DT) — highest bench press, slower 40
        case balanced   // RB, FB, TE, OLB, MLB — balanced across drills
    }

    private static func positionGroup(for position: Position) -> CombinePositionGroup {
        switch position {
        case .QB, .WR, .CB, .FS, .SS:
            return .speedster
        case .LT, .LG, .C, .RG, .RT, .DE, .DT:
            return .bigman
        case .RB, .FB, .TE, .OLB, .MLB:
            return .balanced
        case .K, .P:
            return .balanced  // Won't be reached (K/P excluded above)
        }
    }

    /// Real NFL Combine drill ranges per position group, split into 4 tiers:
    /// Elite (attr 95-99), Good (80-94), Average (65-79), Below Average (<65).
    /// Each tier stores (min, max) for the drill result.
    private struct CombineDrillTiers {
        let elite: (Double, Double)
        let good: (Double, Double)
        let average: (Double, Double)
        let belowAvg: (Double, Double)

        /// Returns the (min, max) range for a given physical attribute value (40-99).
        func range(for attribute: Int) -> (Double, Double) {
            switch attribute {
            case 95...99: return elite
            case 80...94: return good
            case 65...79: return average
            default:      return belowAvg
            }
        }
    }

    /// Position-group–specific drill tiers based on real NFL Combine data.
    /// For time-based drills (40, 3-cone, shuttle) lower is better.
    /// For reps/distance drills (bench, vert, broad) higher is better.
    private static func drillTiers(for group: CombinePositionGroup) -> (
        forty: CombineDrillTiers,
        bench: CombineDrillTiers,
        vert: CombineDrillTiers,
        broad: CombineDrillTiers,
        cone: CombineDrillTiers,
        shuttle: CombineDrillTiers
    ) {
        switch group {
        // Tier ranges define the elite..below-average envelope used by `drillResult`,
        // which now uses a normal-ish distribution (mean = midpoint, sigma = span/4).
        // Wider envelopes produce a more realistic spread with outliers on both ends.
        case .speedster:
            return (
                forty:   CombineDrillTiers(elite: (4.25, 4.35), good: (4.36, 4.45), average: (4.46, 4.55), belowAvg: (4.56, 4.75)),
                bench:   CombineDrillTiers(elite: (16, 22), good: (12, 16), average: (8, 12), belowAvg: (4, 8)),
                vert:    CombineDrillTiers(elite: (40, 44), good: (36, 40), average: (32, 36), belowAvg: (28, 32)),
                broad:   CombineDrillTiers(elite: (128, 138), good: (120, 128), average: (112, 120), belowAvg: (104, 112)),
                cone:    CombineDrillTiers(elite: (6.50, 6.70), good: (6.70, 6.90), average: (6.90, 7.10), belowAvg: (7.10, 7.40)),
                shuttle: CombineDrillTiers(elite: (3.95, 4.10), good: (4.10, 4.25), average: (4.25, 4.40), belowAvg: (4.40, 4.60))
            )
        case .bigman:
            return (
                forty:   CombineDrillTiers(elite: (4.80, 5.00), good: (5.00, 5.15), average: (5.15, 5.30), belowAvg: (5.30, 5.55)),
                bench:   CombineDrillTiers(elite: (30, 38), good: (25, 30), average: (20, 25), belowAvg: (14, 20)),
                vert:    CombineDrillTiers(elite: (30, 34), good: (27, 30), average: (24, 27), belowAvg: (20, 24)),
                broad:   CombineDrillTiers(elite: (108, 118), good: (100, 108), average: (94, 100), belowAvg: (86, 94)),
                cone:    CombineDrillTiers(elite: (7.20, 7.45), good: (7.45, 7.65), average: (7.65, 7.85), belowAvg: (7.85, 8.20)),
                shuttle: CombineDrillTiers(elite: (4.40, 4.60), good: (4.60, 4.75), average: (4.75, 4.90), belowAvg: (4.90, 5.10))
            )
        case .balanced:
            return (
                forty:   CombineDrillTiers(elite: (4.35, 4.48), good: (4.48, 4.60), average: (4.60, 4.72), belowAvg: (4.72, 4.90)),
                bench:   CombineDrillTiers(elite: (22, 30), good: (16, 22), average: (12, 16), belowAvg: (8, 12)),
                vert:    CombineDrillTiers(elite: (37, 42), good: (33, 37), average: (29, 33), belowAvg: (25, 29)),
                broad:   CombineDrillTiers(elite: (120, 132), good: (110, 120), average: (102, 110), belowAvg: (94, 102)),
                cone:    CombineDrillTiers(elite: (6.70, 6.95), good: (6.95, 7.15), average: (7.15, 7.35), belowAvg: (7.35, 7.65)),
                shuttle: CombineDrillTiers(elite: (4.10, 4.25), good: (4.25, 4.40), average: (4.40, 4.55), belowAvg: (4.55, 4.75))
            )
        }
    }

    /// Generates a drill result using a normal-ish distribution (sum of 3 uniform rolls)
    /// centered on the attribute-driven midpoint of the tier range. This produces a
    /// realistic spread with most prospects clustering around the mean and a few
    /// outliers on both ends.
    /// For time-based drills (lower = better), higher attributes produce lower results.
    /// For rep/distance drills (higher = better), higher attributes produce higher results.
    private static func drillResult(
        tiers: CombineDrillTiers,
        attribute: Int,
        combineModifier: Double,
        lowerIsBetter: Bool
    ) -> Double {
        // Span the full position range from elite to belowAvg.
        // Use the mid of average tier as the population mean, and use the full
        // elite-to-belowAvg span as ~4 standard deviations.
        let bestEnd: Double  // fastest time / most reps
        let worstEnd: Double // slowest time / fewest reps
        if lowerIsBetter {
            bestEnd  = min(tiers.elite.0, tiers.elite.1)
            worstEnd = max(tiers.belowAvg.0, tiers.belowAvg.1)
        } else {
            bestEnd  = max(tiers.elite.0, tiers.elite.1)
            worstEnd = min(tiers.belowAvg.0, tiers.belowAvg.1)
        }
        let mean = (bestEnd + worstEnd) / 2.0
        let stdDev = abs(bestEnd - worstEnd) / 4.0  // ~95% of values fall within elite..belowAvg

        // Normal-ish distribution (avg of 3 uniform rolls in [-1, 1])
        let roll = (Double.random(in: -1.0...1.0)
                  + Double.random(in: -1.0...1.0)
                  + Double.random(in: -1.0...1.0)) / 3.0

        // Attribute bias: maps 40-99 attribute to ~+1.4..-1.4 std-dev shift.
        // attr 70 (median) → 0 shift, attr 99 (elite) → toward best end, attr 40 → toward worst.
        let attrBias = (70.0 - Double(attribute)) / 20.0  // higher attr → smaller (negative) bias

        // Combine modifier shifts ~0.5 std-dev
        let modBias = combineModifier * 0.5

        // For "lowerIsBetter" drills, higher attribute should reduce the value.
        // attrBias positive = lower attr = should be slower (higher value if lowerIsBetter).
        let signedAttrBias = lowerIsBetter ? attrBias : -attrBias
        let signedModBias = lowerIsBetter ? -modBias : modBias

        return mean + (roll + signedAttrBias + signedModBias) * stdDev
    }

    /// Converts a speed attribute (40-99) to a realistic 40-yard dash time.
    /// Uses position-specific mean + standard deviation (normal-ish distribution).
    /// Speed attribute biases the result: high SPD shifts toward fast end of position curve,
    /// low SPD shifts toward slow end, but position is the dominant factor (a 99-SPD OL
    /// still runs ~4.95, a 60-SPD WR still runs ~4.55).
    private static func fortyTimeFromSpeed(speed: Int, position: Position, combineModifier: Double) -> Double {
        // Position-specific mean + std dev (in seconds).
        // Calibrated to real NFL Combine distributions — skill positions widened
        // so an elite 99-SPD WR/CB/RB can post sub-4.35 times like the real combine.
        let mean: Double
        let stdDev: Double
        switch position {
        case .WR, .CB, .FS, .SS:
            mean = 4.46;  stdDev = 0.11   // Most 4.28-4.64, top performers 4.25-4.36
        case .RB:
            mean = 4.52;  stdDev = 0.11   // Most 4.34-4.70
        case .QB:
            mean = 4.78;  stdDev = 0.14   // Most 4.55-5.00 (Mahomes 4.80, Lamar 4.34)
        case .OLB:
            mean = 4.66;  stdDev = 0.11   // Most 4.50-4.85
        case .MLB:
            mean = 4.72;  stdDev = 0.11   // Most 4.55-4.90
        case .TE:
            mean = 4.68;  stdDev = 0.11   // Most 4.50-4.85
        case .FB:
            mean = 4.78;  stdDev = 0.12   // Most 4.60-5.00
        case .DE:
            mean = 4.76;  stdDev = 0.12   // Most 4.55-4.95, top edge 4.40-4.55
        case .DT:
            mean = 4.95;  stdDev = 0.12   // Most 4.75-5.15
        case .LT, .LG, .C, .RG, .RT:
            mean = 5.13;  stdDev = 0.14   // Most 4.90-5.40
        case .K, .P:
            mean = 4.95;  stdDev = 0.15
        }

        // Two uniform rolls averaged → bell-curve roughly [-0.5, +0.5] stddev.
        let roll = (Double.random(in: -1.0...1.0) + Double.random(in: -1.0...1.0)) / 2.0

        // Speed attribute bias — wider divisor so elite SPD truly separates from average.
        // SPD 50 → +1.25 stddev (slower than position avg)
        // SPD 75 → 0 (position avg)
        // SPD 99 → -1.20 stddev (clearly faster than position avg)
        let speedBias = (75.0 - Double(speed)) / 20.0

        // Combine modifier: warriors (-0.6 std), bad testers (+0.6 std)
        let modBias = -combineModifier * 0.6

        let result = mean + (roll + speedBias + modBias) * stdDev
        return result
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

    // MARK: - Enhanced Interview System

    /// Conduct an interview with a prospect at the combine. Reveals personality, footballIQ, and character notes.
    /// - Parameters:
    ///   - prospect: The prospect to interview (mutated in place).
    ///   - interviewerQuality: HC or scout playCalling/motivation attribute (1-99).
    /// - Returns: Tuple of revealed personality, footballIQ, and character notes.
    static func conductInterview(
        prospect: CollegeProspect,
        interviewerQuality: Int
    ) -> (personality: PersonalityArchetype, footballIQ: Int, characterNotes: [String]) {
        // 1. Reveal personality with noise based on interviewer quality
        let personalityRoll = Int.random(in: 1...100)
        let revealedPersonality: PersonalityArchetype
        if personalityRoll <= interviewerQuality {
            revealedPersonality = prospect.truePersonality.archetype
        } else {
            // Misread: return a wrong archetype
            let wrong = PersonalityArchetype.allCases.filter { $0 != prospect.truePersonality.archetype }
            revealedPersonality = wrong.randomElement() ?? prospect.truePersonality.archetype
        }

        // 2. Reveal footballIQ scaled by draft projection tier with interviewer noise
        let trueMentalAvg = Int(prospect.trueMental.average.rounded())
        let projRound = prospect.draftProjection ?? 5
        let iqFloor: Int
        let iqCeiling: Int
        switch projRound {
        case 1:      iqFloor = 70; iqCeiling = 95
        case 2...3:  iqFloor = 60; iqCeiling = 85
        case 4...5:  iqFloor = 50; iqCeiling = 78
        default:     iqFloor = 45; iqCeiling = 75
        }
        let scaledIQ = iqFloor + Int(Double(trueMentalAvg - 40) / 59.0 * Double(iqCeiling - iqFloor))
        let maxNoise = max(1, 20 - (interviewerQuality * 20 / 100))
        let iqNoise = Int.random(in: -maxNoise...maxNoise)
        let footballIQ = min(iqCeiling, max(iqFloor, scaledIQ + iqNoise))

        // 3. Generate 1-3 character notes based on true attributes
        var characterPool: [String] = []
        let mental = prospect.trueMental
        let personality = prospect.truePersonality

        if mental.leadership >= 75 { characterPool.append("Natural leader") }
        if mental.workEthic >= 80 { characterPool.append("High character") }
        if mental.workEthic < 45 { characterPool.append("Off-field concerns") }
        if mental.coachability >= 80 { characterPool.append("Extremely coachable") }
        if mental.coachability < 40 { characterPool.append("Resistant to coaching") }
        if mental.clutch >= 80 { characterPool.append("Clutch performer") }
        if mental.clutch < 40 { characterPool.append("Folds under pressure") }
        if personality.archetype == .teamLeader { characterPool.append("Team-first mentality") }
        if personality.archetype == .dramaQueen { characterPool.append("Maturity concerns") }
        if personality.archetype == .fieryCompetitor { characterPool.append("Intense competitor") }
        if personality.archetype == .mentor { characterPool.append("Mature beyond his years") }
        if personality.archetype == .loneWolf { characterPool.append("Keeps to himself") }

        // Noise: poor interviewers may miss notes or get wrong read
        if interviewerQuality < 50 && Int.random(in: 1...100) > interviewerQuality {
            // Replace a note with a misleading one
            let misleading = ["Seemed fine", "Hard to read", "Came across as average"]
            characterPool.append(misleading.randomElement()!)
        }

        if characterPool.isEmpty {
            characterPool.append("Nothing stood out, solid character")
        }

        characterPool.shuffle()
        let noteCount = min(characterPool.count, Int.random(in: 1...3))
        let characterNotes = Array(characterPool.prefix(noteCount))

        // 4. Update prospect state
        prospect.interviewCompleted = true
        prospect.scoutedPersonality = revealedPersonality
        prospect.interviewFootballIQ = footballIQ
        prospect.interviewCharacterNotes = characterNotes
        prospect.interviewNotes = characterNotes.joined(separator: ". ") + "."

        return (personality: revealedPersonality, footballIQ: footballIQ, characterNotes: characterNotes)
    }

    // MARK: - Pro Day System

    /// Send a scout to a Pro Day at a college. Generates combine-like results for all prospects at that school.
    /// For combine invitees, allows improving one drill result. For non-invitees, generates hand-timed results.
    /// Also generates a scout report at `.proDay` phase for each prospect.
    static func attendProDay(
        scout: Scout,
        college: String,
        prospects: inout [CollegeProspect]
    ) {
        let collegeIndices = prospects.indices.filter { prospects[$0].college == college }
        guard !collegeIndices.isEmpty else { return }

        for i in collegeIndices {
            let phys = prospects[i].truePhysical
            let position = prospects[i].position

            // K/P only get height/weight — no athletic drills
            if position == .K || position == .P {
                prospects[i].proDayCompleted = true
                // Still generate a scout report
                let report = generateScoutReport(scout: scout, prospect: prospects[i], phase: .proDay)
                applyReport(report: report, to: prospects[i])
                continue
            }

            if prospects[i].combineInvite {
                // Combine invitees can improve ONE drill result (athlete chooses best chance)
                improveOneDrill(prospect: &prospects[i], physical: phys)
            } else {
                // Non-combine invitees: generate hand-timed results (±3% less accurate)
                generateHandTimedResults(prospect: &prospects[i], physical: phys, position: position)
            }

            prospects[i].proDayCompleted = true

            // Generate scout report at Pro Day phase
            let report = generateScoutReport(scout: scout, prospect: prospects[i], phase: .proDay)
            applyReport(report: report, to: prospects[i])
        }

        scout.proDaysAttended += 1
        if !scout.proDayColleges.contains(college) {
            scout.proDayColleges.append(college)
        }
    }

    /// For combine invitees at pro day: improve their weakest drill result.
    private static func improveOneDrill(prospect: inout CollegeProspect, physical: PhysicalAttributes) {
        let homefieldBoost = 0.3

        // Pick the drill where they underperformed most (or a random one)
        // We'll try to improve their worst drill relative to their athletic ability
        let drills = ["forty", "bench", "vertical", "broad", "shuttle", "cone"]
        let drill = drills.randomElement()!

        switch drill {
        case "forty":
            let baseForty = 5.5 - (Double(physical.speed) * 0.013)
            let variance = Double.random(in: -0.06...0.04) - homefieldBoost * 0.03
            let proDayForty = max(4.2, min(5.5, baseForty + variance))
            if let existing = prospect.fortyTime {
                prospect.fortyTime = min(existing, proDayForty)
            }
        case "bench":
            let baseBench = Int(Double(physical.strength) * 0.35) - 5
            let variance = Int.random(in: -1...4)
            let proDayBench = max(8, min(45, baseBench + variance))
            if let existing = prospect.benchPress {
                prospect.benchPress = max(existing, proDayBench)
            }
        case "vertical":
            let baseVert = 20.0 + Double(physical.acceleration + physical.agility) * 0.13
            let variance = Double.random(in: -0.5...2.0)
            let proDayVert = max(24.0, min(46.0, baseVert + variance))
            if let existing = prospect.verticalJump {
                prospect.verticalJump = max(existing, proDayVert)
            }
        case "broad":
            let baseBroad = 80 + Int(Double(physical.strength + physical.acceleration) * 0.3)
            let variance = Int.random(in: -1...5)
            let proDayBroad = max(95, min(145, baseBroad + variance))
            if let existing = prospect.broadJump {
                prospect.broadJump = max(existing, proDayBroad)
            }
        case "shuttle":
            let baseShuttle = 4.8 - (Double(physical.agility + physical.speed) * 0.005)
            let variance = Double.random(in: -0.08...0.04)
            let proDayShuttle = max(3.7, min(4.8, baseShuttle + variance))
            if let existing = prospect.shuttleTime {
                prospect.shuttleTime = min(existing, proDayShuttle)
            }
        case "cone":
            let baseCone = 7.8 - (Double(physical.agility + physical.acceleration) * 0.007)
            let variance = Double.random(in: -0.10...0.05)
            let proDayCone = max(6.4, min(7.6, baseCone + variance))
            if let existing = prospect.coneDrill {
                prospect.coneDrill = min(existing, proDayCone)
            }
        default: break
        }
    }

    /// For non-combine invitees at pro day: generate hand-timed results (±3% less accurate than combine).
    private static func generateHandTimedResults(
        prospect: inout CollegeProspect,
        physical: PhysicalAttributes,
        position: Position
    ) {
        let posGroup = positionGroup(for: position)
        // Hand-timed = slightly favorable (no electronic precision) but noisier
        let handTimedBias = 0.03

        // 40-yard dash (hand-timed tends to be ~0.1 sec faster)
        let fortyBase: Double = {
            let raw = 5.5 - (Double(physical.speed) * 0.013)
            switch posGroup {
            case .speedster: return raw - 0.05
            case .bigman:    return raw + 0.15
            case .balanced:  return raw
            }
        }()
        let fortyNoise = Double.random(in: -0.05...0.05)
        prospect.fortyTime = max(4.22, min(5.40, fortyBase + fortyNoise - handTimedBias))

        // Bench press
        let benchBase: Int = {
            let raw = Int(Double(physical.strength) * 0.35) - 5
            switch posGroup {
            case .bigman:    return raw + 8
            case .balanced:  return raw + 2
            case .speedster: return raw - 2
            }
        }()
        prospect.benchPress = max(8, min(45, benchBase + Int.random(in: -3...3)))

        // Vertical jump
        let vertBase = 20.0 + Double(physical.agility + physical.acceleration) * 0.13
        prospect.verticalJump = max(24.0, min(46.0, vertBase + Double.random(in: -2.0...2.0)))

        // Broad jump
        let broadBase: Int = {
            let raw = 80 + Int(Double(physical.strength + physical.acceleration) * 0.3)
            switch posGroup {
            case .speedster: return raw + 2
            case .bigman:    return raw - 4
            case .balanced:  return raw
            }
        }()
        prospect.broadJump = max(95, min(145, broadBase + Int.random(in: -4...4)))

        // 3-cone drill
        let coneBase = 7.8 - (Double(physical.agility + physical.acceleration) * 0.007)
        prospect.coneDrill = max(6.40, min(7.60, coneBase + Double.random(in: -0.10...0.10)))

        // Shuttle
        let shuttleBase: Double = {
            let raw = 4.8 - (Double(physical.agility + physical.speed) * 0.005)
            switch posGroup {
            case .speedster: return raw - 0.05
            case .bigman:    return raw + 0.10
            case .balanced:  return raw
            }
        }()
        prospect.shuttleTime = max(3.80, min(4.80, shuttleBase + Double.random(in: -0.08...0.08)))
    }

    // MARK: - Personal Workout System

    /// Invite a prospect for a personal workout. Highest accuracy evaluation (confidence 0.9).
    /// Generates a scout report at `.personalWorkout` phase with scheme fit evaluation.
    static func conductPersonalWorkout(
        prospect: CollegeProspect,
        coaches: [Coach]
    ) {
        // 1. Generate a high-confidence scout report
        // Use the best coaching staff member's scouting ability as the basis
        let bestScoutingAbility = coaches.map { $0.scoutingAbility }.max() ?? 50

        // Create a virtual "scout" with high accuracy for the workout evaluation
        let errorRange = max(1, Int(8.0 * (1.0 - Double(bestScoutingAbility) / 100.0)))

        let overallNoise = Int.random(in: -errorRange...errorRange)
        let scoutedOverall = min(99, max(1, prospect.trueOverall + overallNoise))

        let potentialNoise = Int.random(in: -(errorRange + 2)...(errorRange + 2))
        let scoutedPotential = min(99, max(1, prospect.truePotential + potentialNoise))

        // 2. Scheme fit evaluation based on coaches
        let schemeFitNotes = evaluateSchemeFit(prospect: prospect, coaches: coaches)

        // 3. Personality read (very accurate in personal setting)
        let personalityNotes: String?
        if Int.random(in: 1...100) <= 85 {
            personalityNotes = accuratePersonalityNote(archetype: prospect.truePersonality.archetype)
                + " " + schemeFitNotes
        } else {
            personalityNotes = schemeFitNotes
        }

        // 4. Generate full workout report
        let strengthNotes = generatePositionStrengths(for: prospect, accuracy: min(99, bestScoutingAbility + 15))
        let weaknessNotes = generatePositionWeaknesses(for: prospect, accuracy: min(99, bestScoutingAbility + 15))

        let report = ScoutingReport(
            prospectID: prospect.id,
            scoutID: UUID(), // Virtual "coaching staff" report
            scoutName: "Coaching Staff",
            date: currentDateString(),
            phase: .personalWorkout,
            overallGrade: scoutedOverall,
            potentialGrade: scoutedPotential,
            strengthNotes: strengthNotes,
            weaknessNotes: weaknessNotes,
            personalityNotes: personalityNotes,
            confidenceLevel: 0.9
        )

        // 5. Apply report
        prospect.scoutingReports.append(report)

        // Update best scouted values
        if let bestReport = prospect.scoutingReports.max(by: { $0.confidenceLevel < $1.confidenceLevel }) {
            prospect.scoutedOverall = bestReport.overallGrade
            prospect.scoutedPotential = bestReport.potentialGrade

            let ovr = bestReport.overallGrade
            switch ovr {
            case 90...99: prospect.scoutGrade = "A+"
            case 85...89: prospect.scoutGrade = "A"
            case 80...84: prospect.scoutGrade = "A-"
            case 75...79: prospect.scoutGrade = "B+"
            case 70...74: prospect.scoutGrade = "B"
            case 65...69: prospect.scoutGrade = "B-"
            case 60...64: prospect.scoutGrade = "C+"
            case 55...59: prospect.scoutGrade = "C"
            case 50...54: prospect.scoutGrade = "C-"
            case 45...49: prospect.scoutGrade = "D+"
            case 40...44: prospect.scoutGrade = "D"
            default:      prospect.scoutGrade = "F"
            }
        }

        prospect.proDayCompleted = true
    }

    /// Evaluate how well a prospect fits the team's schemes based on coaching staff.
    private static func evaluateSchemeFit(prospect: CollegeProspect, coaches: [Coach]) -> String {
        var fitNotes: [String] = []

        // Find the OC and DC for scheme references
        let oc = coaches.first { $0.role == .offensiveCoordinator }
        let dc = coaches.first { $0.role == .defensiveCoordinator }

        let isOffense = [Position.QB, .RB, .FB, .WR, .TE, .LT, .LG, .C, .RG, .RT].contains(prospect.position)

        if isOffense, let scheme = oc?.offensiveScheme {
            switch prospect.truePositionAttributes {
            case .quarterback(let qb):
                if scheme == .westCoast && qb.accuracyShort >= 75 {
                    fitNotes.append("Accuracy profile fits the West Coast scheme well")
                } else if scheme == .airRaid && qb.accuracyDeep >= 70 {
                    fitNotes.append("Deep ball ability suits the Air Raid system")
                } else if (scheme == .spread || scheme == .option || scheme == .rpo) && qb.scrambling >= 70 {
                    fitNotes.append("Mobility is ideal for the spread/option scheme")
                }
            case .runningBack(let rb):
                if scheme == .powerRun && rb.breakTackle >= 70 {
                    fitNotes.append("Physical runner, great fit for power run game")
                } else if (scheme == .spread || scheme == .rpo) && rb.elusiveness >= 70 {
                    fitNotes.append("Elusiveness works well in zone-read concepts")
                }
            case .wideReceiver(let wr):
                if scheme == .westCoast && wr.routeRunning >= 70 {
                    fitNotes.append("Route precision fits the West Coast timing game")
                } else if scheme == .airRaid && wr.catching >= 70 {
                    fitNotes.append("Reliable hands suit the high-volume passing attack")
                }
            default: break
            }
        } else if !isOffense, let scheme = dc?.defensiveScheme {
            switch prospect.truePositionAttributes {
            case .defensiveLine(let dl):
                if scheme == .base34 && dl.passRush >= 70 {
                    fitNotes.append("Pass rush ability fits the 3-4 front well")
                } else if scheme == .base43 && dl.blockShedding >= 70 {
                    fitNotes.append("Block shedding suits the 4-3 scheme")
                }
            case .linebacker(let lb):
                if scheme == .base34 && lb.blitzing >= 70 {
                    fitNotes.append("Blitzing ability ideal for 3-4 OLB role")
                } else if scheme == .base43 && lb.zoneCoverage >= 70 {
                    fitNotes.append("Zone coverage skills fit the 4-3 scheme well")
                }
            case .defensiveBack(let db):
                if scheme == .tampa2 && db.zoneCoverage >= 70 {
                    fitNotes.append("Zone instincts are perfect for Tampa 2")
                } else if scheme == .cover3 && db.manCoverage >= 70 {
                    fitNotes.append("Man coverage ability fits the Cover 3 scheme")
                } else if scheme == .pressMan && db.press >= 70 {
                    fitNotes.append("Press technique is ideal for the press man scheme")
                }
            default: break
            }
        }

        if fitNotes.isEmpty {
            fitNotes.append("Scheme fit is average. Versatile enough to contribute.")
        }

        return fitNotes.joined(separator: ". ") + "."
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

    // MARK: - Mock Draft Generation

    /// A single entry in a mock draft projection.
    struct MockDraftPick {
        let pickNumber: Int
        let round: Int
        let prospectID: UUID
        let teamAbbreviation: String
        let teamID: UUID
        /// Top positional needs for the team at the time of the pick.
        let teamNeeds: [Position]
        /// Why this pick was made: "BPA at position of need", "Best Player Available", etc.
        let pickRationale: String
        /// Media comment: "Perfect fit", "Surprise pick", "Steal of the draft", etc.
        let mediaComment: String
    }

    /// Generate a mock draft projection for rounds 1-3 (up to 96+ picks).
    ///
    /// Called at: midseason (week 9), entering combine phase, entering draft phase.
    /// The mock simulates which prospect each team would take based on roster needs,
    /// with +-3-5 pick variance to represent media imperfection.
    /// Applies positional draft value so P/K/FB never appear in round 1.
    /// Enforces position diversity: max 1 per position in top 5, max 2 in top 10 (QB exempted up to 2 in top 5).
    ///
    /// - Parameters:
    ///   - prospects: All available college prospects.
    ///   - draftPicks: Current draft pick assignments (used for team order). If empty, uses team order by wins (worst first).
    ///   - teams: All 32 teams.
    ///   - players: All current NFL players (used to evaluate team needs).
    /// - Returns: Array of mock pick assignments for rounds 1-3.
    static func generateMockDraft(
        prospects: [CollegeProspect],
        draftPicks: [DraftPick],
        teams: [Team],
        players: [Player]
    ) -> [MockDraftPick] {
        guard !prospects.isEmpty, !teams.isEmpty else { return [] }

        let teamLookup = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        // Build team pick order for rounds 1-3.
        let teamOrder: [(pickNumber: Int, round: Int, teamID: UUID, abbreviation: String)]

        if !draftPicks.isEmpty {
            let roundPicks = draftPicks
                .filter { $0.round >= 1 && $0.round <= 3 }
                .sorted { $0.pickNumber < $1.pickNumber }
            teamOrder = roundPicks.compactMap { pick in
                guard let team = teamLookup[pick.currentTeamID] else { return nil }
                return (pickNumber: pick.pickNumber, round: pick.round, teamID: team.id, abbreviation: team.abbreviation)
            }
        } else {
            // Pre-draft: order by worst record first, generate 3 rounds
            let sorted = teams.sorted { ($0.wins - $0.losses) < ($1.wins - $1.losses) }
            var order: [(pickNumber: Int, round: Int, teamID: UUID, abbreviation: String)] = []
            for round in 1...3 {
                let roundTeams = round % 2 == 1 ? sorted : sorted.reversed()
                for (index, team) in roundTeams.prefix(32).enumerated() {
                    let pickNum = (round - 1) * 32 + index + 1
                    order.append((pickNumber: pickNum, round: round, teamID: team.id, abbreviation: team.abbreviation))
                }
            }
            teamOrder = order
        }

        guard !teamOrder.isEmpty else { return [] }

        // Pre-compute team needs
        let playersByTeam = Dictionary(grouping: players) { $0.teamID ?? UUID() }
        var teamNeeds: [UUID: [Position: Double]] = [:]
        for team in teams {
            let roster = playersByTeam[team.id] ?? []
            teamNeeds[team.id] = evaluateTeamNeedsForMock(roster: roster)
        }

        // Sort prospects by composite score: trueOverall * positionalDraftValue
        let sortedProspects = prospects
            .filter { $0.isDeclaringForDraft }
            .sorted {
                Double($0.trueOverall) * positionalDraftValue(for: $0.position) >
                Double($1.trueOverall) * positionalDraftValue(for: $1.position)
            }

        var takenIDs = Set<UUID>()
        var mockPicks: [MockDraftPick] = []
        // Track position counts for diversity enforcement in top 10
        var positionCountsTop5: [Position: Int] = [:]
        var positionCountsTop10: [Position: Int] = [:]

        for entry in teamOrder {
            let needs = teamNeeds[entry.teamID] ?? [:]
            let topNeeds = needs.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
            let available = sortedProspects.filter { !takenIDs.contains($0.id) }
            guard !available.isEmpty else { break }

            // Score each available prospect
            let scored = available.prefix(80).compactMap { prospect -> (CollegeProspect, Double, String, String)? in
                let posValue = positionalDraftValue(for: prospect.position)
                var score = Double(prospect.trueOverall) * posValue

                // Positional need boost
                let needMultiplier = needs[prospect.position] ?? 1.0
                score *= needMultiplier

                // QB premium
                if prospect.position == .QB && (needs[.QB] ?? 1.0) > 1.2 {
                    score *= 1.15
                }

                // Potential factor
                score += Double(prospect.truePotential) * 0.15

                // Media noise: +-3-5 points of variance (media isn't perfect)
                let noise = Double.random(in: -5.0...5.0)
                score += noise

                // Position diversity enforcement for round 1
                if entry.round == 1 {
                    let pickNum = entry.pickNumber
                    // Top 5: max 1 per position (QB can have 2)
                    if pickNum <= 5 {
                        let currentCount = positionCountsTop5[prospect.position] ?? 0
                        let maxAllowed = prospect.position == .QB ? 2 : 1
                        if currentCount >= maxAllowed {
                            return nil // skip this prospect
                        }
                    }
                    // Top 10: max 2 per position
                    if pickNum <= 10 {
                        let currentCount = positionCountsTop10[prospect.position] ?? 0
                        if currentCount >= 2 {
                            return nil // skip this prospect
                        }
                    }
                }

                // Determine rationale
                let isNeedPosition = topNeeds.contains(prospect.position)
                let rationale: String
                if isNeedPosition && needMultiplier > 1.15 {
                    rationale = "BPA at position of need"
                } else if isNeedPosition {
                    rationale = "Addresses team need"
                } else {
                    rationale = "Best Player Available"
                }

                return (prospect, score, rationale, "")
            }

            if let best = scored.max(by: { $0.1 < $1.1 }) {
                takenIDs.insert(best.0.id)

                // Update position diversity trackers
                if entry.round == 1 {
                    if entry.pickNumber <= 5 {
                        positionCountsTop5[best.0.position, default: 0] += 1
                    }
                    if entry.pickNumber <= 10 {
                        positionCountsTop10[best.0.position, default: 0] += 1
                    }
                }

                // Generate media comment based on pick position vs projected round
                let projectedRound = best.0.draftProjection ?? entry.round
                let mediaComment: String
                if entry.round == 1 && projectedRound >= 3 {
                    mediaComment = "Reaches for need"
                } else if entry.round >= 2 && projectedRound == 1 {
                    mediaComment = "Steal of the draft"
                } else if entry.round == 1 && projectedRound == 1 {
                    let isNeed = topNeeds.contains(best.0.position)
                    if isNeed {
                        mediaComment = "Perfect fit"
                    } else {
                        mediaComment = "Best player available"
                    }
                } else if entry.pickNumber <= 10 && projectedRound >= 2 {
                    mediaComment = "Surprise pick"
                } else {
                    mediaComment = ""
                }

                mockPicks.append(MockDraftPick(
                    pickNumber: entry.pickNumber,
                    round: entry.round,
                    prospectID: best.0.id,
                    teamAbbreviation: entry.abbreviation,
                    teamID: entry.teamID,
                    teamNeeds: topNeeds,
                    pickRationale: best.2,
                    mediaComment: mediaComment
                ))
            }
        }

        return mockPicks
    }

    /// Updates team interest on all prospects based on positional need matching.
    ///
    /// Each team's top 2-3 positional needs are identified, and prospects at those
    /// positions receive that team's ID in their `teamInterest` array.
    static func updateTeamInterest(
        prospects: inout [CollegeProspect],
        teams: [Team],
        players: [Player]
    ) {
        let playersByTeam = Dictionary(grouping: players) { $0.teamID ?? UUID() }

        // Clear existing interest
        for i in prospects.indices {
            prospects[i].teamInterest = []
        }

        for team in teams {
            let roster = playersByTeam[team.id] ?? []
            let needs = evaluateTeamNeedsForMock(roster: roster)

            // Get top 3 need positions (highest multiplier)
            let topNeeds = needs
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key }

            // Add this team's interest to matching prospects
            for i in prospects.indices where topNeeds.contains(prospects[i].position) {
                // Only interested in prospects projected in rounds 1-3
                if let proj = prospects[i].draftProjection, proj <= 3 {
                    prospects[i].teamInterest.append(team.id)
                } else if prospects[i].trueOverall >= 65 {
                    // Also interested in high-talent prospects regardless of projection
                    prospects[i].teamInterest.append(team.id)
                }
            }
        }
    }

    /// Updates prospect mock draft annotations from mock draft results.
    static func applyMockDraftToProspects(
        prospects: inout [CollegeProspect],
        mockDraft: [MockDraftPick]
    ) {
        // Clear previous mock annotations
        for i in prospects.indices {
            prospects[i].mockDraftPickNumber = nil
            prospects[i].mockDraftTeam = nil
        }

        // Apply new mock draft data
        for pick in mockDraft {
            if let idx = prospects.firstIndex(where: { $0.id == pick.prospectID }) {
                prospects[idx].mockDraftPickNumber = pick.pickNumber
                prospects[idx].mockDraftTeam = pick.teamAbbreviation
            }
        }
    }

    /// Evaluates which positions a team needs most (mirrors DraftEngine logic).
    private static func evaluateTeamNeedsForMock(roster: [Player]) -> [Position: Double] {
        let idealCounts: [Position: Int] = [
            .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
            .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
            .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
            .CB: 5, .FS: 2, .SS: 2,
            .K: 1, .P: 1
        ]

        var currentCounts: [Position: Int] = [:]
        for player in roster {
            currentCounts[player.position, default: 0] += 1
        }

        var positionOveralls: [Position: [Int]] = [:]
        for player in roster {
            positionOveralls[player.position, default: []].append(player.overall)
        }

        var needs: [Position: Double] = [:]
        for position in Position.allCases {
            let ideal = idealCounts[position] ?? 1
            let current = currentCounts[position] ?? 0
            let deficit = max(0, ideal - current)

            var multiplier = 1.0 + Double(deficit) * 0.15

            if let overalls = positionOveralls[position], !overalls.isEmpty {
                let avgOverall = Double(overalls.reduce(0, +)) / Double(overalls.count)
                if avgOverall < 60.0 {
                    multiplier += 0.2
                } else if avgOverall < 70.0 {
                    multiplier += 0.1
                }
            } else {
                multiplier += 0.3
            }

            needs[position] = multiplier
        }

        return needs
    }

    // MARK: - Regional College Mapping

    /// Maps scout roles to the colleges in their scouting region.
    private static func colleges(forRegion role: ScoutRole) -> [String] {
        switch role {
        case .regionalScout1: // East — ACC / Big East
            return ["Clemson", "Miami", "Florida State", "Virginia Tech",
                    "Boston College", "Wake Forest", "Duke", "Pittsburgh", "Notre Dame"]
        case .regionalScout2: // West — Pac-12 / Mountain West
            return ["USC", "Oregon", "Washington", "UCLA", "Stanford",
                    "Arizona State", "Colorado", "Utah"]
        case .regionalScout3: // South — SEC / Sun Belt
            return ["Alabama", "Georgia", "LSU", "Florida", "Tennessee",
                    "Auburn", "Ole Miss", "Arkansas", "Kentucky", "Texas A&M"]
        case .regionalScout4: // North — Big Ten / MAC
            return ["Ohio State", "Michigan", "Penn State", "Wisconsin",
                    "Michigan State", "Iowa", "Minnesota", "Illinois"]
        case .regionalScout5: // Central — Big 12 / AAC
            return ["Oklahoma", "Texas", "Baylor", "TCU", "North Carolina"]
        case .chiefScout, .extraScout1, .extraScout2:
            return colleges // Chief Scout and extra scouts can evaluate any prospect
        }
    }

    // MARK: - Weekly Scout Reports (In-Season)

    /// Generate weekly scout reports during regular season.
    /// Each scout evaluates 3-5 prospects per week from their assigned region.
    /// Earlier weeks have more uncertainty; later weeks provide better data.
    static func generateWeeklyReports(
        scouts: [Scout],
        prospects: [CollegeProspect],
        week: Int
    ) -> [ScoutingReport] {
        guard !scouts.isEmpty, !prospects.isEmpty else { return [] }

        var reports: [ScoutingReport] = []

        // R27: consensus board built from public knowledge only (current scouted
        // overalls + media draft projection) — never from hidden true ratings.
        // Used to resolve "Top 50 / Top 150" watch assignments.
        let consensusBoard = prospects.sorted { a, b in
            let aOvr = a.scoutedOverall ?? -1
            let bOvr = b.scoutedOverall ?? -1
            if aOvr != bOvr { return aOvr > bOvr }
            return (a.draftProjection ?? 8) < (b.draftProjection ?? 8)
        }

        for scout in scouts {
            let regionalColleges = colleges(forRegion: scout.scoutRole)
            let regionalProspects = prospects.filter { regionalColleges.contains($0.college) }

            guard !regionalProspects.isEmpty else { continue }

            // R27: narrow the weekly visit pool by the scout's assignments.
            // Watch pool (top-50/top-150 of the consensus board) first, then
            // focus position. Always fall back to the region if a filter
            // would empty the pool.
            var visitPool = regionalProspects
            if let pool = scout.assignmentPool {
                let watchIDs = Set(consensusBoard.prefix(pool.boardSize).map(\.id))
                let watched = visitPool.filter { watchIDs.contains($0.id) }
                if !watched.isEmpty { visitPool = watched }
            }
            if let focusPos = scout.focusPosition {
                let focused = visitPool.filter { $0.position == focusPos }
                if !focused.isEmpty { visitPool = focused }
            }
            let isTargeted = scout.assignmentPool != nil || scout.focusPosition != nil

            // Each scout evaluates 3-5 prospects per week; a targeted scout
            // covers a narrower pool and gets one extra visit in (4-6).
            let evaluationCount = isTargeted ? Int.random(in: 4...6) : Int.random(in: 3...5)
            let shuffled = visitPool.shuffled()
            let toEvaluate = Array(shuffled.prefix(evaluationCount))

            for prospect in toEvaluate {
                // Chief Scout gets +10% accuracy bonus
                let chiefBonus = scout.scoutRole.isChief ? 10 : 0
                // Familiarity bonus: scouts with 2+ seasons in role know their region better
                let familiarityBonus = scout.seasonsInRole >= 2 ? 5 : 0
                var effectiveAccuracy = min(99, scout.accuracy + chiefBonus + familiarityBonus)

                // Position specialization bonus
                if let spec = scout.positionSpecialization, spec == prospect.position {
                    effectiveAccuracy = min(99, effectiveAccuracy + 10)
                }

                // R27: focus assignment bonuses — a scout dialed into a position
                // reads it sharper; a watch-pool assignment means deeper film work.
                if let focusPos = scout.focusPosition, focusPos == prospect.position {
                    effectiveAccuracy = min(99, effectiveAccuracy + 10)
                }
                if scout.assignmentPool != nil {
                    effectiveAccuracy = min(99, effectiveAccuracy + 5)
                }

                // Earlier weeks = more uncertainty, later weeks = better data
                // Week 1: -15 accuracy, Week 18: +5 accuracy (linear ramp)
                let weekModifier = Int(Double(week - 1) / 17.0 * 20.0) - 15
                effectiveAccuracy = min(99, max(10, effectiveAccuracy + weekModifier))

                // Base confidence is collegeSeason level (0.4), improved by week progression
                let weekConfidenceBoost = Double(week) / 18.0 * 0.15
                let baseConfidence = 0.4 + weekConfidenceBoost
                let experienceBonus = min(0.1, Double(scout.experience) * 0.01)
                let confidence = min(0.7, baseConfidence + experienceBonus)

                // Calculate scouted overall with error margin
                let maxError = max(1, 30 - (effectiveAccuracy * 30 / 100))
                let overallError = Int.random(in: -maxError...maxError)
                let scoutedOvr = min(99, max(1, prospect.trueOverall + overallError))

                // Calculate scouted potential
                let potentialMaxError = max(1, 30 - (scout.potentialRead * 30 / 100))
                let potentialError = Int.random(in: -potentialMaxError...potentialMaxError)
                let scoutedPot = min(99, max(1, prospect.truePotential + potentialError))

                // Generate college production notes
                let productionNotes = generateProductionNotes(for: prospect, week: week)

                let strengthNotes = generateStrengthNotes(for: prospect, accuracy: effectiveAccuracy)
                let weaknessNotes = generateWeaknessNotes(for: prospect, accuracy: effectiveAccuracy)
                let personalityNotes = generatePersonalityNotes(for: prospect, scout: scout)

                let report = ScoutingReport(
                    prospectID: prospect.id,
                    scoutID: scout.id,
                    scoutName: scout.fullName,
                    date: "Week \(week)",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: scoutedPot,
                    strengthNotes: strengthNotes,
                    weaknessNotes: weaknessNotes,
                    personalityNotes: personalityNotes,
                    confidenceLevel: confidence,
                    productionNotes: productionNotes
                )
                reports.append(report)
            }
        }

        return reports
    }

    /// Apply weekly scout reports: append to prospect's report list and update scouted values
    /// using the best (highest confidence) report available.
    static func applyWeeklyReports(_ reports: [ScoutingReport], to prospects: inout [CollegeProspect]) {
        let reportsByProspect = Dictionary(grouping: reports, by: { $0.prospectID })

        for i in prospects.indices {
            guard let newReports = reportsByProspect[prospects[i].id] else { continue }

            // Append reports
            prospects[i].scoutingReports.append(contentsOf: newReports)

            // Find the best report (highest confidence) across ALL reports for this prospect
            guard let bestReport = prospects[i].scoutingReports.max(by: {
                $0.confidenceLevel < $1.confidenceLevel
            }) else { continue }

            // Update scouted values from the best report
            prospects[i].scoutedOverall = bestReport.overallGrade
            prospects[i].scoutedPotential = bestReport.potentialGrade

            // Set scout grade based on best scouted overall
            let ovr = bestReport.overallGrade
            switch ovr {
            case 90...99: prospects[i].scoutGrade = "A+"
            case 85...89: prospects[i].scoutGrade = "A"
            case 80...84: prospects[i].scoutGrade = "A-"
            case 75...79: prospects[i].scoutGrade = "B+"
            case 70...74: prospects[i].scoutGrade = "B"
            case 65...69: prospects[i].scoutGrade = "B-"
            case 60...64: prospects[i].scoutGrade = "C+"
            case 55...59: prospects[i].scoutGrade = "C"
            case 50...54: prospects[i].scoutGrade = "C-"
            case 45...49: prospects[i].scoutGrade = "D+"
            case 40...44: prospects[i].scoutGrade = "D"
            default:      prospects[i].scoutGrade = "F"
            }
        }
    }

    /// Generate college production notes based on position and week progression.
    private static func generateProductionNotes(for prospect: CollegeProspect, week: Int) -> String {
        let gamesPlayed = min(week, 12) // College season ~12 games
        let overall = prospect.trueOverall

        switch prospect.position {
        case .QB:
            let tdsPerGame = Double(overall) / 30.0
            let totalTDs = Int(tdsPerGame * Double(gamesPlayed))
            let totalINTs = Int(Double(gamesPlayed) * (1.0 - Double(overall) / 120.0))
            let yards = Int(Double(gamesPlayed) * Double(overall) * 2.8)
            return "\(totalTDs) TDs, \(totalINTs) INTs, \(yards) yards in \(gamesPlayed) games"
        case .RB, .FB:
            let yardsPerGame = Double(overall) * 0.9
            let totalYards = Int(yardsPerGame * Double(gamesPlayed))
            let tds = Int(Double(overall) / 12.0 * Double(gamesPlayed) / 4.0)
            return "\(totalYards) rushing yards, \(tds) TDs in \(gamesPlayed) games"
        case .WR, .TE:
            let recPerGame = Double(overall) / 18.0
            let totalRec = Int(recPerGame * Double(gamesPlayed))
            let totalYards = Int(Double(totalRec) * Double(overall) / 7.0)
            let tds = Int(Double(overall) / 15.0 * Double(gamesPlayed) / 5.0)
            return "\(totalRec) receptions, \(totalYards) yards, \(tds) TDs in \(gamesPlayed) games"
        case .DE, .DT:
            let sacks = Double(overall) / 20.0 * Double(gamesPlayed) / 5.0
            let tfls = sacks * 1.5
            return String(format: "%.1f sacks, %.0f TFLs in %d games", sacks, tfls, gamesPlayed)
        case .OLB, .MLB:
            let tacklesPerGame = Double(overall) / 12.0
            let totalTackles = Int(tacklesPerGame * Double(gamesPlayed))
            return "\(totalTackles) tackles in \(gamesPlayed) games"
        case .CB, .FS, .SS:
            let ints = Int(Double(overall) / 25.0 * Double(gamesPlayed) / 6.0)
            let pds = ints * 3 + Int.random(in: 1...4)
            return "\(ints) INTs, \(pds) pass deflections in \(gamesPlayed) games"
        case .LT, .LG, .C, .RG, .RT:
            let sacked = overall >= 70 ? "zero sacks allowed" : "\(Int.random(in: 1...3)) sacks allowed"
            return "Started all \(gamesPlayed) games, \(sacked)"
        case .K:
            let attempts = Int(Double(gamesPlayed) * 2.5)
            let made = Int(Double(attempts) * Double(overall) / 110.0)
            return "\(made)/\(attempts) FG in \(gamesPlayed) games"
        case .P:
            let avgYards = 38.0 + Double(overall) / 10.0
            return String(format: "%.1f avg punt yards in %d games", avgYards, gamesPlayed)
        }
    }

    // MARK: - Declaration Period

    /// Simulates the draft declaration period: ~70 underclassmen declare, ~5-10 withdraw,
    /// all seniors auto-declare. Returns news items for top declarations and withdrawals.
    static func generateDeclarations(
        prospects: inout [CollegeProspect]
    ) -> [(name: String, isDeclaration: Bool, headline: String)] {
        var newsItems: [(name: String, isDeclaration: Bool, headline: String)] = []

        // Separate seniors (age 22+) and underclassmen (age < 22)
        let seniorAge = 22

        // 1. All seniors auto-declare
        for i in prospects.indices where prospects[i].age >= seniorAge {
            prospects[i].isDeclaringForDraft = true
        }

        // 2. Underclassmen: ~70 declare based on talent (higher overall = more likely)
        var underclassmenIndices = prospects.indices.filter { prospects[$0].age < seniorAge }
        underclassmenIndices.sort { prospects[$0].trueOverall > prospects[$1].trueOverall }

        var declarationCount = 0
        let targetDeclarations = Int.random(in: 65...75)

        for i in underclassmenIndices {
            guard declarationCount < targetDeclarations else { break }

            // Higher-rated underclassmen are more likely to declare
            let declareChance: Int
            let overall = prospects[i].trueOverall
            if overall >= 80 { declareChance = 95 }
            else if overall >= 70 { declareChance = 75 }
            else if overall >= 60 { declareChance = 40 }
            else { declareChance = 15 }

            if Int.random(in: 1...100) <= declareChance {
                prospects[i].isDeclaringForDraft = true
                declarationCount += 1

                // Track top declarations for news
                if newsItems.filter({ $0.isDeclaration }).count < 5 {
                    let pos = prospects[i].position.rawValue
                    newsItems.append((
                        name: prospects[i].fullName,
                        isDeclaration: true,
                        headline: "\(prospects[i].college) \(pos) \(prospects[i].fullName) declares for draft"
                    ))
                }
            } else {
                prospects[i].isDeclaringForDraft = false
            }
        }

        // 3. Withdrawals: ~5-10 declared underclassmen change their mind
        let withdrawalCount = Int.random(in: 5...10)
        let declaredUnderclassmen = prospects.indices.filter {
            prospects[$0].age < seniorAge && prospects[$0].isDeclaringForDraft && prospects[$0].trueOverall < 75
        }.shuffled()

        for i in declaredUnderclassmen.prefix(withdrawalCount) {
            prospects[i].isDeclaringForDraft = false
            let pos = prospects[i].position.rawValue
            newsItems.append((
                name: prospects[i].fullName,
                isDeclaration: false,
                headline: "Top \(pos) \(prospects[i].fullName) returns to \(prospects[i].college) for senior year"
            ))
        }

        return newsItems
    }

    // MARK: - UDFA Pool

    /// Returns undrafted prospects sorted by trueOverall (best first) for UDFA signing.
    static func getUDFAPool(prospects: [CollegeProspect]) -> [CollegeProspect] {
        return prospects
            .filter { $0.isDeclaringForDraft && $0.mockDraftPickNumber == nil }
            .sorted { $0.trueOverall > $1.trueOverall }
    }

    // MARK: - Pre-Scouted Data (First Season)

    /// Generate pre-scouted data for first season (simulates previous GM's scouting work).
    /// Top 50 prospects get advanced scouting, next 100 basic, next 100 minimal, rest unknown.
    static func applyPreScoutedData(prospects: inout [CollegeProspect]) {
        // Sort by true overall to determine tiers
        let sortedIndices = prospects.indices.sorted {
            prospects[$0].trueOverall > prospects[$1].trueOverall
        }

        for (rank, idx) in sortedIndices.enumerated() {
            if rank < 50 {
                // Advanced scouting: within +-5 of true, accurate grade, personality/potential
                let error = Int.random(in: -5...5)
                let scoutedOvr = min(99, max(1, prospects[idx].trueOverall + error))
                prospects[idx].scoutedOverall = scoutedOvr

                // Accurate scout grade
                switch scoutedOvr {
                case 90...99: prospects[idx].scoutGrade = "A+"
                case 85...89: prospects[idx].scoutGrade = "A"
                case 80...84: prospects[idx].scoutGrade = "A-"
                case 75...79: prospects[idx].scoutGrade = "B+"
                case 70...74: prospects[idx].scoutGrade = "B"
                case 65...69: prospects[idx].scoutGrade = "B-"
                case 60...64: prospects[idx].scoutGrade = "C+"
                case 55...59: prospects[idx].scoutGrade = "C"
                case 50...54: prospects[idx].scoutGrade = "C-"
                case 45...49: prospects[idx].scoutGrade = "D+"
                case 40...44: prospects[idx].scoutGrade = "D"
                default:      prospects[idx].scoutGrade = "F"
                }

                // Potential revealed with moderate accuracy (within +-8)
                let potError = Int.random(in: -8...8)
                prospects[idx].scoutedPotential = min(99, max(1,
                    prospects[idx].truePotential + potError))

                // Personality revealed (80% accurate)
                if Int.random(in: 1...100) <= 80 {
                    prospects[idx].scoutedPersonality = prospects[idx].truePersonality.archetype
                } else {
                    let wrong = PersonalityArchetype.allCases.filter {
                        $0 != prospects[idx].truePersonality.archetype
                    }
                    prospects[idx].scoutedPersonality = wrong.randomElement()
                }

                // Generate a pre-scout report
                let report = ScoutingReport(
                    prospectID: prospects[idx].id,
                    scoutID: UUID(),
                    scoutName: "Previous Staff",
                    date: "Pre-Season",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: prospects[idx].scoutedPotential ?? scoutedOvr,
                    strengthNotes: "Thorough evaluation from previous scouting department.",
                    weaknessNotes: "Full report on file.",
                    personalityNotes: prospects[idx].scoutedPersonality != nil
                        ? "Personality assessment included." : nil,
                    confidenceLevel: 0.65,
                    productionNotes: generateProductionNotes(for: prospects[idx], week: 12)
                )
                prospects[idx].scoutingReports.append(report)

            } else if rank < 150 {
                // Basic scouting: within +-10 of true, grade set (possibly inaccurate)
                let error = Int.random(in: -10...10)
                let scoutedOvr = min(99, max(1, prospects[idx].trueOverall + error))
                prospects[idx].scoutedOverall = scoutedOvr

                switch scoutedOvr {
                case 90...99: prospects[idx].scoutGrade = "A+"
                case 85...89: prospects[idx].scoutGrade = "A"
                case 80...84: prospects[idx].scoutGrade = "A-"
                case 75...79: prospects[idx].scoutGrade = "B+"
                case 70...74: prospects[idx].scoutGrade = "B"
                case 65...69: prospects[idx].scoutGrade = "B-"
                case 60...64: prospects[idx].scoutGrade = "C+"
                case 55...59: prospects[idx].scoutGrade = "C"
                case 50...54: prospects[idx].scoutGrade = "C-"
                case 45...49: prospects[idx].scoutGrade = "D+"
                case 40...44: prospects[idx].scoutGrade = "D"
                default:      prospects[idx].scoutGrade = "F"
                }

                let report = ScoutingReport(
                    prospectID: prospects[idx].id,
                    scoutID: UUID(),
                    scoutName: "Previous Staff",
                    date: "Pre-Season",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: scoutedOvr,
                    strengthNotes: "Basic evaluation on file.",
                    weaknessNotes: "Limited tape review.",
                    personalityNotes: nil,
                    confidenceLevel: 0.45,
                    productionNotes: generateProductionNotes(for: prospects[idx], week: 8)
                )
                prospects[idx].scoutingReports.append(report)

            } else if rank < 250 {
                // Minimal scouting: within +-15 of true, only general info
                let error = Int.random(in: -15...15)
                let scoutedOvr = min(99, max(1, prospects[idx].trueOverall + error))
                prospects[idx].scoutedOverall = scoutedOvr

                let report = ScoutingReport(
                    prospectID: prospects[idx].id,
                    scoutID: UUID(),
                    scoutName: "Previous Staff",
                    date: "Pre-Season",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: scoutedOvr,
                    strengthNotes: "Name on the board. Minimal evaluation.",
                    weaknessNotes: "Needs further evaluation.",
                    personalityNotes: nil,
                    confidenceLevel: 0.25
                )
                prospects[idx].scoutingReports.append(report)
            }
            // Remaining prospects (rank >= 250): no scouted data
        }
    }

    // MARK: - Next Year's Draft Class Preview

    /// A lightweight preview prospect for next year's draft class.
    /// No detailed attributes -- just name, position, college, and a rough projected grade.
    struct NextYearProspect: Identifiable {
        let id = UUID()
        let firstName: String
        let lastName: String
        let position: Position
        let college: String
        let classYear: String        // "Junior" or "Sophomore"
        let projectedGrade: String   // "Top 10 Pick", "1st Round", "Day 2"

        var fullName: String { "\(firstName) \(lastName)" }
    }

    /// Generates top ~25 prospects for NEXT year's draft class.
    ///
    /// These are early buzz projections with only surface-level info:
    /// name, position, college, class year, and a rough projected grade.
    /// Full scouting begins next season.
    ///
    /// - Parameter count: Number of preview prospects to generate (default 25).
    /// - Returns: An array of `NextYearProspect` sorted by projected grade.
    static func generateNextYearPreview(count: Int = 25) -> [NextYearProspect] {
        var prospects: [NextYearProspect] = []

        // Position distribution for the preview (heavy on premium positions)
        let previewPositions: [Position] = [
            .QB, .QB, .QB,
            .WR, .WR, .WR,
            .DE, .DE,
            .CB, .CB,
            .OLB, .OLB,
            .LT, .LT,
            .RB, .RB,
            .TE,
            .DT, .DT,
            .MLB,
            .FS, .SS,
            .WR, .RG, .C
        ]

        let gradeDistribution: [String] = [
            "Top 10 Pick", "Top 10 Pick", "Top 10 Pick",
            "1st Round", "1st Round", "1st Round", "1st Round", "1st Round",
            "1st Round", "1st Round",
            "Day 2", "Day 2", "Day 2", "Day 2", "Day 2",
            "Day 2", "Day 2", "Day 2", "Day 2", "Day 2",
            "Day 2", "Day 2", "Day 2", "Day 2", "Day 2"
        ]

        for i in 0..<min(count, previewPositions.count) {
            let name = RandomNameGenerator.randomName()
            let college = colleges.randomElement()!
            let classYear = i < 8 ? "Junior" : (Bool.random() ? "Junior" : "Sophomore")
            let grade = i < gradeDistribution.count ? gradeDistribution[i] : "Day 2"

            prospects.append(NextYearProspect(
                firstName: name.first,
                lastName: name.last,
                position: previewPositions[i],
                college: college,
                classYear: classYear,
                projectedGrade: grade
            ))
        }

        return prospects
    }

    // MARK: - Combine Media Summary (#259)

    struct CombineMediaMention {
        let prospectID: UUID
        let prospectName: String
        let position: String
        let headline: String
        let category: String  // "Standout", "Stock Riser", "Stock Faller", "Surprise"
    }

    /// Generates combine media coverage and stamps `combineMediaMention` on highlighted prospects.
    static func generateCombineMedia(prospects: inout [CollegeProspect]) -> [CombineMediaMention] {
        var mentions: [CombineMediaMention] = []

        let invited = prospects.filter { $0.combineInvite && $0.fortyTime != nil }
        guard !invited.isEmpty else { return mentions }

        // --- Standouts: prospects with any elite drill result (top 5% for position) ---
        // Limited to 1-3 per position to prevent unrealistic clustering (e.g. 5 QBs)
        let standoutCandidates = invited.filter { p in
            let bm = CombineBenchmarks.benchmarks(for: p.position)
            return isElite(p.fortyTime, benchmark: bm.fortyYard)
                || isElite(Double(p.benchPress ?? 0), benchmark: bm.benchPress)
                || isElite(p.verticalJump, benchmark: bm.verticalJump)
                || isElite(Double(p.broadJump ?? 0), benchmark: bm.broadJump)
                || isElite(p.coneDrill, benchmark: bm.threeCone)
                || isElite(p.shuttleTime, benchmark: bm.shuttle)
        }
        .sorted { ($0.trueOverall) > ($1.trueOverall) }

        // Limit to 1-3 standouts per position to ensure diversity
        var standoutPositionCount: [Position: Int] = [:]
        var selectedStandouts: [CollegeProspect] = []
        for p in standoutCandidates {
            let posCount = standoutPositionCount[p.position, default: 0]
            let maxPerPosition = Int.random(in: 1...2) // 1-2 per position
            if posCount < maxPerPosition {
                selectedStandouts.append(p)
                standoutPositionCount[p.position, default: 0] += 1
            }
            if selectedStandouts.count >= Int.random(in: 4...7) { break }
        }

        for p in selectedStandouts {
            let headline = standoutHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Standout"
            ))
        }

        let standoutIDs = Set(mentions.map { $0.prospectID })

        // --- Stock Risers: combine improved grade vs pre-combine projection ---
        let riserCandidates = invited.filter { p in
            guard !standoutIDs.contains(p.id) else { return false }
            guard let proj = p.draftProjection else { return false }
            // Lower projection number = better. If true overall suggests higher pick
            // than projection, they rose.
            let combineGrade = combineAveragePercentile(p)
            return combineGrade >= 70 && proj >= 3  // Decent combine but was projected late
        }
        .sorted { combineAveragePercentile($0) > combineAveragePercentile($1) }

        let riserIDs = Set(riserCandidates.prefix(Int.random(in: 3...5)).map { $0.id })
        for p in riserCandidates.prefix(Int.random(in: 3...5)) {
            let headline = riserHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Stock Riser"
            ))
        }

        // --- Stock Fallers: high OVR but poor combine (slow 40, low bench) ---
        let fallerCandidates = invited.filter { p in
            guard !standoutIDs.contains(p.id), !riserIDs.contains(p.id) else { return false }
            let combineGrade = combineAveragePercentile(p)
            return p.trueOverall >= 70 && combineGrade < 40
        }
        .sorted { $0.trueOverall > $1.trueOverall }

        let fallerIDs = Set(fallerCandidates.prefix(Int.random(in: 2...3)).map { $0.id })
        for p in fallerCandidates.prefix(Int.random(in: 2...3)) {
            let headline = fallerHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Stock Faller"
            ))
        }

        // --- Surprises: low-projected prospects with elite combine numbers ---
        let surpriseCandidates = invited.filter { p in
            guard !standoutIDs.contains(p.id), !riserIDs.contains(p.id),
                  !fallerIDs.contains(p.id) else { return false }
            guard let proj = p.draftProjection else { return false }
            let combineGrade = combineAveragePercentile(p)
            return proj >= 5 && combineGrade >= 75
        }
        .sorted { combineAveragePercentile($0) > combineAveragePercentile($1) }

        for p in surpriseCandidates.prefix(Int.random(in: 2...3)) {
            let headline = surpriseHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Surprise"
            ))
        }

        // Stamp combineMediaMention on prospects (prefixed with category for color coding)
        let mentionMap = Dictionary(
            mentions.map { ($0.prospectID, "[\($0.category)] \($0.headline)") },
            uniquingKeysWith: { a, _ in a }
        )
        for i in prospects.indices {
            if let taggedHeadline = mentionMap[prospects[i].id] {
                prospects[i].combineMediaMention = taggedHeadline
            }
        }

        return mentions
    }

    // MARK: - Combine Media Helpers

    private static func isElite(_ value: Double?, benchmark: CombineBenchmarks.DrillBenchmark) -> Bool {
        guard let value else { return false }
        if benchmark.lowerIsBetter {
            // Top 5% = within 5% of elite threshold toward lower
            return value <= benchmark.elite * 1.02
        } else {
            return value >= benchmark.elite * 0.98
        }
    }

    private static func combineAveragePercentile(_ p: CollegeProspect) -> Int {
        let bm = CombineBenchmarks.benchmarks(for: p.position)
        var pcts: [Int] = []
        if let v = p.fortyTime { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.fortyYard)) }
        if let v = p.benchPress { pcts.append(CombineBenchmarks.percentile(value: Double(v), benchmark: bm.benchPress)) }
        if let v = p.verticalJump { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.verticalJump)) }
        if let v = p.broadJump { pcts.append(CombineBenchmarks.percentile(value: Double(v), benchmark: bm.broadJump)) }
        if let v = p.coneDrill { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.threeCone)) }
        if let v = p.shuttleTime { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.shuttle)) }
        guard !pcts.isEmpty else { return 50 }
        return pcts.reduce(0, +) / pcts.count
    }

    private static func standoutHeadline(for p: CollegeProspect) -> String {
        if let ft = p.fortyTime, ft < 4.40 {
            return "\(p.fullName) blazes \(String(format: "%.2f", ft)) 40-yard dash — first round stock!"
        }
        if let bp = p.benchPress, bp >= 35 {
            return "\(p.fullName) powers through \(bp) bench reps, dominates strength testing"
        }
        if let vj = p.verticalJump, vj >= 40.0 {
            return "\(p.fullName) soars with \(String(format: "%.1f", vj))\" vertical, elite athleticism on display"
        }
        return "\(p.fullName) posts elite combine numbers across the board"
    }

    private static func riserHeadline(for p: CollegeProspect) -> String {
        if let ft = p.fortyTime {
            return "\(p.fullName) surprises with \(String(format: "%.2f", ft)) 40, vaults up draft boards"
        }
        return "\(p.fullName) impresses at combine, stock soaring"
    }

    private static func fallerHeadline(for p: CollegeProspect) -> String {
        if let ft = p.fortyTime, ft > 4.70 {
            return "\(p.fullName) disappoints with \(String(format: "%.2f", ft)) 40-time, stock drops"
        }
        return "\(p.fullName) underwhelms at combine, raising red flags for scouts"
    }

    private static func surpriseHeadline(for p: CollegeProspect) -> String {
        if let ft = p.fortyTime, ft < 4.50 {
            return "Unknown \(p.position.rawValue) \(p.fullName) runs \(String(format: "%.2f", ft)) 40, turns heads at combine"
        }
        return "Late-round prospect \(p.fullName) steals the show with elite testing"
    }

    // MARK: - Risk Profile (Medical & Character)

    /// Generates a medical / character risk profile for a prospect.
    /// Distribution (heuristic):
    ///   - 80% clean (no flags)
    ///   - 14% one medical flag
    ///   - 4%  one red (off-field/character) flag
    ///   - 2%  both medical AND red flag
    /// Modifies `medicalConcerns` and `redFlags` on the prospect.
    static func generateRiskProfile(for prospect: inout CollegeProspect) {
        let medicalPool = [
            "ACL repair 2024",
            "Past concussion history",
            "Chronic shoulder",
            "Knee soreness flagged",
            "Lower back tightness",
            "Prior hamstring strain",
            "Previous foot fracture",
            "Hip flexor history"
        ]
        let redFlagPool = [
            "Off-field arrest",
            "Failed drug test",
            "Practice habits questioned",
            "Locker-room concerns",
            "Missed team meetings",
            "Coach clashed with player",
            "Social media incident"
        ]

        let roll = Int.random(in: 1...100)
        switch roll {
        case 1...80:
            // Clean — leave nil
            prospect.medicalConcerns = nil
            prospect.redFlags = nil
        case 81...94:
            // One medical flag
            prospect.medicalConcerns = [medicalPool.randomElement()!]
            prospect.redFlags = nil
        case 95...98:
            // One red flag
            prospect.medicalConcerns = nil
            prospect.redFlags = [redFlagPool.randomElement()!]
        default:
            // Both
            prospect.medicalConcerns = [medicalPool.randomElement()!]
            prospect.redFlags = [redFlagPool.randomElement()!]
        }
    }

    // MARK: - Top-30 Visit System

    /// Result of a Top-30 visit, returned for caller to surface in UI.
    /// The visit itself mutates the prospect (sets `interviewCompleted`, appends visiting team,
    /// fills `medicalConcerns` etc.). The struct is returned so callers can show a summary.
    struct Top30VisitResult {
        /// 2-3 character / leadership notes from a deep interview.
        let interviewNotes: [String]
        /// Football IQ revealed in the interview, 40..99.
        let footballIQRevised: Int
        /// 0-2 medical concerns surfaced during the medical exam.
        let medicalConcerns: [String]
        /// 1-2 workout impressions tailored to the visiting team's needs.
        let workoutImpressions: [String]
        /// Team-fit score (0..1) versus visiting team's roster context.
        let teamFitScore: Double
    }

    /// Conducts a Top-30 visit which combines (a) a deep interview,
    /// (b) a focused workout for the visiting team's needs,
    /// (c) a medical check.
    /// Mutates the prospect:
    ///   - sets `interviewCompleted = true`
    ///   - appends `visitingTeamID` to `top30VisitedByTeams` (idempotent)
    ///   - merges generated medical concerns into `medicalConcerns`
    ///   - revises `interviewFootballIQ` and persists character notes
    /// Returns enriched results that the caller can surface in UI / persist further.
    static func conductTop30Visit(
        prospect: inout CollegeProspect,
        visitingTeamID: UUID,
        interviewerQuality: Int
    ) -> Top30VisitResult {
        // 1. Mark as visited by this team (idempotent).
        if !prospect.top30VisitedByTeams.contains(visitingTeamID) {
            prospect.top30VisitedByTeams.append(visitingTeamID)
        }

        // 2. Deep interview — reuse the existing interview engine.
        let interview = conductInterview(prospect: prospect, interviewerQuality: interviewerQuality)
        // conductInterview already mutates interviewCompleted, scoutedPersonality,
        // interviewFootballIQ, interviewCharacterNotes, interviewNotes. We pass
        // a copy via the non-inout overload, then re-apply onto the inout binding.
        prospect.interviewCompleted = true
        prospect.scoutedPersonality = interview.personality
        prospect.interviewFootballIQ = interview.footballIQ
        prospect.interviewCharacterNotes = interview.characterNotes

        // 3. Medical check — 25% chance per visit to surface a concern.
        var newMedicalConcerns: [String] = []
        if Int.random(in: 1...100) <= 25 {
            let medicalPool = [
                "Knee soreness flagged",
                "Past concussion history",
                "Shoulder labrum noted",
                "Lingering ankle issue",
                "Back stiffness on exam",
                "Hip mobility limited"
            ]
            newMedicalConcerns.append(medicalPool.randomElement()!)
            // Small chance of a second concern.
            if Int.random(in: 1...100) <= 25 {
                let second = medicalPool.randomElement()!
                if !newMedicalConcerns.contains(second) {
                    newMedicalConcerns.append(second)
                }
            }

            // Merge into prospect
            var existing = prospect.medicalConcerns ?? []
            for c in newMedicalConcerns where !existing.contains(c) {
                existing.append(c)
            }
            prospect.medicalConcerns = existing.isEmpty ? nil : existing
        }

        // 4. Workout impressions — position-specific.
        let workoutImpressions = generateWorkoutImpressions(for: prospect.position, prospect: prospect)

        // 5. Team-fit score — heuristic combining trueOverall, position value, and personality fit.
        // Without a roster handle here, we approximate fit using the prospect's traits
        // and let UI/coordinator refine with team-context if needed.
        let baseFit = Double(prospect.trueOverall) / 99.0
        let posValue = positionalDraftValue(for: prospect.position)
        let personalityBonus: Double
        switch prospect.truePersonality.archetype {
        case .teamLeader, .quietProfessional, .mentor: personalityBonus = 0.10
        case .steadyPerformer:                          personalityBonus = 0.05
        case .dramaQueen, .feelPlayer:                  personalityBonus = -0.10
        case .classClown:                               personalityBonus = -0.03
        default:                                        personalityBonus = 0.0
        }
        let rawFit = baseFit * 0.6 + posValue * 0.3 + personalityBonus
        let teamFit = Swift.min(1.0, Swift.max(0.0, rawFit + Double.random(in: -0.05...0.05)))

        return Top30VisitResult(
            interviewNotes: interview.characterNotes,
            footballIQRevised: interview.footballIQ,
            medicalConcerns: newMedicalConcerns,
            workoutImpressions: workoutImpressions,
            teamFitScore: teamFit
        )
    }

    /// Generates 1-2 position-specific workout impressions for a Top-30 visit.
    private static func generateWorkoutImpressions(for position: Position, prospect: CollegeProspect) -> [String] {
        let positives: [String]
        let negatives: [String]
        switch position {
        case .QB:
            positives = ["Crisp ball placement", "Quick processing on whiteboard", "Clean throwing motion", "Velocity on intermediate routes"]
            negatives = ["Mechanics break down under pressure", "Slow second-read progression", "Footwork inconsistent"]
        case .WR:
            positives = ["Smooth route running", "Strong hands at the catch", "Crisp releases off press", "Adjusts well to off-target throws"]
            negatives = ["Drops at the catch point", "Lacks burst out of breaks", "Limited release package"]
        case .RB, .FB:
            positives = ["Patient runner with vision", "Strong contact balance", "Soft hands out of backfield"]
            negatives = ["Lacks burst through hole", "Pass protection needs work", "Limited route tree"]
        case .TE:
            positives = ["Reliable hands in traffic", "Functional in-line blocking", "Adjusts to ball in air"]
            negatives = ["Stiff in space", "Loses leverage as a blocker"]
        case .LT, .RT, .LG, .RG, .C:
            positives = ["Anchors well in pass pro", "Quick out of stance", "Plays with leverage"]
            negatives = ["Late hands in pass pro", "Struggles with second-level blocks", "Over-extends and lunges"]
        case .DE, .DT:
            positives = ["Active hands at point of attack", "Quick first step", "Diverse pass-rush plan"]
            negatives = ["Limited counter moves", "Plays high off the snap", "Loses gap integrity"]
        case .OLB, .MLB:
            positives = ["Reads keys quickly", "Smooth in coverage drops", "Sheds blocks well"]
            negatives = ["Late to trigger downhill", "Stiff hips in coverage"]
        case .CB:
            positives = ["Fluid hips in transition", "Sticky in press coverage", "Good ball skills at catch point"]
            negatives = ["Grabby downfield", "Bites on double moves", "Tackling inconsistent"]
        case .FS, .SS:
            positives = ["Range to the deep middle", "Aggressive downhill trigger", "Tackles in space"]
            negatives = ["Takes poor angles", "Coverage discipline lapses"]
        case .K, .P:
            positives = ["Consistent ball flight", "Good leg under pressure"]
            negatives = ["Inconsistent operation time", "Leg speed average"]
        }

        // Bias the impressions toward the prospect's true ability so high-overall prospects
        // skew positive, low-overall ones skew negative.
        let posValue = prospect.truePositionAttributes.overall
        let positiveWeight: Int
        if posValue >= 80 { positiveWeight = 80 }
        else if posValue >= 70 { positiveWeight = 60 }
        else if posValue >= 60 { positiveWeight = 45 }
        else { positiveWeight = 30 }

        var result: [String] = []
        let count = Int.random(in: 1...2)
        for _ in 0..<count {
            let pool = (Int.random(in: 1...100) <= positiveWeight) ? positives : negatives
            if let pick = pool.randomElement(), !result.contains(pick) {
                result.append(pick)
            }
        }
        if result.isEmpty, let p = positives.randomElement() {
            result.append(p)
        }
        return result
    }
}

// MARK: - Combine Benchmarks

struct CombineBenchmarks {
    struct DrillBenchmark {
        let elite: Double
        let average: Double
        let poor: Double
        let lowerIsBetter: Bool  // true for timed drills
    }

    struct PositionBenchmarks {
        let fortyYard: DrillBenchmark
        let benchPress: DrillBenchmark
        let verticalJump: DrillBenchmark
        let broadJump: DrillBenchmark
        let threeCone: DrillBenchmark
        let shuttle: DrillBenchmark
    }

    // All-time records
    static let records = (
        fortyYard: (value: 4.21, name: "Xavier Worthy", year: 2024),
        benchPress: (value: 49, name: "Stephen Paea", year: 2011),
        verticalJump: (value: 46.0, name: "Gerald Sensabaugh", year: 2005),
        broadJump: (value: 147, name: "Byron Jones", year: 2015),
        threeCone: (value: 6.28, name: "Jordan Thomas", year: 2018),
        shuttle: (value: 3.75, name: "Dunta Robinson", year: 2004)
    )

    static func benchmarks(for position: Position) -> PositionBenchmarks {
        switch position {
        case .QB:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.35, average: 4.87, poor: 5.20, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 26, average: 18, poor: 10, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 40.5, average: 32.0, poor: 26.0, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 129, average: 111, poor: 98, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.55, average: 7.15, poor: 7.55, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 3.98, average: 4.45, poor: 4.80, lowerIsBetter: true)
            )
        case .RB, .FB:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.24, average: 4.53, poor: 4.72, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 36, average: 20, poor: 12, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 43, average: 35, poor: 29, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 135, average: 121, poor: 110, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.50, average: 6.95, poor: 7.30, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 3.93, average: 4.25, poor: 4.50, lowerIsBetter: true)
            )
        case .WR:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.21, average: 4.48, poor: 4.65, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 27, average: 15, poor: 8, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 45, average: 36, poor: 30, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 132, average: 120, poor: 110, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.42, average: 6.85, poor: 7.15, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 3.81, average: 4.30, poor: 4.55, lowerIsBetter: true)
            )
        case .TE:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.40, average: 4.70, poor: 4.92, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 35, average: 21, poor: 14, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 43.5, average: 33, poor: 27, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 134, average: 116, poor: 106, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.73, average: 7.15, poor: 7.50, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 4.01, average: 4.40, poor: 4.65, lowerIsBetter: true)
            )
        case .LT, .LG, .C, .RG, .RT:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.71, average: 5.26, poor: 5.55, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 45, average: 26, poor: 18, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 38.5, average: 28, poor: 22, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 121, average: 104, poor: 94, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 7.06, average: 7.80, poor: 8.30, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 4.14, average: 4.65, poor: 5.10, lowerIsBetter: true)
            )
        case .DE:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.36, average: 4.80, poor: 5.05, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 38, average: 23, poor: 16, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 41.5, average: 33, poor: 27, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 134, average: 117, poor: 106, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.70, average: 7.25, poor: 7.60, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 4.00, average: 4.40, poor: 4.65, lowerIsBetter: true)
            )
        case .DT:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.49, average: 5.06, poor: 5.35, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 49, average: 29, poor: 21, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 37.5, average: 29.5, poor: 24, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 125, average: 107, poor: 96, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 7.07, average: 7.55, poor: 7.95, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 4.21, average: 4.65, poor: 4.95, lowerIsBetter: true)
            )
        case .OLB, .MLB:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.38, average: 4.68, poor: 4.90, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 41, average: 22, poor: 14, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 42.5, average: 34, poor: 28, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 138, average: 120, poor: 108, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.45, average: 7.10, poor: 7.50, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 3.96, average: 4.25, poor: 4.55, lowerIsBetter: true)
            )
        case .CB:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.23, average: 4.48, poor: 4.62, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 27, average: 15, poor: 8, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 45, average: 36.5, poor: 30, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 147, average: 126, poor: 114, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.48, average: 6.90, poor: 7.20, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 3.81, average: 4.20, poor: 4.45, lowerIsBetter: true)
            )
        case .FS, .SS:
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.29, average: 4.54, poor: 4.72, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 32, average: 17, poor: 10, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 44, average: 36, poor: 30, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 146, average: 122, poor: 110, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.56, average: 6.90, poor: 7.20, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 3.90, average: 4.25, poor: 4.50, lowerIsBetter: true)
            )
        case .K, .P:
            // Use safety benchmarks as fallback
            return PositionBenchmarks(
                fortyYard: DrillBenchmark(elite: 4.29, average: 4.54, poor: 4.72, lowerIsBetter: true),
                benchPress: DrillBenchmark(elite: 32, average: 17, poor: 10, lowerIsBetter: false),
                verticalJump: DrillBenchmark(elite: 44, average: 36, poor: 30, lowerIsBetter: false),
                broadJump: DrillBenchmark(elite: 146, average: 122, poor: 110, lowerIsBetter: false),
                threeCone: DrillBenchmark(elite: 6.56, average: 6.90, poor: 7.20, lowerIsBetter: true),
                shuttle: DrillBenchmark(elite: 3.90, average: 4.25, poor: 4.50, lowerIsBetter: true)
            )
        }
    }

    /// Calculate percentile (0-100) for a drill value at a position.
    static func percentile(value: Double, benchmark: DrillBenchmark) -> Int {
        if benchmark.lowerIsBetter {
            // Lower is better (timed drills): elite=95th, avg=50th, poor=15th
            if value <= benchmark.elite {
                return min(99, Int(95 + (benchmark.elite - value) / 0.05 * 2))
            }
            if value <= benchmark.average {
                return 50 + Int(45 * (benchmark.average - value) / (benchmark.average - benchmark.elite))
            }
            if value <= benchmark.poor {
                return 15 + Int(35 * (benchmark.poor - value) / (benchmark.poor - benchmark.average))
            }
            return max(1, Int(15 * (benchmark.poor + 0.3 - value) / 0.3))
        } else {
            // Higher is better (bench, jumps)
            if value >= benchmark.elite {
                return min(99, Int(95 + (value - benchmark.elite) / 2.0 * 2))
            }
            if value >= benchmark.average {
                return 50 + Int(45 * (value - benchmark.average) / (benchmark.elite - benchmark.average))
            }
            if value >= benchmark.poor {
                return 15 + Int(35 * (value - benchmark.poor) / (benchmark.average - benchmark.poor))
            }
            return max(1, Int(15 * value / benchmark.poor))
        }
    }

    /// Color for a percentile value.
    static func percentileColor(_ pct: Int) -> String {
        if pct >= 90 { return "gold" }
        if pct >= 70 { return "green" }
        if pct >= 40 { return "white" }
        return "orange"
    }
}
